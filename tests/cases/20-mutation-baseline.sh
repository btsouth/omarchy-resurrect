# The mutation runner decides a mutation was caught when the suite goes red. A
# case that is red before anything has been broken therefore makes every mutation
# look caught, and the run reports a clean sweep over a suite that is not
# passing. That is worse than no run: it is a false claim of coverage, and it is
# how a mutation that changes nothing comes to be believed.
#
# So the runner checks the baseline first, and refuses to report on mutations
# when the suite does not pass on its own.
#
# This case runs the runner, and the runner runs the suite once per mutation, so
# under the runner it skips itself: three suites inside every mutation is time
# bought with nothing.

if [[ -n ${RESS_MUTATION_RUN:-} ]]; then
  echo "  (skipped: this case runs the mutation runner, and the runner is running)"
  return 0
fi

# ---- 1. a baseline that passes: the gate opens ------------------------------
#
# No mutation matches this filter, so the only thing this proves is the state the
# baseline check leaves the run in. It is the cheap half of the pair: a whole
# mutation would run the suite a second time.

OUT=$(cd "$REPO_DIR" && ./tests/mutate.sh no-such-mutation 2>&1); STATUS=$?
assert_ok "the runner starts when the suite passes"
assert_output "cases passed" "and says so before it begins"

# ---- 2. a baseline that fails: the gate closes ------------------------------
#
# A copy of the repo with one assertion deliberately broken. The runner must
# refuse to run, and must not report anything as caught.
#
# The copy runs with its own PATH. Leaving this tree's doubles on it as well puts
# two copies of each double in front of the real tool, and the git double
# resolves the real git by scanning PATH for one that is not itself: with two
# copies on the path they point at each other and the case hangs rather than
# failing. (The double also refuses to hand off to another copy now, which is the
# fix for anyone else who nests a suite inside a suite.)

COPY="$SANDBOX/red-baseline"
mkdir -p "$COPY"
rsync -a --exclude '.git/' "$REPO_DIR/" "$COPY/"
printf '\nassert_equals "1" "2" "a case that fails on purpose"\n' >>"$COPY/tests/cases/11-empty.sh"

COPY_PATH="${PATH//"$TESTS_DIR/bin":/}"
OUT=$(cd "$COPY" && PATH="$COPY_PATH" ./tests/mutate.sh aur-ignores-denylist 2>&1); STATUS=$?
assert_fails "the runner refuses to run against a suite that is already red"
assert_output "does not pass on its own" "and says why"
assert_output "11-empty" "and names the case that is red"
assert_no_output "mutations caught" "nothing is reported as caught"
assert_no_output "SURVIVED" "and no mutation was run at all"
