import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ScrollEdgesModel.js" as EdgesModel
import "SettingsModel.js" as Model

// The host owns persistence and panel lifetime. The form keeps a draft so an
// unfinished hex field can never turn a live indicator into an invalid color.
Item {
  id: root

  readonly property string pluginId: "io.github.nodrej.scroll-edges"
  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool initialized: false
  property bool entryRead: false
  property bool entryReady: false
  property var currentEntry: ({})
  property var draft: Model.defaults()
  property bool dirty: false
  property string saveError: ""
  property bool previewOnScreens: false
  property var previewService: null

  readonly property bool canSave: entryReady && shell !== null
    && typeof shell.updateEntryInline === "function"
  readonly property color previewTint: glowEditor.previewColor
  readonly property color previewLabel: labelEditor.previewColor
  readonly property var palette: [Commons.Color.accent, Commons.Color.foreground, Commons.Color.background, Commons.Color.urgent, Commons.Color.muted]

  function initialize() {
    draft = Model.values(currentEntry)
    dirty = false
    initialized = true
  }

  function open(payloadJson) {
    // A second summon should keep any edits already in progress.
    if (!opened) {
      initialized = false
      if (entryRead) initialize()
      previewOnScreens = false
      saveError = ""
    }
    opened = true
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function stopPreview() {
    if (previewService) previewService.previewing = false
  }

  function close() {
    if (opened && initialized) {
      glowEditor.commitField()
      labelEditor.commitField()
      saveNow()
    }
    opened = false
    previewOnScreens = false
    stopPreview()
  }

  function dismiss() {
    // Stop immediately, even if the host unloads the panel in this call.
    close()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function setValue(key, value, immediate) {
    var next = Model.copy(draft)
    next[key] = value
    draft = next
    dirty = true
    if (immediate) saveNow()
    else saveDelay.restart()
  }

  function saveNow() {
    saveDelay.stop()
    if (!dirty || !canSave) return
    try {
      var next = Model.build(currentEntry, draft)
      shell.updateEntryInline(pluginId, next)
      // Keep repeated edits consistent while the file watcher catches up.
      currentEntry = next
      dirty = false
      saveError = ""
    } catch (e) {
      saveError = "Can't save here. The shell settings API is unavailable."
    }
  }

  function resetDefaults() {
    saveDelay.stop()
    draft = Model.defaults()
    dirty = false
    if (!canSave) return
    try {
      var next = Model.reset(currentEntry)
      shell.updateEntryInline(pluginId, next)
      currentEntry = next
      saveError = ""
    } catch (e) {
      saveError = "Can't save here. The shell settings API is unavailable."
    }
  }

  function syncPreview() {
    if (previewService && previewService !== service) previewService.previewing = false
    previewService = service
    if (!service) return
    // These values are only for drawing samples. Saved settings and real
    // window counts continue updating independently behind the preview.
    service.previewSettings = {
      glowSize: draft.glowSize,
      glowOpacity: draft.glowOpacity,
      color: String(previewTint),
      labelColor: String(previewLabel)
    }
    service.previewing = opened && previewOnScreens
  }

  onServiceChanged: syncPreview()
  onOpenedChanged: syncPreview()
  onPreviewOnScreensChanged: syncPreview()
  onDraftChanged: syncPreview()
  onPreviewTintChanged: syncPreview()
  onPreviewLabelChanged: syncPreview()
  Component.onDestruction: {
    saveNow()
    stopPreview()
  }

  // Read only. The shell API replaces the whole entry, so each save starts
  // with the latest copy rather than dropping keys this version doesn't own.
  FileView {
    id: shellConfig
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.currentEntry = EdgesModel.settingsFor(text(), root.pluginId)
      root.entryRead = true
      root.entryReady = root.currentEntry.id === root.pluginId
      if (root.opened && !root.initialized) root.initialize()
    }
    onLoadFailed: {
      root.entryRead = true
      root.entryReady = false
      if (root.opened && !root.initialized) root.initialize()
    }
  }

  Timer {
    id: saveDelay
    interval: 300
    onTriggered: root.saveNow()
  }

  component Hint: Text {
    width: parent.width
    textFormat: Text.PlainText
    color: Commons.Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component ColorEditor: Column {
    id: editor
    property string title: ""
    property string followLabel: ""
    property string defaultLabel: ""
    property string value: ""
    property color themeColor: Commons.Color.accent
    readonly property bool following: value === ""
    readonly property string validHex: Model.hex(hexField.text)
    readonly property color previewColor: following ? themeColor
      : validHex !== "" ? validHex : value !== "" ? value : themeColor
    signal committed(string value)
    spacing: Style.space(6)

    // Swatches deliberately replace the editor text. Keep later resets and
    // theme changes in step even after that explicit assignment.
    onValueChanged: if (hexField) hexField.text = value || String(themeColor)
    onThemeColorChanged: if (hexField && following) hexField.text = String(themeColor)

    function commitField() {
      if (!following && validHex !== "" && validHex !== value) committed(validHex)
    }

    PanelSectionHeader { text: editor.title }
    Toggle {
      width: parent.width
      label: editor.followLabel
      description: "Default: " + editor.defaultLabel
      checked: editor.following
      onClicked: editor.committed(editor.following ? String(editor.themeColor) : "")
    }
    Row {
      visible: !editor.following
      width: parent.width
      spacing: Style.space(10)
      TextField {
        id: hexField
        width: Math.max(Style.space(100), parent.width - currentSwatch.width - parent.spacing)
        text: editor.value || String(editor.themeColor)
        placeholderText: "#rrggbb or #rgb"
        foreground: editor.validHex !== "" ? Commons.Color.foreground : Commons.Color.urgent
        selectByMouse: true
        onEditingFinished: editor.commitField()
        onAccepted: editor.commitField()
      }
      Rectangle {
        id: currentSwatch
        width: hexField.height
        height: width
        radius: Style.cornerRadius
        color: editor.previewColor
        border.width: 1
        border.color: Commons.Color.foreground
      }
    }
    Hint {
      visible: !editor.following && editor.validHex === ""
      text: "Enter #rrggbb or #rgb. Invalid colors are not saved."
      color: Commons.Color.urgent
    }
    Row {
      visible: !editor.following
      spacing: Style.space(8)
      Repeater {
        model: root.palette
        Button {
          required property var modelData
          text: "●"
          foreground: modelData
          bordered: true
          focusable: true
          tooltipText: String(modelData)
          onClicked: {
            // Re-selecting the saved swatch also clears an unfinished field.
            hexField.text = String(modelData)
            editor.committed(String(modelData))
          }
        }
      }
    }
  }

  component SliderEditor: Column {
    id: editor
    property string title: ""
    property string hint: ""
    property string defaultLabel: ""
    property string suffix: " px"
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 1
    property bool integer: true
    signal moved(real value)
    signal released()
    spacing: Style.space(4)

    PanelSectionHeader {
      text: editor.title + "  " + (editor.integer ? Math.round(editor.value) : Math.round(editor.value * 100))
        + editor.suffix + "  (default: " + editor.defaultLabel + ")"
    }
    PanelSlider {
      id: slider
      width: parent.width
      value: editor.value
      minimum: editor.minimum
      maximum: editor.maximum
      integer: editor.integer
      step: editor.step
      trackColor: Util.alpha(Commons.Color.foreground, 0.15)
      fillColor: Commons.Color.accent
      knobColor: activeFocus ? Commons.Color.foreground : Commons.Color.accent
      activeFocusOnTab: true
      onMoved: function(value) { editor.moved(value) }
      onReleased: editor.released()
      Keys.onLeftPressed: {
        editor.moved(Math.max(minimum, value - step))
        editor.released()
      }
      Keys.onRightPressed: {
        editor.moved(Math.min(maximum, value + step))
        editor.released()
      }
    }
    Hint { text: editor.hint }
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-scroll-edges-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      BorderSurface {
        id: card
        anchors.centerIn: parent
        width: Math.min(Style.space(600), parent.width - Style.space(32))
        height: Math.min(form.implicitHeight + Style.space(32), parent.height - Style.space(32))
        color: Commons.Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius

        MouseArea { anchors.fill: parent }

        Flickable {
          id: scroll
          anchors.fill: parent
          anchors.margins: Style.space(16)
          contentWidth: width
          contentHeight: form.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          clip: true

          Column {
            id: form
            width: scroll.width
            spacing: Style.space(12)
            enabled: root.initialized

            Row {
              width: parent.width
              Text {
                width: parent.width - closeButton.width
                text: "Scroll edges"
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Button {
                id: closeButton
                text: "Close"
                focusable: true
                onClicked: root.dismiss()
              }
            }

            Hint {
              visible: !root.canSave || root.saveError !== ""
              text: root.saveError || (!root.shell || typeof root.shell.updateEntryInline !== "function"
                ? "Can't save here. Open this window through the Omarchy shell."
                : "Can't save here until the plugin's settings entry can be read.")
              color: Commons.Color.urgent
            }

            ColorEditor {
              id: glowEditor
              width: parent.width
              title: "Glow color"
              followLabel: "Follow theme accent"
              defaultLabel: "theme accent"
              themeColor: Commons.Color.accent
              value: root.draft.color
              onCommitted: function(value) { root.setValue("color", value, true) }
            }
            ColorEditor {
              id: labelEditor
              width: parent.width
              title: "Label color"
              followLabel: "Follow theme background"
              defaultLabel: "theme background"
              themeColor: Commons.Color.background
              value: root.draft.labelColor
              onCommitted: function(value) { root.setValue("labelColor", value, true) }
            }
            PanelSeparator {}
            SliderEditor {
              width: parent.width
              title: "Glow size"
              defaultLabel: "44 px"
              hint: "How far the glow reaches in from the edge."
              value: root.draft.glowSize
              minimum: 4
              maximum: 160
              onMoved: function(value) { root.setValue("glowSize", value, false) }
              onReleased: root.saveNow()
            }
            SliderEditor {
              width: parent.width
              title: "Glow strength"
              defaultLabel: "62%"
              suffix: "%"
              hint: "How strong the glow is at the edge itself."
              value: root.draft.glowOpacity
              minimum: 0
              maximum: 1
              step: 0.01
              integer: false
              onMoved: function(value) { root.setValue("glowOpacity", value, false) }
              onReleased: root.saveNow()
            }
            SliderEditor {
              width: parent.width
              title: "Hidden-window threshold"
              defaultLabel: "56 px"
              hint: "Pixels of a window that may still be on screen before it counts as hidden."
              value: root.draft.peek
              minimum: 0
              maximum: 300
              onMoved: function(value) { root.setValue("peek", value, false) }
              onReleased: root.saveNow()
            }
            PanelSeparator {}
            PanelSectionHeader { text: "Live preview" }
            Rectangle {
              width: parent.width
              height: Style.space(110)
              color: Commons.Color.background
              border.color: Commons.Color.muted
              border.width: 1
              clip: true
              Text {
                anchors.centerIn: parent
                text: "Screen edge samples"
                color: Commons.Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Repeater {
                model: ["left", "right"]
                EdgeIndicator {
                  required property string modelData
                  edge: modelData
                  count: modelData === "left" ? 2 : 5
                  glowSize: root.draft.glowSize
                  glowAlpha: root.draft.glowOpacity
                  tint: root.previewTint
                  labelColor: root.previewLabel
                }
              }
            }
            Toggle {
              visible: root.service !== null
              width: parent.width
              label: "Show on my screens while open"
              description: "Sample counts on every monitor. Stops when this window closes."
              checked: root.previewOnScreens
              onClicked: root.previewOnScreens = !root.previewOnScreens
            }
            Button {
              text: "Reset to defaults"
              bordered: true
              focusable: true
              enabled: root.canSave
              onClicked: root.resetDefaults()
            }
          }
        }
      }
    }
  }
}
