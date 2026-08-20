# The vault manifest is ress.json, and a vault written under the old name is
# still readable — then quietly moved to the new one.

seed_machine
ress init >/dev/null
VAULT="$XDG_DATA_HOME/ress/vault"

ress backup -m first
assert_ok "backup"
assert_file "$VAULT/ress.json" "manifest is written as ress.json"
assert_no_file "$VAULT/resurrect.json" "the old name is not written"
assert_equals "$(jq -r '.ressVersion' "$VAULT/ress.json")" "1.1.0" "manifest records the ress version"

# ---- a vault from before the rename ---------------------------------------

git -C "$VAULT" mv ress.json resurrect.json
git -C "$VAULT" -c commit.gpgsign=false commit -q -m "pretend this vault is old"

ress status
assert_ok "status reads a legacy vault"
assert_output "backups    2"

ress status --json
assert_equals "$(jq -r '.hasVault' <<<"$OUT")" "1" "status sees the legacy manifest"

# Restore accepts it rather than reporting an empty vault.
ress restore --dry-run --only packages
assert_ok "dry-run restore reads a legacy vault"
assert_no_output "no vault at"

# The next backup moves it, and says so.
ress backup -m second
assert_ok "backup over a legacy vault"
assert_output "vault manifest renamed to ress.json"
assert_file "$VAULT/ress.json"
assert_no_file "$VAULT/resurrect.json" "the legacy manifest is retired"

# ---- the backup suffix -----------------------------------------------------

printf 'replaced by the restore\n' >"$HOME/.bashrc"
ress restore --yes --only config
assert_ok "restore config"
assert_file "$HOME/.bashrc.ress-bak" "a replaced file is kept under the new suffix"
assert_file_contains "$HOME/.bashrc.ress-bak" "replaced by the restore"
assert_file_contains "$HOME/.bashrc" "alias ll" "the vault's copy is in place"

# Neither suffix is ever captured back into the vault.
printf 'stale\n' >"$HOME/.bashrc.resurrect-bak"
ress backup -m third >/dev/null
assert_no_file "$VAULT/home/.bashrc.ress-bak" "the new suffix is excluded from capture"
assert_no_file "$VAULT/home/.bashrc.resurrect-bak" "the old suffix is still excluded"
