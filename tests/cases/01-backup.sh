# A backup captures each category into the vault and commits it.

seed_machine
machine_install foreign some-aur-tool
seed_plugin tsouth89.example
seed_webapp Excalidraw https://excalidraw.com

ress init
assert_ok "ress init"

VAULT="$XDG_DATA_HOME/ress/vault"
assert_dir "$VAULT/.git" "init creates a git vault"

ress backup -m "first"
assert_ok "ress backup"

assert_file "$VAULT/packages/native.txt"
assert_file_contains "$VAULT/packages/foreign.txt" "some-aur-tool"
assert_file_contains "$VAULT/home/.bashrc" "alias ll"
assert_file "$VAULT/home/.config/hypr/hyprland.conf"
assert_file_contains "$VAULT/plugins/plugins.tsv" "tsouth89.example"
assert_file "$VAULT/webapps/apps/Excalidraw.desktop"
assert_file "$VAULT/omarchy/shell.json"

# The vault is a git repo with the backup committed.
assert_equals "$(git -C "$VAULT" rev-list --count HEAD)" "1" "one commit"
assert_equals "$(git -C "$VAULT" log -1 --pretty=%s)" "first" "commit subject"

ress status
assert_ok "ress status"
assert_output "backups    1"

ress status --json
assert_ok "ress status --json"
assert_equals "$(jq -r '.hasVault' <<<"$OUT")" "1" "status reports a vault"
assert_equals "$(jq -r '.manifest.machine.user' <<<"$OUT")" "$USER" "manifest records the user"
