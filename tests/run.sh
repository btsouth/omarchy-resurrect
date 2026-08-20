#!/bin/bash
#
# ress test runner.
#
#   tests/run.sh              run every case
#   tests/run.sh restore      run cases whose name matches "restore"
#   tests/run.sh -v           keep going but print each case's output on failure
#
# Every case runs in its own sandbox: a throwaway $HOME, a fake package
# database, and a PATH where tests/bin shadows pacman, yay, sudo, systemctl and
# the omarchy CLI. Nothing outside the sandbox is read or written.

set -uo pipefail

TESTS_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$TESTS_DIR")

filter=""
verbose=0
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) verbose=1 ;;
    *) filter="$arg" ;;
  esac
done

# Syntax first: a parse error makes every case fail in the same confusing way.
if ! bash -n "$REPO_DIR/bin/ress"; then
  printf '\e[31mbin/ress does not parse.\e[0m\n' >&2
  exit 1
fi

total=0; failed=0; assertions=0
started=$SECONDS

for case_file in "$TESTS_DIR"/cases/*.sh; do
  [[ -f $case_file ]] || continue
  name=$(basename "$case_file" .sh)
  [[ -n $filter && $name != *"$filter"* ]] && continue
  total=$((total + 1))

  # Each case is a separate bash process so a `set -e` death or a stray exit
  # cannot take the runner with it. The case reports its own tally on fd 3.
  result=$(
    bash -c '
      source "$1/lib/harness.sh"
      harness_setup
      trap harness_teardown EXIT
      source "$2"
      printf "\nTALLY %s %s\n" "$CASE_FAILURES" "$CASE_ASSERTIONS"
    ' _ "$TESTS_DIR" "$case_file" 2>&1
  )
  # The tally is matched anywhere on the line: a case's last line of output may
  # not end in a newline, and losing the tally reads as "the case died".
  tally=$(printf '%s\n' "$result" | grep -o 'TALLY [0-9]\+ [0-9]\+' | tail -1)
  body=$(printf '%s\n' "$result" | sed 's/TALLY [0-9]\+ [0-9]\+$//')
  case_failures=$(awk '{print $2}' <<<"$tally"); case_failures=${case_failures:-1}
  case_assertions=$(awk '{print $3}' <<<"$tally"); case_assertions=${case_assertions:-0}
  assertions=$((assertions + case_assertions))

  if [[ -z $tally ]]; then
    printf '\e[31m  ✗\e[0m %-38s case died\n' "$name"
    printf '%s\n' "$body" | sed 's/^/      /'
    failed=$((failed + 1))
  elif (( case_failures > 0 )); then
    printf '\e[31m  ✗\e[0m %-38s %d/%d assertions failed\n' "$name" "$case_failures" "$case_assertions"
    printf '%s\n' "$body"
    failed=$((failed + 1))
  else
    printf '\e[32m  ✓\e[0m %-38s %d assertions\n' "$name" "$case_assertions"
    (( verbose )) && [[ -n $body ]] && printf '%s\n' "$body" | sed 's/^/      /'
  fi
done

printf '\n'
if (( failed > 0 )); then
  printf '\e[31m%d of %d cases failed\e[0m (%d assertions, %ds)\n' "$failed" "$total" "$assertions" "$((SECONDS - started))"
  exit 1
fi
printf '\e[32m%d cases passed\e[0m (%d assertions, %ds)\n' "$total" "$assertions" "$((SECONDS - started))"
