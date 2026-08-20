#!/bin/bash
#
# Test harness for ress.
#
# Every case runs against a throwaway $HOME with a PATH full of test doubles
# (tests/bin). Nothing here touches the real machine: no package is installed,
# no unit is enabled, and the fake `sudo` never elevates anything — it logs the
# call and runs the rest of the line as the current user.
#
# Sourced by tests/run.sh before each case; a case is a plain bash file that
# calls the helpers below.

set -uo pipefail

TESTS_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPO_DIR=$(dirname "$TESTS_DIR")
RESS="$REPO_DIR/bin/ress"

# ---------------------------------------------------------------- sandbox

# Set up a fresh $HOME, a fresh fake-machine state, and a PATH where the test
# doubles shadow the real tools. Called once per case by run.sh.
harness_setup() {
  SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/ress-test.XXXXXX")
  export SANDBOX

  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_DATA_HOME="$HOME/.local/share"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"

  # The fake machine the doubles read and write.
  export FAKE_STATE="$SANDBOX/machine"
  mkdir -p "$FAKE_STATE"
  : >"$FAKE_STATE/native.txt"
  : >"$FAKE_STATE/foreign.txt"
  : >"$FAKE_STATE/repo-packages.txt"
  : >"$FAKE_STATE/aur-packages.txt"
  : >"$FAKE_STATE/enabled-units.txt"
  : >"$FAKE_STATE/shell-running"

  # Every double appends one line per invocation. Cases assert on this.
  export CALLS="$SANDBOX/calls.log"
  : >"$CALLS"

  export PATH="$TESTS_DIR/bin:$PATH"

  # git needs an identity and must not read the developer's real config.
  export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null
  git config --file "$GIT_CONFIG_GLOBAL" user.name "Test User"
  git config --file "$GIT_CONFIG_GLOBAL" user.email "test@example.invalid"
  git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
  git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false

  # Colour off, so assertions match plain text.
  export TERM=dumb

  CASE_FAILURES=0
  CASE_ASSERTIONS=0
}

harness_teardown() {
  [[ -n ${SANDBOX:-} && -d ${SANDBOX:-} ]] && rm -rf "$SANDBOX"
  return 0
}

# ------------------------------------------------------------ fake machine

# machine_install <native|foreign> <pkg>...  — pretend these are installed.
machine_install() {
  local kind="$1"; shift
  printf '%s\n' "$@" >>"$FAKE_STATE/$kind.txt"
  sort -u -o "$FAKE_STATE/$kind.txt" "$FAKE_STATE/$kind.txt"
}

# machine_publish <repo|aur> <pkg>... — pretend these exist to be installed
# from. A package that is not published here fails to install, which is how a
# case exercises the failure paths.
machine_publish() {
  local kind="$1"; shift
  local file
  case "$kind" in
    repo) file="$FAKE_STATE/repo-packages.txt" ;;
    aur)  file="$FAKE_STATE/aur-packages.txt" ;;
    *) echo "machine_publish: unknown kind $kind" >&2; return 1 ;;
  esac
  printf '%s\n' "$@" >>"$file"
  sort -u -o "$file" "$file"
}

machine_enable_unit() {
  printf '%s\n' "$@" >>"$FAKE_STATE/enabled-units.txt"
  sort -u -o "$FAKE_STATE/enabled-units.txt" "$FAKE_STATE/enabled-units.txt"
}

machine_shell_running() { printf 'yes' >"$FAKE_STATE/shell-running"; }
machine_shell_stopped() { : >"$FAKE_STATE/shell-running"; }

# The AUR RPC answer the fake curl serves. Names listed here "exist" in the AUR.
machine_aur_rpc() {
  printf '%s\n' "$@" >>"$FAKE_STATE/aur-rpc.txt"
  sort -u -o "$FAKE_STATE/aur-rpc.txt" "$FAKE_STATE/aur-rpc.txt"
}

machine_aur_offline() { printf 'offline' >"$FAKE_STATE/aur-rpc-offline"; }

# ------------------------------------------------------------------ ress

# Run the CLI. Stdout+stderr land in $OUT, the exit code in $STATUS.
# Anything on stdin is fed to the process, so a case can answer prompts.
ress() {
  OUT=$("$RESS" "$@" 2>&1)
  STATUS=$?
  printf '%s' "$OUT"
  return 0
}

