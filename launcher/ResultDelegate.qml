// One row in the launcher results list.

import QtQuick
import Quickshell.Widgets

Item {
    id: row

    required property var modelData
    required property int index

    // Wired by Launcher
    property int currentIndex: -1
    property color bgColor
    property color fgColor
    property color subFgColor
    property color accentColor
    property color borderColor
    property string fontFamily

    signal activated(int index)
    signal hovered(int index)

    readonly property bool isSelected: index === currentIndex

    height: 44
    anchors.left:  parent ? parent.left  : undefined
    anchors.right: parent ? parent.right : undefined

    // Selection background
    Rectangle {
        anchors.fill: parent
        radius: 6
        color: row.isSelected
            ? Qt.rgba(row.accentColor.r, row.accentColor.g, row.accentColor.b, 0.18)
            : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
        onClicked: row.activated(row.index)
        // Hover wins over keyboard selection — first entry into a row claims it.
        onContainsMouseChanged: if (containsMouse) row.hovered(row.index)
        onPositionChanged:      if (!row.isSelected) row.hovered(row.index)
    }

    Row {
        id: rowLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12

        // Icon: primary URL with a generic-app fallback on load error,
        // and a nerd-font glyph if even the fallback can't render.
        Item {
            id: iconBox
            width: 32
            height: 32
            anchors.verticalCenter: parent.verticalCenter

            readonly property string primaryUrl: row.modelData?.iconUrl ?? ""
            property bool primaryFailed: false

            // Delegates are recycled — reset the failure flag on row reuse.
            onPrimaryUrlChanged: primaryFailed = false

            IconImage {
                id: iconImg
                anchors.fill: parent
                source: iconBox.primaryFailed
                    ? "image://icon/application-x-executable"
                    : iconBox.primaryUrl
                visible: status === Image.Ready && source !== ""
                asynchronous: true
                smooth: true
                implicitSize: 32

                onStatusChanged: {
                    if (status === Image.Error && !iconBox.primaryFailed)
                        iconBox.primaryFailed = true;
                }
            }

            // Glyph fallback. Menu category rows get a larger glyph than
            // app-row icon fallbacks.
            Text {
                anchors.centerIn: parent
                visible: !iconImg.visible
                text: row.modelData?.iconText ?? ""
                color: row.fgColor
                font.family: row.fontFamily
                font.pixelSize: row.modelData?.chevron ? 32 : 18
                opacity: 0.9
            }
        }

        // Title + subtitle
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: rowLayout.width - iconBox.width - tagBox.width - rowLayout.spacing * 2
            spacing: 2

            Text {
                width: parent.width
                text: row.modelData?.title ?? ""
                color: row.fgColor
                font.family: row.fontFamily
                font.pixelSize: 13
                font.bold: row.isSelected
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: row.modelData?.subtitle ?? ""
                color: row.subFgColor
                font.family: row.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }

        // Right-side affordance — chevron for menu entries, tag pill for results.
        Item {
            id: tagBox
            anchors.verticalCenter: parent.verticalCenter
            width: row.modelData?.chevron ? 16 : (tagText.implicitWidth + 14)
            height: 18

            // Chevron (menu mode)
            Text {
                anchors.centerIn: parent
                visible: row.modelData?.chevron === true
                text: ""
                color: row.subFgColor
                font.family: row.fontFamily
                font.pixelSize: 14
                opacity: row.isSelected ? 1.0 : 0.6
            }

            // Tag pill (result mode)
            readonly property bool _showTag: !row.modelData?.chevron && (row.modelData?.providerTag ?? "").length > 0
            Rectangle {
                anchors.fill: parent
                visible: tagBox._showTag
                radius: 9
                color: Qt.rgba(row.borderColor.r, row.borderColor.g, row.borderColor.b, 0.35)
            }
            Text {
                id: tagText
                anchors.centerIn: parent
                visible: tagBox._showTag
                text: row.modelData?.providerTag ?? ""
                color: row.subFgColor
                font.family: row.fontFamily
                font.pixelSize: 9
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.5
            }
        }
    }
}
