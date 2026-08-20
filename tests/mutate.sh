#!/bin/bash
#
# Mutation testing for the ress suite.
#
#   tests/mutate.sh              run every mutation
#   tests/mutate.sh aur          run the ones whose name matches "aur"
#
# A passing test suite says the tests agree with the code. It does not say the
# tests would notice if the code were wrong. This breaks one behaviour at a
# time in a throwaway copy of the repo and checks that at least one case goes
# red. A mutation that SURVIVES is a feature the suite only appears to cover.
#
# It takes a while — every mutation runs the whole suite — so it is a thing you
# run when you have changed what the tests are for, not on every edit.

set -uo pipefail

TESTS_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=$(dirname "$TESTS_DIR")
WORK="${TMPDIR:-/tmp}/ress-mutation.$$"
FILTER="${1:-}"

trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"

survived=0
caught=0
skipped=0

run_mutation() {
  local name="$1" old="$2" new="$3"
  [[ -n $FILTER && $name != *"$FILTER"* ]] && return 0

  local dir="$WORK/$name"
  cp -a "$SRC" "$dir"
  rm -rf "$dir/.git"

  python3 - "$dir/bin/ress" "$old" "$new" <<'PY'
import sys, pathlib
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path); s = p.read_text()
if old not in s:
    sys.exit(3)
p.write_text(s.replace(old, new, 1))
PY
  local rc=$?
  if (( rc == 3 )); then
    printf '  \e[35m?\e[0m %-24s the anchor text no longer exists — update this mutation\n' "$name"
    skipped=$((skipped + 1))
    rm -rf "$dir"
    return 0
  fi
  if ! bash -n "$dir/bin/ress" 2>/dev/null; then
    printf '  \e[35m?\e[0m %-24s mutation does not parse\n' "$name"
    skipped=$((skipped + 1))
    rm -rf "$dir"
    return 0
  fi

  local out
  out=$(cd "$dir" && ./tests/run.sh 2>&1)
  if grep -q 'cases passed' <<<"$out"; then
    printf '  \e[31m✗\e[0m %-24s SURVIVED — nothing noticed\n' "$name"
    survived=$((survived + 1))
  else
    printf '  \e[32m✓\e[0m %-24s caught by %s\n' "$name" \
      "$(grep '✗' <<<"$out" | grep -oE '[0-9]+-[a-z-]+' | sort -u | tr '\n' ' ')"
    caught=$((caught + 1))
  fi
  rm -rf "$dir"
}

# ---- the two consent gates ------------------------------------------------

run_mutation aur-always-builds \
  '  AUR_KEPT=()
  AUR_MODE="skip"' \
  '  AUR_KEPT=()
  AUR_MODE="build"'

run_mutation aur-ignores-flag \
  'local decision="${AUR_CHOICE:-}"' \
  'local decision="yes"'

run_mutation aur-ignores-denylist \
  'aur_denied() { merged_list aur-deny | grep -qxF -- "$1"; }' \
  'aur_denied() { return 1; }'

run_mutation units-always-enable \
  'case "$(units_decision_kind)" in
    no)' \
  'case "yes" in
    no)'

run_mutation units-no-validation \
  'valid_unit "$unit" || continue
    systemctl --user is-enabled' \
  'systemctl --user is-enabled'

run_mutation eof-kills-restore \
  'read -r -p "Enable $(plural "${#units[@]}" "user service")? [y/N] " reply || reply=""' \
  'read -r -p "Enable $(plural "${#units[@]}" "user service")? [y/N] " reply'

# ---- the secret scanner ---------------------------------------------------

run_mutation scanner-finds-nothing \
  'SECRET_FINDINGS=$(printf' \
  'found=""; SECRET_FINDINGS=$(printf'

run_mutation scanner-block-commits \
  'if [[ $(secret_scan_mode) == block ]]; then' \
  'if false; then'

