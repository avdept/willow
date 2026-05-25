// Apple-dock-style tear-off calendar icon. Used as
// CalendarProvider.iconComponent. Theme/fontFamily/launcherOpen are
// injected by ResultDelegate's icon Loader.

import QtQuick

Item {
    id: root
    // Without anchors.fill, root has implicit 0×0 and child anchors collapse.
    anchors.fill: parent

    property var theme: null
    property string fontFamily: ""
    property bool launcherOpen: false

    // Re-sample on open to catch midnight rollover that happened while
    // hidden; ticker catches rollover during an open session.
    property date now: new Date()
    onLauncherOpenChanged: if (launcherOpen) {
        const next = new Date();
        if (next.toDateString() !== root.now.toDateString())
            root.now = next;
    }
    Timer {
        interval: 60 * 1000
        running: root.launcherOpen
        repeat: true
        onTriggered: {
            const next = new Date();
            if (next.toDateString() !== root.now.toDateString())
                root.now = next;
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 6
        clip: true
        color: root.theme ? Qt.rgba(root.theme.bg.r, root.theme.bg.g, root.theme.bg.b, 0.92) : "#ffffff"
        border.color: root.theme ? root.theme.border : "#444"
        border.width: 1

        Rectangle {
            id: banner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.round(parent.height * 0.32)
            color: root.theme ? root.theme.danger : "#d20f39"

            Text {
                anchors.centerIn: parent
                // "ddd" gives locale-short weekday — no translations needed.
                text: Qt.formatDate(root.now, "ddd").toUpperCase()
                color: "#ffffff"
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Math.round(banner.height * 0.6))
                font.bold: true
                font.letterSpacing: 0.5
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: banner.bottom
            anchors.bottom: parent.bottom
            text: root.now.getDate()
            color: root.theme ? root.theme.fg : "#000"
            font.family: root.fontFamily
            font.pixelSize: Math.max(14, Math.round((parent.height - banner.height) * 0.7))
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
