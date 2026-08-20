import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One bar icon and one panel: how fresh the backup is, what it holds, and the
// two buttons that matter. Everything here is a thin face over
// bin/ress — the panel never touches the filesystem itself.
Panel {
  id: root
  moduleName: "tsouth89.resurrect"
  ipcTarget: "tsouth89.resurrect"
  manageIpc: false

  // ------------------------------------------------------------------ theme
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color stateColor: engine.busy ? accent
    : engine.freshness === "fresh" ? foreground
    : engine.freshness === "stale" ? Qt.darker(foreground, 1.35)
    : urgent

  // ------------------------------------------------------------------ state
  property string tab: "backup"
  property int cursor: 0
  property bool cursorActive: false
  property string applyUrl: ""
  property string notice: ""

  readonly property var tabs: ["backup", "share", "apply"]
  readonly property var rows: {
    if (tab === "share") return [
      { id: "share",  label: "Export loadout" },
      { id: "copy",   label: "Copy the share command" },
      { id: "folder", label: "Open the profile folder" }
    ]
    if (tab === "apply") return [
      { id: "url",    label: "Profile URL" },
      { id: "preview", label: "Preview what it installs" },
      { id: "apply",  label: "Apply this loadout" }
    ]
    var out = [{ id: "backup", label: "Back up now" }, { id: "restore", label: "Restore this machine" }]
    for (var i = 0; i < Model.CATEGORIES.length; i++)
      out.push({ id: "cat:" + Model.CATEGORIES[i].key, label: Model.CATEGORIES[i].label })
    out.push({ id: "auto", label: "Scheduled backups" })
    return out
  }

  readonly property string currentRowId: cursorActive && cursor >= 0 && cursor < rows.length
    ? rows[cursor].id : ""

  function hasCursor(id) { return currentRowId === id }

  // -------------------------------------------------------------- behaviour

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dx !== 0) {
      var t = tabs.indexOf(tab) + dx
      if (t >= 0 && t < tabs.length) { tab = tabs[t]; cursor = 0 }
      return
    }
    if (dy === 0) return
    cursor = Math.max(0, Math.min(rows.length - 1, cursor + dy))
  }

  function activate() {
    if (!cursorActive) { cursorActive = true; return }
    trigger(currentRowId)
  }

  function trigger(id) {
    if (id.indexOf("cat:") === 0) {
      var key = id.substring(4)
      engine.setCategory(key, !engine.categoryEnabled(key))
      return
    }
    switch (id) {
      case "backup":
        if (!engine.backupNow()) flash("Already running")
        break
      case "restore":
        // Restore installs packages and needs sudo, so it belongs in a terminal
        // you can watch and answer — not behind a button that silently sudos.
        Quickshell.execDetached(["omarchy-launch-terminal", engine.cli, "restore"])
        root.close()
        break
      case "auto":
        engine.setValue("AUTO_BACKUP", engine.autoBackup ? "off" : "on")
        break
      case "share":
        if (!engine.shareNow()) flash("Already running")
        break
      case "copy":
        copyProc.command = ["wl-copy", "--", shareCommand]
        copyProc.running = true
        break
      case "folder":
        Quickshell.execDetached(["xdg-open", engine.home + "/.local/share/ress/profile"])
        break
      case "url":
        urlField.forceActiveFocus()
        break
      case "preview":
        if (applyUrl === "") { flash("Paste a profile URL first"); break }
        // `--` last: a pasted URL is user input, and end-of-options is what
        // stops one that starts with a dash from arriving as a flag.
        Quickshell.execDetached(["omarchy-launch-terminal", engine.cli, "apply", "--dry-run", "--", applyUrl])
        break
      case "apply":
        if (applyUrl === "") { flash("Paste a profile URL first"); break }
        Quickshell.execDetached(["omarchy-launch-terminal", engine.cli, "apply", "--", applyUrl])
        root.close()
        break
    }
  }

  function flash(message) { notice = message; noticeTimer.restart() }

  readonly property string shareCommand:
    "ress apply " + engine.setting("PROFILE_URL", "ress.sh/gh/<you>/<your-loadout>")

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursor = 0
    notice = ""
    if (panelFlick) panelFlick.contentY = 0
    engine.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: engine
    panelOwned: true
    uiActive: root.opened
    staleHours: Math.max(1, Math.min(720, parseInt(root.setting("staleHours", 48), 10) || 48))
    onFinished: function(action, state) {
      root.flash(state === "ok"
        ? (action === "backup" ? "Backed up" : "Loadout exported")
        : (action + " finished with problems"))
    }
  }

  Timer { id: noticeTimer; interval: 3200; onTriggered: root.notice = "" }
  Process {
    id: copyProc
    running: false
    command: []
    onExited: function(exitCode) {
      root.flash(exitCode === 0 ? "Copied to the clipboard"
                                : "Could not copy — wl-clipboard is not installed")
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function backup(): string { return engine.backupNow() ? "started" : "busy" }

    // Open straight to a tab, so a keybind can go to Share without three keys.
    function openTab(name: string): string {
      if (root.tabs.indexOf(name) < 0) return "unknown tab: " + name
      root.tab = name
      root.cursor = 0
      root.cursorActive = false
      root.open()
      return "ok"
    }
  }

  // ------------------------------------------------------------- bar button

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Text {
          id: barGlyph
          anchors.centerIn: parent
          text: "󰁯"
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          color: engine.anyBusy ? root.barForeground
            : engine.freshness === "none" ? Qt.darker(root.barForeground, 1.6)
            : engine.freshness === "stale" ? Qt.darker(root.barForeground, 1.3)
            : root.barForeground

          // A backup running is the one thing worth animating: it is the only
          // state the icon can be in that you might want to wait for. The pulse
          // lives on its own property so opacity snaps back when it stops.
          property real pulse: 1.0
          opacity: engine.anyBusy ? pulse : 1.0

          SequentialAnimation on pulse {
            running: engine.anyBusy
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutQuad }
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) engine.backupNow()
      else root.toggle()
    }
  }

  // ------------------------------------------------------------------ panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        if (key === "b") root.trigger("backup")
        else if (key === "r") root.trigger("restore")
        else if (key === "s") { root.tab = "share"; root.cursor = 0 }
        else if (key === "a") { root.tab = "apply"; root.cursor = 0 }
        else if (key === "?") root.tab = "backup"
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ------------------------------------------------------------ hero
          PanelHero {
            width: parent.width
            title: "ress"
            meta: engine.anyBusy ? (engine.currentStep || "Working…")
              : engine.externallyBusy ? "Scheduled backup running…"
              : engine.lastBackup > 0 ? ("Backed up " + engine.agoText)
              : "Never backed up"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰁯"
                color: root.stateColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          // Progress only exists while something is running, and it reads the
          // real step names out of the CLI rather than guessing at a duration.
          Column {
            visible: engine.anyBusy
            width: parent.width
            spacing: Style.spacing.labelGap

            Rectangle {
              width: parent.width
              height: Math.max(2, Style.space(3))
              radius: height / 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

              Rectangle {
                id: progressFill
                height: parent.height
                radius: parent.radius
                color: root.accent
                width: engine.currentProgress >= 0
                  ? parent.width * engine.currentProgress
                  : parent.width * 0.35
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

                SequentialAnimation on x {
                  id: sweep
                  running: engine.busy && engine.currentProgress < 0
                  loops: Animation.Infinite
                  // `target` is not set on a property value source, so reset
                  // the item itself rather than reading it off the animation.
                  onRunningChanged: if (!running) progressFill.x = 0
                  NumberAnimation { from: 0; to: panelFlick.width * 0.65; duration: 900; easing.type: Easing.InOutQuad }
                  NumberAnimation { from: panelFlick.width * 0.65; to: 0; duration: 900; easing.type: Easing.InOutQuad }
                }
              }
            }

            Text {
              width: parent.width
              text: engine.currentCategory
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            visible: root.notice !== "" || engine.lastError !== ""
            width: parent.width
            text: engine.lastError !== "" ? engine.lastError : root.notice
            color: engine.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ------------------------------------------------------------ tabs
          Row {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.tabs
              TabChip {
                required property var modelData
                tabId: modelData
              }
            }
          }


          PanelSeparator { foreground: root.foreground }

          // ---------------------------------------------------- backup tab
          Column {
            visible: root.tab === "backup"
            width: parent.width
            spacing: Style.space(10)

            Row {
              width: parent.width
              spacing: Style.space(8)

              ActionRow {
                width: (parent.width - Style.space(8)) / 2
                rowId: "backup"
                glyph: ""
                title: engine.busy && engine.busyAction === "backup" ? "Backing up…" : "Back up now"
                subtitle: "b"
              }
              ActionRow {
                width: (parent.width - Style.space(8)) / 2
                rowId: "restore"
                glyph: "󰦛"
                title: "Restore"
                subtitle: "r · opens a terminal"
              }
            }

            Text {
              visible: !!(engine.status && engine.status.manifest)
              width: parent.width
              text: (engine.status && engine.status.manifest)
                ? Model.summarize(engine.status.manifest.counts) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            PanelSectionHeader {
              text: "WHAT TRAVELS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: Model.CATEGORIES
                CategoryRow {
                  required property var modelData
                  width: parent.width
                  category: modelData
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            ActionRow {
              width: parent.width
              rowId: "auto"
              glyph: ""
              title: "Scheduled backups"
              subtitle: engine.autoBackup
                ? ("every " + engine.intervalHours + "h · next in " + Math.round(engine.nextDueIn / 3600) + "h")
                : "off"
              trailing: true
              trailingOn: engine.autoBackup
            }

            Text {
              width: parent.width
              text: engine.remote !== ""
                ? ("Pushes to " + Model.stripCredentials(engine.remote))
                : ("Vault: " + engine.vault)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
          }

          // ----------------------------------------------------- share tab
          Column {
            visible: root.tab === "share"
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: "A loadout is your setup without your data: the package list, "
                + "the plugins, the web apps and the theme. No dotfiles, no keys, "
                + "no home directory. Push it to a public repo and anyone can "
                + "become this machine."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            ActionRow {
              width: parent.width
              rowId: "share"
              glyph: ""
              title: engine.busy && engine.busyAction === "share" ? "Exporting…" : "Export loadout"
              subtitle: "one profile.json — no dotfiles, no attachments"
            }
            ActionRow {
              width: parent.width
              rowId: "copy"
              glyph: ""
              title: "Copy the share link"
              subtitle: root.shareCommand
            }
            ActionRow {
              width: parent.width
              rowId: "folder"
              glyph: ""
              title: "Open the profile folder"
              subtitle: "push it to GitHub, then share the URL"
            }
          }

          // ----------------------------------------------------- apply tab
          Column {
            visible: root.tab === "apply"
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: "Paste a ress.sh link or a GitHub URL. Nothing is installed "
                + "until you have seen the full list: apply only ever installs "
                + "packages, adds plugins, adds web apps and sets a theme. "
                + "A profile cannot carry a script."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            TextField {
              id: urlField
              width: parent.width
              placeholderText: "ress.sh/gh/someone/their-loadout"
              text: root.applyUrl
              foreground: root.foreground
              font.family: root.fontFamily
              hasCursor: root.hasCursor("url")
              onTextChanged: root.applyUrl = text
              onAccepted: root.trigger("preview")
              // The key catcher is blocked while this has focus, so without this
              // Escape does nothing and the field cannot be left by keyboard.
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }

            ActionRow {
              width: parent.width
              rowId: "preview"
              glyph: ""
              title: "Preview what it installs"
              subtitle: "a full dry run, in a terminal, changing nothing"
            }
            ActionRow {
              width: parent.width
              rowId: "apply"
              glyph: ""
              title: "Apply this loadout"
              subtitle: "asks again before the first package"
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------- components

  component TabChip: CursorSurface {
    id: tabButton
    property string tabId: ""
    readonly property bool selected: root.tab === tabId

    current: tabButton.selected
    foreground: root.foreground
    implicitWidth: tabLabel.implicitWidth + Style.space(20)
    implicitHeight: tabLabel.implicitHeight + Style.space(10)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { root.tab = tabButton.tabId; root.cursor = 0; root.cursorActive = false }
    }

    Text {
      id: tabLabel
      anchors.centerIn: parent
      text: tabButton.tabId.charAt(0).toUpperCase() + tabButton.tabId.slice(1)
      color: tabButton.selected ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property string rowId: ""
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool trailing: false
    property bool trailingOn: false

    hasCursor: root.hasCursor(actionRow.rowId)
    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        for (var i = 0; i < root.rows.length; i++)
          if (root.rows[i].id === actionRow.rowId) root.cursor = i
      }
      onClicked: root.trigger(actionRow.rowId)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        text: actionRow.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: actionContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: actionRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          visible: actionRow.subtitle !== ""
          text: actionRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }

      ToggleSwitch {
        visible: actionRow.trailing
        checked: actionRow.trailingOn
        hasCursor: actionRow.hasCursor
        foreground: root.foreground
        Layout.alignment: Qt.AlignVCenter
        onToggled: root.trigger(actionRow.rowId)
      }
    }
  }

  component CategoryRow: CursorSurface {
    id: categoryRow
    property var category: null
    readonly property string key: category ? category.key : ""
    readonly property bool on: engine.categoryEnabled(key)

    hasCursor: root.hasCursor("cat:" + key)
    foreground: root.foreground
    implicitHeight: categoryContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        for (var i = 0; i < root.rows.length; i++)
          if (root.rows[i].id === "cat:" + categoryRow.key) root.cursor = i
      }
      onClicked: root.trigger("cat:" + categoryRow.key)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      ColumnLayout {
        id: categoryContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text {
            text: categoryRow.category ? categoryRow.category.label : ""
            color: categoryRow.on ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            visible: categoryRow.key === "secrets"
            text: "\uf023"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Item { Layout.fillWidth: true }
        }
        Text {
          Layout.fillWidth: true
          text: categoryRow.category ? categoryRow.category.detail : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        checked: categoryRow.on
        hasCursor: categoryRow.hasCursor
        foreground: root.foreground
        Layout.alignment: Qt.AlignVCenter
        onToggled: root.trigger("cat:" + categoryRow.key)
      }
    }
  }
}
