// Calendar provider — owns calendar state (current month/year, focused
// day, eventually view mode + connected backends) and delegates
// rendering to per-view components under launcher/calendar/.
//
// Layout: uses the `resultsLayout: "custom"` hook (see Provider.qml /
// Launcher.qml). The launcher hands the right pane to `customComponent`
// and forwards keyboard input via `handleKey`.
//
// Today's customComponent is `MonthComponent` (Apple-style 6×7 grid).
// Week / Day views will sit alongside it in launcher/calendar/ and
// follow the same shape (take theme/fontFamily/provider, call provider
// mutators for state changes). Once we add view modes, swap the
// customComponent via a small router or a Loader keyed off `viewMode`.
//
// Future work: 3rd-party calendars (CalDAV / Google / iCloud) feeding
// per-day event blobs that views can decorate cells / timelines with.

import QtQuick
import "calendar"

Provider {
    id: prov

    name: "Calendar"
    tag: "calendar"
    iconText: ""                                       // fallback only
    iconComponent: Component { CalendarIcon {} }        // live tear-off page
    description: "Month view"
    shortcuts: ["cal", "calendar"]

    resultsLayout: "custom"
    requestedWidth: 1120
    requestedHeight: 640

    // ── State ───────────────────────────────────────────────────────────
    // Bound directly into MonthGrid (month is 0-11).
    property int displayedMonth: (new Date()).getMonth()
    property int displayedYear:  (new Date()).getFullYear()

    // Events loaded from the vdirsyncer cache. Views read this via
    // `provider.eventsModel.eventsFor(date)`. Refreshed when the
    // displayed month changes (and once at startup).
    property EventsModel eventsModel: EventsModel {}

    // The event currently shown in the right-hand details pane (null =
    // pane hidden). Set by chip clicks; cleared by goBack() or the
    // pane's close button.
    property var selectedEvent: null

    function selectEvent(ev) { selectedEvent = ev; }

    // Lowercase-trimmed search query; cells use this to filter their
    // chips by `summary`. Empty = no filtering. Driven by the launcher's
    // search input via the standard `search()` provider hook below.
    property string searchQuery: ""

    // Qt.callLater dedupes calls scheduled in the same event-loop tick,
    // so going Dec → Jan (both displayedMonth and displayedYear fire)
    // only triggers one Python spawn instead of two.
    Component.onCompleted: _refreshEvents()
    onDisplayedMonthChanged: Qt.callLater(_refreshEvents)
    onDisplayedYearChanged:  Qt.callLater(_refreshEvents)

    function _refreshEvents() {
        // Window covers the visible 6×7 grid: pad the displayed month by
        // a week on either side so leading / trailing rows from adjacent
        // months are populated too.
        const start = new Date(displayedYear, displayedMonth, 1);
        start.setDate(start.getDate() - 7);
        const end = new Date(displayedYear, displayedMonth + 1, 1);
        end.setDate(end.getDate() + 7);
        eventsModel.refresh(start, end);
    }

    // ── Navigation (called from view components & handleKey) ────────────
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

    // Launcher calls this on Escape before falling back to backToMenu.
    // We use it to close the details pane on first Escape; a second
    // Escape exits the calendar.
    function goBack() {
        if (selectedEvent !== null) {
            selectedEvent = null;
            return true;
        }
        return false;
    }

    // Launcher resets every provider when it closes / returns to menu.
    // Snap the view back to today's month, drop any selected event and
    // clear the search filter, so re-entering the calendar always
    // starts on a clean current month.
    function reset() {
        const t = new Date();
        displayedMonth = t.getMonth();
        displayedYear  = t.getFullYear();
        searchQuery    = "";
        selectedEvent  = null;
    }

    // Search input is repurposed as an in-view event filter — we don't
    // produce launcher result rows (the calendar owns the whole pane);
    // we just store the query and let the cell delegates filter chips.
    function search(text) {
        searchQuery = (text || "").toLowerCase().trim();
    }
    function activate(result) {}

    // ── View ────────────────────────────────────────────────────────────
    // The Launcher's Loader instantiates this and pushes `theme`,
    // `fontFamily`, and `provider` onto the root via setters in onLoaded.
    customComponent: Component { MonthComponent {} }
}
