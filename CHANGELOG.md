# Changelog

Newest first. The version here is the one in `manifest.json` and in
`ress --version`; the plugin id stays `tsouth89.resurrect` whatever the version,
for the reason in the README.

## 1.2.0

### Web apps

- A launcher's `Exec` line is read as an argument list, so the three forms
  Omarchy has written parse: a bare URL, a bare URL followed by browser flags,
  and the quoted URL the current installer writes. A quoted launcher, and one
  carrying a Chromium profile flag, used to be captured and then refused on the
  machine that needed them — and the launchers Omarchy ships were captured in
  their place, so the category travelled the wrong set in both directions.
- A launcher byte-identical to one in `/usr/share/omarchy/applications` is not
  captured: it is not this machine's state, and a fresh install has it already.
- Browser flags and the `omarchy-launch-or-focus-webapp` form travel through the
  installer's custom-exec argument, assembled from validated pieces rather than
  copied out of the vault. A launcher whose second word is a command is refused.
- An `Exec` line longer than a launcher could need (1024 bytes) is refused
  unread, so a fetched vault cannot buy a stall with one.
- A launcher a restore cannot rebuild is named at capture, listed as refused by
  `ress verify`, and left out of a shared loadout rather than published.

### Status

- `ress status --json` no longer exits 2 with no output when a setting holds a
  value it does not expect (`INCLUDE_OMARCHY=`, `AUTO_INTERVAL_HOURS=24h`), when
  the last-backup stamp is not a number, or when a vault's manifest is not JSON.
  The panel reads nothing but this command, so a blank panel was the visible
  symptom.

### Plugins and themes

- A remote a restore will not clone — a `file://` URL, a bare local path — is
  named at capture, where the checkout still exists and pushing it somewhere git
  can fetch is a thing that can be done. A theme with the same problem is worse
  off and gets the same warning: it does not travel as files either.
- `ress verify` lists plugins and themes it cannot re-clone as refused rather
  than missing, instead of telling a machine for ever to restore what a restore
  cannot do.

### Verify and the loadout

- `ress verify` counts only what a restore can rebuild, and lists the rest
  separately. Asked the other way it reported a match for a vault it would not
  write.
- A name with a space in it is one entry in `verify --json`, not one per word.
- `ress share` applies the same rule, so a loadout no longer carries a launcher a
  restore would refuse or the profile format cannot express, and it says how many
  were left out.

### Tests and gates

- `tests/cases/18-webapp-launchers.sh`, `19-status-config.sh`,
  `20-mutation-baseline.sh` and `21-plugin-remotes.sh`.
- The QML case picks a `node` that runs, rather than the first on `PATH`: on a
  machine where that is a mise or asdf shim, the shim fails before node starts
  and the case died for a reason that had nothing to do with QML.
- The mutation runner checks the suite passes before it breaks anything. A case
  that is already red counts as a catch for every mutation, which is a clean
  sweep over tests that are not passing.
- Continuous integration: `.github/workflows/tests.yml` runs the suite on every
  push and pull request, and `mutations.yml` runs the mutation sweep weekly.

## 1.1.0

Everything from the rename to the release of the version `manifest.json` carried
until now.

- `ress verify` checks the machine against the vault, and exits non-zero when they
  do not match, so it can be the last line of a provisioning script.
- The two steps a restore never takes on its own, and now asks about: building an
  AUR package from a PKGBUILD (with `--aur`, `--no-aur`, `--review-aur` and a deny
  list at `~/.config/ress/aur-deny`), and enabling a systemd user service, which
  is the one step that arranges for code to run later without being asked again.
- The vault is read back before it is committed, looking for the shapes
  credentials have. `ress scan` runs the same check on demand, and reports the
  file without ever printing the match.
- `~/.config/autostart` is captured only when `CAPTURE_AUTOSTART=1`, because every
  entry in it is a command that runs at the next login.
- The dry run says what the omarchy category would do, rather than the words
  "dry run".
- A vault's `schemaVersion` must be a plain integer before it reaches arithmetic.
  Bash arithmetic is not a numeric context: it evaluates the contents of a bare
  name and performs command substitution inside an array subscript, so a vault
  declaring `CFG[$(…)]` ran that command before any prompt, on the path that
  fetches a stranger's vault. **Upgrade if you are on 1.0.0.**
- The vault format is renamed with the project: the manifest is `ress.json` and a
  replaced file is kept as `*.ress-bak`. Both old names (`resurrect.json`,
  `*.resurrect-bak`) are still read.
- The test harness, the mutation runner, and the QML half of the suite:
  `tests/run.sh`, `tests/mutate.sh`, `Model.js` under node, and qmllint.
- `restore --from ssh://…`, `git://…` and the scp form `git@host:path` reach git
  as written instead of being turned into `https://ssh://…` (#1).

## 1.0.0

- First release: `backup`, `restore` (resumable, with the AUR and systemd-unit
  questions asked rather than assumed), `share`, `apply`, `verify`, `scan`,
  `enable-units`, `status`, `diff`, `init`, `set`, `secrets`, `doctor`, `link`,
  and the bar widget and panel.
