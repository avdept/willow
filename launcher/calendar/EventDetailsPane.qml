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
    // Owning CalendarProvider — supplies `linkify()` for the description.
    property var provider: null

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

    // linkify is shared (Provider.qml); descriptions are multi-line so we
    // also convert newlines to <br> on top of that.
    function _descHtml(text) {
        if (!pane.provider) return "";
        return pane.provider.linkify(text).replace(/\n/g, "<br>");
    }

    // PARTSTAT → glyph + colour. Used by the Attendees list.
    function _statusGlyph(s) {
        switch ((s || "").toUpperCase()) {
        case "ACCEPTED":  return "✓";
        case "DECLINED":  return "✗";
        case "TENTATIVE": return "?";
        case "DELEGATED": return "→";
        default:          return "·";        // NEEDS-ACTION / unknown
        }
    }
    function _statusColor(s) {
        if (!pane.theme) return "#888";
        switch ((s || "").toUpperCase()) {
        case "ACCEPTED":  return pane.theme.success;
        case "DECLINED":  return pane.theme.danger;
        case "TENTATIVE": return pane.theme.warn;
        case "DELEGATED": return pane.theme.info;
        default:          return pane.theme.subFg;
        }
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

        // Metadata rows — each is `<glyph>  <value>` with the glyph in
        // subFg and the value either in fg (primary) or subFg (muted,
        // for the calendar source).
        Column {
            width: parent.width
            spacing: 6

            component MetadataRow : Row {
                property string glyph: ""
                property string value: ""
                property bool muted: false
                spacing: 8
                width: parent.width
                visible: value.length > 0
                Text {
                    text: parent.glyph
                    color: pane.theme ? pane.theme.subFg : "#888"
                    font.family: pane.fontFamily
                    font.pixelSize: 14
                    width: 18
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: parent.value
                    color: parent.muted
                        ? (pane.theme ? pane.theme.subFg : "#888")
                        : (pane.theme ? pane.theme.fg : "#000")
                    font.family: pane.fontFamily
                    font.pixelSize: 12
                    width: parent.width - 26
                    wrapMode: parent.muted ? Text.NoWrap : Text.WordWrap
                    elide: parent.muted ? Text.ElideRight : Text.ElideNone
                }
            }

            MetadataRow {
                glyph: "󰃭"
                value: pane._hasEvent ? pane._whenLine() : ""
            }
            MetadataRow {
                glyph: ""
                value: pane._hasEvent ? (pane.event.location || "") : ""
            }
            MetadataRow {
                glyph: ""
                value: pane._hasEvent ? (pane.event.calendar || "") : ""
                muted: true
            }
        }

        // Attendees — visible whenever the event has any. Capped at 8
        // visible rows; the rest fold into "+N more". Organizer is
        // tagged inline.
        Column {
            width: parent.width
            spacing: 4
            visible: pane._hasEvent
                && (pane.event.attendees || []).length > 0

            readonly property var _all: pane._hasEvent ? (pane.event.attendees || []) : []
            readonly property int _maxVisible: 8
            readonly property string _organizerEmail:
                pane._hasEvent && pane.event.organizer
                    ? (pane.event.organizer.email || "")
                    : ""

            Text {
                text: "Attendees (" + parent._all.length + ")"
                color: pane.theme ? pane.theme.subFg : "#888"
                font.family: pane.fontFamily
                font.pixelSize: 11
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.5
            }

            Repeater {
                model: parent._all.slice(0, parent._maxVisible)
                delegate: Row {
                    required property var modelData
                    width: parent.width
                    spacing: 8

                    Text {
                        text: pane._statusGlyph(parent.modelData.status)
                        color: pane._statusColor(parent.modelData.status)
                        font.family: pane.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        width: 14
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        text: {
                            const m = parent.modelData;
                            const base = (m.name && m.name.length > 0) ? m.name : (m.email || "(unknown)");
                            const isOrg = m.email && m.email === parent.parent._organizerEmail;
                            return isOrg ? base + "  · organizer" : base;
                        }
                        color: pane.theme ? pane.theme.fg : "#000"
                        font.family: pane.fontFamily
                        font.pixelSize: 12
                        width: parent.width - 22
                        elide: Text.ElideRight
                    }
                }
            }

            Text {
                visible: parent._all.length > parent._maxVisible
                text: "+ " + (parent._all.length - parent._maxVisible) + " more"
                color: pane.theme ? pane.theme.subFg : "#888"
                font.family: pane.fontFamily
                font.pixelSize: 11
                opacity: 0.85
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
            text: pane._hasEvent ? pane._descHtml(pane.event.description || "") : ""
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
