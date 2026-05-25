// New-todo form. Lives in the right sidebar of TodoView. Name field
// grabs active focus on load (per user request). Enter on any single-
// line field saves; Escape on any field cancels.
//
// Dates are entered as plain ISO-like strings for now ("YYYY-MM-DD"
// or "YYYY-MM-DD HH:MM"). A proper picker can replace these later.

import QtQuick

Item {
    id: root

    // Injected by parent (TodoView).
    property var theme: null
    property string fontFamily: ""
    property var provider: null

    // Bound to inputs below.
    property string fName: ""
    property string fDescription: ""
    property string fDueDate: ""
    property string fPriority: "medium"
    property string fTags: ""
    property string fReminderAt: ""

    readonly property bool _editing: provider && provider.editingId.length > 0

    // Pull provider.editingDraft into the form's local state. Called
    // whenever the form transitions to formOpen=true; gives both
    // "new" (empty draft) and "edit" (pre-filled draft) the same path.
    function _hydrateFromDraft() {
        const d = (root.provider && root.provider.editingDraft) || {};
        fName = d.name || "";
        fDescription = d.description || "";
        fDueDate = d.due_date || "";
        fPriority = d.priority || "medium";
        fTags = d.tags || "";
        fReminderAt = d.reminder_at || "";
    }

    function _save() {
        const n = fName.trim();
        if (!n.length) {
            nameRow.focusInput();
            return;
        }
        const tags = fTags.split(",").map(s => s.trim()).filter(s => s.length);
        const fields = {
            name: n,
            description: fDescription.trim(),
            due_date: fDueDate.trim() || null,
            priority: fPriority,
            tags: tags,
            reminder_at: fReminderAt.trim() || null
        };
        if (_editing)
            root.provider.updateTodo(root.provider.editingId, fields);
        else
            root.provider.addTodo(fields);
        root.provider.closeForm();
    }

    function _cancel() {
        root.provider.closeForm();
    }

    function _delete() {
        if (!_editing)
            return;
        root.provider.removeTodo(root.provider.editingId);
        root.provider.closeForm();
    }

    // Hydrate + focus whenever the form is shown OR the user switches
    // modes while the form is already open (e.g. clicking + while
    // editing). Listening on editingDraftChanged catches the
    // already-open case where formOpen doesn't flip.
    function _onShown() {
        if (!root.provider || !root.provider.formOpen)
            return;
        root._hydrateFromDraft();
        Qt.callLater(() => nameRow.focusInput());
    }

    Connections {
        target: root.provider
        function onFormOpenChanged() {
            root._onShown();
        }
        function onEditingDraftChanged() {
            root._onShown();
        }
    }

    // ── Field components ────────────────────────────────────────────────
    // Borderless input row: nerd-font glyph on the left, TextInput on
    // the right with an inline placeholder. A 1px bottom rule serves as
    // the separator and brightens when the input is focused.
    component FieldRow: Item {
        id: rowItem
        property alias text: input.text
        property string glyph: ""
        property string placeholder: ""
        property bool large: false
        signal accepted
        signal escaped
        function focusInput() {
            input.forceActiveFocus();
        }

        width: parent ? parent.width : 0
        height: large ? 46 : 38

        Text {
            id: glyphIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            horizontalAlignment: Text.AlignHCenter
            text: rowItem.glyph
            color: input.activeFocus && root.theme ? root.theme.accent : (root.theme ? root.theme.subFg : "#888")
            font.family: root.fontFamily
            font.pixelSize: rowItem.large ? 16 : 13
        }

        TextInput {
            id: input
            anchors.left: glyphIcon.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: TextInput.AlignVCenter
            color: root.theme ? root.theme.fg : "#000"
            font.family: root.fontFamily
            font.pixelSize: rowItem.large ? 16 : 13
            selectByMouse: true
            clip: true
            selectionColor: root.theme ? root.theme.accent : "#1e66f5"
            Keys.onEscapePressed: rowItem.escaped()
            Keys.onReturnPressed: rowItem.accepted()
            Keys.onEnterPressed: rowItem.accepted()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                text: rowItem.placeholder
                color: root.theme ? root.theme.subFg : "#888"
                font: parent.font
                opacity: 0.5
                visible: input.text.length === 0
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: root.theme ? root.theme.accent : "#1e66f5"
            opacity: input.activeFocus ? 1.0 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                }
            }
        }
    }

    // Multi-line variant. Enter inserts a newline; Esc cancels.
    component FieldArea: Item {
        id: areaItem
        property alias text: input.text
        property string glyph: ""
        property string placeholder: ""
        function focusInput() {
            input.forceActiveFocus();
        }

        width: parent ? parent.width : 0
        height: 70

        Text {
            id: glyphIcon
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 10
            width: 22
            horizontalAlignment: Text.AlignHCenter
            text: areaItem.glyph
            color: input.activeFocus && root.theme ? root.theme.accent : (root.theme ? root.theme.subFg : "#888")
            font.family: root.fontFamily
            font.pixelSize: 13
        }

        TextEdit {
            id: input
            anchors.left: glyphIcon.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            color: root.theme ? root.theme.fg : "#000"
            font.family: root.fontFamily
            font.pixelSize: 13
            selectByMouse: true
            clip: true
            wrapMode: TextEdit.Wrap
            selectionColor: root.theme ? root.theme.accent : "#1e66f5"
            Keys.onEscapePressed: root._cancel()

            Text {
                anchors.top: parent.top
                anchors.left: parent.left
                text: areaItem.placeholder
                color: root.theme ? root.theme.subFg : "#888"
                font: parent.font
                opacity: 0.5
                visible: input.text.length === 0
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: root.theme ? root.theme.accent : "#1e66f5"
            opacity: input.activeFocus ? 1.0 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                }
            }
        }
    }

    // ── Layout ──────────────────────────────────────────────────────────
    Flickable {
        id: scroller
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: buttonBar.top
        contentWidth: width
        contentHeight: form.implicitHeight + 28
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: form
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 14
            spacing: 14

            // Nerd-font glyphs (nf-fa-*): pencil, align-left, calendar,
            // flag, tag, bell. They'll render as boxes if the font
            // doesn't have them — swap to whatever set you prefer.
            FieldRow {
                id: nameRow
                glyph: ""
                placeholder: "What needs doing?"
                large: true
                text: root.fName
                onTextChanged: root.fName = text
                onAccepted: root._save()
                onEscaped: root._cancel()
            }

            FieldArea {
                glyph: ""
                placeholder: "Notes (optional)"
                text: root.fDescription
                onTextChanged: root.fDescription = text
            }

            FieldRow {
                glyph: ""
                placeholder: "Due date — YYYY-MM-DD HH:MM"
                text: root.fDueDate
                onTextChanged: root.fDueDate = text
                onAccepted: root._save()
                onEscaped: root._cancel()
            }

            // Priority — text options with an accent underscore on the
            // selected one. No border / fill. "Priority" label on the
            // left mirrors the placeholder slot in the FieldRows above.
            Item {
                width: parent.width
                height: 38

                Text {
                    id: prioIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: "󰘃"
                    color: root.theme ? root.theme.subFg : "#888"
                    font.family: root.fontFamily
                    font.pixelSize: 13
                }

                Text {
                    id: prioLabel
                    anchors.left: prioIcon.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Priority"
                    color: root.theme ? root.theme.subFg : "#888"
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: 13
                }

                Row {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    spacing: 22

                    PrioOption {
                        value: "low"
                        label: "Low"
                    }
                    PrioOption {
                        value: "medium"
                        label: "Medium"
                    }
                    PrioOption {
                        value: "high"
                        label: "High"
                    }
                }
            }

            FieldRow {
                glyph: ""
                placeholder: "Tags — home, errands"
                text: root.fTags
                onTextChanged: root.fTags = text
                onAccepted: root._save()
                onEscaped: root._cancel()
            }

            FieldRow {
                glyph: ""
                placeholder: "Remind me at — YYYY-MM-DD HH:MM"
                text: root.fReminderAt
                onTextChanged: root.fReminderAt = text
                onAccepted: root._save()
                onEscaped: root._cancel()
            }
        }
    }

    component PrioOption: Item {
        property string value: ""
        property string label: ""
        readonly property bool _active: root.fPriority === value
        height: parent.height
        // A few px of horizontal padding so the click target
        // is a touch wider than the glyph itself.
        implicitWidth: txt.implicitWidth + 6

        Text {
            id: txt
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: parent._active && root.theme ? root.theme.fg : (root.theme ? root.theme.subFg : "#888")
            opacity: parent._active ? 1.0 : 0.5
            font.family: root.fontFamily
            font.pixelSize: 13
            Behavior on color   { ColorAnimation  { duration: 140 } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }

        // Accent underscore, sized to the text, sitting
        // just below it. Fades in on selection.
        Rectangle {
            anchors.left: txt.left
            anchors.right: txt.right
            anchors.top: txt.bottom
            anchors.topMargin: 3
            height: 2
            radius: 1
            color: root.theme ? root.theme.accent : "#1e66f5"
            opacity: parent._active ? 1.0 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.fPriority = parent.value
        }
    }

    // ── Bottom button bar ───────────────────────────────────────────────
    Rectangle {
        id: buttonBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 56
        color: "transparent"

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: root.theme ? root.theme.border : "#444"
            opacity: 0.5
        }

        // Delete sits on the left, only present in edit mode. Single
        // click removes the todo — there's no undo dialog yet, but the
        // JSON file is the source of truth if you ever need to recover.
        Rectangle {
            id: deleteBtn
            width: 72
            height: 30
            radius: 4
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: root._editing
            color: deleteMa.containsMouse && root.theme ? Qt.rgba(root.theme.danger.r, root.theme.danger.g, root.theme.danger.b, 0.10) : "transparent"
            border.color: root.theme ? root.theme.danger : "#d20f39"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "Delete"
                color: root.theme ? root.theme.danger : "#d20f39"
                font.family: root.fontFamily
                font.pixelSize: 12
                font.bold: true
            }

            MouseArea {
                id: deleteMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root._delete()
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 14
            spacing: 8

            Rectangle {
                width: 72
                height: 30
                radius: 4
                color: cancelMa.containsMouse && root.theme ? Qt.rgba(root.theme.fg.r, root.theme.fg.g, root.theme.fg.b, 0.08) : "transparent"
                border.color: root.theme ? root.theme.border : "#444"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: root.theme ? root.theme.fg : "#000"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                }

                MouseArea {
                    id: cancelMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._cancel()
                }
            }

            Rectangle {
                width: 80
                height: 30
                radius: 4
                readonly property bool _enabled: root.fName.trim().length > 0
                color: !_enabled ? Qt.rgba(0, 0, 0, 0) : (saveMa.containsMouse && root.theme ? Qt.darker(root.theme.accent, 1.15) : (root.theme ? root.theme.accent : "#1e66f5"))
                border.color: root.theme ? root.theme.accent : "#1e66f5"
                border.width: 1
                opacity: _enabled ? 1.0 : 0.5

                Text {
                    anchors.centerIn: parent
                    text: root._editing ? "Update" : "Save"
                    color: parent._enabled ? "#ffffff" : (root.theme ? root.theme.subFg : "#888")
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    id: saveMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent._enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (parent._enabled)
                        root._save()
                }
            }
        }
    }
}
