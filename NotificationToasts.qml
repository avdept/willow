// Transient toast popups stacked at the top-right corner. Each toast
// auto-expires after toastDurationMs, leaving the notification in the
// drawer's persistent list. Click a toast to dismiss it from the toast
// stack early (does not dismiss the underlying notification).

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "shared"

PanelWindow {
    id: toasts

    required property var theme
    required property string fontFamily

    property int toastDurationMs: 5000
    property int maxToasts: 5

    // When the drawer is open the user is already reading the list — hide
    // existing toasts immediately (no animation) and suppress new ones.
    property bool drawerOpen: false
    onDrawerOpenChanged: if (drawerOpen) toasts.items = []

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notification-toasts"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        right: true
    }
    exclusiveZone: 0
    color: "transparent"

    implicitWidth: 360
    implicitHeight: Math.max(1, list.implicitHeight + list.anchors.topMargin + 8)

    // Input region tracks the visible list bounds; when items is empty the
    // list has 0 height and the panel passes clicks through.
    mask: Region { item: list }

    property var items: []

    function _push(notif) {
        if (!notif) return;
        if (toasts.drawerOpen) return;
        // Treat a same-id arrival as a replace: drop the existing toast (if any)
        // and re-add at the end so the slide-in animation + timer restart.
        let next = toasts.items.filter(x => !x.notif || x.notif.id !== notif.id);
        if (next.length >= toasts.maxToasts)
            next = next.slice(1);
        toasts.items = next.concat([{ notif: notif }]);
    }

    function _expire(notif) {
        toasts.items = toasts.items.filter(x => x.notif && x.notif !== notif);
    }

    Connections {
        target: NotificationManager
        function onNewNotification(notif) {
            toasts._push(notif);
        }
    }

    Column {
        id: list
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 8
        anchors.topMargin: 40
        width: parent.width - 16
        spacing: 8

        Repeater {
            model: toasts.items

            delegate: Rectangle {
                id: toast
                required property var modelData
                readonly property var notif: toast.modelData ? toast.modelData.notif : null
                readonly property string iconSrc: toast.notif ? (toast.notif.appIcon || toast.notif.image || "") : ""

                width: parent.width
                radius: 8
                color: Qt.rgba(toasts.theme.bg.r, toasts.theme.bg.g, toasts.theme.bg.b, 0.92)
                border.color: toasts.theme.border
                border.width: 1
                clip: true

                readonly property real _naturalHeight: toastContent.implicitHeight + 24
                property bool _dismissing: false
                property real _visProgress: 0
                Component.onCompleted: _visProgress = 1
                Behavior on _visProgress {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.OutQuart
                        onFinished: if (toast._dismissing) toasts._expire(toast.notif)
                    }
                }

                property real _dragX: 0
                Behavior on _dragX {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                height: _naturalHeight * _visProgress
                opacity: _visProgress * Math.max(0, 1 - _dragX / toast.width)
                transform: Translate {
                    x: (toast.width + 40) * (1 - _visProgress) + toast._dragX
                }

                function _dismiss() {
                    if (_dismissing) return;
                    _dismissing = true;
                    _visProgress = 0;
                }

                Timer {
                    id: expireTimer
                    interval: toasts.toastDurationMs
                    running: true
                    repeat: false
                    onTriggered: toast._dismiss()
                }

                Connections {
                    target: toast.notif
                    function onClosed() {
                        toasts._expire(toast.notif);
                    }
                }

                HoverHandler {
                    onHoveredChanged: hovered ? expireTimer.stop() : expireTimer.restart()
                }

                MouseArea {
                    id: bodyArea
                    anchors.fill: parent
                    cursorShape: NotificationManager.defaultActionOf(toast.notif) ? Qt.PointingHandCursor : Qt.ArrowCursor

                    property real pressX: 0
                    property bool dragging: false
                    readonly property int dragStartThreshold: 6
                    readonly property real dismissThreshold: toast.width * 0.33

                    onPressed: function (mouse) {
                        pressX = mouse.x;
                        dragging = false;
                        expireTimer.stop();
                    }
                    onPositionChanged: function (mouse) {
                        if (!pressed) return;
                        const delta = mouse.x - pressX;
                        if (delta > dragStartThreshold) dragging = true;
                        toast._dragX = Math.max(0, delta);
                    }
                    onReleased: {
                        if (dragging && toast._dragX > dismissThreshold) {
                            toast._dismiss();
                        } else {
                            toast._dragX = 0;
                            expireTimer.restart();
                        }
                    }
                    onClicked: {
                        if (dragging) return;
                        const a = NotificationManager.defaultActionOf(toast.notif);
                        if (a) {
                            a.invoke();
                            toast._dismiss();
                        }
                    }
                }

                Rectangle {
                    id: stripe
                    width: 3
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1
                    radius: 2
                    color: {
                        if (!toast.notif) return toasts.theme.accent;
                        const u = toast.notif.urgency;
                        if (u === NotificationUrgency.Critical) return toasts.theme.danger;
                        if (u === NotificationUrgency.Low)      return toasts.theme.subFg;
                        return toasts.theme.accent;
                    }
                }

                MouseArea {
                    id: closeBtn
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 4
                    anchors.rightMargin: 6
                    width: 18
                    height: 18
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toast._dismiss()

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: toasts.theme.subFg
                        font.family: toasts.fontFamily
                        font.pixelSize: 16
                    }
                }

                Column {
                    id: toastContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 14
                    anchors.rightMargin: 28
                    anchors.topMargin: 12
                    anchors.bottomMargin: 12
                    spacing: 4

                    Row {
                        width: parent.width
                        spacing: 10

                        Rectangle {
                            id: toastImageBox
                            width: 48
                            height: 48
                            radius: 4
                            color: toasts.theme.border
                            clip: true
                            visible: !!(toast.notif && toast.notif.image)

                            Image {
                                anchors.fill: parent
                                source: toast.notif ? (toast.notif.image || "") : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        Column {
                            width: parent.width - (toastImageBox.visible ? toastImageBox.width + parent.spacing : 0)
                            spacing: 3

                            Text {
                                width: parent.width
                                text: toast.notif ? (toast.notif.summary || "") : ""
                                color: toasts.theme.fg
                                font.family: toasts.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: toast.notif ? (toast.notif.body || "") : ""
                                color: toasts.theme.fg
                                font.family: toasts.fontFamily
                                font.pixelSize: 11
                                textFormat: (toast.notif && toast.notif.hasBodyMarkup) ? Text.RichText : Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                visible: text.length > 0
                            }
                        }
                    }

                    ProgressBar {
                        width: parent.width
                        from: 0
                        to: 100
                        value: NotificationManager.progressOf(toast.notif)
                        visible: NotificationManager.progressOf(toast.notif) >= 0
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 6
                        readonly property var buttonActions: NotificationManager.nonDefaultActions(toast.notif)
                        visible: buttonActions.length > 0

                        Repeater {
                            model: parent.buttonActions

                            delegate: MouseArea {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    modelData.invoke();
                                    toast._dismiss();
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 3
                                    color: "transparent"
                                    border.color: toasts.theme.border
                                    border.width: 1
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.text || parent.modelData.identifier
                                    color: toasts.theme.fg
                                    font.family: toasts.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
