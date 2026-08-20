import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The engine's QML face. Two instances exist: one the panel owns, and one the
// shell mounts headless (kind: "service") to run scheduled backups. They share
// no state and need none — the CLI's config file and its last-backup stamp are
// the only truth, and both are watched here rather than polled.
Item {
  id: root

  // Set by the panel on its own copy. The headless instance leaves it false and
  // is the only one that ever starts a backup on a timer.
  property bool panelOwned: false

  // Injected by shell.qml when mounted as a service; unused, but declaring them
  // keeps the shell from warning about a missing property.
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/ress/config"
  readonly property string stampPath: home + "/.local/state/ress/last-backup"
  readonly property string attemptPath: home + "/.local/state/ress/last-attempt"
  readonly property string runningPath: home + "/.local/state/ress/running"
  // decodeURIComponent because a $HOME containing a space arrives percent-encoded
  // in a file: URL, and every subsequent Process would fail on the literal %20.
  readonly property string cli: decodeURIComponent(Qt.resolvedUrl("bin/ress").toString().replace(/^file:\/\//, ""))

  // ------------------------------------------------------------------ state
  property var config: ({})
  property int lastBackup: 0
  property int lastAttempt: 0
  // Another ress process (typically the headless scheduler) holds the lock.
  property bool externallyBusy: false
  property int now: Math.floor(Date.now() / 1000)
  property var status: null
  property bool loadingStatus: false

  property bool busy: false
  readonly property bool anyBusy: busy || externallyBusy
  property string busyAction: ""
  property string currentStep: ""
  property string currentCategory: ""
  property real currentProgress: -1
  property var log: []
  property string lastResult: ""
  property string lastError: ""

  readonly property string freshness: Model.freshness(lastBackup, now, staleHours)
  readonly property string agoText: Model.ago(lastBackup, now)

  // Set from the bar widget's inline settings, which is what the manifest
  // advertises. Hardcoding it made that setting a no-op.
  property int staleHours: 48

  // True only while the panel is actually on screen. The clock below ticks a
  // minute at a time for a visible "4m ago", and far more slowly otherwise —
  // nothing on the bar changes faster than the stale threshold.
  property bool uiActive: false
  readonly property string vault: setting("VAULT", home + "/.local/share/ress/vault")
  readonly property string remote: setting("REMOTE", "")
  readonly property bool autoBackup: setting("AUTO_BACKUP", "off") === "on"
  // The two things a restore will not do without being asked. Three states
  // each — ask, yes, no — so they are strings rather than booleans.
  readonly property string aurMode: setting("AUR", "ask")
  readonly property string enableUnits: setting("ENABLE_UNITS", "ask")
  readonly property int intervalHours: Math.max(1, parseInt(setting("AUTO_INTERVAL_HOURS", "24"), 10) || 24)

  signal finished(string action, string state)

  function setting(key, fallback) {
    var v = config[key]
    return (v === undefined || v === null || v === "") ? fallback : v
  }

  // The CLI's own defaults, for a machine that has never written a config file.
  // Falling back to "off" drew all six toggles off while `ress backup` would in
  // fact capture five of them — the panel disagreeing with the engine about
  // what the next backup does.
  readonly property var categoryDefaults: ({
    packages: true, config: true, omarchy: true,
    webapps: true, plugins: true, secrets: false
  })

  function categoryEnabled(key) {
    var value = config["INCLUDE_" + key.toUpperCase()]
    if (value === undefined || value === null || value === "")
      return categoryDefaults[key] === true
    return value === "1"
  }

  // ------------------------------------------------------------------ config

  function parseConfig(raw) {
    var next = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      // Strip comments only at the start of a line or after whitespace: a `#`
      // inside a value (a URL fragment, say) is part of the value.
      var line = lines[i].replace(/(^|\s)#.*$/, "$1").replace(/^\s+|\s+$/g, "")
      var eq = line.indexOf("=")
      if (eq <= 0) continue
      next[line.substring(0, eq).replace(/\s/g, "")] = line.substring(eq + 1).replace(/^\s+|\s+$/g, "")
    }
    config = next
  }

  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.parseConfig(text())
    onFileChanged: reload()
    onLoadFailed: root.parseConfig("")
  }

  FileView {
    path: root.stampPath
    watchChanges: true
    printErrors: false
    onLoaded: root.lastBackup = parseInt(String(text()).replace(/\s/g, ""), 10) || 0
    onFileChanged: reload()
    onLoadFailed: root.lastBackup = 0
  }

  FileView {
    path: root.attemptPath
    watchChanges: true
    printErrors: false
    onLoaded: root.lastAttempt = parseInt(String(text()).replace(/\s/g, ""), 10) || 0
    onFileChanged: reload()
    onLoadFailed: root.lastAttempt = 0
  }

  FileView {
    path: root.runningPath
    watchChanges: true
    printErrors: false
    onLoaded: root.externallyBusy = !root.busy
    onFileChanged: reload()
    onLoadFailed: root.externallyBusy = false
  }

  // Only the panel-owned instance needs a wall clock at all; the headless one
  // schedules from a deadline and recomputes when it fires. A minute while the
  // panel is open, ten minutes while it is not. This is an integer compare, not
  // a subprocess.
  Timer {
    interval: root.uiActive ? 60000 : 600000
    repeat: true
    running: root.panelOwned
    onTriggered: root.now = Math.floor(Date.now() / 1000)
  }

  // ------------------------------------------------------------- run the CLI

  function run(args, action) {
    if (busy) return false
    busy = true
    busyAction = action
    currentStep = ""
    currentCategory = ""
    currentProgress = -1
    lastError = ""
    lastResult = ""
    log = []
    worker.command = [cli, "--porcelain"].concat(args)
    worker.running = true
    return true
  }

  function backupNow()  { return run(["backup"], "backup") }
  function shareNow()   { return run(["share"], "share") }
  function refresh()    { if (!statusProc.running) { loadingStatus = true; statusProc.running = true } }

  // execDetached rather than a shared Process: assigning `command` to a Process
  // that is still running drops the write, so a second quick toggle vanished.
  // Two of these landing at once is safe because `ress set` takes a lock on the
  // config file and re-reads it inside that lock — it is not the vault lock,
  // which would make the bar show a backup running for a settings change.
  function setCategory(key, on) {
    Quickshell.execDetached([cli, "set", "INCLUDE_" + key.toUpperCase() + "=" + (on ? "1" : "0")])
  }

  function setValue(key, value) {
    Quickshell.execDetached([cli, "set", key + "=" + value])
  }

  function appendLog(entry) {
    var next = log.slice(-40)
    next.push(entry)
    log = next
  }

  function handleRecord(line) {
    var record = Model.parseRecord(line)
    if (!record) return
    if (record.type === "step") {
      currentCategory = record.category
      currentStep = record.message
      currentProgress = -1
      if (record.state === "fail") lastError = record.category + ": " + record.message
      appendLog({ category: record.category, state: record.state, message: record.message })
    } else if (record.type === "progress") {
      currentCategory = record.category
      currentProgress = record.total > 0 ? record.done / record.total : -1
    } else if (record.type === "log") {
      appendLog({ category: "", state: "note", message: record.message })
    } else if (record.type === "done") {
      lastResult = record.state
    }
  }

  Process {
    id: worker
    running: false
    command: []
    stdout: SplitParser { onRead: function(data) { root.handleRecord(data) } }
    stderr: SplitParser { onRead: function(data) { if (data) root.lastError = String(data) } }
    onExited: function(exitCode) {
      root.busy = false
      root.currentProgress = -1
      if (exitCode === 0) root.lastError = ""
      root.currentStep = exitCode === 0 ? "" : root.currentStep
      if (exitCode !== 0 && !root.lastError) root.lastError = "exited with code " + exitCode
      root.finished(root.busyAction, root.lastResult || (exitCode === 0 ? "ok" : "fail"))
      root.refresh()
    }
  }

  Process {
    id: statusProc
    running: false
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
      onStreamFinished: {
        root.loadingStatus = false
        try {
          root.status = JSON.parse(text || "{}")
        } catch (e) {
          root.status = null
        }
      }
    }
    onExited: root.loadingStatus = false
  }

  // -------------------------------------------------------- scheduled backup
  //
  // Headless instance only. The interval is computed from the deadline rather
  // than polled at a fixed rate, so an idle machine wakes this timer once a day
  // instead of 1,440 times.

  // Measured from the last attempt as well as the last success: a backup that
  // dies partway leaves the success stamp stale, and scheduling off that alone
  // re-fires a full backup every minute on exactly the machine that can least
  // afford it — an offline laptop with AUTO_PUSH on.
  readonly property int nextDueIn: {
    if (!autoBackup) return 0
    var since = Math.max(lastBackup, lastAttempt)
    return Math.max(60, since + intervalHours * 3600 - now)
  }

  Timer {
    id: scheduler
    running: !root.panelOwned && root.autoBackup && !root.busy
    interval: Math.min(2147483, root.nextDueIn) * 1000
    repeat: false
    onTriggered: {
      var since = Math.max(root.lastBackup, root.lastAttempt)
      if (since + root.intervalHours * 3600 <= Math.floor(Date.now() / 1000)) {
        root.run(["backup", "--message", "Scheduled backup"], "backup")
      }
      root.now = Math.floor(Date.now() / 1000)
    }
  }

  Component.onCompleted: if (panelOwned) refresh()
}
