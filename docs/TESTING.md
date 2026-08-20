# Testing ress

Four layers, in the order they catch things. The first three run on any machine
in about a minute. The fourth needs a VM, and there are exactly six things only
it can tell you.

## 1. The suite

```bash
./tests/run.sh              # every case
./tests/run.sh aur          # just the ones whose name matches
```

Each case runs in a throwaway `$HOME` with test doubles on `PATH` for `pacman`,
`yay`, `sudo`, `systemctl`, `curl`, `git` and the `omarchy` CLI. Nothing outside
the sandbox is read or written: no package is installed, no unit is enabled, and
the fake `sudo` has no privileges — it records the call and runs the rest of the
line as you. That is what lets a case assert a restore *did not* do something,
which is most of what the consent work is about.

The `git` double is the subtle one: it rewrites `https://github.com/example/…`
to a local path, but only for `clone`, `fetch`, `pull`, `push` and `ls-remote`.
Rewriting globally would make capture record a `/tmp` path and restore then
refuse it as an unsafe remote — an artefact of the test rather than of ress.

## 2. Mutation testing

```bash
./tests/mutate.sh           # ~12 minutes; every mutation runs the whole suite
```

A passing suite says the tests agree with the code, not that they would notice
if the code were wrong. This breaks one behaviour at a time in a throwaway copy
— the AUR gate always builds, the unit gate always enables, the scanner never
finds anything, `verify` always says the machine matches, `plain()` stops
stripping control characters — and reports any mutation no test caught.

Run it when you change what the tests are *for*, not on every edit. A `SURVIVED`
line is a feature the suite only appears to cover.

## 3. The QML half

`tests/cases/16-qml.sh` covers what the bash suite cannot:

- **`Model.js`** is a `.pragma library` — plain JavaScript with no QML API in it
  — so `tests/model-test.js` runs it under node and asserts on it directly.
- **`qmllint`** with the Omarchy and Quickshell imports resolved. Without the
  import paths it emits forty lines of unresolved-import noise and tells you
  nothing; with them, it is a real check.
- **A cross-file check qmllint cannot do.** The panel reaches the engine through
  a dynamically typed property, so a binding to an engine member that does not
  exist renders blank and reports nothing anywhere. Every `engine.<member>` in
  `Panel.qml` is checked against `Service.qml`.

None of this proves the panel *draws*. See §4.

## 4. On a real machine, without a VM

These use the real tools against scratch directories, and are worth running
before a release. None of them touches the live desktop or the real vault.

```bash
# A real capture of this machine into a scratch vault, then the round-trip
# invariant: a vault captured from a machine must verify against that machine.
ress backup  --vault /tmp/rt-vault -m "round trip"
ress verify  --vault /tmp/rt-vault      # expect: matches, exit 0
ress scan    --vault /tmp/rt-vault

# A real restore into a scratch home. Three commands must not reach the running
# session, so shadow them: a shell restart, the IPC client that edits the live
# bar layout, and the live theme switcher.
mkdir -p /tmp/rt-bin
printf '#!/bin/sh\nexit 0\n' > /tmp/rt-bin/omarchy-restart-shell
printf '#!/bin/sh\nexit 1\n' > /tmp/rt-bin/omarchy-shell
printf '#!/bin/sh\nexit 0\n' > /tmp/rt-bin/omarchy-theme-set
chmod +x /tmp/rt-bin/*

env -i HOME=/tmp/rt-home PATH="/tmp/rt-bin:$PATH" TERM=dumb USER="$USER" \
  ress restore --from /tmp/rt-vault --yes --no-enable-units --skip packages
```

`--skip packages` because installing them for real needs root, and
`--no-enable-units` because `systemctl --user` talks to the session manager
rather than to `$HOME` — enabling a unit for a scratch home would enable it in
your real session.

Then check the upgrade path on a copy of a vault written by the previous
version, and the update mechanism on a copy of the installed plugin:

```bash
cp -a ~/.local/share/ress/vault /tmp/upgrade-vault
git -C /tmp/upgrade-vault remote remove origin      # so nothing can be pushed
ress backup --vault /tmp/upgrade-vault              # expect the manifest rename

cp -a ~/.config/omarchy/plugins/tsouth89.resurrect /tmp/plugin-update
git -C /tmp/plugin-update fetch origin HEAD
git -C /tmp/plugin-update merge --ff-only FETCH_HEAD
omarchy-plugin-validate /tmp/plugin-update
```

The AUR annotation is the one integration the doubles cannot stand in for,
because it is a live HTTP API and the encoding is fiddly (`arg%5B%5D=`, `curl
-g`, and `+` encoded as `%2B` or the AUR reads it as a space). Give a scratch
vault a `packages/foreign.txt` with one real AUR name and one invented one, and
answer `n` at the prompt: the invented one should be marked *not on
aur.archlinux.org*.

## 5. What only a VM can tell you

Everything above leaves six things unproven. All of them need a clean Omarchy
install, which is what `DEMO.md` walks through.

1. **Installing packages.** `sudo pacman -S` and `yay` building real PKGBUILDs
   have never run under test — the doubles record the call and stop. This is the
   single biggest gap, and it is the category most likely to be slow or to fail
   halfway.
2. **A machine that genuinely lacks things.** A scratch `$HOME` on your own
   machine still has every package installed system-wide, so "restore installs
   what is missing" is only ever exercised against a machine where nothing is.
3. **The panel drawing.** `qmllint` proves the QML parses and resolves; it does
   not prove the bar widget appears, that the two consent rows render, or that
   clicking one writes the setting.
4. **Units actually starting.** Enabling is tested; a unit coming up with the
   session at next login is not.
5. **The theme actually applying.** `omarchy-theme-set` is shadowed in every
   test above, so the desktop visibly changing is unverified.
6. **The timing claim.** The README's restore number can only come from a real
   run on a fresh install.
