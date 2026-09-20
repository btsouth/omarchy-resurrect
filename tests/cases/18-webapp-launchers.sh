# Web app launchers: which of them are this machine's state, and which of them
# can come back.
#
# A launcher is an Exec line, and Omarchy writes that line three ways: a bare
# URL, a bare URL followed by browser flags, and a quoted URL, which is what
# `omarchy webapp install` writes today. The restore used to read everything
# after the launcher name as the URL, which refused the second and third forms —
# so a launcher made by the current installer, or one carrying a Chromium
# profile flag, was captured and then dropped on the machine that needed it.

seed_machine
machine_shell_running

mkdir -p "$OMARCHY_PATH/applications" "$HOME/.local/share/applications"

# ---- 1. a launcher Omarchy itself ships ------------------------------------

cat >"$OMARCHY_PATH/applications/YouTube.desktop" <<'DESKTOP'
[Desktop Entry]
Name=YouTube
Exec=omarchy-launch-webapp https://youtube.com/
Icon=youtube
Type=Application
DESKTOP
# The machine has a byte-identical copy, which is what the shipped set looks
# like on any install where it has been used.
cp "$OMARCHY_PATH/applications/YouTube.desktop" "$HOME/.local/share/applications/YouTube.desktop"

# ---- 2. the launchers the user made ---------------------------------------

# The form the current installer writes: a quoted URL, per the Desktop Entry
# spec, with a percent that is doubled the way the spec wants it read back.
cat >"$HOME/.local/share/applications/Quoted.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Quoted
Exec=omarchy-launch-webapp "https://example.com/a?q=1"
Icon=quoted
Type=Application
DESKTOP
cat >"$HOME/.local/share/applications/Pct.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Pct
Exec=omarchy-launch-webapp "https://example.com/b%%20c"
Icon=pct
Type=Application
DESKTOP

# A launcher carrying a Chromium profile flag, and a percent in its URL: one
# app, two accounts, and a path the spec wants written back as %%.
cat >"$HOME/.local/share/applications/Teams.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Teams
Exec=omarchy-launch-webapp https://teams.example.com/v2/a%20b --profile-directory=Microsoft365
Icon=microsoft-teams
Type=Application
DESKTOP

# Not a launcher at all: the URL is followed by a command.
cat >"$HOME/.local/share/applications/Bad.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Bad
Exec=omarchy-launch-webapp https://evil.example.com; rm -rf /home
Icon=bad
Type=Application
DESKTOP

# ---- 3. the capture --------------------------------------------------------

ress init
assert_ok "ress init"
VAULT="$XDG_DATA_HOME/ress/vault"

ress backup -m webapps
assert_ok "the backup"

assert_file "$VAULT/webapps/apps/Quoted.desktop" "a quoted launcher is captured"
assert_file "$VAULT/webapps/apps/Teams.desktop" "a launcher with flags is captured"
assert_no_file "$VAULT/webapps/apps/YouTube.desktop" \
  "a launcher Omarchy ships is not this machine's state"
assert_output "Omarchy ships were left out" "and the capture says so"
assert_output "cannot re-create" "as does the one a restore will refuse"
assert_output "Bad" "by name"

# ---- 4. the restore --------------------------------------------------------

ress --vault "$VAULT" restore --dry-run --yes
assert_ok "a dry run over the same vault"
assert_output "https://teams.example.com/v2/a%20b --profile-directory=Microsoft365" \
  "the plan shows the flags it would rebuild with"

# Two of the three are gone, so the restore creates them; Teams is left in place,
# so the restore also exercises replacing a launcher you already have.
rm -rf "$HOME/.local/share/applications/Quoted.desktop" \
       "$HOME/.local/share/applications/Pct.desktop"
: >"$CALLS"

ress --vault "$VAULT" restore --yes
assert_ok "the restore"

# The quoted URL came back as a URL, not as a string with quotes in it.
assert_called "omarchy webapp install Quoted https://example.com/a?q=1" \
  "a quoted launcher is rebuilt from its URL"
# A doubled percent is one literal percent, and reaches the installer that way.
assert_called "omarchy webapp install Pct https://example.com/b%20c" \
  "and a percent is read back the way the spec writes it"
# The flags travel, through the Exec line the installer takes for exactly this,
# and a percent in that line goes back out doubled, which is how the spec spells
# one literal percent in an Exec argument.
assert_called "omarchy webapp install Teams https://teams.example.com/v2/a%20b microsoft-teams omarchy-launch-webapp https://teams.example.com/v2/a%%20b --profile-directory=Microsoft365" \
  "a launcher with browser flags is rebuilt with them"
assert_file_contains "$HOME/.local/share/applications/Teams.desktop" \
  "Exec=omarchy-launch-webapp https://teams.example.com/v2/a%%20b --profile-directory=Microsoft365" \
  "and the launcher on disk carries them"
