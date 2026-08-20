.pragma library

// Formatting helpers shared by the panel and the bar icon. Kept out of QML so
// the bindings above read as layout, not arithmetic.

var CATEGORIES = [
  { key: "packages", label: "Packages",  detail: "Explicit pacman and AUR packages" },
  { key: "config",   label: "Dotfiles",  detail: "Shell, Hyprland, terminals, editors" },
  { key: "omarchy",  label: "Omarchy",   detail: "Bar layout, themes, hooks, extensions" },
  { key: "webapps",  label: "Web apps",  detail: "Launchers made with omarchy webapp" },
  { key: "plugins",  label: "Plugins",   detail: "Shell plugins, by git remote" },
  { key: "secrets",  label: "Secrets",   detail: "Encrypted with age. Off by default" }
]

function ago(epochSeconds, nowSeconds) {
  if (!epochSeconds) return "never"
  var d = Math.max(0, nowSeconds - epochSeconds)
  if (d < 60) return "just now"
  if (d < 3600) return Math.floor(d / 60) + "m ago"
  if (d < 86400) return Math.floor(d / 3600) + "h ago"
  if (d < 2592000) return Math.floor(d / 86400) + "d ago"
  return Math.floor(d / 2592000) + "mo ago"
}

// Three states, because that is how often you actually care: it is current,
// it is getting old, or there is nothing to restore from.
function freshness(epochSeconds, nowSeconds, staleHours) {
  if (!epochSeconds) return "none"
  var age = Math.max(0, nowSeconds - epochSeconds)
  return age > (staleHours || 48) * 3600 ? "stale" : "fresh"
}

// A remote may carry a token (https://TOKEN@host/…). The CLI strips it before
// writing it to a config file; the panel strips it before putting it on screen.
function stripCredentials(url) {
  return String(url || "").replace(/^([a-z][a-z0-9+.-]*:\/\/)[^\/@]*@/, "$1")
}

function plural(n, one, many) {
  return n + " " + (n === 1 ? one : (many || one + "s"))
}

function summarize(counts) {
  if (!counts) return ""
  return [
    plural(counts.packages || 0, "package"),
    plural(counts.config || 0, "config path"),
    plural(counts.webapps || 0, "web app"),
    plural(counts.plugins || 0, "plugin")
  ].join(" · ")
}

// The CLI's --porcelain protocol. One record per line, pipe separated.
function parseRecord(line) {
  var parts = String(line || "").split("|")
  switch (parts[0]) {
    case "BEGIN":    return { type: "begin", action: parts[1], vault: parts[2] }
    case "STEP":     return { type: "step", category: parts[1], state: parts[2], message: parts.slice(3).join("|") }
    case "PROGRESS": return { type: "progress", category: parts[1], done: Number(parts[2]), total: Number(parts[3]) }
    case "LOG":      return { type: "log", message: parts.slice(1).join("|") }
    case "DONE":     return { type: "done", state: parts[1], message: parts.slice(2).join("|") }
  }
  return null
}
