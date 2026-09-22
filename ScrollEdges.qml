import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "ScrollEdgesModel.js" as Model

// Scroll edges
//
// The scrolling layout keeps a workspace's windows in one long row (or column,
// on a rotated monitor) and shows the slice that fits. Whether anything is
// parked past the edge is currently only legible as a few pixels of window
// peeking in, which on an ultrawide is easy to miss entirely.
//
// This lights up the edge it went past and says how many.
Item {
  id: root

  readonly property string pluginId: "io.github.nodrej.scroll-edges"

  // Tunables. The defaults are what this was built against; each can be
  // overridden per machine from the plugin's own entry in shell.json, since an
  // ultrawide and a 13" laptop don't want the same answers:
  //
  //   { "id": "io.github.nodrej.scroll-edges", "peek": 56, "glowSize": 44, "glowOpacity": 0.62,
  //     "color": "#7aa2f7", "labelColor": "#1a1b26" }
  //
  // Services aren't handed their shell.json entry the way bar widgets are, so
  // the file is read below. Anything missing or unreadable leaves the defaults.
  property var settings: ({})

  function setting(key, fallback) {
    var value = Number(root.settings[key])
    return (isFinite(value) && value >= 0) ? value : fallback
  }

  // Pixels of a window that may remain on screen before it counts as hidden.
  // Roughly "a sliver you'd have to look for" — a column showing more than
  // this is visible enough to announce itself.
  readonly property int peekThreshold: setting("peek", 56)

  // Sized against the complaint this exists to answer: on a 3440px-wide
  // monitor a hairline at the edge is no easier to notice than the sliver of
  // window it replaces.
  readonly property int glowSize: setting("glowSize", 44)
  readonly property real glowAlpha: setting("glowOpacity", 0.62)

  // The theme's accent and background by default, so the indicators follow a
  // theme switch. A hex override pins them instead, for anyone whose accent
  // is too quiet to notice at the edge — or too close to their wallpaper.
  readonly property string colorOverride: Model.colorSetting(root.settings.color)
  readonly property string labelColorOverride: Model.colorSetting(root.settings.labelColor)
  readonly property color tint: colorOverride !== "" ? colorOverride : Color.accent
  readonly property color labelColor: labelColorOverride !== "" ? labelColorOverride : Color.background

  // Hyprland's event socket drives the refreshes; the poll only covers a view
  // that settles into its final position without a further event to say so.
  // That can only follow an event, so the poll sleeps through an idle desktop
  // rather than re-reading the layout every few seconds all day.
  readonly property int safetyPollInterval: 2500
  readonly property int safetyPollWindow: 10000

  property double lastEventMs: 0

  // Monitor name -> Model counts.
  property var edges: ({})

  function countsFor(name) {
    var counts = edges[name]
    return counts ? counts : Model.emptyCounts()
  }

  // Quickshell already tracks Hyprland's windows and monitors from the event
  // socket, but the geometry inside each object is only re-read on request.
  // Asking for both lists is a socket round trip and no subprocess at all.
  function refresh() {
    Hyprland.refreshToplevels()
    Hyprland.refreshMonitors()
  }

  // Counts and the bounds they are measured against are read from the models in
  // one pass, so a half-arrived refresh can never mix a new window position with
  // an old monitor size.
  function recount() {
    var clients = []
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) clients.push(toplevels[i].lastIpcObject)

    var monitors = []
    var screens = Hyprland.monitors.values
    for (var j = 0; j < screens.length; j++) monitors.push(screens[j].lastIpcObject)

    root.edges = Model.scanAll(clients, monitors, root.peekThreshold)
  }

  Component.onCompleted: {
    refresh()
    recount()
  }

  // Watched rather than read once, so an edit to shell.json lands without
  // restarting the shell — the same way the rest of the shell treats it.
  FileView {
    id: shellConfig

    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    preload: true
    watchChanges: true
    printErrors: false

    // `text()` is stale inside the change signal, so both paths go through
    // reload() -> onLoaded and always parse the file as it now stands.
    onFileChanged: reload()
    onLoaded: root.settings = Model.settingsFor(text(), root.pluginId)
    onLoadFailed: root.settings = ({})
  }

  Connections {
    target: Hyprland

    // Almost anything can move a column across an edge — opening, closing,
    // focusing, moving between workspaces or monitors. Rather than maintain a
    // list that silently goes stale, let every event schedule the same cheap
    // debounced read.
    function onRawEvent(event) {
      root.lastEventMs = Date.now()
      debounce.restart()
    }
  }

  Timer {
    id: debounce
    interval: 45
    onTriggered: root.refresh()
  }

  Timer {
    id: safetyPoll
    interval: root.safetyPollInterval
    running: true
    repeat: true
    onTriggered: {
      if (Date.now() - root.lastEventMs > root.safetyPollWindow) return
      root.refresh()
    }
  }

  // A refresh lands asynchronously, object by object, so the objects say when
  // there is something new to count rather than the plugin guessing how long a
  // round trip takes. The timer coalesces that burst into a single pass.
  Timer {
    id: recountDebounce
    interval: 30
    onTriggered: root.recount()
  }

  Instantiator {
    model: Hyprland.toplevels

    delegate: Connections {
      required property var modelData

      target: modelData
      function onLastIpcObjectChanged() { recountDebounce.restart() }
    }
  }

  Instantiator {
    model: Hyprland.monitors

    delegate: Connections {
      required property var modelData

      target: modelData
      function onLastIpcObjectChanged() { recountDebounce.restart() }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel

      required property var modelData

      readonly property var counts: root.countsFor(modelData.name)
      readonly property bool shown: counts.total > 0 && !counts.fullscreen

      function reservedAt(side) {
        var reserved = counts.reserved
        return (reserved && reserved.length === 4) ? reserved[side] : 0
      }

      // Keep the surface mapped just past the fade so the indicators can
      // animate out instead of blinking off with the window.
      property bool armed: false

      screen: modelData
      visible: armed && !remapGuard.remapping
      color: "transparent"

      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore

      // Top rather than Overlay: a fullscreen window should cover these, and
      // the counts already stand down when one is up.
      WlrLayershell.namespace: "omarchy-scroll-edges"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // Nothing here is clickable; an empty mask passes every pointer event
      // through to the windows underneath.
      mask: Region {}

      Component.onCompleted: if (shown) armed = true

      onShownChanged: {
        if (shown) {
          disarm.stop()
          armed = true
        } else {
          disarm.restart()
        }
      }

      Timer {
        id: disarm
        interval: 240
        onTriggered: panel.armed = false
      }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }

      // Indicators live inside the bar's reserved area rather than under it,
      // so a top-edge chip doesn't land on the clock and the glow stops at the
      // bar instead of tinting it.
      Item {
        anchors.fill: parent
        anchors.leftMargin: panel.reservedAt(0)
        anchors.topMargin: panel.reservedAt(1)
        anchors.rightMargin: panel.reservedAt(2)
        anchors.bottomMargin: panel.reservedAt(3)

        Repeater {
          model: ["left", "right", "top", "bottom"]

          EdgeIndicator {
            required property string modelData

            edge: modelData
            count: panel.counts[modelData]
            shown: panel.shown
            glowSize: root.glowSize
            glowAlpha: root.glowAlpha
            tint: root.tint
            labelColor: root.labelColor
          }
        }
      }
    }
  }
}
