# The QML half. bin/ress is covered by everything else here; Panel.qml,
# Service.qml and Model.js are not, and a broken binding is a widget that
# vanishes from the bar with an error only the shell's log ever sees.

QMLLINT=/usr/lib/qt6/bin/qmllint
OMARCHY_SHELL=/usr/share/omarchy/shell

# ---- 1. Model.js is plain JavaScript, so it gets real unit tests ---------

if command -v node >/dev/null 2>&1; then
  OUT=$(node "$REPO_DIR/tests/model-test.js" 2>&1); STATUS=$?
  assert_ok "Model.js unit tests"
  assert_output "all Model.js assertions passed"
else
  echo "  (skipped: no node — Model.js unit tests need one)"
fi

# ---- 2. the .qml files must at least parse and resolve ------------------

if [[ -x $QMLLINT && -d $OMARCHY_SHELL ]]; then
  # Quickshell maps the shell's config root to the `qs` module namespace, so
  # the import root is a directory containing a `qs` pointing at it.
  ROOT="$SANDBOX/qml-imports"
  mkdir -p "$ROOT"
  ln -sfn "$OMARCHY_SHELL" "$ROOT/qs"

  for f in Panel.qml Service.qml; do
    OUT=$("$QMLLINT" -I "$ROOT" -I /usr/lib/qt6/qml "$REPO_DIR/$f" 2>&1); STATUS=$?
    # Warnings here are pre-existing patterns: properties resolved at runtime on
    # a dynamically typed `bar`, and ids reached from a nested component. An
    # Error is a file that will not load.
    ERRORS=$(printf '%s\n' "$OUT" | grep -c '^Error:' || true)
    assert_equals "$ERRORS" "0" "$f has no qmllint errors"
    assert_no_output "was not found. Did you add all imports" \
      "$f resolves every type it uses"
  done

  # Every engine.<member> the panel binds to has to exist on Service.qml. The
  # panel reaches the engine through a dynamically typed property, so qmllint
  # cannot see this: a binding to a member that does not exist renders blank
  # and says nothing anywhere.
  MISSING=""
  for member in $(grep -oE 'engine\.[A-Za-z_][A-Za-z0-9_]*' "$REPO_DIR/Panel.qml" |
                  sed 's/^engine\.//' | sort -u); do
    grep -qE "(property [A-Za-z<>]+ $member\b|function $member\(|signal $member\b)" \
      "$REPO_DIR/Service.qml" || MISSING="$MISSING $member"
  done
  assert_equals "$MISSING" "" "every engine.<member> the panel binds to exists on the engine"
  # ...and the ids in the row list have to match the ones trigger() handles,
  # or a click does nothing.
  for id in aur units backup restore auto share copy folder url preview apply; do
    grep -q "\"$id\"" "$REPO_DIR/Panel.qml" ||
      _fail "Panel.qml has no row id \"$id\""
  done
  _pass
else
  echo "  (skipped: no qmllint or no Omarchy shell to resolve imports against)"
fi
