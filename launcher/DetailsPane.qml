// Side-by-side details pane. Renders a generic `detail` blob produced
// by a provider; the launcher shows this whenever an active provider
// has `detailsEnabled: true`.
//
// Expected `detail` shape (every field optional):
//   {
//     loading: bool,
//     error:   string,
//     iconUrl: string,                              // top-left avatar
//     iconText: string,                             // glyph fallback
//     title:   string,
//     subtitle:string,                              // "owner/repo #123"
//     state:   { text: string, color: string },    // top pill — color is
//                                                   // a Theme key name
//                                                   // ("success" | …)
//     meta:    [ { label: string, value: string }, … ],
//     body:    string                               // multi-line plain text
//   }
//
// Anything missing is simply not rendered.

import QtQuick
import QtQuick.Controls
import Quickshell.Widgets

Item {
    id: pane

    required property var detail
    required property var theme            // .bg .fg .subFg .accent .border …
    required property string fontFamily

    readonly property bool _hasDetail: detail != null
    readonly property bool _loading: _hasDetail && detail.loading === true
    readonly property string _error: _hasDetail && detail.error ? detail.error : ""

    function _themeColor(name) {
        if (name === "success") return theme.success;
        if (name === "info")    return theme.info;
        if (name === "purple")  return theme.purple;
        if (name === "warn")    return theme.warn;
        if (name === "danger")  return theme.danger;
        if (name === "cyan")    return theme.cyan;
        if (name === "accent")  return theme.accent;
        return theme.border;
    }

    // Empty state — no row picked yet.
    Text {
        anchors.centerIn: parent
        visible: !pane._hasDetail
        text: "Select an item to see details"
        color: pane.theme.subFg
        font.family: pane.fontFamily
        font.pixelSize: 12
        opacity: 0.7
    }

    // Content. Header (avatar + title + subtitle) is shown as soon as
    // we have any detail data, including the loading skeleton the
    // provider pushes synchronously on selection. State / meta / body
    // only render once the data they need is present; while loading,
    // a small inline "Loading…" placeholder sits below the header.
    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        visible: pane._hasDetail

        // ── Header: avatar + title/subtitle ──────────────────────────
        Row {
            width: parent.width
            spacing: 10

            Item {
                width: 40
                height: 40

                IconImage {
                    id: avatar
                    anchors.fill: parent
                    source: pane.detail?.iconUrl ?? ""
                    visible: status === Image.Ready && source !== ""
                    asynchronous: true
                    smooth: true
                    implicitSize: 40
                }
                Text {
                    anchors.centerIn: parent
                    visible: !avatar.visible
                    text: pane.detail?.iconText ?? ""
                    color: pane.theme.fg
                    font.family: pane.fontFamily
                    font.pixelSize: 28
                    opacity: 0.85
                }
            }

            Column {
                spacing: 2
                width: parent.width - 50

                Text {
                    width: parent.width
                    text: pane.detail?.title ?? ""
                    color: pane.theme.fg
                    font.family: pane.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: pane.detail?.subtitle ?? ""
                    color: pane.theme.subFg
                    font.family: pane.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }
        }

        // Inline loading indicator (sits under the header until the
        // fetch lands).
        Text {
            width: parent.width
            visible: pane._loading
            text: "Loading…"
            color: pane.theme.subFg
            font.family: pane.fontFamily
            font.pixelSize: 11
            opacity: 0.75
        }

        // Inline error (shown in place of body / meta).
        Text {
            width: parent.width
            visible: pane._error.length > 0 && !pane._loading
            wrapMode: Text.WordWrap
            text: pane._error
            color: pane.theme.danger
            font.family: pane.fontFamily
            font.pixelSize: 11
        }

        // ── State pill ───────────────────────────────────────────────
        Item {
            width: stateText.implicitWidth + 16
            height: 20
            visible: (pane.detail?.state?.text?.length ?? 0) > 0 && !pane._loading

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: {
                    const c = pane._themeColor(pane.detail?.state?.color ?? "");
                    return Qt.rgba(c.r, c.g, c.b, 0.85);
                }
            }
            Text {
                id: stateText
                anchors.centerIn: parent
                text: pane.detail?.state?.text ?? ""
                color: pane.theme.bg
                font.family: pane.fontFamily
                font.pixelSize: 9
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.6
            }
        }

        // ── Meta rows ────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 3
            visible: !pane._loading && pane._error.length === 0 && (pane.detail?.meta?.length ?? 0) > 0

            Repeater {
                model: pane.detail?.meta ?? []
                delegate: Row {
                    required property var modelData
                    width: parent ? parent.width : 0
                    spacing: 8

                    Text {
                        text: modelData?.label ?? ""
                        color: pane.theme.subFg
                        font.family: pane.fontFamily
                        font.pixelSize: 11
                        width: 70
                        opacity: 0.85
                    }
                    Text {
                        text: modelData?.value ?? ""
                        color: pane.theme.fg
                        font.family: pane.fontFamily
                        font.pixelSize: 11
                        width: parent.width - 78
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ── Body ─────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: bodyScroll.implicitHeight > 0
                ? Math.min(bodyScroll.contentHeight + 16, pane.height - y - 16)
                : 0
            color: Qt.rgba(pane.theme.border.r, pane.theme.border.g, pane.theme.border.b, 0.15)
            border.color: pane.theme.border
            border.width: 1
            radius: 6
            visible: !pane._loading && pane._error.length === 0 && (pane.detail?.body ?? "").length > 0

            ScrollView {
                id: bodyScroll
                anchors.fill: parent
                anchors.margins: 8
                clip: true

                TextArea {
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    text: pane.detail?.body ?? ""
                    color: pane.theme.fg
                    font.family: pane.fontFamily
                    font.pixelSize: 11
                    background: null
                }
            }
        }
    }
}
