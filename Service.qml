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
  readonly property string cli: Qt.resolvedUrl("bin/ress").toString().replace(/^file:\/\//, "")

  // ------------------------------------------------------------------ state
  property var config: ({})
  property int lastBackup: 0
  property int now: Math.floor(Date.now() / 1000)
  property var status: null
  property bool loadingStatus: false

  property bool busy: false
  property string busyAction: ""
  property string currentStep: ""
  property string currentCategory: ""
  property real currentProgress: -1
  property var log: []
  property string lastResult: ""
  property string lastError: ""

  readonly property string freshness: Model.freshness(lastBackup, now, staleHours)
  readonly property string agoText: Model.ago(lastBackup, now)
  readonly property int staleHours: 48
  readonly property string vault: setting("VAULT", home + "/.local/share/ress/vault")
  readonly property string remote: setting("REMOTE", "")
  readonly property bool autoBackup: setting("AUTO_BACKUP", "off") === "on"
  readonly property int intervalHours: Math.max(1, parseInt(setting("AUTO_INTERVAL_HOURS", "24"), 10) || 24)

  signal finished(string action, string state)

  function setting(key, fallback) {
    var v = config[key]
    return (v === undefined || v === null || v === "") ? fallback : v
  }

  function categoryEnabled(key) {
    return setting("INCLUDE_" + key.toUpperCase(), "0") === "1"
  }

  // ------------------------------------------------------------------ config

  function parseConfig(raw) {
    var next = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/#.*$/, "").replace(/^\s+|\s+$/g, "")
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

  // One tick a minute, and only while it can change anything on screen: this is
  // an integer compare, not a subprocess.
  Timer {
    interval: 60000
    repeat: true
    running: true
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

  function setCategory(key, on) {
    settingProc.command = [cli, "set", "INCLUDE_" + key.toUpperCase() + "=" + (on ? "1" : "0")]
    settingProc.running = true
  }

  function setValue(key, value) {
    settingProc.command = [cli, "set", key + "=" + value]
    settingProc.running = true
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

  Process {
    id: settingProc
    running: false
    command: []
  }

  // -------------------------------------------------------- scheduled backup
  //
  // Headless instance only. The interval is computed from the deadline rather
  // than polled at a fixed rate, so an idle machine wakes this timer once a day
  // instead of 1,440 times.

  readonly property int nextDueIn: {
    if (!autoBackup) return 0
    var due = lastBackup + intervalHours * 3600
    return Math.max(60, due - now)
  }

  Timer {
    id: scheduler
    running: !root.panelOwned && root.autoBackup && !root.busy
    interval: Math.min(2147483, root.nextDueIn) * 1000
    repeat: false
    onTriggered: {
      if (root.lastBackup + root.intervalHours * 3600 <= Math.floor(Date.now() / 1000)) {
        root.run(["backup", "--message", "Scheduled backup"], "backup")
      }
      root.now = Math.floor(Date.now() / 1000)
    }
  }

  // The panel talks to whichever instance is loaded; scripts and keybinds talk
  // to this one.
  IpcHandler {
    target: "resurrect"
    enabled: !root.panelOwned

    function backup(): string { return root.backupNow() ? "started" : "busy" }
    function status(): string { return root.freshness + " " + root.agoText }
    function due(): string { return String(root.nextDueIn) }
  }

  Component.onCompleted: if (panelOwned) refresh()
}
