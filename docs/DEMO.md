# Running the fresh-machine test

`ress diff --stock` already gives a measured number without any of this. Do the
full run when you want proof, and the recording: an actual fresh Omarchy
becoming your machine, on the clock.

## 1. Decide how the vault reaches the new machine

The new machine has to be able to read your vault. Two ways, and for a test the
first is much less work.

**A — copy the folder (simplest).** The vault is self-contained at
`~/.local/share/ress/vault`. Drop it on a VMware shared folder, a USB image, or
`scp` it over. No remote, no repo, no auth.

```bash
ress backup                                    # make sure it is current
cp -a ~/.local/share/ress/vault /path/to/shared/ress-vault
```

**B — a private git repo (what you'd really use).** Also proves the clone path.

```bash
gh auth setup-git                              # lets git push over https
gh repo create btsouth/omarchy-vault --private
ress set REMOTE=https://github.com/btsouth/omarchy-vault.git
ress backup --push
```

Keep it **private**: the vault holds your dotfiles. Credentials are excluded
from every capture — keys, tokens, `hosts.yml`, `.netrc`, `known_hosts` — but
your Hyprland, Neovim and shell config are in there, and that is yours.

On the new machine a private repo needs credentials before it can be cloned, so
either run `gh auth login` there first, or use method A for the test.

## 2. Get a fresh machine without losing work

Everything here lives in git and is pushed, so reverting a VM cannot lose the
project — at worst it ends a running terminal session.

**Linked clone (safest).** VMware: power off, *VM ▸ Manage ▸ Clone*, base it on
a clean Omarchy snapshot, choose **linked clone** — fast, small on disk. Boot the
clone, test there, delete it. Your working VM is never touched, so nothing
running inside it is interrupted.

**Snapshot forward and back.** Snapshot the current VM as `work`, revert to a
clean Omarchy snapshot, test, then revert to `work`. Costs no disk; costs you the
open session.

**A second VM from the ISO.** Slowest and most honest, because it includes the
Omarchy install itself — the true bare-metal-to-desktop number.

## 3. Run it

On the fresh machine, from a terminal. Two commands, no pipe into a shell:

```bash
omarchy plugin add https://github.com/btsouth/omarchy-resurrect --yes

time ~/.config/omarchy/plugins/tsouth89.resurrect/bin/ress restore \
  --vault /path/to/shared/ress-vault --yes --aur --enable-units
```

With a git remote instead, swap the second line for:

```bash
time ~/.config/omarchy/plugins/tsouth89.resurrect/bin/ress restore \
  --from https://github.com/btsouth/omarchy-vault --yes --aur --enable-units
```

It will ask for your password once, for `pacman`.

`--yes` answers ress's own question about overwriting your home directory. It
deliberately does not answer the other two — building AUR packages and enabling
systemd user services — so an unattended run needs `--aur --enable-units` as
well. **For a recorded demo, leave them off and answer the prompts on camera**:
the questions are the point, and watching one get asked is more convincing than
a paragraph claiming it would have been.

ress prints its own elapsed time at the end; `time` brackets everything
including the download.

If the AUR is slow or something times out, **run it again** — the restore is
resumable and picks up at the step it stopped on. A rerun that completes is a
better demo than a run that never stumbles.

## 4. Check it actually worked

`ress` is not on PATH until you link it, so either run `ress link` first or use
the full path below.

```bash
~/.config/omarchy/plugins/tsouth89.resurrect/bin/ress link
ress verify                       # the whole check, in one line, exit 0 if it matches
```

`ress verify` compares this machine against the vault category by category and
exits non-zero if anything is missing — which is the claim being demonstrated,
stated by the tool rather than by you. The longer form, if you want it on screen:

```bash
ress status                       # counts should match the source machine
ress diff --stock                 # how far this machine was from a fresh install
pacman -Qq | wc -l                # package count in the same range
ls ~/.local/share/applications/   # your web apps
omarchy theme list                # your themes
```

Then look at the desktop: same theme, same bar layout, same wallpaper, your web
apps in the launcher. Log out and back in to pick up shell and session changes.

Worth opening one config you actually customised — `~/.config/hypr/bindings.lua`
or your Neovim setup — and confirming it is yours and not a default.

## 5. What to record

- The **whole run** as one take, failures included.
- The final line: `This machine is yours again — in 14s.`
- `ress verify` afterwards, saying it matches.
- The desktop afterwards.

No recorder ships by default. Either `sudo pacman -S wf-recorder` inside the VM,
or record the VM window from the host — which also captures the boot and keeps a
recorder out of the machine you are presenting as fresh.

## What the first real run found

Run on a clean Omarchy VM on 19 Aug 2026. It completed in **14 seconds**, and it
found three bugs that no amount of local testing had:

- Empty fields in the plugin list shifted every later column, because tab is IFS
  whitespace and `read` collapses runs of it.
- A fresh Omarchy carries the ISO's `offline.db` and none of the online package
  databases, so every install failed with `target not found`. Checking whether
  any database file exists is not enough; the fix installs, and refreshes and
  retries only on failure.
- A category that failed was still recorded as done, so "rerun to pick up where
  it stopped" skipped the step that had failed.

Still not exercised: encrypted secrets, since `age` is not installed on the
source machine.
