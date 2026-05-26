import QtQuick
import Quickshell.Widgets

Item {
    id: row

    required property var modelData
    required property int index

    property int currentIndex: -1
    required property var theme
    required property string fontFamily
    required property bool launcherOpen

    property int iconSize: 28

    signal activated(int index)
    signal hovered(int index)

    readonly property bool isSelected: index === currentIndex

    height: iconSize + 16

    Rectangle {
        anchors.fill: parent
        color: row.isSelected
            ? Qt.rgba(row.theme.accent.r, row.theme.accent.g, row.theme.accent.b, 0.18)
            : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
        onClicked: row.activated(row.index)
        onContainsMouseChanged: if (containsMouse) row.hovered(row.index)
        onPositionChanged:      if (!row.isSelected) row.hovered(row.index)
    }

    Item {
        id: iconBox
        width: row.iconSize
        height: row.iconSize
        anchors.centerIn: parent

        readonly property var customIcon: row.modelData?.iconComponent ?? null
        readonly property string primaryUrl: row.modelData?.iconUrl ?? ""
        property bool primaryFailed: false

        onPrimaryUrlChanged: primaryFailed = false

        readonly property bool _hasGlyph: (row.modelData?.iconText ?? "").length > 0

        Loader {
            id: customIconLoader
            anchors.fill: parent
            active: iconBox.customIcon !== null
            sourceComponent: iconBox.customIcon
            visible: active && status === Loader.Ready
            onLoaded: if (item) {
                item.theme = row.theme;
                item.fontFamily = row.fontFamily;
                if (item.launcherOpen !== undefined)
                    item.launcherOpen = Qt.binding(() => row.launcherOpen);
            }
        }

        IconImage {
            id: iconImg
            anchors.fill: parent
            source: iconBox.primaryFailed
                ? (iconBox._hasGlyph ? "" : "image://icon/application-x-executable")
                : iconBox.primaryUrl
            visible: !customIconLoader.active && status === Image.Ready && source !== ""
            asynchronous: true
            smooth: true
            implicitSize: row.iconSize

            onStatusChanged: {
                if (status === Image.Error && !iconBox.primaryFailed)
                    iconBox.primaryFailed = true;
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !customIconLoader.active && !iconImg.visible
            text: row.modelData?.iconText ?? ""
            color: row.theme.fg
            font.family: row.fontFamily
            font.pixelSize: row.iconSize
            opacity: 0.9
        }
    }
}
