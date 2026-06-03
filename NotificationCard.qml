// A single notification card. Reused for ungrouped notifs and for members
// of expanded groups. The drawer owns the surrounding chrome (group header
// + insets) — this component renders only the per-notification UI.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import "shared"

Rectangle {
    id: card

    required property var notif
    required property var theme
    required property string fontFamily
    required property real now

    signal clicked()

    readonly property string bodyImage: card.notif.image || ""
    readonly property string appIconSrc: card.notif.appIcon || ""
    readonly property string thumbSrc: NotificationManager.iconUrl(bodyImage || appIconSrc)
    readonly property var defaultAction: NotificationManager.defaultActionOf(card.notif)

    radius: 8
    color: Qt.rgba(card.theme.bg.r, card.theme.bg.g, card.theme.bg.b, 0.92)
    border.color: card.theme.border
    border.width: 1
    clip: true

    readonly property real _naturalHeight: cardCol.implicitHeight + 20
    property bool _dismissing: false
    property real _dismissProgress: 0
    property real _dragX: 0
    property real _expandProgress: 1.0

    height: _naturalHeight * _expandProgress * (1 - _dismissProgress)
    opacity: _expandProgress * (1 - _dismissProgress) * Math.max(0, 1 - _dragX / card.width)
    transform: Translate {
        x: (card.width + 40) * card._dismissProgress + card._dragX
    }

    Behavior on _dismissProgress {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutQuart
            onFinished: if (card._dismissing) card.notif.dismiss()
        }
    }

    Behavior on _dragX {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    Behavior on _expandProgress {
        NumberAnimation { duration: 280; easing.type: Easing.OutQuart }
    }

    function _dismiss() {
        if (_dismissing) return;
        _dismissing = true;
        _dismissProgress = 1;
    }

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
        }
        onPositionChanged: function (mouse) {
            if (!pressed) return;
            const delta = mouse.x - pressX;
            if (delta > dragStartThreshold) dragging = true;
            card._dragX = Math.max(0, delta);
        }
        onReleased: {
            if (dragging && card._dragX > dismissThreshold) {
                card._dismiss();
            } else {
                card._dragX = 0;
            }
        }
        onClicked: {
            if (dragging) return;
            card.clicked();
        }
    }

    Column {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 10
        spacing: 6

        Item {
            width: parent.width
            height: 18

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                IconImage {
                    width: 14
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter
                    source: NotificationManager.iconUrl(card.appIconSrc)
                    visible: source.toString().length > 0 && card.bodyImage.length > 0
                    smooth: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.notif.appName || ""
                    color: card.theme.subFg
                    font.family: card.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }

            Text {
                anchors.right: closeBtn.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: NotificationManager.formatAge(NotificationManager.timestampOf(card.notif), card.now)
                color: card.theme.subFg
                font.family: card.fontFamily
                font.pixelSize: 10
                opacity: 0.8
            }

            MouseArea {
                id: closeBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                cursorShape: Qt.PointingHandCursor
                onClicked: card._dismiss()

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: card.theme.subFg
                    font.family: card.fontFamily
                    font.pixelSize: 14
                }
            }
        }

        Row {
            width: parent.width
            spacing: 10

            Rectangle {
                id: imageBox
                width: 56
                height: 56
                radius: 4
                color: card.theme.border
                clip: true
                visible: card.thumbSrc.length > 0

                IconImage {
                    anchors.fill: parent
                    source: card.thumbSrc
                    smooth: true
                    asynchronous: true
                }
            }

            Column {
                width: parent.width - (imageBox.visible ? imageBox.width + parent.spacing : 0)
                spacing: 3

                Text {
                    width: parent.width
                    text: card.notif.summary || ""
                    color: card.theme.fg
                    font.family: card.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                }

                Text {
                    width: parent.width
                    text: card.notif.body || ""
                    color: card.theme.fg
                    font.family: card.fontFamily
                    font.pixelSize: 11
                    textFormat: card.notif.hasBodyMarkup ? Text.RichText : Text.PlainText
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: 6
                    visible: text.length > 0
                }
            }
        }

        ProgressBar {
            width: parent.width
            from: 0
            to: 100
            value: NotificationManager.progressOf(card.notif)
            visible: NotificationManager.progressOf(card.notif) >= 0
        }

        RowLayout {
            width: parent.width
            spacing: 6
            readonly property var buttonActions: NotificationManager.nonDefaultActions(card.notif)
            visible: buttonActions.length > 0

            Repeater {
                model: parent.buttonActions

                delegate: MouseArea {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.invoke()

                    Rectangle {
                        anchors.fill: parent
                        radius: 3
                        color: "transparent"
                        border.color: card.theme.border
                        border.width: 1
                    }

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.text || parent.modelData.identifier
                        color: card.theme.fg
                        font.family: card.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
