# Restore writes files; the one thing it can turn on is a systemd user unit,
# and that never happens without being asked for.

seed_machine

# A vault whose owner had two user services enabled, with the unit files to go
# with them.
VAULT=$(make_vault)
mkdir -p "$VAULT/home/.config/systemd/user"
cat >"$VAULT/home/.config/systemd/user/syncthing.service" <<'UNIT'
[Unit]
Description=Syncthing
[Service]
ExecStart=/usr/bin/syncthing serve --no-browser
[Install]
WantedBy=default.target
UNIT
cat >"$VAULT/home/.config/systemd/user/phone-home.service" <<'UNIT'
[Unit]
Description=Something less friendly
[Service]
ExecStart=/home/someone/.local/bin/phone-home --every 60
[Install]
WantedBy=default.target
UNIT
printf 'syncthing.service\nphone-home.service\n' >"$VAULT/services/user-units.txt"
seal_vault "$VAULT"

# ---- 1. --yes does not answer the units question --------------------------

ress --vault "$VAULT" restore --yes --only config
assert_ok "restore with --yes"
assert_file "$HOME/.config/systemd/user/syncthing.service" "the unit file is restored"
assert_not_called "systemctl --user enable" "--yes does not enable anything"
assert_output "left disabled"
assert_output "ress enable-units"

# ---- 2. the prompt names what each unit runs ------------------------------

ress_answer "n" -- --vault "$VAULT" restore --yes --restart --only config
assert_output "syncthing.service"
assert_output "/usr/bin/syncthing serve --no-browser" "the prompt shows what will run"
assert_output "/home/someone/.local/bin/phone-home" "including the unfriendly one"
assert_not_called "systemctl --user enable" "answering no enables nothing"

# ---- 3. answering yes enables them ----------------------------------------

ress_answer "y" -- --vault "$VAULT" restore --yes --restart --only config
assert_ok "restore answering yes"
assert_called "systemctl --user enable -- syncthing.service"
assert_called "systemctl --user enable -- phone-home.service"
assert_output "2 user services enabled"

# ---- 4. once enabled, they are not asked about again ----------------------

OUT=""; ress --vault "$VAULT" restore --yes --restart --only config
assert_ok "restore again"
assert_no_output "user services" "nothing pending, nothing said"

# ---- 5. --enable-units skips the question --------------------------------

: >"$FAKE_STATE/enabled-units.txt"; : >"$CALLS"
ress --vault "$VAULT" restore --yes --restart --only config --enable-units
assert_ok "restore --enable-units"
assert_called "systemctl --user enable -- syncthing.service" "--enable-units enables without asking"
assert_output "2 user services enabled"

# ---- 6. --no-enable-units and ENABLE_UNITS=no ----------------------------

: >"$FAKE_STATE/enabled-units.txt"; : >"$CALLS"
ress --vault "$VAULT" restore --yes --restart --only config --no-enable-units
assert_not_called "systemctl --user enable" "--no-enable-units leaves them alone"

ress set ENABLE_UNITS=no >/dev/null
: >"$CALLS"
ress --vault "$VAULT" restore --yes --restart --only config
assert_not_called "systemctl --user enable" "ENABLE_UNITS=no leaves them alone"
assert_output "ENABLE_UNITS=no" "the skip says which setting caused it"
ress set ENABLE_UNITS=ask >/dev/null

# ---- 7. ress enable-units ------------------------------------------------

: >"$FAKE_STATE/enabled-units.txt"; : >"$CALLS"
ress_answer "n" -- --vault "$VAULT" enable-units
assert_ok "enable-units, declined"
assert_output "/usr/bin/syncthing serve"
assert_output "Nothing was enabled"
assert_not_called "systemctl --user enable"

ress --vault "$VAULT" enable-units --all
assert_ok "enable-units --all"
assert_called "systemctl --user enable -- phone-home.service"
assert_output "2 user services enabled"

ress --vault "$VAULT" enable-units
assert_ok "enable-units with nothing to do"
assert_output "already enabled here"

# ---- 8. a named unit, and one that is not in the vault -------------------

: >"$FAKE_STATE/enabled-units.txt"; : >"$CALLS"
ress --vault "$VAULT" enable-units --all syncthing.service
assert_called "systemctl --user enable -- syncthing.service"
assert_not_called "systemctl --user enable -- phone-home.service" "only the named unit is enabled"

ress --vault "$VAULT" enable-units --all totally-made-up.service
assert_output "is not a service this vault has enabled"
assert_not_called "systemctl --user enable -- totally-made-up.service"

# ---- 9. a unit whose file never arrived ----------------------------------

: >"$FAKE_STATE/enabled-units.txt"; : >"$CALLS"
printf 'ghost.service\n' >>"$VAULT/services/user-units.txt"
ress --vault "$VAULT" enable-units --all
assert_output "ghost.service is not installed here"
assert_not_called "systemctl --user enable -- ghost.service"

# ---- 10. a vault cannot smuggle a name onto the systemctl line -----------

: >"$FAKE_STATE/enabled-units.txt"; : >"$CALLS"
printf -- '--now\n../../etc/evil.service\n' >>"$VAULT/services/user-units.txt"
ress --vault "$VAULT" enable-units --all
assert_not_called "enable -- --now" "an option-shaped name never reaches systemctl"
assert_not_called "evil.service" "a traversing name never reaches systemctl"
