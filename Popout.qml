// Generic popout container. Hangs below the bar, attached to an anchor item,
// with a slide-down animation and a soft drop shadow.

import QtQuick
import QtQuick.Effects
import Quickshell

PopupWindow {
    id: popup

    // ── API ──────────────────────────────────────────────────────────────
    required property var bar
    required property var anchorItem
    required property color bgColor
    required property color borderColor
    required property color fgColor
    required property color accentColor
    property color dangerColor: accentColor

    property bool open: false

    // ── Tunables ─────────────────────────────────────────────────────────
    property int popupWidth: 280
    property int cornerRadius: 4
    property int contentPadding: 14
    property int contentPaddingBottom: contentPadding
    property int contentSpacing: 8
    property int animDuration: 380
    property int shadowMargin: 24

    default property alias content: contentArea.data

    // ── Positioning ──────────────────────────────────────────────────────
    property real _snapX: 0
    anchor.window: bar
    anchor.rect.x: _snapX
    anchor.rect.y: bar ? bar.implicitHeight - 1 : 0
    anchor.rect.width: 0
    anchor.rect.height: 0
    anchor.edges: Edges.Bottom

    implicitWidth: popupWidth + shadowMargin * 2
    implicitHeight: contentArea.height + contentPadding + contentPaddingBottom + shadowMargin
    color: "transparent"

    // Slide: 0 = hidden above bar, 1 = fully visible
    property real _slide: open ? 1.0 : 0.0
    Behavior on _slide {
        NumberAnimation {
            duration: popup.animDuration
            easing.type: Easing.InOutQuart
        }
    }

    onOpenChanged: {
        if (open && anchorItem && bar) {
            const leftInBar = anchorItem.mapToItem(bar.contentItem, 0, 0).x;
            _snapX = leftInBar + (anchorItem.width - popupWidth) / 2 - shadowMargin;
        }
    }

    visible: _slide > 0.001

    Item {
        id: clipper
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: popup.shadowMargin
        anchors.rightMargin: popup.shadowMargin
        anchors.bottomMargin: popup.shadowMargin
        clip: false

        Rectangle {
            id: container
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: contentArea.height + popup.cornerRadius + popup.contentPadding + popup.contentPaddingBottom
            radius: popup.cornerRadius
            color: popup.bgColor

            // Slide down from above the bar — translates by its own height.
            transform: Translate {
                y: -container.height * (1 - popup._slide)
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.18
                shadowBlur: 1.0
                shadowVerticalOffset: 6
                shadowHorizontalOffset: 0
            }

            Column {
                id: contentArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: popup.contentPadding
                anchors.rightMargin: popup.contentPadding
                anchors.topMargin: popup.cornerRadius + popup.contentPadding
                spacing: popup.contentSpacing
            }
        }
    }
}
