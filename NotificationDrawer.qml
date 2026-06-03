// Right-side notification drawer. Toggle via: qs ipc call notifs toggle
//
// Covers the full screen with exclusionMode Ignore so a click outside the
// surface (or Escape) closes it; the visible surface is inset to the right
// edge and slides in/out. Reads from NotificationManager.trackedNotifications.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "shared"

PanelWindow {
    id: drawer

    required property var theme
    required property string fontFamily

    property bool open: false
    property string expandedKey: ""

    anchors {
        top: true
        right: true
        bottom: true
        left: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notification-drawer"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"

    property bool _mapped: false
    visible: _mapped

    onOpenChanged: {
        if (open) {
            unmapTimer.stop();
            _mapped = true;
        } else {
            unmapTimer.restart();
        }
    }

    Timer {
        id: unmapTimer
        interval: 300
        onTriggered: drawer._mapped = false
    }

    property real _slide: open ? 1.0 : 0.0
    Behavior on _slide {
        NumberAnimation {
            duration: 280
            easing.type: Easing.InOutQuart
        }
    }

    property real _now: Date.now()
    Timer {
        interval: 30000
        running: drawer.open
        repeat: true
        triggeredOnStart: true
        onTriggered: drawer._now = Date.now()
    }

    IpcHandler {
        target: "notifs"
        function toggle() { drawer.open = !drawer.open }
        function show()   { drawer.open = true }
        function hide()   { drawer.open = false }
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: drawer.open
        Keys.onEscapePressed: drawer.open = false
    }

    MouseArea {
        anchors.fill: parent
        enabled: drawer.open
        onClicked: drawer.open = false
    }

    Item {
        id: surface

        width: 360
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 10
        anchors.topMargin: 42
        anchors.bottomMargin: 10

        transform: Translate {
            x: (surface.width + 20) * (1 - drawer._slide)
        }

        MouseArea {
            anchors.fill: parent
            enabled: drawer.open
            onClicked: {}
        }

        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            height: 40
            radius: 8
            color: Qt.rgba(drawer.theme.bg.r, drawer.theme.bg.g, drawer.theme.bg.b, 0.92)
            border.color: drawer.theme.border
            border.width: 1

            Text {
                id: titleText
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: NotificationManager.trackedNotifications.values.length > 0 ? "Notifications" : "No notifications"
                color: drawer.theme.fg
                font.family: drawer.fontFamily
                font.pixelSize: 13
                font.bold: true
            }

            Text {
                anchors.left: titleText.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: NotificationManager.trackedNotifications.values.length
                color: drawer.theme.subFg
                font.family: drawer.fontFamily
                font.pixelSize: 11
                visible: NotificationManager.trackedNotifications.values.length > 0
            }

            MouseArea {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: clearText.implicitWidth + 12
                height: 24
                cursorShape: Qt.PointingHandCursor
                visible: NotificationManager.trackedNotifications.values.length > 0
                onClicked: NotificationManager.clearAll()

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: "transparent"
                    border.color: drawer.theme.border
                    border.width: 1
                }

                Text {
                    id: clearText
                    anchors.centerIn: parent
                    text: "Clear all"
                    color: drawer.theme.fg
                    font.family: drawer.fontFamily
                    font.pixelSize: 11
                }
            }
        }

        Item {
            id: divider
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            height: 0
        }

        ScrollView {
            id: scroll
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: divider.bottom
            anchors.bottom: parent.bottom
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            clip: true

            Column {
                width: scroll.availableWidth
                spacing: 12

                Repeater {
                    model: {
                        NotificationManager.trackedNotifications.values.length;
                        return NotificationManager.groupedByApp();
                    }

                    delegate: Column {
                        id: groupWrapper
                        required property var modelData
                        readonly property var group: groupWrapper.modelData
                        readonly property bool isMany: group.notifs.length > 1
                        readonly property bool isExpanded: drawer.expandedKey === group.key

                        width: parent.width
                        spacing: 6

                        Rectangle {
                            visible: groupWrapper.isMany
                            width: parent.width - 16
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 28
                            radius: 4
                            color: "transparent"

                            MouseArea {
                                anchors.fill: parent
                                anchors.rightMargin: 28
                                cursorShape: Qt.PointingHandCursor
                                onClicked: drawer.expandedKey = groupWrapper.isExpanded ? "" : groupWrapper.group.key
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                IconImage {
                                    width: 14
                                    height: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: NotificationManager.iconUrl(groupWrapper.group.appIcon)
                                    visible: source.toString().length > 0
                                    smooth: true
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: groupWrapper.group.appName + " · " + groupWrapper.group.notifs.length
                                    color: drawer.theme.fg
                                    font.family: drawer.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: groupWrapper.isExpanded ? "⌃" : "⌄"
                                    color: drawer.theme.subFg
                                    font.family: drawer.fontFamily
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                id: groupCloseBtn
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NotificationManager.dismissGroup(groupWrapper.group.key)

                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: drawer.theme.subFg
                                    font.family: drawer.fontFamily
                                    font.pixelSize: 14
                                }
                            }
                        }

                        Item {
                            id: stackArea
                            width: groupWrapper.width - 16
                            anchors.horizontalCenter: groupWrapper.horizontalCenter

                            readonly property bool collapsed: groupWrapper.isMany && !groupWrapper.isExpanded
                            readonly property real collapsedPeek: 14
                            readonly property real expandedSpacing: 6
                            readonly property int maxStack: 3

                            // Track the lowest card bottom so the Column above us
                            // gives this stack enough room. childrenRect re-evaluates
                            // automatically as card y/height bindings update.
                            height: childrenRect.height

                            Repeater {
                                id: cardsRepeater
                                model: groupWrapper.group.notifs

                                delegate: NotificationCard {
                                    id: stackedCard
                                    required property var modelData
                                    required property int index
                                    notif: modelData
                                    theme: drawer.theme
                                    fontFamily: drawer.fontFamily
                                    now: drawer._now
                                    width: stackArea.width

                                    z: 1000 - index

                                    _expandProgress: (stackArea.collapsed && index >= stackArea.maxStack) ? 0 : 1

                                    onClicked: {
                                        if (stackArea.collapsed) {
                                            drawer.expandedKey = groupWrapper.group.key;
                                        } else {
                                            const a = NotificationManager.defaultActionOf(stackedCard.notif);
                                            if (a) {
                                                a.invoke();
                                                stackedCard._dismiss();
                                            }
                                        }
                                    }

                                    y: {
                                        if (stackArea.collapsed) {
                                            return Math.min(index, stackArea.maxStack - 1) * stackArea.collapsedPeek;
                                        }
                                        let yPos = 0;
                                        for (let i = 0; i < index; i++) {
                                            const c = cardsRepeater.itemAt(i);
                                            if (c) yPos += c._naturalHeight + stackArea.expandedSpacing;
                                        }
                                        return yPos;
                                    }

                                    Behavior on y {
                                        NumberAnimation { duration: 320; easing.type: Easing.OutQuart }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
