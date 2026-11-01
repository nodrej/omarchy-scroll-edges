import QtQuick
import qs.Ui

// The host owns the settings panel, so every monitor's icon follows the same
// open state whether the window was opened here or from a keyboard shortcut.
BarWidget {
  id: root
  moduleName: "io.github.nodrej.scroll-edges"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-arrow_expand_horizontal: arrows pointing toward the screen edges.
    text: "\u{F084E}"
    active: !!(root.bar && root.bar.shell && root.bar.shell.isPluginOpen(root.moduleName))
    tooltipText: "Scroll edges settings"
    onPressed: function(b) {
      if (b === Qt.LeftButton && root.bar && root.bar.shell)
        root.bar.shell.toggle(root.moduleName)
    }
  }
}
