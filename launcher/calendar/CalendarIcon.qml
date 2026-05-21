// Live calendar icon — Apple-dock-style tear-off page. Red header strip
// with today's short weekday name; large day number underneath.
//
// Used as `CalendarProvider.iconComponent`. The launcher injects `theme`
// and `fontFamily` via Loader.onLoaded and sizes us via anchors.fill on
// the icon box (48×48 by default).

import QtQuick

Item {
    id: root
    // Fill the icon-box (48×48 by default). Without this the root has
    // implicit size 0×0 and the Rectangle anchors collapse to nothing.
    anchors.fill: parent

    // Injected by the icon-box Loader in ResultDelegate.qml.
    property var theme: null
    property string fontFamily: ""

    // Re-sample once a minute so the icon flips at midnight even when
    // the launcher has been idle. We only reassign `now` when the calendar
    // day has actually changed — otherwise every minute would invalidate
    // the bound Text bindings for no visible reason.
    property date now: new Date()
    Timer {
        interval: 60 * 1000
        running: true
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

        // Red banner with the weekday name.
        Rectangle {
            id: banner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.round(parent.height * 0.32)
            color: root.theme ? root.theme.danger : "#d20f39"

            Text {
                anchors.centerIn: parent
                // Qt.formatDate(date, "ddd") gives locale-short weekday
                // ("Thu", "Чт", "Do", …) without us shipping translations.
                text: Qt.formatDate(root.now, "ddd").toUpperCase()
                color: "#ffffff"
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Math.round(banner.height * 0.6))
                font.bold: true
                font.letterSpacing: 0.5
            }
        }

        // Day number, centred in the remaining space.
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