# The other path, with no custom exec: the installer quotes the URL itself and
# doubles the percent, so the file matches what was captured.
assert_file_contains "$HOME/.local/share/applications/Pct.desktop" \
  "Exec=omarchy-launch-webapp \"https://example.com/b%%20c\"" \
  "and a percent is written back the way the spec spells it"
assert_file "$HOME/.local/share/applications/Teams.desktop.ress-bak" \
  "the launcher it replaced was kept"

# The one that is not a launcher reached nothing, and is named as refused.
assert_not_called "webapp install Bad" "a launcher that is not one is refused"
assert_not_called "rm -rf" "and nothing it named ran"
assert_output "Bad" "the refusal names it"

# ---- 5. verify counts what a restore can rebuild ---------------------------

ress --vault "$VAULT" verify --json
assert_ok "verify: the machine matches for everything restorable"
assert_equals "$(jq -r '.categories.webapps.want' <<<"$OUT")" "3" \
  "three launchers a restore can rebuild"
assert_equals "$(jq -r '.categories.webapps.have' <<<"$OUT")" "3" "all three are here"
assert_equals "$(jq -r '.categories.webapps.refused[0]' <<<"$OUT")" "Bad" \
  "the one it cannot is listed as refused, not as missing"
assert_equals "$(jq -r '.complete' <<<"$OUT")" "true" \
  "and a launcher a restore would refuse is not a mismatch"

# ---- 6. a loadout carries the launchers it can and says what it left out ----

ress share --out "$SANDBOX/loadout"
assert_ok "ress share"
assert_output "left out of the profile" "the flagged launcher is called out"
assert_equals \
  "$(jq -r '[.webapps[].name] | sort | join(",")' "$SANDBOX/loadout/profile.json")" \
  "Pct,Quoted" \
  "and the profile holds the two that rebuild from a URL"

# ---- 7. the name in the file is the name that matters ----------------------
#
# A restore rebuilds a launcher under its Name= field, so that is the name the
# check has to look for. Matching the vault's file name instead made verify
# report missing a launcher the restore had just created.

VAULT4=$(make_vault "$SANDBOX/v4")
cat >"$VAULT4/webapps/apps/Alpha.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Beta
Exec=omarchy-launch-webapp https://beta.example.com/
Icon=beta
Type=Application
DESKTOP
seal_vault "$VAULT4"

ress --vault "$VAULT4" restore --yes
assert_ok "a vault whose launcher file is not named after its Name= field"
assert_called "omarchy webapp install Beta https://beta.example.com/ beta" \
  "the restore rebuilds it under the name in the file"

ress --vault "$VAULT4" verify --json
assert_ok "verify matches a launcher the restore just created"
assert_equals "$(jq -r '.categories.webapps | "\(.want)/\(.have)"' <<<"$OUT")" "1/1" \
  "it looks for the name, not the file name"
assert_equals "$(jq -r '.categories.webapps.missing | length' <<<"$OUT")" "0" "and finds nothing missing"

# ---- 8. a launcher with a second Exec line ---------------------------------
#
# The second Exec= is a Desktop Action: another command the first line does not
# account for. A restore refuses the launcher, so verify lists it as refused
# rather than counting it, and the loadout export leaves it out.

cat >"$HOME/.local/share/applications/TwoExec.desktop" <<'DESKTOP'
[Desktop Entry]
Name=TwoExec
Exec=omarchy-launch-webapp https://two.example.com/
Icon=two
Type=Application

[Desktop Action Talk]
Name=Start a call
Exec=some-other-command --call
DESKTOP
cp "$HOME/.local/share/applications/TwoExec.desktop" "$VAULT4/webapps/apps/TwoExec.desktop"
seal_vault "$VAULT4"

ress --vault "$VAULT4" verify --json
assert_ok "verify stays a match with a launcher it cannot rebuild"
assert_equals "$(jq -r '.categories.webapps.want' <<<"$OUT")" "1" \
  "the one it cannot rebuild is not counted as work"
assert_equals "$(jq -r '.categories.webapps.refused[0]' <<<"$OUT")" "TwoExec" "it is listed as refused"

ress share --out "$SANDBOX/loadout2"
assert_ok "ress share beside a launcher that cannot come back"
assert_equals "$(jq -r '[.webapps[].name] | index("TwoExec")' "$SANDBOX/loadout2/profile.json")" \
  "null" "a launcher a restore would refuse is not published in a loadout"

# ---- 9. a name with a space in it is one name ------------------------------
#
# A web app label is two words as often as not, and the lists a category reports
# were split on spaces, so "Microsoft Teams" arrived in the JSON as two entries
# and a caller counting them got a number that was not a count.

