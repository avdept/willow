// Self-contained dropdown: a clickable trigger chip displaying the
// current value, plus a popup list. Controlled component — caller
// owns `open` and handles `triggerClicked` and `selected`.
//
// Customize what each row renders via `labelFor(item, index)`.
// Mark the active row via `isSelected(item, index)` — it gets a
// check mark and a bold label. Use `currentLabel` to drive the
// trigger text; `emphasized: true` switches to the accent style.

import QtQuick

Rectangle {
    id: root

    property var theme: null
    property string fontFamily: ""
    property var items: []

    property var labelFor: (item, index) => item
    property var isSelected: (item, index) => false

    property string currentLabel: ""
    property string placeholder: "Select…"
    property bool emphasized: false
    property bool bordered: false
    property bool openUpward: false
    property bool open: false

    property int maxHeight: 260
    property int rowHeight: 26
    property int popupWidth: 0

    signal triggerClicked
    signal selected(int index, var item)

    implicitWidth: triggerText.implicitWidth + 14
    implicitHeight: 20
    color: triggerMa.containsMouse && root.theme ? (root.emphasized ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.10) : Qt.rgba(root.theme.fg.r, root.theme.fg.g, root.theme.fg.b, 0.08)) : "transparent"
    border.color: root.theme ? (root.emphasized ? root.theme.accent : root.theme.border) : "#444"
    border.width: bordered ? 1 : 0

    Text {
        id: triggerText
        anchors.centerIn: parent
        text: (root.currentLabel.length > 0 ? root.currentLabel : root.placeholder) + "  ▾"
        color: root.theme ? (root.emphasized ? root.theme.accent : root.theme.subFg) : "#888"
        font.family: root.fontFamily
        font.pixelSize: 11
        font.bold: root.emphasized
    }

    MouseArea {
        id: triggerMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.triggerClicked()
    }

    Rectangle {
        id: popup
        visible: root.open
        z: 100
        anchors.right: parent.right
        y: root.openUpward ? -height - 6 : root.height + 6
        width: root.popupWidth > 0 ? root.popupWidth : Math.max(180, root.width)
        color: root.theme ? Qt.rgba(root.theme.bg.r, root.theme.bg.g, root.theme.bg.b, 0.98) : "#fff"
        border.color: root.theme ? root.theme.border : "#444"
        border.width: 1
        height: Math.min(root.maxHeight, (list.count === 0 ? root.rowHeight : list.contentHeight) + 12)

        ListView {
            id: list
            anchors.fill: parent
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            clip: true
            model: root.items
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool _selected: root.isSelected(modelData, index)
                width: list.width
                height: root.rowHeight
                color: ma.containsMouse && root.theme ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.14) : (_selected && root.theme ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.20) : "transparent")

                Text {
                    anchors.left: parent.left
                    anchors.right: tick.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8
                    anchors.rightMargin: 4
                    text: root.labelFor(row.modelData, row.index)
                    color: root.theme ? root.theme.fg : "#000"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.bold: row._selected
                    elide: Text.ElideRight
                }

                Text {
                    id: tick
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 8
                    width: 12
                    horizontalAlignment: Text.AlignHCenter
                    visible: row._selected
                    text: "✓"
                    color: root.theme ? root.theme.accent : "#1e66f5"
                    font.family: root.fontFamily
                    font.pixelSize: 11
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(row.index, row.modelData)
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                visible: list.count === 0
                height: root.rowHeight
                color: "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8
                    text: "No items"
                    color: root.theme ? root.theme.subFg : "#888"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.italic: true
                    opacity: 0.7
                }
            }
        }
    }
}
