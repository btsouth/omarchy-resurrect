# The secrets category: off by default, encrypted, and the recipient mode that
# exists so a backup can run with nobody watching.

seed_machine
ress init >/dev/null
VAULT="$XDG_DATA_HOME/ress/vault"

mkdir -p "$HOME/.ssh"
printf 'PRIVATE KEY MATERIAL\n' >"$HOME/.ssh/id_test"
chmod 600 "$HOME/.ssh/id_test"

ress secrets init
assert_ok "secrets init"
assert_file "$XDG_CONFIG_HOME/ress/secrets"

# ---- 1. off by default ----------------------------------------------------

ress backup -m "no secrets"
assert_ok "backup"
assert_no_file "$VAULT/secrets/secrets.tar.age" "nothing is encrypted until it is turned on"
assert_output "secrets: turned off"

# ---- 2. recipient mode runs unattended ------------------------------------

printf '.ssh\n' >"$XDG_CONFIG_HOME/ress/secrets"
KEY="$XDG_CONFIG_HOME/ress/secrets.key"
printf 'AGE-SECRET-KEY-TEST\n' >"$KEY"
printf 'age1testtesttesttesttest\n' >"$KEY.pub"
ress set SECRETS_MODE=recipient SECRETS_RECIPIENT="$KEY.pub" INCLUDE_SECRETS=1
assert_ok "configure recipient mode"

ress backup -m "with secrets"
assert_ok "backup with secrets, no terminal"
assert_file "$VAULT/secrets/secrets.tar.age" "the blob is written"
assert_called "age -R $KEY.pub" "encrypted to the recipient file"

# The plaintext never lands in the vault.
assert_no_file "$VAULT/home/.ssh/id_test" ".ssh is not in the plain capture"
assert_file_lacks "$VAULT/secrets/secrets.tar.age" "PRIVATE KEY MATERIAL" "the blob holds no plaintext"

# ---- 3. and restores without one ------------------------------------------

rm -rf "$HOME/.ssh"
ress restore --yes --only secrets
assert_ok "restore secrets with no terminal"
assert_file "$HOME/.ssh/id_test" "the secret came back"
assert_file_contains "$HOME/.ssh/id_test" "PRIVATE KEY MATERIAL"
assert_equals "$(stat -c '%a' "$HOME/.ssh/id_test")" "600" "and with 0600 permissions"
assert_equals "$(stat -c '%a' "$HOME/.ssh")" "700" "in a 0700 directory"

# ---- 4. a recipient string instead of a path is diagnosed ----------------

rm -rf "$HOME/.ssh"
ress set SECRETS_RECIPIENT=age1exampleexampleexampleexample
ress restore --yes --restart --only secrets
assert_fails "restore cannot decrypt without a private key"
assert_output "recipient string" "and says exactly which mistake it was"
assert_output ".pub file"
assert_no_file "$HOME/.ssh/id_test"

# ---- 5. a missing identity file is diagnosed too -------------------------

ress set SECRETS_RECIPIENT="$SANDBOX/gone.key.pub"
ress restore --yes --restart --only secrets
assert_fails "restore without the identity"
assert_output "no identity at"

# ---- 6. passphrase mode still refuses to run unattended ------------------

ress set SECRETS_MODE=passphrase SECRETS_RECIPIENT=
ress restore --yes --restart --only secrets
assert_output "passphrase mode needs a terminal"

# ---- 7. the dry run says what it cannot say -------------------------------

ress restore --dry-run --only secrets
assert_ok "dry run"
assert_output "only readable after you decrypt it"
