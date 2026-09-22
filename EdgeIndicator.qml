import QtQuick
import qs.Commons

// One screen edge's worth of "there is more this way": an accent glow bleeding
// inward from the edge, plus a small pill naming how many windows are parked
// out there.
//
// Fills its parent and anchors itself against the named edge, so the window
// mounts one of these per side and lets the counts decide which ones show.
Item {
  id: root

  property string edge: "left"          // left | right | top | bottom
  property int count: 0
  property bool shown: true

  property int glowSize: 44
  property real glowAlpha: 0.62
  property color tint: Color.accent
  property color labelColor: Color.background

  readonly property bool horizontal: edge === "left" || edge === "right"
  // Gradients run left-to-right and top-to-bottom, so on the near edges the
  // accent belongs at stop 0 and on the far edges at stop 1.
  readonly property bool nearFirst: edge === "left" || edge === "top"
  readonly property bool active: shown && count > 0

  anchors.fill: parent
  visible: opacity > 0
  opacity: active ? 1 : 0

  Behavior on opacity {
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }

  // Gradients always run left-to-right / top-to-bottom, so turn a stop's
  // position into distance from the screen edge first: 0 at the edge, 1 at the
  // inward end of the band.
  //
  // The exponent is the whole character of the thing. Squared or steeper reads
  // as a hairline with a smudge after it — which is the sliver of window this
  // replaces. Just above linear keeps enough color out at half the band's
  // width to register as a deliberate highlight in peripheral vision.
  function stopColor(position) {
    var distance = root.nearFirst ? position : 1 - position
    return Util.alpha(root.tint, root.glowAlpha * Math.pow(1 - distance, 1.35))
  }

  Rectangle {
    id: glow

    anchors.left: root.edge !== "right" ? parent.left : undefined
    anchors.right: root.edge !== "left" ? parent.right : undefined
    anchors.top: root.edge !== "bottom" ? parent.top : undefined
    anchors.bottom: root.edge !== "top" ? parent.bottom : undefined
    width: root.horizontal ? root.glowSize : undefined
    height: root.horizontal ? undefined : root.glowSize

    // Five stops rather than three: the curve below is shallow enough that a
    // single mid stop would straighten it back out into a flat ramp.
    gradient: Gradient {
      orientation: root.horizontal ? Gradient.Horizontal : Gradient.Vertical
      GradientStop { position: 0.0; color: root.stopColor(0.0) }
      GradientStop { position: 0.25; color: root.stopColor(0.25) }
      GradientStop { position: 0.5; color: root.stopColor(0.5) }
      GradientStop { position: 0.75; color: root.stopColor(0.75) }
      GradientStop { position: 1.0; color: root.stopColor(1.0) }
    }
  }

  Rectangle {
    id: pill

    readonly property int pad: Style.space(7)

    anchors.left: root.edge === "left" ? parent.left : undefined
    anchors.right: root.edge === "right" ? parent.right : undefined
    anchors.top: root.edge === "top" ? parent.top : undefined
    anchors.bottom: root.edge === "bottom" ? parent.bottom : undefined
    anchors.horizontalCenter: root.horizontal ? undefined : parent.horizontalCenter
    anchors.verticalCenter: root.horizontal ? parent.verticalCenter : undefined
    anchors.margins: Style.space(3)

    implicitWidth: label.implicitWidth + pad * 2
    implicitHeight: label.implicitHeight + pad

    // Filled rather than outlined: an accent chip carries across an ultrawide
    // at a glance, where a bordered one still asks to be read.
    radius: Style.cornerRadius
    color: Util.alpha(root.tint, 0.92)
    border.width: 0

    Text {
      id: label
      anchors.centerIn: parent

      // The arrow points the way the windows went, and sits on the side of the
      // number that edge is on, so the pill reads outward from the screen.
      text: {
        if (root.edge === "left") return "‹" + root.count
        if (root.edge === "right") return root.count + "›"
        if (root.edge === "top") return "⌃" + root.count
        return root.count + "⌄"
      }

      color: root.labelColor
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }
  }
}
