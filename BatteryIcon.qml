// Pure presentational iOS/macOS-style battery body — outline + nub + fill.
// No interaction; used by Battery.qml (bar widget) and LockView.qml (status row).

import QtQuick

Item {
    id: root

    required property color fgColor
    required property color fillColor
    property int pct: 0

    width: 18
    height: 10

    Rectangle {
        id: bodyOutline
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width - 2
        radius: 2
        color: "transparent"
        border.color: root.fgColor
        border.width: 1
    }

    Rectangle {
        anchors.left: bodyOutline.right
        anchors.leftMargin: 1
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: 4
        radius: 1
        color: root.fgColor
    }

    Rectangle {
        x: bodyOutline.x + 1
        y: bodyOutline.y + 1
        height: bodyOutline.height - 2
        width: Math.max(0, (bodyOutline.width - 2) * (root.pct / 100))
        radius: 1
        color: root.fillColor
    }
}