# Same, with a canned answer sequence for interactive prompts. Each argument
# before -- is one line of stdin.
#
# Run under script(1) for a pty: ress refuses to prompt without a terminal, so
# a plain pipe would exercise the non-interactive path instead of the prompt.
# The pty's \r is stripped so assertions can match ordinary text.
ress_answer() {
  local answers=()
  while (( $# > 0 )) && [[ $1 != "--" ]]; do answers+=("$1"); shift; done
  shift || true
  local cmd; cmd=$(printf '%q ' "$RESS" "$@")
  # Written to a file rather than captured inline: PIPESTATUS is only readable
  # after a real pipeline, and $(a | b) makes the whole thing one command.
  local tmp="$SANDBOX/run.out"
  printf '%s\n' "${answers[@]:-}" | script -qe -c "$cmd" /dev/null >"$tmp" 2>&1
  STATUS=${PIPESTATUS[1]}
  OUT=$(tr -d '\r' <"$tmp")
  printf '%s' "$OUT"
  return 0
}

# A run with a terminal but no answers queued: every prompt reads EOF, which is
# a "no". Used to prove a prompt is reached at all.
ress_tty() {
  local cmd; cmd=$(printf '%q ' "$RESS" "$@")
  OUT=$(script -qe -c "$cmd" /dev/null </dev/null 2>&1 | tr -d '\r')
  STATUS=$?
  printf '%s' "$OUT"
  return 0
}

# ------------------------------------------------------------- assertions

_pass() { CASE_ASSERTIONS=$((CASE_ASSERTIONS + 1)); }
_fail() {
  CASE_ASSERTIONS=$((CASE_ASSERTIONS + 1))
  CASE_FAILURES=$((CASE_FAILURES + 1))
  printf '    \e[31mFAIL\e[0m %s\n' "$1" >&2
  [[ -n ${2:-} ]] && printf '%s\n' "$2" | sed 's/^/         /' >&2
  return 0
}

assert_ok() {
  local what="${1:-command succeeded}"
  (( STATUS == 0 )) && _pass || _fail "$what (exit $STATUS)" "$OUT"
}

assert_fails() {
  local what="${1:-command failed}"
  (( STATUS != 0 )) && _pass || _fail "$what — expected non-zero exit" "$OUT"
}

assert_exit() {
  local want="$1" what="${2:-exit code}"
  (( STATUS == want )) && _pass || _fail "$what: want $want, got $STATUS" "$OUT"
}

assert_output() {
  local needle="$1" what="${2:-output contains \"$1\"}"
  [[ $OUT == *"$needle"* ]] && _pass || _fail "$what" "$OUT"
}

assert_no_output() {
  local needle="$1" what="${2:-output does not contain \"$1\"}"
  [[ $OUT != *"$needle"* ]] && _pass || _fail "$what" "$OUT"
}

assert_file() {
  local path="$1" what="${2:-$1 exists}"
  [[ -f $path ]] && _pass || _fail "$what"
}

assert_no_file() {
  local path="$1" what="${2:-$1 does not exist}"
  [[ ! -e $path ]] && _pass || _fail "$what"
}

assert_dir() {
  local path="$1" what="${2:-$1 is a directory}"
  [[ -d $path ]] && _pass || _fail "$what"
}

assert_file_contains() {
  local path="$1" needle="$2" what="${3:-$1 contains \"$2\"}"
  [[ -f $path ]] || { _fail "$what — file missing"; return 0; }
  grep -qF -- "$needle" "$path" && _pass || _fail "$what" "$(cat "$path")"
}

assert_file_lacks() {
  local path="$1" needle="$2" what="${3:-$1 does not contain \"$2\"}"
  [[ -f $path ]] || { _pass; return 0; }
  grep -qF -- "$needle" "$path" && _fail "$what" "$(cat "$path")" || _pass
}

# A test double logged this command line.
assert_called() {
  local needle="$1" what="${2:-a double was called with \"$1\"}"
  grep -qF -- "$needle" "$CALLS" && _pass || _fail "$what" "$(cat "$CALLS")"
}

assert_not_called() {
  local needle="$1" what="${2:-no double was called with \"$1\"}"
  grep -qF -- "$needle" "$CALLS" && _fail "$what" "$(cat "$CALLS")" || _pass
}

assert_equals() {
  local got="$1" want="$2" what="${3:-value}"
  [[ $got == "$want" ]] && _pass || _fail "$what: want \"$want\", got \"$got\""
}

# ------------------------------------------------------------------ setup

# The shape of a machine most cases want: a vault, a couple of packages, a
# dotfile, a plugin, a web app.
seed_machine() {
  machine_install native bash git rsync
  machine_publish repo bash git rsync

  mkdir -p "$HOME/.config/hypr" "$HOME/.local/bin"
  printf 'bind = SUPER, Q, killactive\n' >"$HOME/.config/hypr/hyprland.conf"
  printf 'alias ll="ls -l"\n' >"$HOME/.bashrc"

  mkdir -p "$HOME/.config/omarchy"
  printf '{"bar":{"layout":{"right":[{"id":"omarchy.clock"}]}}}\n' >"$HOME/.config/omarchy/shell.json"
}

seed_plugin() {
  local id="$1" remote="${2:-https://github.com/example/$1}"
  local dir="$HOME/.config/omarchy/plugins/$id"
  mkdir -p "$dir"
  printf '{"schemaVersion":1,"id":"%s","name":"%s","version":"1.0.0","kinds":["service"],"entryPoints":{"service":"S.qml"}}\n' \
    "$id" "$id" >"$dir/manifest.json"
  : >"$dir/S.qml"
  git -C "$dir" init -q -b main
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "seed"
  git -C "$dir" remote add origin "$remote"
}

seed_webapp() {
  local name="$1" url="$2"
  mkdir -p "$HOME/.local/share/applications"
  cat >"$HOME/.local/share/applications/$name.desktop" <<DESKTOP
[Desktop Entry]
Name=$name
Exec=omarchy-launch-webapp $url
Icon=$name
Type=Application
DESKTOP
}

# Publish a fake upstream at $FAKE_STATE/remotes/<name>, referenced by cases and
# by vaults as https://github.com/example/<name>. Prints the commit sha, which
# is what a vault records and what a pinned clone asks for.
#
#   seed_remote plugin <name> <plugin-id>
#   seed_remote theme  <name>
seed_remote() {
  local kind="$1" name="$2" id="${3:-}"
  local dir="$FAKE_STATE/remotes/$name"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  case "$kind" in
    plugin)
      printf '{"schemaVersion":1,"id":"%s","name":"%s","version":"1.0.0","kinds":["service"],"entryPoints":{"service":"S.qml"}}\n' \
        "$id" "$id" >"$dir/manifest.json"
      : >"$dir/S.qml"
      ;;
    theme)
      printf 'background = "#000000"\n' >"$dir/theme.conf"
      ;;
    *) echo "seed_remote: unknown kind $kind" >&2; return 1 ;;
  esac
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "seed $kind $name"
  git -C "$dir" rev-parse HEAD
}

