import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
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
    signal joinClicked()

    // Lets the action row run full width by reclaiming the content's right
    // margin (which only exists to keep the title clear of the close button).
    property int actionsExtend: 0

    spacing: 6

    readonly property string bodyImage: notif ? (notif.image || "") : ""
    readonly property string appIcon: notif ? (notif.appIcon || "") : ""
    readonly property string thumbSrc: NotificationManager.iconUrl(preferBodyImage ? (bodyImage || appIcon) : (bodyImage || ""))
    readonly property int progress: NotificationManager.progressOf(notif)

    // Nerd-font glyph via the x-glyph hint, used instead of a themed icon.
    readonly property string glyph: (notif && notif.hints && notif.hints["x-glyph"] !== undefined)
        ? String(notif.hints["x-glyph"]) : ""

    // Meeting link via the x-join-url hint → rendered as a "Join" button.
    readonly property string joinUrl: (notif && notif.hints && notif.hints["x-join-url"] !== undefined)
        ? String(notif.hints["x-join-url"]) : ""

    Row {
        width: Math.max(1, parent.width)
        spacing: 10

        Rectangle {
            id: imageBox
            width: content.imageSize
            height: content.imageSize
            radius: content.theme.radius
            // No background plate behind a bare glyph — only behind images.
            color: content.thumbSrc.length > 0 ? content.imageBg : "transparent"
            clip: true
            visible: content.thumbSrc.length > 0 || content.glyph.length > 0

            IconImage {
                anchors.fill: parent
                source: content.thumbSrc
                smooth: true
                visible: content.thumbSrc.length > 0
            }

            Text {
                anchors.centerIn: parent
                visible: content.thumbSrc.length === 0 && content.glyph.length > 0
                text: content.glyph
                // fg tracks the theme: dark on a light theme, light on a dark one.
                color: content.theme.fg
                font.family: content.fontFamily
                font.pixelSize: content.imageSize
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

    component ActionButton : MouseArea {
        property string label: ""
        Layout.fillWidth: true
        Layout.preferredHeight: content.actionHeight
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: content.theme.radius
            color: content.theme.accent
        }
        Text {
            anchors.centerIn: parent
            width: Math.max(1, parent.width - 10)
            text: parent.label
            color: content.theme.bg
            font.family: content.fontFamily
            font.pixelSize: 10
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    RowLayout {
        width: Math.max(1, parent.width + content.actionsExtend)
        spacing: 6
        readonly property var buttonActions: NotificationManager.nonDefaultActions(content.notif)
        visible: buttonActions.length > 0 || content.joinUrl.length > 0

        // Opens the x-join-url directly — no DBus round-trip, so it works after
        // the sender (notify-send) has exited.
        ActionButton {
            visible: content.joinUrl.length > 0
            label: "Join"
            onClicked: {
                Quickshell.execDetached(["xdg-open", content.joinUrl]);
                content.joinClicked();
            }
        }

        Repeater {
            model: parent.buttonActions
            delegate: ActionButton {
                required property var modelData
                label: NotificationManager.actionText(modelData)
                onClicked: content.actionInvoked(modelData)
            }
        }
    }
}
