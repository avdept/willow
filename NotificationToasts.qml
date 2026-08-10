// Transient toast stack (top-right). Each is a NotificationCard in toast mode
// (urgency stripe, auto-expire, slide-in; "dismissed" leaves the notification).

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

    // Map the layer surface only while toasts exist. An always-mapped
    // transparent overlay proved flaky over long uptimes (the surface would
    // stop presenting); a fresh surface per burst — same approach the drawer
    // uses — is reliable. Empty = unmapped = fully click-through.
    visible: toastModel.count > 0

    implicitWidth: 372
    // Extra bottom room so the last card's drop shadow isn't clipped.
    // `|| 0` guards against a non-finite list height ever poisoning the
    // window size (which silently unmaps the layer in the compositor).
    implicitHeight: Math.max(1, (list.implicitHeight || 0) + list.anchors.topMargin + 18)

    mask: Region { item: list }

    onVisibleChanged: console.warn("[toast] window visible=" + visible + " modelCount=" + toastModel.count)

    ListModel {
        id: toastModel
        dynamicRoles: true
    }

    // Sticky toasts (never auto-expire) should survive the maxToasts cap.
    function _isPersistent(notif) {
        return notif && NotificationManager.toastDurationOf(notif, toasts.toastDurationMs) === 0;
    }

    // Monotonic row id — uniquely identifies a toast row so we can always
    // remove the exact row even after its `notif` reference is gone.
    property int _seq: 0

    // Drop any rows whose notification has been cleared (defensive: prevents
    // dead "zombie" rows from clogging the model up to maxToasts).
    function _pruneDead() {
        for (let i = toastModel.count - 1; i >= 0; i--) {
            if (!toastModel.get(i).notif) {
                console.warn("[toast] pruned dead row, token=" + toastModel.get(i).token);
                toastModel.remove(i);
            }
        }
    }

    function _push(notif) {
        if (!notif) { console.warn("[toast] _push: null notif"); return; }
        if (toasts.drawerOpen) { console.warn("[toast] _push: suppressed, drawerOpen"); return; }
        console.warn("[toast] _push:", notif.id, notif.appName, "modelCount=" + toastModel.count);
        _pruneDead();
        for (let i = toastModel.count - 1; i >= 0; i--) {
            const item = toastModel.get(i);
            if (item.notif && item.notif.id === notif.id)
                toastModel.remove(i);
        }
        // Drop the oldest auto-expiring toast first; only evict a persistent
        // one if every toast is persistent.
        while (toastModel.count >= toasts.maxToasts) {
            let evict = -1;
            for (let i = 0; i < toastModel.count; i++) {
                if (!_isPersistent(toastModel.get(i).notif)) { evict = i; break; }
            }
            toastModel.remove(evict >= 0 ? evict : 0);
        }
        toastModel.append({ notif: notif, token: ++toasts._seq });
        console.warn("[toast] appended token=" + toasts._seq + " modelCount=" + toastModel.count);
    }

    // Remove the exact row by its token (robust even if `notif` is now null).
    function _expireToken(token) {
        for (let i = toastModel.count - 1; i >= 0; i--) {
            if (toastModel.get(i).token === token) {
                toastModel.remove(i);
                console.warn("[toast] expired token=" + token + " modelCount=" + toastModel.count);
                return;
            }
        }
        console.warn("[toast] expire MISS token=" + token);
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
        anchors.rightMargin: 14
        anchors.topMargin: 40
        // Side gaps (window is wider than the cards) leave room for the shadow.
        width: parent.width - 28
        spacing: 14

        Repeater {
            model: toastModel

            delegate: NotificationCard {
                id: toast
                required property int token
                width: parent.width
                theme: toasts.theme
                fontFamily: toasts.fontFamily
                now: 0

                showHeader: false
                showStripe: true
                animateAppear: true
                dismissesNotif: false
                autoExpireMs: NotificationManager.toastDurationOf(toast.notif, toasts.toastDurationMs)

                Component.onCompleted: console.warn("[toast] delegate created: token=" + toast.token,
                    toast.notif ? toast.notif.id : "null",
                    "natH=" + toast._naturalHeight, "w=" + toast.width, "autoExpire=" + toast.autoExpireMs)

                onClicked: {
                    // Bail on the synthetic click fired while the delegate is
                    // torn down on reload (its methods are already gone).
                    if (typeof toast._dismiss !== "function")
                        return;
                    const a = NotificationManager.defaultActionOf(toast.notif);
                    if (a) {
                        NotificationManager.invokeAction(toast.notif, a);
                        toast._dismiss();
                    }
                }
                onDismissed: toasts._expireToken(toast.token)
            }
        }
    }
}
