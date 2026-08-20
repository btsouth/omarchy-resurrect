# A vault fetched from a URL this machine has not used before is not treated as
# less trustworthy — a fresh install replaying its owner's vault is always first
# contact — but nothing is assumed about it either.

seed_machine

# Two vaults published as fake upstreams.
for name in mine theirs; do
  V=$(make_vault "$FAKE_STATE/remotes/$name")
  mkdir -p "$V/home"
  printf 'from %s\n' "$name" >"$V/home/.bashrc"
  printf 'somepkg\n' >"$V/packages/native.txt"
  printf 'plain.plugin\t\t1\t\n' >"$V/plugins/plugins.tsv"
  seal_vault "$V" "$name-box"
done
machine_publish repo somepkg

ress init --remote "$(remote_url mine)" >/dev/null
assert_ok "init with a remote"

# ---- 1. a URL this machine already backs up to is not first contact -------

ress_answer "y" "y" -- restore --from "$(remote_url mine)" --only config
assert_ok "restore from the configured remote"
assert_no_output "has not restored from this vault before"
assert_file_contains "$HOME/.bashrc" "from mine"

# ---- 2. a different URL is ------------------------------------------------

ress_answer "y" "y" -- restore --from "$(remote_url theirs)" --restart --only config
assert_ok "restore from elsewhere"
assert_output "has not restored from this vault before"
assert_file_contains "$HOME/.bashrc" "from theirs"

# The prompt said the remote would move, and it did.
assert_output "back up there from now on"
assert_equals "$(sed -n 's/^REMOTE=//p' "$XDG_CONFIG_HOME/ress/config")" "$(remote_url theirs)" \
  "the vault remote follows the vault"

# ---- 3. .git URLs and trailing slashes are the same URL -------------------

ress set REMOTE="$(remote_url theirs).git" >/dev/null
ress_answer "y" "y" -- restore --from "$(remote_url theirs)/" --restart --only config
assert_no_output "has not restored from this vault before" "a trailing slash is not a different repo"
ress set REMOTE="$(remote_url theirs)" >/dev/null

# ---- 4. --allow-unpinned on first contact asks a second time -------------

ress_answer "y" "n" -- restore --from "$(remote_url mine)" --restart --only plugins --allow-unpinned
assert_fails "declining the unpinned question cancels the restore"
assert_output "allow-unpinned on a vault this machine has not used before"
assert_output "Take branch heads from this vault?"
assert_output "cancelled"

# Accepting it proceeds. (The plugin itself has no remote, so nothing is
# cloned — what is under test is the question, not the clone.)
ress_answer "y" "y" "y" -- restore --from "$(remote_url mine)" --restart --only plugins --allow-unpinned
assert_ok "accepting the unpinned question proceeds"

# ---- 5. no second question when the vault is one this machine uses -------

ress set REMOTE="$(remote_url mine)" >/dev/null
ress_answer "y" "y" -- restore --from "$(remote_url mine)" --restart --only plugins --allow-unpinned
assert_ok "restore from the configured remote with --allow-unpinned"
assert_no_output "Take branch heads from this vault?"
