// Month view — Apple-style 6×7 grid via `MonthGrid` + `DayOfWeekRow`
// (locale-aware). Today is a filled circle in `theme.danger`; focused
// day is outlined in `theme.accent`; out-of-month days fade.

import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Item {
    id: root
    anchors.fill: parent

    // Injected by Launcher.onLoaded; null until then so bindings guard.
    property var theme: null
    property string fontFamily: ""
    property var provider: null

    readonly property var _monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    function _chipBg(hovered) {
        if (!root.theme) return "#1e66f522";
        const a = root.theme.accent;
        return Qt.rgba(a.r, a.g, a.b, hovered ? 0.30 : 0.18);
    }

    // Calendar elements anchor to detailsDivider.left instead of
    // parent.right when this flips on — that's what shrinks the grid.
    readonly property bool _showDetails:
        root.provider && root.provider.selectedEvent !== null

    // Day whose events are expanded (set by tapping "+N more"); "" means none.
    // Cleared when the displayed month/year changes. The expansion renders as
    // a root-level popup (see dayPopup) so it can be wider than the cell, cast
    // a shadow, and be dismissed by a click-catcher behind it.
    property string expandedDateKey: ""
    // Source cell geometry in root coordinates, captured when opening.
    property real _exX: 0
    property real _exY: 0
    property real _exW: 0
    property real _exH: 0

    function _openExpansion(cell) {
        const p = cell.mapToItem(root, 0, 0);
        root._exX = p.x;
        root._exY = p.y;
        root._exW = cell.width;
        root._exH = cell.height;
        root.expandedDateKey = cell._dateKey;
    }

    // Events for the expanded day, filtered like the cells.
    readonly property var _expandedEvents: {
        if (!provider || !provider.eventsModel || expandedDateKey === "") return [];
        const all = provider.eventsModel.eventsByDate[expandedDateKey] || [];
        const q = provider.searchQuery || "";
        return q.length === 0 ? all
            : all.filter(e => (e.summary || "").toLowerCase().indexOf(q) !== -1);
    }
    readonly property int _expandedDay: {
        if (expandedDateKey === "") return 0;
        const d = new Date(expandedDateKey + "T00:00:00");
        return isNaN(d.getTime()) ? 0 : d.getDate();
    }

    Connections {
        target: root.provider
        ignoreUnknownSignals: true
        function onDisplayedMonthChanged() { root.expandedDateKey = ""; }
        function onDisplayedYearChanged()  { root.expandedDateKey = ""; }
    }

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
                radius: root.theme.radius
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

        // Each cell is its own box: subtle right+bottom borders form
        // the grid, day number sits in the top-right corner (with a
        // red circle when it's today), and the rest of the cell holds
        // event chips.
        delegate: Rectangle {
            id: cell
            required property var model
            // The contentItem is a QQ.Grid that doesn't stretch its
            // children — they'd default to their implicit text size and
            // leave most of the MonthGrid empty. Force each cell to its
            // share of the available area.
            width:  grid.availableWidth  / 7
            height: grid.availableHeight / 6
            readonly property bool inMonth: model.month === grid.month
            readonly property bool isToday: model.today === true
            readonly property string _dateKey: Qt.formatDate(model.date, "yyyy-MM-dd")
            readonly property bool _expanded: root.expandedDateKey === cell._dateKey
            // Raise above sibling cells so the inline expansion overlay can
            // extend over neighbouring days.
            z: _expanded ? 10 : 0

            color: {
                if (!root.theme) return "transparent";
                if (!cell.inMonth)
                    return Qt.rgba(root.theme.fg.r, root.theme.fg.g, root.theme.fg.b, 0.025);
                return "transparent";
            }

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

            // Cells auto-update when sync completes because `eventsByDate`
            // is reassigned wholesale on each refresh. Filter by lowercase
            // substring against the provider's searchQuery.
            readonly property var events: {
                if (!root.provider || !root.provider.eventsModel) return [];
                const all = root.provider.eventsModel.eventsFor(cell.model.date);
                const q = root.provider.searchQuery || "";
                if (q.length === 0) return all;
                return all.filter(e => (e.summary || "").toLowerCase().indexOf(q) !== -1);
            }
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
                    // 2px stripe uses the calendar's colour, falls back
                    // to theme.accent. `clip: true` keeps the stripe
                    // inside the rounded corners.
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        width: eventsCol.width
                        height: 14
                        radius: root.theme.radius
                        clip: true
                        color: root._chipBg(chipArea.containsMouse)
                        opacity: cell.inMonth ? 1.0 : 0.55

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

                MouseArea {
                    visible: cell._overflow
                    width: moreText.implicitWidth
                    height: moreText.implicitHeight
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._openExpansion(cell)

                    Text {
                        id: moreText
                        text: "+" + (cell.events.length - (cell._maxChips - 1)) + " more"
                        color: root.theme ? root.theme.subFg : "#888"
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        opacity: cell.inMonth ? 0.85 : 0.45
                    }
                }
            }

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

    // detailsDivider's width collapses to 0 when the pane is hidden,
    // pinning its left edge at parent.right so the calendar fills the
    // pane (everything above anchors to detailsDivider.left).
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
        provider: root.provider
        event: root.provider ? root.provider.selectedEvent : null
        onClose: if (root.provider) root.provider.selectEvent(null)
        // Clicking a description URL: ask the launcher to fully close
        // so the browser can keep focus.
        onLinkOpened: if (root.provider) root.provider.requestClose()

        Behavior on width {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
    }

    // ── Expanded-day popup ("+N more") ──────────────────────────────────
    // Click-catcher: dismisses the expansion on any click outside the popup.
    MouseArea {
        anchors.fill: parent
        visible: root.expandedDateKey !== ""
        z: 90
        onClicked: root.expandedDateKey = ""
    }

    // The popup itself — wider than the source cell, clamped to the grid,
    // grows down (or up near the bottom edge), with a drop shadow. Sits above
    // the catcher so clicks inside it don't dismiss.
    Item {
        id: dayPopup
        visible: root.expandedDateKey !== ""
        z: 91

        readonly property int _rowH: 18
        readonly property int _headH: 24
        readonly property int _pad: 8
        readonly property int _needed: _headH + root._expandedEvents.length * _rowH + _pad
        readonly property real _below: (grid.y + grid.height) - root._exY
        readonly property real _above: (root._exY + root._exH) - grid.y
        readonly property bool _down: _needed <= _below || _below >= _above
        readonly property real _w: Math.min(grid.width, Math.max(root._exW * 1.7, root._exW + 90))

        width: _w
        height: Math.min(_needed, Math.max(root._exH, _down ? _below : _above))
        x: Math.max(grid.x, Math.min(root._exX + root._exW / 2 - _w / 2, grid.x + grid.width - _w))
        y: _down ? root._exY : (root._exY + root._exH - height)

        Rectangle {
            id: popupBg
            anchors.fill: parent
            radius: root.theme.radius
            color: root.theme ? root.theme.bg : "#ffffff"
            border.width: 1
            border.color: root.theme ? root.theme.border : "#bcc0cc"
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.28
                shadowBlur: 1.0
                shadowVerticalOffset: 4
                shadowHorizontalOffset: 0
            }
        }

        Item {
            id: popHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: dayPopup._headH

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root._expandedDay > 0 ? root._expandedDay : ""
                color: root.theme ? root.theme.fg : "#000"
                font.family: root.fontFamily
                font.pixelSize: 13
                font.bold: true
            }

            MouseArea {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expandedDateKey = ""

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: root.theme ? root.theme.subFg : "#888"
                    font.family: root.fontFamily
                    font.pixelSize: 16
                }
            }
        }

        ListView {
            id: popList
            anchors.top: popHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            anchors.bottomMargin: 6
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root._expandedEvents

            delegate: Rectangle {
                id: pchip
                required property var modelData
                width: ListView.view.width
                height: 16
                radius: root.theme.radius
                clip: true
                color: root._chipBg(pchipArea.containsMouse)

                MouseArea {
                    id: pchipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.provider)
                            root.provider.selectEvent(pchip.modelData);
                        root.expandedDateKey = "";
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 2
                    color: {
                        const c = pchip.modelData.color;
                        if (c && c.length > 0) return c;
                        return root.theme ? root.theme.accent : "#1e66f5";
                    }
                }

                Text {
                    id: pTime
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !pchip.modelData.allDay && text.length > 0
                    text: {
                        const m = pchip.modelData;
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

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: pTime.visible ? pTime.left : parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: pchip.modelData.summary || "(no title)"
                    color: root.theme ? root.theme.fg : "#000"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }
    }
}
