import QtQuick

// The Nanit mark drawn natively: a filled rounded square with a ring cut out
// of its middle, so it takes the bar's theme color like every other icon.
Item {
  id: root
  property real iconSize: 14
  property color color: "white"
  property color background: "black"

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Rectangle {
    anchors.fill: parent
    radius: root.iconSize * 0.42
    color: root.color
  }

  Rectangle {
    anchors.centerIn: parent
    width: root.iconSize * 0.46
    height: width
    radius: width * 0.36
    color: root.color
    border.color: root.background
    border.width: Math.max(1, root.iconSize * 0.11)
  }
}
