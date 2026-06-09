// Transient toast popups stacked at the top-right corner. Each toast is a
// NotificationCard configured with the toast-specific flags (urgency stripe,
// auto-expire, slide-in animation, "dismissed" signal instead of dismissing
// the underlying notification).

import QtQuick
import Quickshell
import Quickshell.Wayland
import "shared"

PanelWindow {
    id: toasts

    required property var theme
    required property string fontFamily

    property int toastDurationMs: 5000
    property int maxToasts: 5

    property bool drawerOpen: false
    onDrawerOpenChanged: if (drawerOpen) toasts._clear()

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

    mask: Region { item: list }

    ListModel {
        id: toastModel
        dynamicRoles: true
    }

    function _push(notif) {
        if (!notif) return;
        if (toasts.drawerOpen) return;
        for (let i = toastModel.count - 1; i >= 0; i--) {
            const item = toastModel.get(i);
            if (item.notif && item.notif.id === notif.id)
                toastModel.remove(i);
        }
        while (toastModel.count >= toasts.maxToasts)
            toastModel.remove(0);
        toastModel.append({ notif: notif });
    }

    function _expire(notif) {
        if (!notif) return;
        for (let i = toastModel.count - 1; i >= 0; i--) {
            const item = toastModel.get(i);
            if (item.notif === notif || (item.notif && item.notif.id === notif.id))
                toastModel.remove(i);
        }
    }

    function _clear() {
        toastModel.clear();
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
            model: toastModel

            delegate: NotificationCard {
                id: toast
                // `notif` is the model role from toastModel; the required
                // property on NotificationCard is auto-filled from it.
                width: parent.width
                theme: toasts.theme
                fontFamily: toasts.fontFamily
                now: 0

                showHeader: false
                showStripe: true
                animateAppear: true
                dismissesNotif: false
                autoExpireMs: toasts.toastDurationMs

                onClicked: {
                    // A MouseArea fires a synthetic click while the delegate is
                    // torn down on config reload; by then its QML methods are
                    // gone. Bail before invoking the action so a reload can't
                    // silently trigger every visible toast's default action.
                    if (typeof toast._dismiss !== "function")
                        return;
                    const a = NotificationManager.defaultActionOf(toast.notif);
                    if (a) {
                        NotificationManager.invokeAction(toast.notif, a);
                        toast._dismiss();
                    }
                }
                onDismissed: toasts._expire(toast.notif)
            }
        }
    }
}
