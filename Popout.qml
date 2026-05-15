// Generic popout container. Hangs below the bar, attached to an anchor item,
// with a fluid open/close animation and a soft drop shadow. Children of this
// component land inside `contentArea` with `contentPadding` on all sides.

import QtQuick
import QtQuick.Effects
import Quickshell

PopupWindow {
    id: popup

    // ── API (caller-provided) ────────────────────────────────────────────
    required property var bar          // the bar PanelWindow
    required property var anchorItem   // bar Item the popup hangs below
    required property color bgColor
    required property color borderColor
    required property color fgColor
    required property color accentColor

    property bool open: false

    // ── Tunables ─────────────────────────────────────────────────────────
    property int popupWidth: 280
    property int popupHeight: 140
    property int cornerRadius: 12
    property int contentPadding: 14
    property int animDuration: 200
    property int shadowMargin: 24      // slack around container for the shadow

    // Children of Popout end up inside contentArea.
    default property alias content: contentArea.data

    // ── Positioning ──────────────────────────────────────────────────────
    property real _snapX: 0

    onOpenChanged: {
        if (open && anchorItem && bar) {
            const leftInBar = anchorItem.mapToItem(bar.contentItem, 0, 0).x;
            // Center popup horizontally on anchor; the visible container sits
            // inside the window with shadowMargin slack on the left.
            _snapX = leftInBar + (anchorItem.width - popupWidth) / 2 - shadowMargin;
        }
    }

    anchor.window: bar
    anchor.rect.x: _snapX
    anchor.rect.y: bar ? bar.implicitHeight - 1 : 0   // 1px overlap with bar
    anchor.rect.width: 0
    anchor.rect.height: 0
    anchor.edges: Edges.Bottom

    implicitWidth: popupWidth + shadowMargin * 2
    implicitHeight: popupHeight + cornerRadius + shadowMargin
    color: "transparent"

    visible: open || container.opacity > 0.01

    // Clip wrapper hides the top corners (above the bar) so only the bottom
    // corners appear rounded. The shadow lives outside this clip rect, around
    // the visible portion of the container.
    Item {
        id: clipper
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: popup.shadowMargin
        anchors.rightMargin: popup.shadowMargin
        anchors.bottomMargin: popup.shadowMargin
        // No top clip — top of container is naturally hidden by the bar above.
        clip: false

        Rectangle {
            id: container
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height + popup.cornerRadius
            radius: popup.cornerRadius
            color: popup.bgColor

            transformOrigin: Item.Top
            scale: popup.open ? 1.0 : 0.94
            opacity: popup.open ? 1.0 : 0.0

            // Soft drop shadow under the popup.
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.18
                shadowBlur: 1.0
                shadowVerticalOffset: 6
                shadowHorizontalOffset: 0
            }

            Behavior on scale {
                NumberAnimation {
                    duration: popup.animDuration
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Math.max(120, popup.animDuration - 20)
                    easing.type: Easing.OutCubic
                }
            }

            Item {
                id: contentArea
                anchors.fill: parent
                anchors.topMargin: popup.cornerRadius + popup.contentPadding
                anchors.bottomMargin: popup.contentPadding
                anchors.leftMargin: popup.contentPadding
                anchors.rightMargin: popup.contentPadding
            }
        }
    }
}
