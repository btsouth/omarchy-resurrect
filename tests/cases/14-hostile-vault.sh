# A vault is a git repository, and `restore --from` fetches one over the
# network. Everything read out of it is attacker-controlled until it matches a
# validator. These are the cases where it does not match.

seed_machine
machine_shell_running

VAULT=$(make_vault)

# ---- names that must never reach a command line --------------------------

{
  printf -- '--overwrite=/etc/passwd\n'
  printf -- '-Rns\n'
  printf '../../../etc/shadow\n'
  printf 'legit-package\n'
} >"$VAULT/packages/native.txt"
printf -- '--asdeps\n../../evil\n' >"$VAULT/packages/foreign.txt"
machine_publish repo legit-package

{
  printf -- '../../../etc\t\t\n'
  printf 'Fine-Theme\t\t\n'
  printf 'ok-theme\thttps://github.com/example/ok-theme\tnot-a-sha\n'
  printf 'evil-theme\tfile:///etc\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
  printf 'ssh-theme\t-oProxyCommand=touch /tmp/pwned\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
} >"$VAULT/omarchy/themes.tsv"

{
  printf -- '../../../../tmp/evil\thttps://github.com/example/x\t1\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
  printf -- 'ok.plugin\t-uroot\t1\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
  printf -- 'local.plugin\tfile:///etc\t1\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
} >"$VAULT/plugins/plugins.tsv"

printf -- '--now\n../../etc/evil.service\nfine.service\n' >"$VAULT/services/user-units.txt"

# A launcher whose Exec is not the plain webapp form, and one with a second
# Exec line hiding a Desktop Action.
cat >"$VAULT/webapps/apps/Evil.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Evil
Exec=rm -rf /home
Icon=evil
Type=Application
DESKTOP
cat >"$VAULT/webapps/apps/Sneaky.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Sneaky
Exec=omarchy-launch-webapp https://example.com
Exec=touch /tmp/pwned
Icon=sneaky
Type=Application
DESKTOP

seal_vault "$VAULT" "hostile"

ress --vault "$VAULT" restore --yes --aur
assert_ok "the restore survives a vault full of bad input"

# Nothing option-shaped or traversing reached a command line.
assert_not_called "overwrite" "an option-shaped package name is refused"
assert_not_called "Rns" "so is a remove flag"
assert_not_called "etc/shadow"
assert_not_called "asdeps"
assert_not_called "enable -- --now"
assert_not_called "evil.service"
assert_not_called "ProxyCommand" "an ssh option smuggled in as a theme remote is refused"
assert_not_called "webapp install Evil" "a launcher that is not the plain webapp form is refused"
assert_not_called "webapp install Sneaky" "and so is one with a second Exec line"
assert_output "refused"

# The one valid package still installed: refusing bad input is not refusing all.
assert_called "pacman -S --needed --noconfirm -- legit-package"

# Nothing was created outside $HOME.
assert_no_file "/tmp/pwned" "nothing escaped to /tmp"
assert_no_file "$HOME/.config/omarchy/themes/../../../etc"
assert_no_file "$HOME/.config/omarchy/plugins/../../../../tmp/evil"

# A theme with an unusable remote is not cloned, and a malformed commit is not
# treated as a pin.
assert_no_file "$HOME/.config/omarchy/themes/evil-theme"
assert_no_file "$HOME/.config/omarchy/themes/ok-theme"
assert_no_file "$HOME/.config/omarchy/plugins/local.plugin"

# ---- a filename that tries to repaint the terminal ------------------------

ress init >/dev/null
mkdir -p "$HOME/.local/bin"
printf 'TOKEN=ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8\n' \
  >"$HOME/.local/bin/$(printf 'deploy\033[31m')"
ress backup -m hostile
assert_ok "backup with a hostile filename"
assert_output "Possible credentials in the vault"
BAD=$(printf '%s' "$OUT" | grep -c "$(printf '\033')\[31m" || true)
assert_equals "$BAD" "0" "the finding list carries no escape sequence from the filename"