VAULT5=$(make_vault "$SANDBOX/v5")
cat >"$VAULT5/webapps/apps/StartPage.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Start Page
Exec=omarchy-launch-webapp https://start.example.com/
Icon=start
Type=Application
DESKTOP
cat >"$VAULT5/webapps/apps/Plain.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Plain
Exec=omarchy-launch-webapp https://plain.example.com/
Icon=plain
Type=Application
DESKTOP
seal_vault "$VAULT5"

ress --vault "$VAULT5" verify --json
assert_fails "verify reports the launchers it cannot find"
assert_equals "$(jq -r '.categories.webapps.missing | length' <<<"$OUT")" "2" \
  "two launchers, not one entry per word"
assert_equals \
  "$(jq -r '.categories.webapps.missing | join("|")' <<<"$OUT")" "Plain|Start Page" \
  "and a name with a space in it stays one name"

# ---- 10. a label a restore refuses -----------------------------------------
#
# The label becomes a filename, and the installer refuses one the filesystem or
# it cannot address (a slash, most of all). A restore refuses that launcher, so
# verify has to as well: counting it would report a machine as matching a vault
# it will not write.

VAULT6=$(make_vault "$SANDBOX/v6")
cat >"$VAULT6/webapps/apps/Bobs.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Bob's Site
Exec=omarchy-launch-webapp https://bob.example.com/
Icon=bob
Type=Application
DESKTOP
seal_vault "$VAULT6"

ress --vault "$VAULT6" verify --json
assert_equals "$(jq -r '.categories.webapps.want' <<<"$OUT")" "0" \
  "a launcher a restore refuses is not counted as work"
assert_equals "$(jq -r '.categories.webapps.refused | join("|")' <<<"$OUT")" "Bob's Site" \
  "and it is named in the refused list"

ress --vault "$VAULT6" verify
assert_output "1 entry a restore cannot rebuild" "the count reads as English"

: >"$CALLS"
ress --vault "$VAULT6" restore --yes
assert_ok "the restore survives a launcher it refuses"
assert_not_called "webapp install Bob" "and does not install it"
assert_output "Bob's Site" "the refusal names it"

# ---- 11. a launcher that focuses instead of opening ------------------------
#
# omarchy-launch-or-focus-webapp is a different launcher, not a detail: rebuilt
# as the plain form it opens a second window where the original focused the one
# you had.

cat >"$HOME/.local/share/applications/Focus.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Focus
Exec=omarchy-launch-or-focus-webapp https://focus.example.com/
Icon=focus
Type=Application
DESKTOP

VAULT7=$(make_vault "$SANDBOX/v7")
cp "$HOME/.local/share/applications/Focus.desktop" "$VAULT7/webapps/apps/Focus.desktop"
seal_vault "$VAULT7"

ress --vault "$VAULT7" restore --dry-run --yes
assert_output "(via launch-or-focus-webapp)" "the plan says which launcher it would write"

: >"$CALLS"
ress --vault "$VAULT7" restore --yes
assert_ok "the restore of an or-focus launcher"
assert_called "omarchy webapp install Focus https://focus.example.com/ focus omarchy-launch-or-focus-webapp https://focus.example.com/" \
  "the launcher form travels with the URL"
assert_file_contains "$HOME/.local/share/applications/Focus.desktop" \
  "Exec=omarchy-launch-or-focus-webapp https://focus.example.com/" \
  "and the launcher on disk focuses rather than opens"

# ---- 12. the capture names what a restore will refuse ----------------------
#
# TwoExec was written into the home directory in section 8 and never warned
# about, because the capture only asked whether the first Exec line parsed.

ress backup -m launchers
assert_ok "a backup beside a launcher with a Desktop Action"
assert_output "cannot re-create" "the capture says a restore will refuse it"
assert_output "TwoExec" "by name"

# ---- 13. an Exec line long enough to be a weapon ---------------------------
#
# The parser walks the line a character at a time, so its cost is quadratic in
# the line's length, and the line comes out of a vault that `--from <git-url>`
# fetched from a stranger. Half a minute of stall per launcher is a cheap thing
# for someone else to buy, so a line no launcher needs is refused unread.

VAULT8=$(make_vault "$SANDBOX/v8")
{
  printf '[Desktop Entry]\nName=Huge\n'
  printf 'Exec=omarchy-launch-webapp https://a.example.com/'
  printf 'A%.0s' $(seq 1 40000)
  printf '\nIcon=huge\nType=Application\n'
} >"$VAULT8/webapps/apps/Huge.desktop"
seal_vault "$VAULT8"

started=$(date +%s)
ress --vault "$VAULT8" verify --json
took=$(( $(date +%s) - started ))
assert_equals "$(jq -r '.categories.webapps.refused | join("|")' <<<"$OUT")" "Huge" \
  "a 40 KB Exec line is refused"
assert_equals "$(( took <= 5 ? 1 : 0 ))" "1" "and answered in ${took}s rather than half a minute"
