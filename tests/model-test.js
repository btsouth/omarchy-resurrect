// Unit tests for Model.js, the formatting the panel and the bar icon share.
//
// Model.js is a QML `.pragma library`: plain JavaScript with no QML API in it,
// which is exactly why it can be tested here rather than by starting a shell.
// The pragma line is stripped before evaluating, since node does not know it.
//
// Run through tests/cases/16-qml.sh, or directly: node tests/model-test.js

const fs = require("fs");
const path = require("path");

const source = fs
  .readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\s*\.pragma\s+library\s*$/m, "");

const Model = {};
new Function("exports", source + "\n" + [
  "CATEGORIES", "ago", "freshness", "stripCredentials",
  "plural", "summarize", "parseRecord", "consent",
].map((name) => `exports.${name} = typeof ${name} !== "undefined" ? ${name} : undefined;`)
  .join("\n"))(Model);

let failures = 0;
function check(what, got, want) {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g !== w) {
    console.log(`  FAIL ${what}\n       want ${w}\n       got  ${g}`);
    failures++;
  }
}

// ---- consent: a setting with three states, none of them "on" -------------
check("consent yes", Model.consent("yes", "always", "never", "asks"), "always");
check("consent no", Model.consent("no", "always", "never", "asks"), "never");
check("consent ask", Model.consent("ask", "always", "never", "asks"), "asks");
// Anything unrecognised has to read as "ask", the same way the CLI's
// units_decision_kind and aur_gate fall back, or the panel would tell you a
// machine is set to something it is not.
check("consent junk", Model.consent("wat", "always", "never", "asks"), "asks");
check("consent empty", Model.consent("", "always", "never", "asks"), "asks");
check("consent undefined", Model.consent(undefined, "always", "never", "asks"), "asks");

// ---- plural / summarize --------------------------------------------------
check("plural 1", Model.plural(1, "plugin"), "1 plugin");
check("plural 2", Model.plural(2, "plugin"), "2 plugins");
check("plural 0", Model.plural(0, "plugin"), "0 plugins");
check("plural irregular", Model.plural(2, "entry", "entries"), "2 entries");
check("summarize", Model.summarize({ packages: 1, config: 2, webapps: 0, plugins: 3 }),
  "1 package · 2 config paths · 0 web apps · 3 plugins");
check("summarize nothing", Model.summarize(null), "");

// ---- freshness / ago -----------------------------------------------------
const now = 1000000;
check("freshness none", Model.freshness(0, now, 48), "none");
check("freshness fresh", Model.freshness(now - 3600, now, 48), "fresh");
check("freshness stale", Model.freshness(now - 49 * 3600, now, 48), "stale");
check("freshness custom threshold", Model.freshness(now - 2 * 3600, now, 1), "stale");
check("ago never", Model.ago(0, now), "never");
check("ago just now", Model.ago(now - 5, now), "just now");
check("ago minutes", Model.ago(now - 300, now), "5m ago");
check("ago hours", Model.ago(now - 7200, now), "2h ago");
check("ago days", Model.ago(now - 3 * 86400, now), "3d ago");
// A clock that went backwards must not produce a negative age.
check("ago future", Model.ago(now + 5000, now), "just now");

// ---- stripCredentials ----------------------------------------------------
check("strip token", Model.stripCredentials("https://TOKEN@github.com/a/b"),
  "https://github.com/a/b");
check("strip user:pass", Model.stripCredentials("https://u:p@github.com/a/b"),
  "https://github.com/a/b");
check("strip nothing to strip", Model.stripCredentials("https://github.com/a/b"),
  "https://github.com/a/b");
check("strip empty", Model.stripCredentials(""), "");

// ---- parseRecord: the --porcelain protocol the panel reads ---------------
check("parse step", Model.parseRecord("STEP|packages|ok|done"),
  { type: "step", category: "packages", state: "ok", message: "done" });
check("parse begin", Model.parseRecord("BEGIN|restore|/v").action, "restore");
check("parse progress", Model.parseRecord("PROGRESS|config|3|10"),
  { type: "progress", category: "config", done: 3, total: 10 });
check("parse log", Model.parseRecord("LOG|will run: 1 Omarchy hook").message,
  "will run: 1 Omarchy hook");
check("parse done", Model.parseRecord("DONE|fail|blocked by the secret scan").state, "fail");
// A message containing the separator must survive intact, since paths and
// commands in LOG records legitimately contain one.
check("parse embedded pipes", Model.parseRecord("LOG|a|b|c").message, "a|b|c");
// Anything that is not a record is not a record: the panel drops it rather
// than half-parsing it.
check("parse prose", Model.parseRecord("Possible credentials in the vault"), null);
check("parse empty", Model.parseRecord(""), null);
check("parse null", Model.parseRecord(null), null);

// ---- the category table the panel renders --------------------------------
check("categories count", Model.CATEGORIES.length, 6);
check("category keys", Model.CATEGORIES.map((c) => c.key),
  ["packages", "config", "omarchy", "webapps", "plugins", "secrets"]);

if (failures > 0) {
  console.log(`${failures} Model.js assertions failed`);
  process.exit(1);
}
console.log("all Model.js assertions passed");