remote_url() { printf 'https://github.com/example/%s' "$1"; }

# A vault built by hand, which is how a case models "someone else's vault"
# without pretending to be another machine. Returns the path.
make_vault() {
  local dir="${1:-$SANDBOX/foreign-vault}"
  mkdir -p "$dir"/{packages,home,omarchy,webapps/apps,webapps/icons,plugins,services,report}
  : >"$dir/packages/native.txt"
  : >"$dir/packages/foreign.txt"
  : >"$dir/plugins/plugins.tsv"
  : >"$dir/services/user-units.txt"
  : >"$dir/omarchy/themes.tsv"
  git -C "$dir" init -q -b main
  printf '%s' "$dir"
}

# Finish a hand-built vault: write its manifest and commit, so restore accepts
# it. Mirrors what `ress backup` would have left behind.
seal_vault() {
  local dir="$1" host="${2:-otherbox}"
  jq -n --arg host "$host" \
    '{schemaVersion: 1, ressVersion: "1.1.0", createdAt: "2026-01-01T00:00:00Z",
      machine: {hostname: $host, user: "someone", omarchy: "4.0.0", kernel: "6.0"},
      categories: ["packages","config","omarchy","webapps","plugins"],
      counts: {packages: 0, config: 0, themes: 0, webapps: 0, plugins: 0, secrets: 0, uncaptured: 0, services: 0}}' \
    >"$dir/ress.json"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "vault"
}
