// Todos right-pane view. Header (title + add button) on top, todo
// list below, and a TodoForm sidebar that slides in from the right
// when `provider.formOpen` is true.

import QtQuick

Item {
    id: root
    anchors.fill: parent

    // Injected by Launcher.Loader.onLoaded.
    property var theme: null
    property string fontFamily: ""
    property var provider: null

    readonly property bool _formOpen: provider && provider.formOpen
    readonly property int _sidebarWidth: provider ? provider._sidebarWidth : 340

    // Matches Launcher.collapseAnimDuration so sidebar and card width
    // animations finish in lockstep — keeps the list column stable.
    readonly property int _slideDuration: 260

    clip: true

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 48

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            text: "Todos"
            color: root.theme ? root.theme.fg : "#000"
            font.family: root.fontFamily
            font.pixelSize: 20
            font.bold: true
        }

        Rectangle {
            id: addBtn
            width: 32
            height: 32
            radius: 6
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            color: addMa.containsMouse && root.theme ? Qt.rgba(root.theme.fg.r, root.theme.fg.g, root.theme.fg.b, 0.10) : "transparent"
            border.color: root.theme ? root.theme.border : "#444"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "+"
                color: root.theme ? root.theme.fg : "#000"
                font.family: root.fontFamily
                font.pixelSize: 20
            }

            MouseArea {
                id: addMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.provider)
                    root.provider.openForm()
            }
        }
    }

    Rectangle {
        id: headerDivider
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        height: 1
        color: root.theme ? root.theme.border : "#444"
        opacity: 0.5
    }

    // List right edge anchors to sidebar.left; card and sidebar widths
    // animate in lockstep so sidebar.left stays put.
    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: formSidebar.left
        anchors.top: headerDivider.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.provider ? root.provider.filteredTodos : []

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            width: ListView.view.width - 12
            x: 6
            height: Math.max(52, content.implicitHeight + 16)
            radius: 6
            color: (rowMa.containsMouse || nameLinks.containsMouse) && root.theme ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.08) : "transparent"

            readonly property bool _done: !!row.modelData.completed_on
            readonly property bool _hasDesc: (row.modelData.description || "").length > 0
            readonly property bool _hasDue: (row.modelData.due_date || "").length > 0
            readonly property bool _hasTags: Array.isArray(row.modelData.tags) && row.modelData.tags.length > 0
            readonly property bool _hasMeta: _hasDue || _hasTags
            readonly property string _priority: row.modelData.priority || "medium"

            function _priorityColor() {
                if (_priority === "high")
                    return root.theme.danger;
                return _priority === "medium" ? root.theme.success : root.theme.info;
            }
            // Declared first so it draws below the checkbox's own MouseArea.
            MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: if (root.provider)
                    root.provider.openForm(row.modelData.id)
            }

            Rectangle {
                id: priorityBar
                width: 3
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: row._priorityColor()
                opacity: row._done ? 0.3 : 1.0
            }

            Rectangle {
                id: check
                width: 18
                height: 18
                radius: 4
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                color: row._done && root.theme ? root.theme.accent : "transparent"
                border.color: root.theme ? (row._done ? root.theme.accent : root.theme.border) : "#444"
                border.width: 1.5

                Text {
                    anchors.centerIn: parent
                    visible: row._done
                    text: "✓"
                    color: "#ffffff"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.provider)
                            return;
                        if (row._done)
                            root.provider.uncompleteTodo(row.modelData.id);
                        else
                            root.provider.completeTodo(row.modelData.id);
                    }
                }
            }

            Column {
                id: content
                anchors.left: check.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Item {
                    width: parent.width
                    height: nameText.implicitHeight

                    Text {
                        id: nameText
                        anchors.fill: parent
                        text: root.provider ? root.provider.linkify(row.modelData.name || "(untitled)") : ""
                        color: root.theme ? root.theme.fg : "#000"
                        linkColor: root.theme ? root.theme.accent : "#1e66f5"
                        textFormat: Text.RichText
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        opacity: row._done ? 0.5 : 1.0
                        font.strikeout: row._done
                    }

                    // Intercept link clicks; non-link clicks fall through
                    // to the row's edit-on-click MouseArea.
                    MouseArea {
                        id: nameLinks
                        anchors.fill: parent
                        hoverEnabled: true
                        propagateComposedEvents: true
                        cursorShape: nameText.linkAt(mouseX, mouseY).length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: mouse => {
                            if (nameText.linkAt(mouse.x, mouse.y).length === 0)
                                mouse.accepted = false;
                        }
                        onClicked: mouse => {
                            const url = nameText.linkAt(mouse.x, mouse.y);
                            if (url.length > 0 && root.provider) {
                                root.provider.openExternal(["xdg-open", url]);
                                root.provider.requestClose();
                            } else {
                                mouse.accepted = false;
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: row._hasDesc
                    text: row.modelData.description || ""
                    color: root.theme ? root.theme.subFg : "#888"
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    opacity: 0.85
                }

                Text {
                    width: parent.width
                    visible: row._hasMeta
                    color: root.theme ? root.theme.subFg : "#888"
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    opacity: row._done ? 0.5 : 0.85
                    text: {
                        const parts = [];
                        if (row._hasDue)
                            parts.push(row.modelData.due_date);
                        if (row._hasTags)
                            parts.push(row.modelData.tags.join(", "));
                        return parts.join("  ·  ");
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: {
                if (!root.provider)
                    return "";
                if (root.provider.searchQuery.length > 0)
                    return "No matches for \"" + root.provider.searchQuery + "\"";
                return "No todos yet — press + to add one.";
            }
            color: root.theme ? root.theme.subFg : "#888"
            font.family: root.fontFamily
            font.pixelSize: 13
            opacity: 0.7
        }
    }

    // Width animates between 0 and _sidebarWidth in lockstep with the
    // launcher's card-width animation; clip: true hides mid-animation
    // content so the sidebar "unfolds" into freshly-allocated space.
    Item {
        id: formSidebar
        anchors.right: parent.right
        anchors.top: headerDivider.bottom
        anchors.bottom: parent.bottom
        width: root._formOpen ? root._sidebarWidth : 0
        clip: true
        // Stay visible during the closing animation so the form
        // doesn't pop out before width finishes shrinking to 0.
        visible: width > 0

        Behavior on width {
            NumberAnimation {
                duration: root._slideDuration
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            id: sidebarDivider
            width: 1
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: root.theme ? root.theme.border : "#444"
            opacity: 0.5
        }

        TodoForm {
            anchors.left: sidebarDivider.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            theme: root.theme
            fontFamily: root.fontFamily
            provider: root.provider
        }
    }
}
