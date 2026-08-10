// Styled single-select dropdown built on QtQuick.Controls ComboBox.
//
//  - Fixed width: set `width` from the caller; the popup matches it.
//  - The popup attaches directly beneath the trigger (no gap) and lives in the
//    window overlay, so it always renders above sibling content — no z-index
//    juggling needed at the call site.
//  - Trigger shows the selected value left-aligned and elided, with the caret
//    pinned to the right.
//  - The popup scrolls (themed scrollbar) once its contents exceed
//    `popupMaxHeight`.
//
// `model` is a plain string array; `onActivated(index)` fires on selection.

import QtQuick
import QtQuick.Controls

ComboBox {
    id: control

    required property var theme
    property string fontFamily: ""
    property int popupMaxHeight: 280
    property int rowHeight: 26

    implicitHeight: 28
    font.family: control.fontFamily
    font.pixelSize: 12

    background: Rectangle {
        radius: control.theme.radius
        color: Qt.rgba(control.theme.fg.r, control.theme.fg.g, control.theme.fg.b, 0.06)
        border.width: 1
        border.color: control.popup.visible ? control.theme.accent : control.theme.border
    }

    // Selected value — left, elided; rightPadding clears the caret.
    contentItem: Text {
        leftPadding: 8
        rightPadding: 22
        text: control.displayText
        font: control.font
        color: control.theme.fg
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
    }

    // Caret — pinned right.
    indicator: Text {
        x: control.width - width - 8
        y: (control.height - height) / 2
        text: "▾"
        font.family: control.fontFamily
        font.pixelSize: 11
        color: control.theme.subFg
    }

    delegate: ItemDelegate {
        id: row
        required property var modelData
        required property int index
        width: ListView.view.width
        height: control.rowHeight
        padding: 0

        contentItem: Text {
            leftPadding: 8
            rightPadding: 8
            text: row.modelData
            color: control.theme.fg
            font.family: control.fontFamily
            font.pixelSize: 12
            font.bold: row.index === control.currentIndex
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            color: row.index === control.highlightedIndex
                ? Qt.rgba(control.theme.accent.r, control.theme.accent.g, control.theme.accent.b, 0.18)
                : (row.index === control.currentIndex
                    ? Qt.rgba(control.theme.accent.r, control.theme.accent.g, control.theme.accent.b, 0.10)
                    : "transparent")
        }
    }

    popup: Popup {
        y: control.height          // flush against the trigger, no gap
        width: control.width
        padding: 1
        implicitHeight: Math.min(control.popupMaxHeight, listView.contentHeight + 2)

        background: Rectangle {
            radius: control.theme.radius
            color: Qt.rgba(control.theme.bg.r, control.theme.bg.g, control.theme.bg.b, 0.98)
            border.width: 1
            border.color: control.theme.border
        }

        contentItem: ListView {
            id: listView
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                id: vbar
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: vbar.hovered || vbar.pressed ? 8 : 4
                    radius: width / 2
                    color: Qt.rgba(control.theme.fg.r, control.theme.fg.g, control.theme.fg.b,
                                   vbar.hovered || vbar.pressed ? 0.65 : 0.4)
                    Behavior on implicitWidth {
                        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                    }
                }
            }
        }
    }
}
