# `ress apply` installs someone else's loadout: a preview, one confirmation,
# and the same AUR question a restore asks — because a loadout comes from a
# stranger by design.

seed_machine
machine_publish repo ripgrep fd
machine_publish aur brave-bin
machine_aur_rpc brave-bin
machine_shell_running

PLUGIN_SHA=$(seed_remote plugin some-widget acme.widget)
THEME_SHA=$(seed_remote theme rose-pine)

PROFILE="$SANDBOX/loadout"
mkdir -p "$PROFILE"
jq -n --arg url "$(remote_url some-widget)" --arg sha "$PLUGIN_SHA" \
      --arg turl "$(remote_url rose-pine)" --arg tsha "$THEME_SHA" '
{
  schemaVersion: 1, kind: "omarchy-loadout", name: "Someone Else’s Rig",
  author: "a stranger", description: "for testing", createdAt: "2026-01-01T00:00:00Z",
  omarchy: "4.0.0",
  packages: {native: ["ripgrep", "fd"], aur: ["brave-bin"]},
  plugins: [{id: "acme.widget", url: $url, commit: $sha}],
  webapps: [{name: "Excalidraw", url: "https://excalidraw.com", icon: "excalidraw"}],
  theme: {name: "rose-pine", url: $turl, commit: $tsha}
}' >"$PROFILE/profile.json"

# ---- 1. the dry run installs nothing --------------------------------------

ress apply --dry-run "$PROFILE"
assert_ok "apply --dry-run"
assert_output "Someone Else" "the loadout names itself"
assert_output "2 packages from the Arch repos"
assert_output "1 package from the AUR"
assert_output "built here from a PKGBUILD"
assert_output "acme.widget"
assert_output "Excalidraw"
assert_output "rose-pine"
assert_output "Dry run — nothing was installed"
assert_not_called "pacman -S --needed"
assert_not_called "yay -S"

# ---- 2. declining installs nothing ----------------------------------------

ress_answer "n" -- apply "$PROFILE"
assert_fails "declining cancels"
assert_output "cancelled"
assert_not_called "pacman -S --needed"

# ---- 3. accepting the loadout still asks about the AUR separately ---------

ress_answer "y" "n" -- apply "$PROFILE"
assert_ok "apply, AUR declined"
assert_called "pacman -S --needed --noconfirm -- fd ripgrep" "repo packages install"
assert_not_called "yay -S" "the AUR question is asked on its own, and was answered no"
assert_output "PKGBUILD fetched from aur.archlinux.org"
assert_dir "$HOME/.config/omarchy/plugins/acme.widget" "the pinned plugin is cloned"
assert_called "omarchy webapp install Excalidraw https://excalidraw.com"
assert_dir "$HOME/.config/omarchy/themes/rose-pine" "the pinned theme is cloned"

# The plugin is checked out at the commit the loadout named, not at a branch.
assert_equals "$(git -C "$HOME/.config/omarchy/plugins/acme.widget" rev-parse HEAD)" "$PLUGIN_SHA" \
  "cloned at the commit the loadout named"

# ---- 4. --aur answers it up front -----------------------------------------

rm -rf "$HOME/.config/omarchy/plugins/acme.widget"
: >"$FAKE_STATE/native.txt"; : >"$CALLS"
ress apply --yes --aur "$PROFILE"
assert_ok "apply --yes --aur"
assert_called "yay -S --needed --noconfirm --answerclean None --answerdiff None -- brave-bin"

# ---- 5. an unpinned loadout is refused unless asked for -------------------

jq 'del(.plugins[0].commit) | del(.theme.commit)' "$PROFILE/profile.json" >"$PROFILE/unpinned.json"
mv "$PROFILE/unpinned.json" "$PROFILE/profile.json"
rm -rf "$HOME/.config/omarchy/plugins/acme.widget" "$HOME/.config/omarchy/themes/rose-pine"

ress apply --dry-run "$PROFILE"
assert_output "names no commit" "an unpinned plugin is called out"
assert_no_output "acme.widget  " "and is not listed as something that will be installed"

ress apply --yes --no-aur "$PROFILE"
assert_no_file "$HOME/.config/omarchy/plugins/acme.widget/manifest.json" "and is not installed"

ress apply --yes --no-aur --allow-unpinned "$PROFILE"
assert_ok "with --allow-unpinned it is"
assert_dir "$HOME/.config/omarchy/plugins/acme.widget"

# ---- 6. a loadout cannot smuggle a command through a package name --------

jq '.packages.native = ["--overwrite=/etc/passwd", "ripgrep"]' "$PROFILE/profile.json" >"$PROFILE/evil.json"
mv "$PROFILE/evil.json" "$PROFILE/profile.json"
: >"$FAKE_STATE/native.txt"; : >"$CALLS"
ress apply --yes --no-aur "$PROFILE"
assert_output "refused 1 unsafe package names"
assert_not_called "overwrite" "an option-shaped name never reaches pacman"
assert_called "pacman -S --needed --noconfirm -- ripgrep" "and the rest still installs"
