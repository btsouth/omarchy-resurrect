# Running the fresh-machine demo

`ress diff --stock` already gives a measured, defensible number without any of
this. Run the full thing only when you want the recording: an actual fresh
Omarchy becoming your machine, start to finish, on the clock.

## Doing it without losing work

Everything Resurrect is lives in this git repo and is pushed to GitHub. Reverting
a VM cannot lose the project — at worst it ends a running terminal session. Pick
whichever of these fits your setup:

**A — Clone the VM (safest; your working VM is never touched).**
In VMware: power off, then *VM ▸ Manage ▸ Clone*, base it on a clean Omarchy
snapshot, and choose a **linked clone** (fast, small on disk). Boot the clone,
run the demo there, delete it afterwards. Your working VM never changes state,
so nothing running inside it is interrupted.

**B — Snapshot forward, then back (simplest; costs you the session).**
1. Snapshot the current VM and name it `work`. This captures everything as it is.
2. Revert to your clean Omarchy snapshot.
3. Run the demo below.
4. Revert to `work`. Everything returns, including this repo.

The only thing lost is the terminal session that was open, not the work.

**C — A second VM from the Omarchy ISO.**
Slowest, and the most honest: it includes the Omarchy install itself, so the
number is genuinely bare-metal-to-desktop. Worth it if you want the full story
in one take.

Option A is the one to reach for. Option B is fine and needs no disk.

## Before you start

Push a vault somewhere the fresh machine can reach:

```bash
ress init --remote git@github.com:you/my-omarchy-vault.git   # private repo is fine
ress backup --push
```

Use an **HTTPS** URL if the fresh machine will not have your SSH key — which,
if you are testing honestly, it will not.

## On the fresh machine

From a TTY, before you have touched anything:

```bash
time bash -c '
  omarchy plugin add https://github.com/tsouth89/omarchy-resurrect --yes &&
  ~/.config/omarchy/plugins/tsouth89.resurrect/bin/ress restore --from https://github.com/you/my-omarchy-vault --yes
'
```

Resurrect prints its own elapsed time at the end; `time` brackets the whole
thing including installing the plugin and cloning the vault.

If the AUR is slow or something times out, run it again — the restore is
resumable and picks up at the step it stopped on.

## What to capture

- The **whole run** as one take, including the failures if there are any. A
  demo that shows a retry working is more convincing than one that never stumbles.
- The final line, which reads `This machine is yours again — in Nm Ns.`
- A shot of the desktop afterwards: same theme, same bar layout, same web apps.

Then put the real number in the README's cost table, replacing the estimate.

## Recording

There is no recorder installed by default. Either:

```bash
sudo pacman -S wf-recorder    # then: wf-recorder -f demo.mp4
```

or record the VM window from the host, which also captures the boot and avoids
putting a recorder inside the machine you are trying to show as fresh.
