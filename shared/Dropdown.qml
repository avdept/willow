// Generic popup list used for header dropdowns (backend / model
// picker in chat, etc.). Caller positions it (x/y/width), passes a
// flat `items` array, and listens for `selected(index, item)`.
//
// Customize what each row renders via `labelFor(item, index)`
// (defaults to returning the item itself, so plain string arrays
// work out of the box). The active row gets a check mark + bold
// label — supply `isSelected(item, index)` to drive it.

import QtQuick

Rectangle {
    id: root

    property var theme: null
    property string fontFamily: ""
    property var items: []
    property int maxHeight: 260
    property int rowHeight: 26

    property var labelFor: (item, index) => item
    property var isSelected: (item, index) => false

    signal selected(int index, var item)

    radius: 6
    color: theme ? Qt.rgba(theme.bg.r, theme.bg.g, theme.bg.b, 0.98) : "#fff"
    border.color: theme ? theme.border : "#444"
    border.width: 1
    height: Math.min(maxHeight, list.contentHeight + 8)

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: 4
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
            radius: 4
            color: ma.containsMouse && root.theme
                ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.14)
                : (_selected && root.theme
                    ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.20)
                    : "transparent")

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

        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: "(empty)"
            color: root.theme ? root.theme.subFg : "#888"
            font.family: root.fontFamily
            font.pixelSize: 11
            opacity: 0.7
        }
    }
}
