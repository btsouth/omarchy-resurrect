# A dry run says what every category would do, and does none of it.

seed_machine
machine_publish repo ripgrep
machine_publish aur brave-bin
machine_aur_rpc brave-bin
machine_shell_running

THEME_SHA=$(seed_remote theme rose-pine)
PLUGIN_SHA=$(seed_remote plugin some-widget acme.widget)

VAULT=$(make_vault)

# packages
printf 'ripgrep\n' >"$VAULT/packages/native.txt"
printf 'brave-bin\n' >"$VAULT/packages/foreign.txt"

# dotfiles and a unit
mkdir -p "$VAULT/home/.config/systemd/user"
printf 'from the vault\n' >"$VAULT/home/.bashrc"
printf '[Service]\nExecStart=/usr/bin/syncthing serve\n[Install]\nWantedBy=default.target\n' \
  >"$VAULT/home/.config/systemd/user/syncthing.service"
printf 'syncthing.service\n' >"$VAULT/services/user-units.txt"

# omarchy state: hooks, a pinned theme, a local theme, an unpinned one, a layout
mkdir -p "$VAULT/omarchy/hooks" "$VAULT/omarchy/themes/handmade"
printf '#!/bin/sh\necho hi\n' >"$VAULT/omarchy/hooks/post-update"
printf 'background = "#111111"\n' >"$VAULT/omarchy/themes/handmade/theme.conf"
{
  printf 'rose-pine\t%s\t%s\n' "$(remote_url rose-pine)" "$THEME_SHA"
  printf 'handmade\t\t\n'
  printf 'driftwood\t%s\t\n' "$(remote_url driftwood)"
} >"$VAULT/omarchy/themes.tsv"
printf '{"bar":{"layout":{"right":[{"id":"omarchy.clock"},{"id":"acme.widget"}]}}}\n' >"$VAULT/omarchy/shell.json"
printf 'rose-pine\n' >"$VAULT/omarchy/theme.name"

# a plugin and a web app
printf 'acme.widget\t%s\t1\t%s\n' "$(remote_url some-widget)" "$PLUGIN_SHA" >"$VAULT/plugins/plugins.tsv"
cat >"$VAULT/webapps/apps/Excalidraw.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Excalidraw
Exec=omarchy-launch-webapp https://excalidraw.com
Icon=Excalidraw
Type=Application
DESKTOP

seal_vault "$VAULT"

ress --vault "$VAULT" restore --dry-run
assert_ok "dry run"

# ---- what it says ---------------------------------------------------------

assert_output "from the Arch repos"
assert_output "ripgrep"
assert_output "built from the AUR"
assert_output "brave-bin"

assert_output ".bashrc" "the dotfile plan names files"

assert_output "syncthing.service" "the unit plan names the unit"
assert_output "/usr/bin/syncthing serve" "and what it would run"
assert_output "you would be asked before any of them is enabled"

assert_output "hooks" "the omarchy plan names hooks"
assert_output "run on update, boot and theme change" "and says what a hook is"
assert_output "rose-pine" "a pinned theme is named"
assert_output "pinned to ${THEME_SHA:0:12}" "with the commit it would be pinned to"
assert_output "from files in the vault" "a hand-made theme travels as files"
assert_output "driftwood" "an unpinned theme is named"
assert_output "no recorded commit" "and says why it would be skipped"
assert_output "bar layout" "the bar layout is named"
assert_output "acme.widget" "with the widgets in it"
assert_output "active theme" "the theme change is named"

assert_output "Excalidraw" "the web app is named"
assert_output "never by copying its .desktop file"

# ---- and does none of it --------------------------------------------------

assert_not_called "pacman -S --needed" "no package is installed"
assert_not_called "yay -S" "nothing is built"
assert_not_called "systemctl --user enable" "no unit is enabled"
assert_not_called "omarchy webapp install" "no web app is rebuilt"
assert_not_called "omarchy-theme-set" "no theme is applied"
assert_file_contains "$HOME/.bashrc" "alias ll" "the real dotfile is untouched"
assert_no_file "$HOME/.config/omarchy/themes/rose-pine" "no theme is cloned"
assert_no_file "$HOME/.config/omarchy/themes" "a dry run does not even make the directory"
assert_no_file "$HOME/.config/omarchy/plugins/acme.widget" "no plugin is cloned"
assert_no_file "$HOME/.local/state/ress/restore.state" "a dry run records no progress"

# ---- the plan matches what the restore then does --------------------------

ress --vault "$VAULT" restore --yes --aur
assert_ok "the real restore"
assert_dir "$HOME/.config/omarchy/themes/rose-pine" "the pinned theme arrived"
assert_dir "$HOME/.config/omarchy/themes/handmade" "the vault's own theme arrived"
assert_no_file "$HOME/.config/omarchy/themes/driftwood" "the unpinned theme did not, as promised"
assert_output "no recorded commit" "and said so again"
assert_dir "$HOME/.config/omarchy/plugins/acme.widget" "the plugin arrived"
assert_called "omarchy webapp install Excalidraw https://excalidraw.com"
assert_called "yay -S --needed --noconfirm --answerclean None --answerdiff None -- brave-bin"
