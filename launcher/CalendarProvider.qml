// Calendar provider — owns month/year state, delegates rendering to
// MonthComponent (Apple-style 6×7 grid). Uses `resultsLayout: "custom"`;
// keyboard input arrives via handleKey().

import QtQuick
import "calendar"

Provider {
    id: prov

    name: "Calendar"
    tag: "calendar"
    iconText: ""
    iconComponent: Component { CalendarIcon {} }
    description: "Month view"
    shortcuts: ["cal", "calendar"]

    resultsLayout: "custom"
    requestedWidth: 1120
    requestedHeight: 640

    // Month is 0-11 (matches Qt's MonthGrid).
    property int displayedMonth: (new Date()).getMonth()
    property int displayedYear:  (new Date()).getFullYear()

    // Loaded from the vdirsyncer cache. Read via eventsModel.eventsFor(date).
    property EventsModel eventsModel: EventsModel {}

    // null = pane hidden. Chip click sets it; goBack / close button clears.
    property var selectedEvent: null

    function selectEvent(ev) { selectedEvent = ev; }

    property string searchQuery: ""

    // Qt.callLater dedupes within an event-loop tick — Dec → Jan fires
    // both month and year changes, but we still only spawn Python once.
    Component.onCompleted: _refreshEvents()
    onDisplayedMonthChanged: Qt.callLater(_refreshEvents)
    onDisplayedYearChanged:  Qt.callLater(_refreshEvents)

    // Re-fetch when the launcher is (re)opened so events synced into the
    // vdirsyncer cache while QS keeps running appear without a reload.
    // Without this, events were only loaded at startup and on month change, so
    // a long-running session showed a stale snapshot until restart. Throttled
    // so repeated opens don't respawn Python needlessly.
    property double _lastFetchMs: 0
    onLauncherOpenChanged: if (launcherOpen && (Date.now() - _lastFetchMs) > 60000)
        _refreshEvents()

    function _refreshEvents() {
        _lastFetchMs = Date.now();
        // Pad by a week on either side so adjacent-month rows are populated.
        const start = new Date(displayedYear, displayedMonth, 1);
        start.setDate(start.getDate() - 7);
        const end = new Date(displayedYear, displayedMonth + 1, 1);
        end.setDate(end.getDate() + 7);
        eventsModel.refresh(start, end);
    }

    function goPrevMonth() {
        if (displayedMonth === 0) { displayedMonth = 11; displayedYear -= 1; }
        else                      { displayedMonth -= 1; }
    }

    function goNextMonth() {
        if (displayedMonth === 11) { displayedMonth = 0; displayedYear += 1; }
        else                       { displayedMonth += 1; }
    }

    function goToday() {
        const t = new Date();
        displayedMonth = t.getMonth();
        displayedYear  = t.getFullYear();
    }

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_PageUp:   goPrevMonth();  return true;
        case Qt.Key_PageDown: goNextMonth();  return true;
        case Qt.Key_Home:     goToday();      return true;
        }
        return false;
    }

    // First Escape closes the details pane; a second Escape exits the
    // calendar (handled by the launcher's backToMenu).
    function goBack() {
        if (selectedEvent !== null) {
            selectedEvent = null;
            return true;
        }
        return false;
    }

    // Snap back to today's month on close so re-entry starts clean.
    function reset() {
        const t = new Date();
        displayedMonth = t.getMonth();
        displayedYear  = t.getFullYear();
        searchQuery    = "";
        selectedEvent  = null;
    }

    // No launcher result rows — calendar owns the whole pane. We store
    // the query so cell delegates can filter chips.
    function search(text) {
        searchQuery = (text || "").toLowerCase().trim();
    }
    function activate(result) {}

    customComponent: Component { MonthComponent {} }
}
