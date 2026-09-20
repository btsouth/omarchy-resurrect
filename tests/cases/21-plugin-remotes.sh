# A plugin or a theme whose git remote a restore will not take is a gap the vault
# cannot close by itself: the far side has no way to fetch the code, and the
# machine that holds the checkout is the only one that can push it somewhere git
# can reach. Saying so at capture is the difference between a backup that reports
# what it holds and one that reports what it kept.
#
# The case worth naming: a plugin developed in a working directory, with a
# `file://` remote. Nothing warns, the restore then refuses it as an unsafe
# remote, and the first machine to say anything is the one that cannot fix it.

seed_machine
machine_shell_running

# One installed from somewhere git can fetch, one developed in a working
# directory, and one with no remote at all.
seed_plugin acme.widget
seed_plugin local.checkout file:///home/someone/Projects/checkout
seed_plugin hand.made
git -C "$HOME/.config/omarchy/plugins/hand.made" remote remove origin

# A theme the same way.
mkdir -p "$HOME/.config/omarchy/themes/local-theme"
printf 'background = "#111111"\n' >"$HOME/.config/omarchy/themes/local-theme/theme.conf"
git -C "$HOME/.config/omarchy/themes/local-theme" init -q -b main
git -C "$HOME/.config/omarchy/themes/local-theme" add -A
git -C "$HOME/.config/omarchy/themes/local-theme" -c commit.gpgsign=false commit -q -m theme
git -C "$HOME/.config/omarchy/themes/local-theme" remote add origin file:///tmp/themes/local-theme

ress init >/dev/null
VAULT="$XDG_DATA_HOME/ress/vault"

# ---- 1. the capture says which ones will not travel ------------------------

ress backup -m remotes
assert_ok "a backup beside remotes a restore will not take"
assert_output "will not be restored" "the capture says a plugin will not travel"
assert_output "local.checkout" "and names it"
assert_output "hand.made" "and the one with no remote at all"
assert_output "not one a restore will clone" "and says why"
assert_output "theme local-theme" "the theme with the same problem is named too"
assert_file_contains "$VAULT/plugins/plugins.tsv" "local.checkout" \
  "the plugin is still recorded: the vault is a record of what was here"

# ---- 2. verify does not ask for what a restore cannot do -------------------

ress --vault "$VAULT" verify --json
assert_ok "verify passes: everything it can count is here"
assert_equals "$(jq -r '.categories.plugins.want' <<<"$OUT")" "1" \
  "only the plugin with a remote a restore can clone is counted"
assert_equals "$(jq -r '.categories.plugins.have' <<<"$OUT")" "1" "and it is here"
assert_equals "$(jq -r '.categories.plugins.missing | length' <<<"$OUT")" "0" \
  "nothing is missing, because nothing restorable is"
assert_equals "$(jq -r '.categories.plugins.refused | sort | join(",")' <<<"$OUT")" \
  "hand.made,local.checkout" "the two that cannot be re-cloned are refused instead"

ress --vault "$VAULT" verify
assert_output "2 entries a restore cannot rebuild" "and the text says so in English"
assert_output "hand.made" "naming them"
