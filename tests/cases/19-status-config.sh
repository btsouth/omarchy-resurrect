# The config file is meant to be edited by hand, and `ress status --json` is
# what the panel reads. A value the script does not expect was handed to
# `jq --argjson` as it was, so `INCLUDE_OMARCHY=` or `AUTO_INTERVAL_HOURS=24h`
# made the command exit 2 with no output at all: no summary in the panel, and
# nothing anywhere saying why.

seed_machine
ress init >/dev/null
ress backup -m status >/dev/null
assert_ok "a vault to report on"

status_json() { ress status --json; }

# ---- 1. a value the script does not expect --------------------------------

mkdir -p "$HOME/.config/ress"
printf 'INCLUDE_OMARCHY=\nAUTO_INTERVAL_HOURS=24h\nINCLUDE_PACKAGES=yes\n' \
  >"$HOME/.config/ress/config"

status_json
assert_ok "status --json survives a hand-edited config"
assert_equals "$(jq -r '.intervalHours' <<<"$OUT")" "24" \
  "a non-numeric interval falls back to the default"
# A flag is read the way the rest of the script reads it: 1 is on and anything
# else is off, which is the rule cat_enabled applies to the next backup. Status
# disagreeing with the engine about that is the defect this pins down.
assert_equals "$(jq -r '.categories.omarchy' <<<"$OUT")" "false" "an empty value reads as off"
assert_equals "$(jq -r '.categories.packages' <<<"$OUT")" "false" "and so does a word"
assert_equals "$(jq -r '.categories.config' <<<"$OUT")" "true" "one that is not in the file stays on"

# ---- 2. a stamp that is not a number --------------------------------------

printf 'INCLUDE_PACKAGES=1\n' >"$HOME/.config/ress/config"
printf 'not-a-number\n' >"$HOME/.local/state/ress/last-backup"
status_json
assert_ok "status --json survives a stamp that is not a number"
assert_equals "$(jq -r '.lastBackup' <<<"$OUT")" "0" \
  "and reports no backup rather than dying on the way"

# ---- 3. a vault whose manifest is not JSON --------------------------------

printf 'not json at all\n' >"$HOME/.local/share/ress/vault/ress.json"
status_json
assert_ok "status --json survives a manifest it cannot read"
assert_equals "$(jq -r '.manifest' <<<"$OUT")" "null" "and says so"
assert_equals "$(jq -r '.hasVault' <<<"$OUT")" "1" "while still reporting the vault"

# ---- 4. the ordinary answer is unchanged ----------------------------------

printf 'INCLUDE_PACKAGES=1\nINCLUDE_OMARCHY=1\nAUTO_INTERVAL_HOURS=12\n' \
  >"$HOME/.config/ress/config"
git -C "$HOME/.local/share/ress/vault" checkout -- ress.json

status_json
assert_ok "status --json on an ordinary config"
assert_equals "$(jq -r '.intervalHours' <<<"$OUT")" "12" "the interval it was told"
assert_equals "$(jq -r '.categories.packages' <<<"$OUT")" "true" "the categories that are on"
assert_equals "$(jq -r '.categories.secrets' <<<"$OUT")" "false" "and the one that is not"
assert_equals "$(jq -r '.manifest | type' <<<"$OUT")" "object" "the manifest as written"
assert_equals "$(jq -r '.settings.secretScan' <<<"$OUT")" "warn" "and the settings beside it"
