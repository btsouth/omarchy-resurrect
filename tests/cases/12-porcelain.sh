# --porcelain is a protocol, not prose. The panel parses it line by line, and a
# consumer must not be told less than a person is.

seed_machine
machine_publish repo ripgrep
machine_publish aur brave-bin

VAULT=$(make_vault)
mkdir -p "$VAULT/home" "$VAULT/omarchy/hooks"
printf 'from the vault\n' >"$VAULT/home/.bashrc"
printf '#!/bin/sh\necho hi\n' >"$VAULT/omarchy/hooks/post-update"
printf 'ripgrep\n' >"$VAULT/packages/native.txt"
printf 'brave-bin\n' >"$VAULT/packages/foreign.txt"
seal_vault "$VAULT"

# Everything ress itself writes is a record. (A subprocess ress calls may print
# its own output — pacman does — so only ress's own lines are checked, which is
# what the panel's parser sees as unparseable noise it must tolerate.)
only_ress_lines() {
  printf '%s\n' "$OUT" | grep -vE '^(installed|built) ' || true
}
assert_protocol() {
  local bad
  bad=$(only_ress_lines | grep -vE '^(BEGIN|STEP|PROGRESS|LOG|DONE)\|' | grep -c . || true)
  assert_equals "$bad" "0" "${1:-every line is a protocol record}" 
  [[ $bad == 0 ]] || only_ress_lines | grep -vE '^(BEGIN|STEP|PROGRESS|LOG|DONE)\|' >&2
}

# ---- restore ---------------------------------------------------------------

ress --porcelain --vault "$VAULT" restore --yes
assert_ok "porcelain restore"
assert_protocol "restore emits only records"

# And still says everything the human version says.
assert_output "LOG|will run: 1 Omarchy hook"
assert_output "LOG|restoring otherbox"
assert_output "LOG|will install 1 from the Arch repos: ripgrep"
assert_output "LOG|will build 1 from the AUR: brave-bin"
assert_output "DONE|ok|restore complete"

# Deferred work reaches the protocol rather than only the terminal.
assert_output "LOG|left for later: 1 AUR package not built"

# ---- backup ----------------------------------------------------------------

ress init >/dev/null
printf 'TOKEN=ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8\n' >"$HOME/.local/bin/deploy"
ress --porcelain backup -m porcelain
assert_ok "porcelain backup"
assert_protocol "backup emits only records"
assert_output "STEP|secrets|warn|possible credentials in 1 file"
assert_no_output "Possible credentials in the vault" "the prose report stays out of the stream"
assert_no_output "ghp_A1b2" "and the match is never in it"

# ---- the blocked backup is a record, not a silent exit --------------------

ress set SECRET_SCAN=block >/dev/null
ress --porcelain backup -m blocked
assert_fails "porcelain backup blocked"
assert_output "DONE|fail|blocked by the secret scan"
assert_protocol "a blocked backup emits only records too"
assert_no_output "Nothing was committed" "the explanation is for a person, not for the protocol"

# ---- a blocked backup never pushes ---------------------------------------

REMOTE="$SANDBOX/remote.git"
git init -q --bare "$REMOTE"
ress set REMOTE="$REMOTE" >/dev/null
ress backup -m blocked --push
assert_fails "block fails the backup"
assert_output "Nothing was committed"
assert_equals "$(git -C "$REMOTE" rev-list --count --all 2>/dev/null || echo 0)" "0" \
  "a vault that failed the scan is never pushed"
