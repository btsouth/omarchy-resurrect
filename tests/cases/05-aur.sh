# Building an AUR package runs a PKGBUILD from aur.archlinux.org on this
# machine. Nothing does that without being asked.

seed_machine
machine_publish repo ripgrep
machine_publish aur brave-bin ttf-fancy questionable
machine_aur_rpc brave-bin ttf-fancy          # `questionable` is not in the AUR

VAULT=$(make_vault)
printf 'ripgrep\n' >"$VAULT/packages/native.txt"
printf 'brave-bin\nttf-fancy\nquestionable\n' >"$VAULT/packages/foreign.txt"
seal_vault "$VAULT"

# ---- 1. no terminal: repo packages yes, AUR packages no -------------------

ress --vault "$VAULT" restore --yes --only packages
assert_ok "restore"
assert_called "pacman -S --needed --noconfirm -- ripgrep" "repo packages still install"
assert_not_called "yay -S" "no PKGBUILD is built without being asked"
assert_output "no terminal to ask at"
assert_output "pass --aur"

# Declining is not a failure, but it is not finished either: it is offered again.
assert_output "Left for later"
assert_output "ress restore --only packages --aur"
: >"$CALLS"
ress --vault "$VAULT" restore --yes --only packages
assert_output "no terminal to ask at" "the deferred step is offered again, not skipped as done"

# ---- 2. the prompt names what it is about to build ------------------------

ress_answer "n" -- --vault "$VAULT" restore --yes --restart --only packages
assert_output "3 packages from the AUR"
assert_output "brave-bin"
assert_output "PKGBUILD fetched from aur.archlinux.org"
assert_output "questionable"
assert_output "not on aur.archlinux.org" "a name with nothing behind it is called out"
assert_not_called "yay -S" "answering no builds nothing"

# ---- 3. answering yes builds them -----------------------------------------

: >"$CALLS"
ress_answer "y" -- --vault "$VAULT" restore --yes --restart --only packages
assert_ok "restore, AUR accepted"
assert_called "yay -S --needed --noconfirm --answerclean None --answerdiff None -- brave-bin questionable ttf-fancy"
assert_output "AUR packages installed"

# ---- 4. r reviews: yay keeps its own prompts ------------------------------

: >"$FAKE_STATE/foreign.txt"; : >"$CALLS"
ress_answer "r" -- --vault "$VAULT" restore --yes --restart --only packages
assert_ok "restore, AUR reviewed"
assert_called "yay -S --needed -- brave-bin" "review mode drops --noconfirm and the answer flags"
assert_not_called "--answerdiff None" "review mode does not answer the PKGBUILD diff for you"
assert_output "yay will show each PKGBUILD"

# ---- 5. --aur and --no-aur skip the question ------------------------------

: >"$FAKE_STATE/foreign.txt"; : >"$CALLS"
ress --vault "$VAULT" restore --yes --restart --only packages --aur
assert_called "yay -S --needed --noconfirm" "--aur builds without a terminal"

: >"$FAKE_STATE/foreign.txt"; : >"$CALLS"
ress --vault "$VAULT" restore --yes --restart --only packages --no-aur
assert_not_called "yay -S"
assert_output "AUR=no"

: >"$FAKE_STATE/foreign.txt"; : >"$CALLS"
ress --vault "$VAULT" restore --yes --restart --only packages --review-aur
assert_called "yay -S --needed -- brave-bin" "--review-aur builds with yay's own review"

# ---- 6. the AUR setting ---------------------------------------------------

: >"$FAKE_STATE/foreign.txt"; : >"$CALLS"
ress set AUR=yes >/dev/null
ress --vault "$VAULT" restore --yes --restart --only packages
assert_called "yay -S --needed --noconfirm" "AUR=yes builds unattended"
ress set AUR=ask >/dev/null

# ---- 7. the deny list -----------------------------------------------------

: >"$FAKE_STATE/foreign.txt"; : >"$CALLS"
printf '# mine\nquestionable\n' >"$XDG_CONFIG_HOME/ress/aur-deny"
ress --vault "$VAULT" restore --yes --restart --only packages --aur
assert_output "1 AUR package on your deny list: questionable"
assert_called "yay -S --needed --noconfirm --answerclean None --answerdiff None -- brave-bin ttf-fancy"
assert_not_called "questionable" "a denied name never reaches the helper"

# A deny list covering everything leaves nothing to ask about.
: >"$FAKE_STATE/foreign.txt"; : >"$CALLS"
printf 'brave-bin\nttf-fancy\nquestionable\n' >"$XDG_CONFIG_HOME/ress/aur-deny"
ress --vault "$VAULT" restore --yes --restart --only packages --aur
assert_not_called "yay -S"
assert_output "3 AUR packages on your deny list"
rm -f "$XDG_CONFIG_HOME/ress/aur-deny"

# ---- 8. the AUR being unreachable annotates, it does not block ------------

: >"$FAKE_STATE/foreign.txt"; : >"$CALLS"
machine_aur_offline
ress_answer "y" -- --vault "$VAULT" restore --yes --restart --only packages
assert_output "could not reach aur.archlinux.org"
assert_called "yay -S --needed --noconfirm" "an unreachable AUR does not stop a build you asked for"

# ---- 9. the dry run separates the two lists ------------------------------

rm -f "$FAKE_STATE/aur-rpc-offline"
: >"$FAKE_STATE/foreign.txt"; : >"$FAKE_STATE/native.txt"; : >"$CALLS"
ress --vault "$VAULT" restore --dry-run --only packages
assert_ok "dry run"
assert_output "from the Arch repos"
assert_output "built from the AUR"
assert_not_called "yay -S" "a dry run builds nothing"
assert_not_called "pacman -S --needed" "a dry run installs nothing"

# ---- 10. a name the official repos have since picked up -------------------

: >"$FAKE_STATE/foreign.txt"; : >"$CALLS"
machine_publish repo ttf-fancy
ress_answer "n" -- --vault "$VAULT" restore --yes --restart --only packages
assert_output "now in the official repos" "a package that moved into the repos is called out"
assert_not_called "yay -S" "and still nothing is built without a yes"

# ---- 11. end of input at the AUR prompt -----------------------------------

: >"$FAKE_STATE/foreign.txt"; : >"$CALLS"
ress_tty --vault "$VAULT" restore --yes --restart --only packages
assert_ok "Ctrl-D at the AUR prompt does not kill the restore"
assert_not_called "yay -S" "and counts as no"
assert_output "Left for later" "with the work recorded as deferred"
