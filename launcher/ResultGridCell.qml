// One cell in a grid-layout results pane (e.g. Style → Theme picker).
//
// Visual: rounded card with a preview image (iconUrl) filling the top
// area and the title below. Selection draws an accent-colored border.
// A small check glyph in the top-right marks the current item — the
// provider signals this via `modelData.data.isCurrent`.

import QtQuick

Item {
    id: cell

    required property var modelData
    required property int index

    // Wired by Launcher
    property int currentIndex: -1
    required property var theme       // .bg .fg .subFg .accent .border
    required property string fontFamily
    // Reserved for future grid cells that host live Component icons —
    // see ResultDelegate.qml for the threading pattern.
    property bool launcherOpen: false

    signal activated(int index)
    signal hovered(int index)

    readonly property bool isSelected: index === currentIndex
    readonly property bool isCurrent: modelData?.data?.isCurrent === true

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 6
        radius: 8
        color: cell.isSelected
            ? Qt.rgba(cell.theme.accent.r, cell.theme.accent.g, cell.theme.accent.b, 0.20)
            : Qt.rgba(cell.theme.border.r, cell.theme.border.g, cell.theme.border.b, 0.18)
        border.color: cell.isSelected
            ? cell.theme.accent
            : (cell.isCurrent
                ? Qt.rgba(cell.theme.accent.r, cell.theme.accent.g, cell.theme.accent.b, 0.6)
                : cell.theme.border)
        border.width: cell.isSelected ? 2 : 1
        Behavior on color        { ColorAnimation { duration: 90 } }
        Behavior on border.color { ColorAnimation { duration: 90 } }

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            // Preview area
            Item {
                id: previewBox
                width: parent.width
                height: parent.height - nameLabel.implicitHeight - parent.spacing
                clip: true

                Image {
                    id: previewImg
                    anchors.fill: parent
                    source: cell.modelData?.iconUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    cache: true
                    visible: status === Image.Ready
                }

                // Placeholder shown while loading or when no preview is
                // available.
                Rectangle {
                    anchors.fill: parent
                    visible: !previewImg.visible
                    color: Qt.rgba(cell.theme.border.r, cell.theme.border.g, cell.theme.border.b, 0.25)
                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData?.iconText ?? ""
                        color: cell.theme.subFg
                        font.family: cell.fontFamily
                        font.pixelSize: 32
                        opacity: 0.7
                    }
                }

                // "current" badge — top-right corner check glyph
                Rectangle {
                    visible: cell.isCurrent
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 4
                    width: 22
                    height: 22
                    radius: 11
                    color: cell.theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: ""
                        color: cell.theme.bg
                        font.family: cell.fontFamily
                        font.pixelSize: 11
                    }
                }
            }

            Text {
                id: nameLabel
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: cell.modelData?.title ?? ""
                color: cell.theme.fg
                font.family: cell.fontFamily
                font.pixelSize: 12
                font.bold: cell.isSelected || cell.isCurrent
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
        onClicked: cell.activated(cell.index)
        onContainsMouseChanged: if (containsMouse) cell.hovered(cell.index)
        onPositionChanged:      if (!cell.isSelected) cell.hovered(cell.index)
    }
}
