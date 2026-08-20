# Degenerate vaults: nothing captured, empty lists, missing categories. These
# are where an unset array or an empty expansion turns into a crash.

seed_machine

# ---- 1. a vault with every file present but empty -------------------------

VAULT=$(make_vault)
seal_vault "$VAULT"

ress --vault "$VAULT" restore --dry-run
assert_ok "dry run against an empty vault"

ress --vault "$VAULT" restore --yes
assert_ok "restore against an empty vault"

ress --vault "$VAULT" verify
assert_ok "verify against an empty vault"
assert_output "not in this vault"

ress --vault "$VAULT" verify --json
assert_equals "$(jq -r '.complete' <<<"$OUT")" "true" "an empty vault is trivially matched"

ress --vault "$VAULT" scan
assert_ok "scan an empty vault"

ress --vault "$VAULT" enable-units
assert_ok "enable-units with no units"
assert_output "already enabled here"

# ---- 2. a vault with only a manifest --------------------------------------

BARE="$SANDBOX/bare"
mkdir -p "$BARE"
git -C "$BARE" init -q -b main
printf '{"schemaVersion":1,"ressVersion":"1.1.0","createdAt":"2026-01-01T00:00:00Z","machine":{"hostname":"x","user":"y","omarchy":"4","kernel":"6"},"categories":[],"counts":{}}\n' >"$BARE/ress.json"
git -C "$BARE" add -A
git -C "$BARE" -c commit.gpgsign=false commit -q -m bare

ress --vault "$BARE" restore --yes
assert_ok "restore from a vault with nothing in it"
assert_output "not in this vault" "a vault with no categories says so, rather than skipping silently"

ress --vault "$BARE" verify
assert_ok "verify a vault with nothing in it"

ress --vault "$BARE" scan
assert_ok "scan a vault with nothing in it"

# ---- 3. lists that exist but hold only blanks and comments ----------------

printf '\n\n' >"$VAULT/packages/native.txt"
printf '\n' >"$VAULT/packages/foreign.txt"
printf '\n\n' >"$VAULT/services/user-units.txt"
printf '\n' >"$VAULT/plugins/plugins.tsv"
printf '\n' >"$VAULT/omarchy/themes.tsv"
mkdir -p "$VAULT/omarchy"
git -C "$VAULT" add -A
git -C "$VAULT" -c commit.gpgsign=false commit -q -m blanks

ress --vault "$VAULT" restore --yes --restart
assert_ok "restore with blank lists"
assert_not_called "pacman -S --needed" "nothing to install"
assert_not_called "yay -S" "nothing to build"
assert_not_called "systemctl --user enable" "nothing to enable"

ress --vault "$VAULT" restore --dry-run
assert_ok "dry run with blank lists"

ress --vault "$VAULT" verify --json
assert_ok "verify with blank lists"

# ---- 4. no vault at all ----------------------------------------------------

ress --vault "$SANDBOX/nowhere" verify
assert_fails "verify without a vault"
assert_output "no vault at"

ress --vault "$SANDBOX/nowhere" scan
assert_fails "scan without a vault"
assert_output "no vault at"

ress --vault "$SANDBOX/nowhere" enable-units
assert_fails "enable-units without a vault"
assert_output "no vault at"

ress --vault "$SANDBOX/nowhere" restore --yes
assert_fails "restore without a vault"
assert_output "no vault at"

# ---- 5. progress belongs to one snapshot of one vault --------------------

# Two different vaults, restored one after the other. The second must not read
# the first one's progress and skip everything as already done.
A=$(make_vault "$SANDBOX/vault-a")
printf 'ripgrep\n' >"$A/packages/native.txt"
seal_vault "$A" "box-a"
B=$(make_vault "$SANDBOX/vault-b")
printf 'fd\n' >"$B/packages/native.txt"
seal_vault "$B" "box-b"
machine_publish repo ripgrep fd

ress --vault "$A" restore --yes --only packages
assert_ok "restore vault A"
assert_called "pacman -S --needed --noconfirm -- ripgrep"

: >"$CALLS"
ress --vault "$B" restore --yes --only packages
assert_ok "restore vault B"
assert_no_output "already done" "a different vault is not the same work"
assert_called "pacman -S --needed --noconfirm -- fd" "and it actually installs"

# The same vault, unchanged, is still resumable — that is the whole point.
: >"$CALLS"
ress --vault "$B" restore --yes --only packages
assert_output "already done" "the same snapshot is remembered"

# A newer backup of the same vault starts over: what was done was done from the
# old snapshot.
jq '.createdAt = "2026-06-06T00:00:00Z"' "$B/ress.json" >"$B/ress.json.new"
mv "$B/ress.json.new" "$B/ress.json"
: >"$CALLS"
ress --vault "$B" restore --yes --only packages
assert_no_output "already done" "a newer backup of the same vault is new work"

# ---- 6. a category name that is not a category ---------------------------

# Selecting nothing used to finish with "this machine is yours again" having
# done nothing at all, which is the same failure mode as a silent skip.
ress --vault "$A" restore --yes --only packagez
assert_fails "a typo in --only is refused"
assert_output "no such category: packagez"
assert_output "choose from:"
assert_no_output "This machine is yours again"

ress --vault "$A" restore --yes --skip pakcages
assert_fails "a typo in --skip is refused"
assert_output "no such category: pakcages"

# The real names still work, including several at once.
ress --vault "$A" restore --yes --restart --only packages,config
assert_ok "a valid --only list is accepted"
