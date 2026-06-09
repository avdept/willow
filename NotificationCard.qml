// Unified notification visual. Used by the drawer (with header + age) and
// by the transient toast popup (with urgency stripe + auto-expire). Toggle
// the per-context behavior via the boolean properties below.

import QtQuick
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "shared"

Rectangle {
    id: card

    // ── Data ────────────────────────────────────────────────────────────
    required property var notif
    required property var theme
    required property string fontFamily
    required property real now

    // ── Per-context configuration ───────────────────────────────────────
    property bool inGroup: false           // Stacked in a multi-notif drawer group
    property bool showHeader: true         // Drawer: app icon + name + age row
    property bool showStripe: false        // Toast: urgency-colored left bar
    property bool animateAppear: false     // Toast: slide-in from the right
    property bool dismissesNotif: true     // false = emit `dismissed` only (toast)
    property int autoExpireMs: 0           // > 0 = auto _dismiss after delay (toast)

    // Group lead-card controls — drawer sets these on the front card of a
    // multi-notif group so the title doubles as the group toggle.
    property bool groupExpandable: false
    property bool groupExpanded: false
    property bool dismissesGroup: false    // X button dismisses the whole group

    signal clicked
    signal dismissed
    signal groupToggleRequested
    signal groupDismissRequested

    readonly property var defaultAction: NotificationManager.defaultActionOf(card.notif)

    // ── Visual ──────────────────────────────────────────────────────────
    radius: 0
    color: Qt.rgba(card.theme.bg.r, card.theme.bg.g, card.theme.bg.b, card.inGroup ? 0.9 : 0.78)
    border.color: card.theme.border
    border.width: 1
    clip: true

    // ── Animation state ─────────────────────────────────────────────────
    readonly property real _naturalHeight: cardCol.implicitHeight + cardCol.anchors.topMargin + cardCol.anchors.bottomMargin
    property bool _dismissing: false
    property real _visProgress: animateAppear ? 0 : 1
    property real _dragX: 0
    property real _expandProgress: 1.0

    Component.onCompleted: if (animateAppear)
        _visProgress = 1

    Behavior on _visProgress {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutQuart
            onFinished: {
                if (card._dismissing) {
                    if (card.dismissesNotif && card.notif)
                        card.notif.dismiss();
                    card.dismissed();
                }
            }
        }
    }
    Behavior on _dragX {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    Behavior on _expandProgress {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutQuart
        }
    }

    height: _naturalHeight * _expandProgress * _visProgress
    opacity: _expandProgress * _visProgress * Math.max(0, 1 - _dragX / Math.max(1, card.width))
    transform: Translate {
        x: (card.width + 40) * (1 - _visProgress) + card._dragX
    }

    function _dismiss() {
        if (_dismissing)
            return;
        _dismissing = true;
        _visProgress = 0;
    }

    // ── Lifecycle plumbing ──────────────────────────────────────────────
    Timer {
        id: expireTimer
        interval: Math.max(1, card.autoExpireMs)
        running: card.autoExpireMs > 0
        repeat: false
        onTriggered: card._dismiss()
    }

    HoverHandler {
        enabled: card.autoExpireMs > 0
        onHoveredChanged: hovered ? expireTimer.stop() : expireTimer.restart()
    }

    Connections {
        target: card.notif
        function onClosed() {
            if (!card.dismissesNotif)
                card.dismissed();
        }
    }

    // ── Urgency stripe (toast) ──────────────────────────────────────────
    Rectangle {
        id: stripe
        visible: card.showStripe
        width: 3
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 4
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: 1.5
        color: {
            if (!card.notif)
                return card.theme.accent;
            const u = card.notif.urgency;
            if (u === NotificationUrgency.Critical)
                return card.theme.danger;
            if (u === NotificationUrgency.Low)
                return card.theme.subFg;
            return card.theme.accent;
        }
    }

    // ── Body interaction (click + swipe-to-dismiss) ─────────────────────
    MouseArea {
        id: bodyArea
        anchors.fill: parent
        cursorShape: card.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor

        property real pressX: 0
        property bool dragging: false
        readonly property int dragStartThreshold: 6
        readonly property real dismissThreshold: card.width * 0.33

        onPressed: function (mouse) {
            pressX = mouse.x;
            dragging = false;
            expireTimer.stop();
        }
        onPositionChanged: function (mouse) {
            if (!pressed)
                return;
            const delta = mouse.x - pressX;
            if (delta > dragStartThreshold)
                dragging = true;
            card._dragX = Math.max(0, delta);
        }
        onReleased: {
            if (dragging && card._dragX > dismissThreshold) {
                card._dismiss();
            } else {
                card._dragX = 0;
                if (card.autoExpireMs > 0)
                    expireTimer.restart();
            }
        }
        onClicked: {
            if (dragging)
                return;
            card.clicked();
        }
    }

    // ── Close (×) button — top right of the rectangle ───────────────────
    MouseArea {
        id: closeBtn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: card.showHeader ? cardCol.anchors.topMargin : 4
        anchors.rightMargin: 6
        width: 18
        height: 18
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (card.dismissesGroup) {
                card.groupDismissRequested();
            } else {
                card._dismiss();
            }
        }

        Text {
            anchors.centerIn: parent
            text: "×"
            color: card.theme.subFg
            font.family: card.fontFamily
            font.pixelSize: 16
        }
    }

    // ── Content column ──────────────────────────────────────────────────
    Column {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.showStripe ? 14 : 12
        anchors.rightMargin: 28
        anchors.topMargin: card.showStripe ? 12 : 10
        anchors.bottomMargin: card.showStripe ? 12 : 10
        spacing: 6

        Item {
            visible: card.showHeader
            width: parent.width
            height: visible ? 18 : 0

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                IconImage {
                    width: 14
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter
                    source: NotificationManager.iconUrl(card.notif ? (card.notif.appIcon || "") : "")
                    visible: source.toString().length > 0 && card.notif && (card.notif.image || "").length > 0
                    smooth: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.notif ? (card.notif.appName || "") : ""
                    color: card.theme.subFg
                    font.family: card.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    visible: text.length > 0
                }

                MouseArea {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 18
                    visible: card.groupExpandable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.groupToggleRequested()

                    Text {
                        id: chevron
                        anchors.centerIn: parent
                        text: ""
                        color: card.theme.fg
                        font.family: card.fontFamily
                        font.pixelSize: 10
                        rotation: card.groupExpanded ? 180 : 0
                        Behavior on rotation {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: card.notif ? NotificationManager.formatAge(NotificationManager.timestampOf(card.notif), card.now) : ""
                color: card.theme.subFg
                font.family: card.fontFamily
                font.pixelSize: 10
                opacity: 0.8
            }
        }

        NotificationContent {
            width: parent.width
            notif: card.notif
            theme: card.theme
            fontFamily: card.fontFamily
            imageSize: card.showStripe ? 48 : 56
            bodyLines: card.showStripe ? 4 : 6
            actionHeight: card.showStripe ? 22 : 24
            preferBodyImage: true
            imageBg: card.showStripe ? "transparent" : card.theme.border
            onActionInvoked: function (action) {
                // Ignore the synthetic click emitted while the card is torn
                // down on reload (see the toast onClicked guard).
                if (typeof card._dismiss !== "function")
                    return;
                NotificationManager.invokeAction(card.notif, action);
                if (!card.dismissesNotif)
                    card._dismiss();
            }
        }
    }
}
