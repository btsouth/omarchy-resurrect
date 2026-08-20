# `ress verify` checks the machine against the vault, and exits non-zero when
# they do not match. A restore says what it did; this says what is true now.

seed_machine
machine_publish repo ripgrep
machine_publish aur brave-bin
machine_aur_rpc brave-bin
machine_shell_running

THEME_SHA=$(seed_remote theme rose-pine)
PLUGIN_SHA=$(seed_remote plugin some-widget acme.widget)

VAULT=$(make_vault)
printf 'ripgrep\n' >"$VAULT/packages/native.txt"
printf 'brave-bin\n' >"$VAULT/packages/foreign.txt"
mkdir -p "$VAULT/home/.config/systemd/user"
printf 'from the vault\n' >"$VAULT/home/.bashrc"
printf '[Service]\nExecStart=/usr/bin/syncthing serve\n[Install]\nWantedBy=default.target\n' \
  >"$VAULT/home/.config/systemd/user/syncthing.service"
printf 'syncthing.service\n' >"$VAULT/services/user-units.txt"
printf 'rose-pine\t%s\t%s\n' "$(remote_url rose-pine)" "$THEME_SHA" >"$VAULT/omarchy/themes.tsv"
printf 'acme.widget\t%s\t1\t%s\n' "$(remote_url some-widget)" "$PLUGIN_SHA" >"$VAULT/plugins/plugins.tsv"
cat >"$VAULT/webapps/apps/Excalidraw.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Excalidraw
Exec=omarchy-launch-webapp https://excalidraw.com
Icon=Excalidraw
Type=Application
DESKTOP
seal_vault "$VAULT"

# ---- 1. nothing restored yet: everything is missing -----------------------

ress --vault "$VAULT" verify
assert_fails "verify exits non-zero when the machine does not match"
assert_output "0 of 2" "no packages"
assert_output "ripgrep"
assert_output "brave-bin"
assert_output "acme.widget"
assert_output "Excalidraw"
assert_output "rose-pine"
assert_output "syncthing.service"
assert_output "Some of the vault is not on this machine"

ress --vault "$VAULT" verify --json
assert_fails "verify --json exits non-zero too"
assert_equals "$(jq -r '.complete' <<<"$OUT")" "false"
assert_equals "$(jq -r '.categories.packages.want' <<<"$OUT")" "2"
assert_equals "$(jq -r '.categories.packages.have' <<<"$OUT")" "0"
assert_equals "$(jq -r '.categories.plugins.missing[0]' <<<"$OUT")" "acme.widget"
assert_equals "$(jq -r '.takenFrom' <<<"$OUT")" "otherbox"

# ---- 2. after a full restore, everything matches --------------------------

ress --vault "$VAULT" restore --yes --aur --enable-units
assert_ok "restore"

ress --vault "$VAULT" verify
assert_ok "verify passes after a restore"
assert_output "This machine matches the vault"
assert_no_output "Some of the vault is not"

ress --vault "$VAULT" verify --json
assert_ok "verify --json passes"
assert_equals "$(jq -r '.complete' <<<"$OUT")" "true"
assert_equals "$(jq -r '.categories.services.have' <<<"$OUT")" "1"

# ---- 3. drift is noticed ---------------------------------------------------

rm -rf "$HOME/.config/omarchy/plugins/acme.widget"
: >"$FAKE_STATE/native.txt"
ress --vault "$VAULT" verify
assert_fails "verify notices what went away"
assert_output "acme.widget"
assert_output "ripgrep"

# A dotfile that changed since the backup counts as not matching.
rm -rf "$HOME/.config/omarchy/plugins"
printf 'edited since the backup\n' >"$HOME/.bashrc"
ress --vault "$VAULT" verify --json
assert_equals "$(jq -r '.categories.config.missing[0]' <<<"$OUT")" "1" "one dotfile differs"

# ---- 4. a restore that declined the AUR is honestly incomplete ------------

VAULT2=$(make_vault "$SANDBOX/v2")
printf 'brave-bin\n' >"$VAULT2/packages/foreign.txt"
seal_vault "$VAULT2"
: >"$FAKE_STATE/foreign.txt"

ress --vault "$VAULT2" restore --yes --no-aur
assert_ok "a restore that skips the AUR still succeeds"
ress --vault "$VAULT2" verify
assert_fails "and verify says the machine does not match"
assert_output "brave-bin"

# ---- 5. services are called out separately ---------------------------------

: >"$FAKE_STATE/enabled-units.txt"
ress --vault "$VAULT" verify
assert_output "Services are only ever enabled on purpose"
assert_output "ress enable-units"

# ---- 6. a theme that ships with Omarchy counts as present -----------------

VAULT3=$(make_vault "$SANDBOX/v3")
printf 'gruvbox\t\t\n' >"$VAULT3/omarchy/themes.tsv"
seal_vault "$VAULT3"

ress --vault "$VAULT3" verify --json
assert_equals "$(jq -r '.categories.themes.have' <<<"$OUT")" "0" "not here yet"

machine_builtin_theme gruvbox
ress --vault "$VAULT3" verify --json
assert_equals "$(jq -r '.categories.themes.have' <<<"$OUT")" "1" \
  "a built-in theme does not need restoring"
