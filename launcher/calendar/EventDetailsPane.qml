// Right-hand details pane for a selected calendar event. Renders
// title, calendar (with its colour stripe), time range, location, and
// description. Emits `close()` when the user dismisses via the X.

import QtQuick
import QtQuick.Controls

Item {
    id: pane

    property var theme: null
    property string fontFamily: ""
    // The event blob from EventsModel (see calendar-events.py for shape).
    property var event: null

    signal close()
    // Fired after Qt.openUrlExternally launches a description link, so
    // the launcher can fully close itself instead of stealing focus
    // back from the just-opened browser.
    signal linkOpened()

    readonly property bool _hasEvent: event != null

    // Locale-aware short date — falls back to a plain ISO render when
    // we can't parse the string (shouldn't happen from our script, but
    // safer than blowing up the pane).
    function _fmtDate(dt) {
        if (!dt) return "";
        const d = (dt instanceof Date) ? dt : new Date(dt);
        if (isNaN(d.getTime())) return ("" + dt);
        return Qt.formatDate(d, "ddd, d MMM yyyy");
    }
    function _fmtTime(dt) {
        if (!dt) return "";
        const d = (dt instanceof Date) ? dt : new Date(dt);
        if (isNaN(d.getTime())) return "";
        return Qt.formatTime(d, "HH:mm");
    }

    // HTML-escape and wrap http(s) URLs in <a> tags so the description
    // Text (textFormat: RichText) renders them clickable. Newlines get
    // converted to <br> so plain-text wrapping still works.
    function _linkify(text) {
        if (!text) return "";
        const esc = text
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
        const urlRe = /(https?:\/\/[^\s<>"']+)/g;
        return esc
            .replace(urlRe, '<a href="$1">$1</a>')
            .replace(/\n/g, "<br>");
    }

    function _whenLine() {
        if (!_hasEvent) return "";
        if (event.allDay) {
            const s = _fmtDate(event.start);
            const e = _fmtDate(event.end);
            // For a single-day all-day event the DTEND is the next day
            // (RFC 5545); show only the start date in that case.
            return (e && e !== s) ? (s + " — " + e) : s;
        }
        const sd = _fmtDate(event.start);
        const ed = _fmtDate(event.end);
        const st = _fmtTime(event.start);
        const et = _fmtTime(event.end);
        if (sd === ed) return sd + ", " + st + " — " + et;
        return sd + " " + st + " — " + ed + " " + et;
    }

    // Top stack: close button, title, and metadata rows. Stays anchored
    // to the top so the description below can claim the remaining
    // vertical space without fragile height-math.
    Column {
        id: topStack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 10

        // Close button — top-right.
        Item {
            width: parent.width
            height: 22

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                radius: 4
                color: closeArea.containsMouse && pane.theme
                    ? Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.10)
                    : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: pane.theme ? pane.theme.subFg : "#888"
                    font.family: pane.fontFamily
                    font.pixelSize: 14
                }
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: pane.close()
                }
            }
        }

        // Title with the calendar's colour stripe on the left.
        Item {
            width: parent.width
            height: Math.max(24, titleText.implicitHeight + 4)

            Rectangle {
                id: titleStripe
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3
                radius: 1
                color: {
                    const c = pane._hasEvent ? pane.event.color : "";
                    if (c && c.length > 0) return c;
                    return pane.theme ? pane.theme.accent : "#1e66f5";
                }
            }

            Text {
                id: titleText
                anchors.left: titleStripe.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: pane._hasEvent
                    ? (pane.event.summary || "(no title)")
                    : ""
                color: pane.theme ? pane.theme.fg : "#000"
                font.family: pane.fontFamily
                font.pixelSize: 17
                font.bold: true
                wrapMode: Text.WordWrap
            }
        }

        // Metadata rows.
        Column {
            width: parent.width
            spacing: 6

            // When / time range
            Row {
                spacing: 8
                width: parent.width
                Text {
                    text: "󰃭"
                    color: pane.theme ? pane.theme.subFg : "#888"
                    font.family: pane.fontFamily
                    font.pixelSize: 14
                    width: 18
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: pane._whenLine()
                    color: pane.theme ? pane.theme.fg : "#000"
                    font.family: pane.fontFamily
                    font.pixelSize: 12
                    width: parent.width - 26
                    wrapMode: Text.WordWrap
                }
            }

            Row {
                spacing: 8
                width: parent.width
                visible: pane._hasEvent
                    && (pane.event.location || "").length > 0
                Text {
                    text: ""
                    color: pane.theme ? pane.theme.subFg : "#888"
                    font.family: pane.fontFamily
                    font.pixelSize: 14
                    width: 18
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: pane._hasEvent ? (pane.event.location || "") : ""
                    color: pane.theme ? pane.theme.fg : "#000"
                    font.family: pane.fontFamily
                    font.pixelSize: 12
                    width: parent.width - 26
                    wrapMode: Text.WordWrap
                }
            }

            Row {
                spacing: 8
                width: parent.width
                visible: pane._hasEvent
                    && (pane.event.calendar || "").length > 0
                Text {
                    text: ""
                    color: pane.theme ? pane.theme.subFg : "#888"
                    font.family: pane.fontFamily
                    font.pixelSize: 14
                    width: 18
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: pane._hasEvent ? (pane.event.calendar || "") : ""
                    color: pane.theme ? pane.theme.subFg : "#888"
                    font.family: pane.fontFamily
                    font.pixelSize: 12
                    width: parent.width - 26
                    elide: Text.ElideRight
                }
            }
        }

        // Divider above the description.
        Rectangle {
            width: parent.width
            height: 1
            color: pane.theme ? pane.theme.border : "#444"
            opacity: 0.4
            visible: pane._hasEvent
                && (pane.event.description || "").length > 0
        }
    }

    // Description fills the remaining space and scrolls when long.
    Flickable {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topStack.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.topMargin: 6
        clip: true
        contentWidth: width
        contentHeight: descText.implicitHeight
        visible: pane._hasEvent
            && (pane.event.description || "").length > 0
        boundsBehavior: Flickable.StopAtBounds

        Text {
            id: descText
            width: parent.width
            text: pane._hasEvent ? pane._linkify(pane.event.description || "") : ""
            color: pane.theme ? pane.theme.fg : "#000"
            linkColor: pane.theme ? pane.theme.accent : "#1e66f5"
            font.family: pane.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            textFormat: Text.RichText
            onLinkActivated: function (link) {
                Qt.openUrlExternally(link);
                pane.linkOpened();
            }

            // Pointer cursor while hovering a link; default arrow elsewhere.
            HoverHandler {
                cursorShape: descText.hoveredLink.length > 0
                    ? Qt.PointingHandCursor
                    : Qt.ArrowCursor
            }
        }
    }
}
