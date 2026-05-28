// Chat custom pane. Conversation list on the left, message stream
// on the right. The launcher's search input doubles as the prompt;
// Enter sends, handled in ChatProvider.handleKey.

import QtQuick
import "../../shared"

Item {
    id: root
    anchors.fill: parent

    property var theme: null
    property string fontFamily: ""
    property var provider: null

    readonly property int _convPaneWidth: 210

    readonly property var _displayMessages: {
        if (!root.provider) return [];
        const base = root.provider.currentMessages || [];
        if (root.provider.sending) {
            return base.concat([{
                role: "assistant",
                content: root.provider.pendingAssistant && root.provider.pendingAssistant.length > 0
                    ? root.provider.pendingAssistant
                    : "…",
                _pending: true
            }]);
        }
        return base;
    }

    clip: true

    Item {
        id: convPane
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root._convPaneWidth

        ListView {
            id: convList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 8
            anchors.bottomMargin: 6
            clip: true
            model: root.provider ? root.provider.conversations : []
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: convRow
                required property var modelData
                readonly property bool _active: root.provider && root.provider.currentConversationId === modelData.id
                width: ListView.view.width - 12
                x: 6
                height: 44
                color: _active && root.theme
                    ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.18)
                    : (convMa.containsMouse && root.theme
                        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.06)
                        : "transparent")

                Column {
                    anchors.left: parent.left
                    anchors.right: delBtn.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    spacing: 2

                    Text {
                        width: parent.width
                        text: convRow.modelData.title || "Untitled"
                        color: root.theme ? root.theme.fg : "#000"
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: convRow.modelData.model || ""
                        color: root.theme ? root.theme.subFg : "#888"
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        opacity: 0.7
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: convMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.provider) root.provider.selectConversation(convRow.modelData.id)
                }

                Item {
                    id: delBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 6
                    width: 18
                    height: 18
                    visible: convMa.containsMouse || delMa.containsMouse

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: delMa.containsMouse && root.theme
                            ? root.theme.danger
                            : (root.theme ? root.theme.subFg : "#888")
                        font.family: root.fontFamily
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: delMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.provider) root.provider.deleteConversation(convRow.modelData.id)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: convList.count === 0
                text: "No chats yet"
                color: root.theme ? root.theme.subFg : "#888"
                font.family: root.fontFamily
                font.pixelSize: 11
                opacity: 0.7
            }
        }
    }

    Rectangle {
        id: paneDivider
        width: 1
        anchors.left: convPane.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: root.theme ? root.theme.border : "#444"
        opacity: 0.5
    }

    Item {
        id: chatPane
        anchors.left: paneDivider.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Item {
            id: chatHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 36

            Text {
                id: statusText
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: root.provider && (root.provider.sending || root.provider.lastError.length > 0)
                text: {
                    if (!root.provider) return "";
                    if (root.provider.sending) return "thinking…";
                    return root.provider.lastError;
                }
                color: root.provider && root.provider.lastError.length > 0 && !root.provider.sending && root.theme
                    ? root.theme.danger
                    : (root.theme ? root.theme.subFg : "#888")
                font.family: root.fontFamily
                font.pixelSize: 11
                opacity: 0.85
            }

            Rectangle {
                id: stopChip
                visible: root.provider && root.provider.sending
                anchors.left: statusText.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 20
                width: stopText.implicitWidth + 14
                radius: 4
                color: stopMa.containsMouse && root.theme
                    ? Qt.rgba(root.theme.danger.r, root.theme.danger.g, root.theme.danger.b, 0.14)
                    : "transparent"
                border.color: root.theme ? root.theme.danger : "#d20f39"
                border.width: 1

                Text {
                    id: stopText
                    anchors.centerIn: parent
                    text: "■ stop"
                    color: root.theme ? root.theme.danger : "#d20f39"
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }

                MouseArea {
                    id: stopMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.provider) root.provider.stopStream()
                }
            }
        }

        Rectangle {
            id: chatHeaderDivider
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: chatHeader.bottom
            height: 1
            color: root.theme ? root.theme.border : "#444"
            opacity: 0.5
        }

        ListView {
            id: msgList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: chatHeaderDivider.bottom
            anchors.bottom: parent.bottom
            clip: true
            model: root._displayMessages
            spacing: 8
            topMargin: 12
            bottomMargin: 12
            boundsBehavior: Flickable.StopAtBounds

            onCountChanged: Qt.callLater(() => positionViewAtEnd())
            Connections {
                target: root.provider
                function onPendingAssistantChanged() {
                    Qt.callLater(() => msgList.positionViewAtEnd());
                }
            }

            delegate: Item {
                id: msgRow
                required property var modelData
                readonly property bool _isUser: msgRow.modelData.role === "user"
                readonly property int _maxBubbleWidth: ListView.view.width - 28

                width: ListView.view.width
                height: bubble.height + 4

                Rectangle {
                    id: bubble
                    width: Math.min(msgRow._maxBubbleWidth, msgText.contentWidth + 18)
                    height: msgText.contentHeight + 18
                    radius: 8
                    anchors.left: msgRow._isUser ? undefined : parent.left
                    anchors.right: msgRow._isUser ? parent.right : undefined
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    color: msgRow._isUser && root.theme
                        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16)
                        : (root.theme ? Qt.rgba(root.theme.fg.r, root.theme.fg.g, root.theme.fg.b, 0.06) : "#eee")

                    Text {
                        id: msgText
                        x: 9
                        y: 9
                        width: msgRow._maxBubbleWidth - 18
                        text: msgRow.modelData.content || ""
                        color: root.theme ? root.theme.fg : "#000"
                        linkColor: root.theme ? root.theme.accent : "#1e66f5"
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                        textFormat: Text.MarkdownText
                        onLinkActivated: url => {
                            if (root.provider) {
                                root.provider.openExternal(["xdg-open", url]);
                                root.provider.requestClose();
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 40
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                visible: msgList.count === 0
                text: {
                    if (!root.provider) return "";
                    if (root.provider.currentModel.length === 0) {
                        const be = root.provider.currentBackend;
                        return be ? "No models loaded in " + be.name + "." : "No model.";
                    }
                    return "Type a message in the search bar above and press Enter.";
                }
                color: root.theme ? root.theme.subFg : "#888"
                font.family: root.fontFamily
                font.pixelSize: 12
                opacity: 0.7
            }
        }

    }
}
