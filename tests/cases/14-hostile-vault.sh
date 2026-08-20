# A vault is a git repository, and `restore --from` fetches one over the
# network. Everything read out of it is attacker-controlled until it matches a
# validator. These are the cases where it does not match.

seed_machine
machine_shell_running

VAULT=$(make_vault)

# ---- names that must never reach a command line --------------------------

{
  printf -- '--overwrite=/etc/passwd\n'
  printf -- '-Rns\n'
  printf '../../../etc/shadow\n'
  printf 'legit-package\n'
} >"$VAULT/packages/native.txt"
printf -- '--asdeps\n../../evil\n' >"$VAULT/packages/foreign.txt"
machine_publish repo legit-package

{
  printf -- '../../../etc\t\t\n'
  printf 'Fine-Theme\t\t\n'
  printf 'ok-theme\thttps://github.com/example/ok-theme\tnot-a-sha\n'
  printf 'evil-theme\tfile:///etc\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
  printf 'ssh-theme\t-oProxyCommand=touch /tmp/pwned\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
} >"$VAULT/omarchy/themes.tsv"

{
  printf -- '../../../../tmp/evil\thttps://github.com/example/x\t1\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
  printf -- 'ok.plugin\t-uroot\t1\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
  printf -- 'local.plugin\tfile:///etc\t1\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
} >"$VAULT/plugins/plugins.tsv"

printf -- '--now\n../../etc/evil.service\nfine.service\n' >"$VAULT/services/user-units.txt"

# A launcher whose Exec is not the plain webapp form, and one with a second
# Exec line hiding a Desktop Action.
cat >"$VAULT/webapps/apps/Evil.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Evil
Exec=rm -rf /home
Icon=evil
Type=Application
DESKTOP
cat >"$VAULT/webapps/apps/Sneaky.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Sneaky
Exec=omarchy-launch-webapp https://example.com
Exec=touch /tmp/pwned
Icon=sneaky
Type=Application
DESKTOP

seal_vault "$VAULT" "hostile"

ress --vault "$VAULT" restore --yes --aur
assert_ok "the restore survives a vault full of bad input"

# Nothing option-shaped or traversing reached a command line.
assert_not_called "overwrite" "an option-shaped package name is refused"
assert_not_called "Rns" "so is a remove flag"
assert_not_called "etc/shadow"
assert_not_called "asdeps"
assert_not_called "enable -- --now"
assert_not_called "evil.service"
assert_not_called "ProxyCommand" "an ssh option smuggled in as a theme remote is refused"
assert_not_called "webapp install Evil" "a launcher that is not the plain webapp form is refused"
assert_not_called "webapp install Sneaky" "and so is one with a second Exec line"
assert_output "refused"

# The one valid package still installed: refusing bad input is not refusing all.
assert_called "pacman -S --needed --noconfirm -- legit-package"

# Nothing was created outside $HOME.
assert_no_file "/tmp/pwned" "nothing escaped to /tmp"
assert_no_file "$HOME/.config/omarchy/themes/../../../etc"
assert_no_file "$HOME/.config/omarchy/plugins/../../../../tmp/evil"

# A theme with an unusable remote is not cloned, and a malformed commit is not
# treated as a pin.
assert_no_file "$HOME/.config/omarchy/themes/evil-theme"
assert_no_file "$HOME/.config/omarchy/themes/ok-theme"
assert_no_file "$HOME/.config/omarchy/plugins/local.plugin"

# ---- a filename that tries to repaint the terminal ------------------------

ress init >/dev/null
mkdir -p "$HOME/.local/bin"
printf 'TOKEN=ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8\n' \
  >"$HOME/.local/bin/$(printf 'deploy\033[31m')"
ress backup -m hostile
assert_ok "backup with a hostile filename"
assert_output "Possible credentials in the vault"
BAD=$(printf '%s' "$OUT" | grep -c "$(printf '\033')\[31m" || true)
assert_equals "$BAD" "0" "the finding list carries no escape sequence from the filename"

# ---- a schema version that is not a number -------------------------------

# `(( schema == SCHEMA ))` is not a numeric context: bash arithmetic evaluates
# the contents of a bare name and runs command substitution inside an array
# subscript. A vault declaring `CFG[$(...)]` as its schemaVersion ran that
# command — on the --from path, before any prompt.
EVIL=$(make_vault "$SANDBOX/evil-schema")
jq -n --arg s "CFG[\$(touch $SANDBOX/EXECUTED)]" \
  '{schemaVersion: $s, ressVersion: "1.1.0", createdAt: "x",
    machine: {hostname: "h", user: "u", omarchy: "4", kernel: "6"},
    categories: [], counts: {}}' >"$EVIL/ress.json"
git -C "$EVIL" add -A
git -C "$EVIL" -c commit.gpgsign=false commit -q -m evil

ress --vault "$EVIL" restore --dry-run
assert_fails "a vault with a non-numeric schema is refused"
assert_output "not declare a schema version as a number"
assert_no_file "$SANDBOX/EXECUTED" "and nothing it wrote there was executed"

ress --vault "$EVIL" restore --yes
assert_fails "the same on a real restore"
assert_no_file "$SANDBOX/EXECUTED"

# The same field in a loadout, which `ress apply` reads before its confirmation.
PROFILE="$SANDBOX/evil-loadout"
mkdir -p "$PROFILE"
jq -n --arg s "CFG[\$(touch $SANDBOX/EXECUTED2)]" \
  '{schemaVersion: $s, kind: "omarchy-loadout", name: "x", author: "y",
    packages: {native: [], aur: []}, plugins: [], webapps: [],
    theme: {name: "", url: "", commit: ""}}' >"$PROFILE/profile.json"
ress apply --dry-run "$PROFILE"
assert_fails "a loadout with a non-numeric schema is refused"
assert_no_file "$SANDBOX/EXECUTED2" "and nothing it wrote there was executed"

# A real numeric schema from the future is still refused, but politely.
jq '.schemaVersion = 99' "$EVIL/ress.json" >"$EVIL/x" && mv "$EVIL/x" "$EVIL/ress.json"
ress --vault "$EVIL" restore --yes
assert_fails "a schema from the future is refused"
assert_output "vault schema 99 is not readable"