run_mutation scanner-leaks-match \
  'printf '"'"'%s\n'"'"' "$SECRET_FINDINGS" | awk -F'"'"'\t'"'"' '"'"'NF { printf "    %-52s %s\n", $1, $2 }'"'"'' \
  'printf '"'"'%s\n'"'"' "$SECRET_FINDINGS" | awk -F'"'"'\t'"'"' '"'"'NF { printf "    %-52s %s\n", $1, $2 }'"'"'; grep -rIhE "ghp_[A-Za-z0-9]{36}" "$VAULT" 2>/dev/null | head -1'

# ---- verify ---------------------------------------------------------------

run_mutation verify-always-complete \
  '(( ${have[$category]} < ${want[$category]} )) && complete=0' \
  '(( ${have[$category]} < ${want[$category]} )) && complete=1'

run_mutation verify-ignores-packages \
  'missing[packages]=$(comm -23 "$wanted_pkgs" "$installed" | tr' \
  'missing[packages]=$(true | tr'

# ---- the vault format -----------------------------------------------------

run_mutation manifest-no-legacy \
  '[[ -f $VAULT/$VAULT_MANIFEST_LEGACY ]] && { printf '"'"'%s'"'"' "$VAULT/$VAULT_MANIFEST_LEGACY"; return 0; }' \
  ':'

run_mutation bak-suffix-old \
  'BAK_SUFFIX=".ress-bak"' \
  'BAK_SUFFIX=".resurrect-bak"'

# ---- restore mechanics ----------------------------------------------------

run_mutation partial-marks-done \
  '&& ! was_partial "$category"; then' \
  '; then'

run_mutation progress-not-scoped \
  'local identity="# $VAULT $(jq -r '"'"'.createdAt // "?"'"'"' "$manifest" 2>/dev/null || echo "?")"' \
  'local identity="# fixed"'

run_mutation category-not-validated \
  '(( known )) || { set +f; die "no such category' \
  '(( 1 )) || { set +f; die "no such category'

run_mutation dryrun-writes-state \
  'if (( ! DRY_RUN )); then
    (( restart )) && rm -f "$RESTORE_STATE"' \
  'if (( 1 )); then
    (( restart )) && rm -f "$RESTORE_STATE"'

run_mutation first-contact-never \
  'same_remote "$from" "$(normalize_source "${CFG[REMOTE]:-}")" || FIRST_CONTACT=1' \
  ':'

# ---- untrusted input ------------------------------------------------------

run_mutation schema-unvalidated \
  'valid_int "$schema" ||
    die "this vault does not declare a schema version as a number — refusing to read it"' \
  ':'

run_mutation plain-not-applied \
  'plain() { printf '"'"'%s'"'"' "$1" | tr -d '"'"'\000-\037\177'"'"'; }' \
  'plain() { printf '"'"'%s'"'"' "$1"; }'

# ---- settings and capture -------------------------------------------------

run_mutation autostart-always \
  '[[ ${CFG[CAPTURE_AUTOSTART]:-0} == 1 ]] && [[ -d $HOME/.config/autostart ]]' \
  '[[ -d $HOME/.config/autostart ]]'

run_mutation settings-unvalidated \
  'if [[ -v CFG_CHOICES[$key] ]]; then' \
  'if false; then'

run_mutation config-no-lock \
  'take_config_lock
  load_config' \
  ':'

# ---- the protocol ---------------------------------------------------------

run_mutation porcelain-prose \
  'if (( PORCELAIN )); then
    for line in "${lines[@]}"; do emit "LOG|will run: $line"; done
    return 0
  fi' \
  'if (( 0 )); then
    for line in "${lines[@]}"; do emit "LOG|will run: $line"; done
    return 0
  fi'

printf '\n'
if (( survived > 0 || skipped > 0 )); then
  printf '\e[31m%d caught, %d survived, %d skipped\e[0m\n' "$caught" "$survived" "$skipped"
  exit 1
fi
printf '\e[32mall %d mutations caught\e[0m\n' "$caught"
