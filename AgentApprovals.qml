import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Agent approvals — one light for every AI agent on this box that is waiting
// on a human. Sources are decoupled: anything that can run a shell writes a
// record via `agent-approval add`, and this widget just watches the directory.
//
//   Clear    → small dim dot, no attention drawn
//   Pending  → hard red/amber flash + count badge, visible on every workspace
//
// Left-click  : focus the oldest pending agent (herdr pane / tmux pane) or open
//               the source's notification; falls back to a notification listing
// Right-click : clear every pending record (you handled them elsewhere)
// Middle-click: force a rescan now

BarWidget {
  id: root
  moduleName: "dsskaggs.agent-approvals"

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/approvals"
  readonly property string binDir: Quickshell.env("HOME") + "/.local/bin"

  property var pending: []                       // array of {source,id,title,detail,created_at}
  readonly property int count: pending.length
  readonly property bool alerting: count > 0
  property bool flashOn: false                   // toggled by flashTimer while alerting

  readonly property int scanIntervalMs: Number(settings.scanIntervalMs) > 0 ? Number(settings.scanIntervalMs) : 3000
  readonly property int flashIntervalMs: Number(settings.flashIntervalMs) > 0 ? Number(settings.flashIntervalMs) : 450

  readonly property color colorIdle:  Qt.rgba(Color.muted.r, Color.muted.g, Color.muted.b, 0.55)
  readonly property color colorHot:   "#ef4444"   // red
  readonly property color colorWarm:  "#f59e0b"   // amber (alternate flash phase)

  implicitWidth: indicator.implicitWidth
  implicitHeight: indicator.implicitHeight

  // ---------- data ----------

  function reload() {
    if (!listProcess.running) listProcess.running = true
  }

  function scan() {
    if (!scanProcess.running) scanProcess.running = true
  }

  Process {
    id: listProcess
    command: [root.binDir + "/agent-approval", "list"]
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: function(exitCode) {
      var next = []
      if (exitCode === 0) {
        try { next = JSON.parse(listOut.text || "[]") } catch (e) { next = [] }
      }
      if (!Array.isArray(next)) next = []
      root.pending = next
    }
  }

  Process {
    id: scanProcess
    command: [root.binDir + "/agent-approval-scan"]
    onExited: function() { root.reload() }
  }

  // Any write to the state dir → instant reload (no waiting on the timer).
  // inotifywait is what Omarchy itself uses to hot-reload plugins.
  Process {
    id: dirWatch
    running: true
    command: ["inotifywait", "-m", "-q", "-e", "close_write,create,delete,moved_to,moved_from",
              "--format", "%e", root.stateDir]
    stdout: SplitParser { onRead: function(line) { root.reload() } }
    onExited: function() { restartWatch.start() }
  }
  Timer {
    id: restartWatch
    interval: 2000
    repeat: false
    onTriggered: dirWatch.running = true
  }

  Timer {
    id: scanTimer
    interval: root.scanIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.scan()
  }

  Timer {
    id: flashTimer
    interval: root.flashIntervalMs
    running: root.alerting
    repeat: true
    onTriggered: root.flashOn = !root.flashOn
    onRunningChanged: if (!running) root.flashOn = false
  }

  // ---------- actions ----------

  function focusOldest() {
    if (!root.alerting) { root.scan(); return }
    var p = root.pending[0]
    var src = String(p.source || "")
    var id  = String(p.id || "")
    if (src === "herdr") {
      // id is "w1_p2" → "w1:p2"
      var pane = id.replace(/_/g, ":")
      Quickshell.execDetached(["sh", "-c",
        "herdr pane focus " + pane + " >/dev/null 2>&1; " +
        "hyprctl dispatch focuswindow 'class:^(herdr|ghostty|Alacritty|kitty|foot)$' >/dev/null 2>&1"])
    } else if (src === "tmux") {
      var tp = id.replace(/_/g, ":")   // best effort; tmux target sanitised on write
      Quickshell.execDetached(["sh", "-c",
        "tmux select-pane -t '" + tp + "' 2>/dev/null; " +
        "hyprctl dispatch focuswindow 'class:^(ghostty|Alacritty|kitty|foot)$' >/dev/null 2>&1"])
    } else if (src === "claude-code") {
      Quickshell.execDetached(["sh", "-c",
        "hyprctl dispatch focuswindow 'class:^(claude|Claude|ghostty|Alacritty|kitty|foot)$' >/dev/null 2>&1"])
    } else if (src === "codex") {
      Quickshell.execDetached(["sh", "-c",
        "hyprctl dispatch focuswindow 'class:^(codex|Codex|ghostty|Alacritty|kitty|foot)$' >/dev/null 2>&1"])
    } else if (src.indexOf("hermes-") === 0) {
      // Hermes approvals surface in Telegram/Buzz or the Hermes desktop app.
      Quickshell.execDetached(["sh", "-c",
        "hyprctl dispatch focuswindow 'class:^(Hermes|hermes|org.telegram.desktop|Telegram)$' >/dev/null 2>&1"])
    }
    Quickshell.execDetached([root.binDir + "/agent-approval", "notify",
      String(p.source || "unknown"), String(p.id || "0"),
      String(p.title || "Approval needed"), String(p.detail || "")])
  }

  function clearAll() {
    Quickshell.execDetached([root.binDir + "/agent-approval", "clear-all"])
    root.reload()
  }

  function tooltip() {
    if (!root.alerting) return "No agent approvals pending"
    var lines = [root.count + " agent" + (root.count === 1 ? "" : "s") + " waiting on you:"]
    for (var i = 0; i < Math.min(root.pending.length, 8); i++) {
      var p = root.pending[i]
      lines.push("• " + String(p.title || p.source))
    }
    if (root.pending.length > 8) lines.push("… +" + (root.pending.length - 8) + " more")
    lines.push("")
    lines.push("left: jump to oldest · right: clear all · middle: rescan")
    return lines.join("\n")
  }

  // ---------- visuals ----------

  BarIconButton {
    id: indicator
    anchors.fill: parent
    bar: root.bar
    slotSize: root.alerting ? Style.bar.statusSlot + 10 : Style.bar.statusSlot
    tooltipText: root.tooltip()
    onPressed: function(button) {
      if (button === Qt.RightButton) root.clearAll()
      else if (button === Qt.MiddleButton) root.scan()
      else root.focusOldest()
    }
    iconComponent: Component {
      Item {
        // Halo — only while alerting, pulses opposite the core so it's unmissable
        Rectangle {
          anchors.centerIn: parent
          visible: root.alerting
          width: Style.space(18)
          height: width
          radius: width / 2
          color: root.flashOn ? root.colorWarm : root.colorHot
          opacity: root.flashOn ? 0.35 : 0.15
          Behavior on opacity { NumberAnimation { duration: root.flashIntervalMs * 0.6 } }
        }
        // Core dot
        Rectangle {
          id: core
          anchors.centerIn: parent
          width: root.alerting ? Style.space(11) : Style.space(8)
          height: width
          radius: width / 2
          color: root.alerting ? (root.flashOn ? root.colorHot : root.colorWarm) : root.colorIdle
          border.width: root.alerting ? 1 : 0
          border.color: "#fff1f2"
          Behavior on width { NumberAnimation { duration: 120 } }
        }
        // Count badge
        Text {
          anchors.left: core.right
          anchors.leftMargin: 3
          anchors.verticalCenter: parent.verticalCenter
          visible: root.alerting
          text: root.count > 9 ? "9+" : String(root.count)
          color: root.flashOn ? "#fecaca" : "#ffffff"
          font.family: Style.font.family
          font.pixelSize: Style.bar.iconFont * 0.85
          font.bold: true
        }
      }
    }
  }
}
