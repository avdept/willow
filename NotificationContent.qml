import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import "shared"

Column {
    id: content

    required property var notif
    required property var theme
    required property string fontFamily

    property int imageSize: 56
    property int titleLines: 2
    property int bodyLines: 6
    property int actionHeight: 24
    property bool preferBodyImage: true
    property color imageBg: theme.border

    signal actionInvoked(var action)

    spacing: 6

    readonly property string bodyImage: notif ? (notif.image || "") : ""
    readonly property string appIcon: notif ? (notif.appIcon || "") : ""
    readonly property string thumbSrc: NotificationManager.iconUrl(preferBodyImage ? (bodyImage || appIcon) : (bodyImage || ""))
    readonly property int progress: NotificationManager.progressOf(notif)

    Row {
        width: Math.max(1, parent.width)
        spacing: 10

        Rectangle {
            id: imageBox
            width: content.imageSize
            height: content.imageSize
            radius: 4
            color: content.imageBg
            clip: true
            visible: content.thumbSrc.length > 0

            IconImage {
                anchors.fill: parent
                source: content.thumbSrc
                smooth: true
            }
        }

        Column {
            width: Math.max(1, parent.width - (imageBox.visible ? imageBox.width + parent.spacing : 0))
            spacing: 3

            Text {
                width: Math.max(1, parent.width)
                text: content.notif ? (content.notif.summary || "") : ""
                color: content.theme.fg
                font.family: content.fontFamily
                font.pixelSize: 12
                font.bold: true
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: content.titleLines
            }

            Text {
                width: Math.max(1, parent.width)
                text: content.notif ? (content.notif.body || "") : ""
                color: content.theme.fg
                font.family: content.fontFamily
                font.pixelSize: 11
                textFormat: (content.notif && content.notif.hasBodyMarkup) ? Text.RichText : Text.PlainText
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: content.bodyLines
                visible: text.length > 0
            }
        }
    }

    ProgressBar {
        width: Math.max(1, parent.width)
        from: 0
        to: 100
        value: content.progress
        visible: content.progress >= 0
    }

    RowLayout {
        width: Math.max(1, parent.width)
        spacing: 6
        readonly property var buttonActions: NotificationManager.nonDefaultActions(content.notif)
        visible: buttonActions.length > 0

        Repeater {
            model: parent.buttonActions

            delegate: MouseArea {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: content.actionHeight
                cursorShape: Qt.PointingHandCursor
                onClicked: content.actionInvoked(modelData)

                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: content.theme.accent
                }

                Text {
                    anchors.centerIn: parent
                    width: Math.max(1, parent.width - 10)
                    text: NotificationManager.actionText(parent.modelData)
                    color: content.theme.bg
                    font.family: content.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
