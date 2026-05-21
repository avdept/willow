// Month view — Apple-style 6×7 grid backed by Qt Quick Controls'
// `MonthGrid` + `DayOfWeekRow` (locale-aware). Header has prev / today /
// next; today is a filled circle in `theme.danger`; the focused day gets
// an outline in `theme.accent`; out-of-month days fade.
//
// Sibling views (Week, Day) live next to this file under launcher/calendar/
// and will follow the same shape: take `theme`, `fontFamily`, and the
// owning `provider`, render the right pane, and call mutators on the
// provider for state changes.

import QtQuick
import QtQuick.Controls

Item {
    id: root
    anchors.fill: parent

    // Set by Launcher.onLoaded (when this component is the active
    // provider's customComponent root). Null until then — bindings
    // below guard against the brief uninitialised window.
    property var theme: null
    property string fontFamily: ""
    property var provider: null

    readonly property var _monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    function _sameDay(a, b) {
        if (!a || !b) return false;
        return a.getFullYear() === b.getFullYear()
            && a.getMonth()    === b.getMonth()
            && a.getDate()     === b.getDate();
    }

    // Chip background — accent at a slightly higher alpha on hover.
    function _chipBg(hovered) {
        if (!root.theme) return "#1e66f522";
        const a = root.theme.accent;
        return Qt.rgba(a.r, a.g, a.b, hovered ? 0.30 : 0.18);
    }

    // True when the right-hand details pane is showing. Calendar
    // elements anchor to detailsDivider.left instead of parent.right
    // when this flips on, which is what makes the grid shrink.
    readonly property bool _showDetails:
        root.provider && root.provider.selectedEvent !== null

    // ── Header: month label + prev / today / next ──────────────────────
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: detailsDivider.left
        anchors.top: parent.top
        height: 56

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            text: root.provider
                ? root._monthNames[root.provider.displayedMonth] + " " + root.provider.displayedYear
                : ""
            color: root.theme ? root.theme.fg : "#000"
            font.family: root.fontFamily
            font.pixelSize: 22
            font.bold: true
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            component NavButton : Rectangle {
                property string glyph: ""
                property string label: ""
                property bool outlined: false
                signal clicked()
                width: label.length > 0 ? 60 : 28
                height: 28
                radius: 6
                color: ma.containsMouse && root.theme
                    ? Qt.rgba(root.theme.fg.r, root.theme.fg.g, root.theme.fg.b, 0.08)
                    : "transparent"
                border.color: outlined && root.theme ? root.theme.border : "transparent"
                border.width: outlined ? 1 : 0
                Text {
                    anchors.centerIn: parent
                    text: parent.label.length > 0 ? parent.label : parent.glyph
                    color: root.theme ? root.theme.fg : "#000"
                    font.family: root.fontFamily
                    font.pixelSize: parent.label.length > 0 ? 12 : 18
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: parent.clicked()
                }
            }

            NavButton { glyph: "‹"; onClicked: if (root.provider) root.provider.goPrevMonth() }
            NavButton { label: "Today"; outlined: true; onClicked: if (root.provider) root.provider.goToday() }
            NavButton { glyph: "›"; onClicked: if (root.provider) root.provider.goNextMonth() }
        }
    }

    Rectangle {
        id: headerDivider
        anchors.left: parent.left
        anchors.right: detailsDivider.left
        anchors.top: header.bottom
        height: 1
        color: root.theme ? root.theme.border : "#444"
        opacity: 0.5
    }

    // ── Day-of-week labels (locale-aware) ──────────────────────────────
    DayOfWeekRow {
        id: dayHeader
        anchors.left: parent.left
        anchors.right: detailsDivider.left
        anchors.top: headerDivider.bottom
        height: 28
        locale: Qt.locale()
        spacing: 0
        topPadding: 4
        bottomPadding: 4
        leftPadding: 0
        rightPadding: 0

        delegate: Text {
            required property string shortName
            // DayOfWeekRow's contentItem is a plain Row that respects each
            // delegate's natural width — so we force 1/7 of the row width
            // here to align with the grid columns below.
            width: dayHeader.availableWidth / 7
            height: dayHeader.availableHeight
            text: shortName.toUpperCase()
            color: root.theme ? root.theme.subFg : "#888"
            font.family: root.fontFamily
            font.pixelSize: 11
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Top edge of the grid (between day-of-week row and first row of cells).
    // Cells only draw their own right + bottom borders, so we need top and
    // left edges at the container level to close the box.
    Rectangle {
        id: gridTopLine
        anchors.left: parent.left
        anchors.right: detailsDivider.left
        anchors.top: dayHeader.bottom
        height: 1
        color: root.theme ? root.theme.border : "#444"
        opacity: 0.5
    }

    Rectangle {
        id: gridLeftLine
        anchors.left: parent.left
        anchors.top: gridTopLine.bottom
        anchors.bottom: parent.bottom
        width: 1
        color: root.theme ? root.theme.border : "#444"
        opacity: 0.5
    }

    // ── The 6×7 month grid ─────────────────────────────────────────────
    MonthGrid {
        id: grid
        anchors.left: gridLeftLine.right
        anchors.right: detailsDivider.left
        anchors.top: gridTopLine.bottom
        anchors.bottom: parent.bottom
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        spacing: 0
        month: root.provider ? root.provider.displayedMonth : 0
        year:  root.provider ? root.provider.displayedYear  : 1970
        locale: Qt.locale()

        onClicked: function (date) {
            if (root.provider) root.provider.setFocused(date);
        }

        // Each cell is its own box: subtle right+bottom borders form the
        // grid; day number sits in the top-right corner (with a filled
        // circle when it's today); the rest of the cell is reserved for
        // event chips (placeholder Column below — wire in once a calendar
        // backend is connected).
        delegate: Rectangle {
            id: cell
            required property var model
            // The contentItem is a QQ.Grid that doesn't stretch its
            // children — they'd default to their implicit text size and
            // leave most of the MonthGrid empty. Force each cell to its
            // share of the available area.
            width:  grid.availableWidth  / 7
            height: grid.availableHeight / 6
            readonly property bool inMonth:  model.month === grid.month
            readonly property bool isToday:  model.today === true
            readonly property bool isFocused: root.provider
                && root._sameDay(model.date, root.provider.focusedDate)

            color: {
                if (!root.theme) return "transparent";
                // Skip the focus tint when the cell is also today —
                // the red day-number marker already distinguishes it,
                // and stacking the accent fill on top looks noisy.
                if (cell.isFocused && !cell.isToday)
                    return Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12);
                if (!cell.inMonth)
                    return Qt.rgba(root.theme.fg.r, root.theme.fg.g, root.theme.fg.b, 0.025);
                return "transparent";
            }

            // Day number, top-right corner. The circle is the today
            // highlight — it sits behind the number when isToday is true.
            Item {
                id: dayBadge
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 4
                anchors.rightMargin: 5
                width: 22
                height: 22

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    visible: cell.isToday
                    color: root.theme ? root.theme.danger : "#d20f39"
                }

                Text {
                    anchors.centerIn: parent
                    text: cell.model.day
                    color: cell.isToday
                        ? "#ffffff"
                        : (root.theme ? root.theme.fg : "#000")
                    opacity: cell.inMonth ? 1.0 : 0.4
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.bold: cell.isToday
                }
            }

            // Events for this day — fetched lazily; the binding tracks
            // `eventsModel.eventsByDate` (reassigned wholesale on each
            // refresh), so cells auto-update when sync completes.
            readonly property var events: root.provider && root.provider.eventsModel
                ? root.provider.eventsModel.eventsFor(cell.model.date)
                : []
            // How many event chips fit; the rest are folded into a
            // "+N more" line at the bottom.
            readonly property int _maxChips: 3
            readonly property bool _overflow: events.length > _maxChips

            Column {
                id: eventsCol
                anchors.top: dayBadge.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.topMargin: 2
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                anchors.bottomMargin: 4
                spacing: 2

                Repeater {
                    model: cell._overflow
                        ? cell.events.slice(0, cell._maxChips - 1)
                        : cell.events
                    // Each chip: subtle accent-tinted background with a
                    // 2px calendar-coloured stripe on the left (falling
                    // back to theme.accent when the calendar has no
                    // colour metadata). `clip: true` keeps the stripe
                    // inside the rounded corners.
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        width: eventsCol.width
                        height: 14
                        radius: 3
                        clip: true
                        color: root._chipBg(chipArea.containsMouse)
                        opacity: cell.inMonth ? 1.0 : 0.55

                        // Click → push this event into the provider's
                        // selectedEvent slot, which the right-hand pane
                        // (declared below) is bound to.
                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: if (root.provider)
                                root.provider.selectEvent(chip.modelData)
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 2
                            color: {
                                const c = parent.modelData.color;
                                if (c && c.length > 0) return c;
                                return root.theme ? root.theme.accent : "#1e66f5";
                            }
                        }

                        // Time (timed events only) — right-aligned, bold.
                        // All-day events skip it entirely.
                        Text {
                            id: timeText
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !parent.modelData.allDay && text.length > 0
                            text: {
                                const m = parent.modelData;
                                if (m.allDay) return "";
                                const d = new Date(m.start);
                                if (isNaN(d.getTime())) return "";
                                return Qt.formatTime(d, "HH:mm");
                            }
                            color: root.theme ? root.theme.fg : "#000"
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                        }

                        // Title — left-aligned, elided. Reserves room
                        // for the time on the right when present.
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            anchors.right: timeText.visible ? timeText.left : parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.summary || "(no title)"
                            color: root.theme ? root.theme.fg : "#000"
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                }

                Text {
                    visible: cell._overflow
                    text: "+" + (cell.events.length - (cell._maxChips - 1)) + " more"
                    color: root.theme ? root.theme.subFg : "#888"
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    opacity: cell.inMonth ? 0.85 : 0.45
                }
            }

            // Right + bottom borders form the inner grid lines.
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: root.theme ? root.theme.border : "#444"
                opacity: 0.5
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.theme ? root.theme.border : "#444"
                opacity: 0.5
            }
        }
    }

    // ── Right-side details pane (visible when an event is selected) ────
    // The pane stays mounted; its width animates between 0 and the
    // open size. Calendar elements above anchor to `detailsDivider.left`
    // unconditionally — when width collapses to 0 the divider's own
    // width drops to 0 too, putting its left edge at parent.right and
    // letting the calendar expand to fill the whole pane.
    Rectangle {
        id: detailsDivider
        anchors.right: detailsPane.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: detailsPane.width > 0.5 ? 1 : 0
        color: root.theme ? root.theme.border : "#444"
        opacity: 0.5
    }

    EventDetailsPane {
        id: detailsPane
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root._showDetails ? 320 : 0
        visible: width > 0.5
        clip: true
        theme: root.theme
        fontFamily: root.fontFamily
        event: root.provider ? root.provider.selectedEvent : null
        onClose: if (root.provider) root.provider.selectEvent(null)
        // Clicking a description URL: ask the launcher to fully close
        // so the browser can keep focus.
        onLinkOpened: if (root.provider) root.provider.requestClose()

        Behavior on width {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
    }
}
