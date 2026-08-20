#!/bin/bash
#
# Shared by every test double. Sourced, never run.
#
# These are test doubles, not tools: they model just enough of a machine for a
# case to assert on. None of them changes anything outside $SANDBOX.

log_call() {
  [[ -n ${CALLS:-} ]] || return 0
  printf '%s\n' "$*" >>"$CALLS"
  return 0
}

state() { printf '%s' "${FAKE_STATE:?FAKE_STATE is not set — run through tests/run.sh}"; }

# Everything after the last `--`, which is how ress closes an option list.
args_after_dashdash() {
  local seen=0 arg
  for arg in "$@"; do
    if (( seen )); then printf '%s\n' "$arg"; continue; fi
    [[ $arg == "--" ]] && seen=1
  done
}

installed_all() { sort -u "$(state)/native.txt" "$(state)/foreign.txt" 2>/dev/null | grep -v '^$' || true; }

is_installed() { installed_all | grep -qxF "$1"; }
