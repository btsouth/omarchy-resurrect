# A source that names its own transport reaches git as given. ssh:// and the scp
# form git@host:path are both accepted for your own vault (see valid_git_remote),
# so neither may be rewritten into https://ssh://host/... on the way to a clone.

seed_machine
machine_publish repo ripgrep

V=$(make_vault "$FAKE_STATE/remotes/mine")
mkdir -p "$V/home"
printf 'from the ssh vault\n' >"$V/home/.bashrc"
printf 'ripgrep\n' >"$V/packages/native.txt"
seal_vault "$V" "mine-box"

# ---- 1. ssh:// is passed through, and the preview really clones it ---------

ress restore --from ssh://git@ssh.example/mine --dry-run
assert_ok "restore --from with an ssh URL"
assert_no_output "https://ssh://" "nothing is prepended to a source that has a scheme"
assert_output "ssh://ssh.example/mine" "the preview names the URL it was handed"
assert_called "git clone -q --depth 1 -- ssh://git@ssh.example/mine" \
  "git is handed the ssh URL verbatim"

# ---- 2. the scp form is passed through too --------------------------------

ress restore --from git@ssh.example:mine --dry-run
assert_ok "restore --from with the scp form"
assert_output "git@ssh.example:mine" "the preview names the scp URL as given"
assert_no_output "https://git@" "the scp form is not pushed through https"

# ---- 3. and the shorthands it was written for are unchanged ---------------

ress restore --from "$(remote_url mine)" --dry-run
assert_ok "restore --from with an https URL"
assert_output "https://github.com/example/mine" "an https URL is still named in full"

ress restore --from github.com/example/mine --dry-run
assert_ok "restore --from with the bare host form"
assert_output "https://github.com/example/mine" "a bare host form still gains https"

# ---- 4. a real restore, not just a preview, over the ssh form -------------

ress_answer "y" "y" -- restore --from ssh://git@ssh.example/mine --restart --only config
assert_ok "a real restore over ssh"
assert_file_contains "$HOME/.bashrc" "from the ssh vault" "the vault's file arrived"
