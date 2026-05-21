// Calendar events model. Shells out to `calendar-events.py` (sibling file)
// for a date window, parses the JSON payload, and buckets events by their
// LOCAL start date so cells can look them up via `eventsFor(date)`.
//
// Refresh is fire-and-forget: callers don't await; bind to `eventsByDate`
// (re-assigned wholesale on each fetch) for reactivity.

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    // ── Public state ────────────────────────────────────────────────────
    // Map: "yyyy-MM-dd" → array of event objects (see script docstring).
    property var eventsByDate: ({})
    property bool loading: false
    property string error: ""
    // ISO timestamp of the most recent successful refresh — useful later
    // for a "stale" indicator in the header.
    property string lastRefreshIso: ""

    // Refresh events for [start, end). `start` and `end` are JS Date
    // objects; `end` is exclusive. Both args are interpreted as local
    // calendar dates (time-of-day is ignored).
    function refresh(start, end) {
        if (!start || !end) return;
        root.loading = true;
        root.error = "";
        root._buf = "";
        _proc.command = [
            "python3",
            root._scriptPath,
            "--start", Qt.formatDate(start, "yyyy-MM-dd"),
            "--end",   Qt.formatDate(end,   "yyyy-MM-dd")
        ];
        if (_proc.running) _proc.running = false;
        _proc.running = true;
    }

    // Shared empty sentinel so unmapped dates don't allocate a fresh
    // array on every call (the cell delegate calls this 42×/refresh).
    readonly property var _noEvents: []

    function eventsFor(d) {
        if (!d) return _noEvents;
        return eventsByDate[Qt.formatDate(d, "yyyy-MM-dd")] || _noEvents;
    }

    // ── Internals ───────────────────────────────────────────────────────
    // Absolute path to the sibling Python helper; computed from this
    // file's URL so it works wherever the project is checked out.
    readonly property string _scriptPath:
        Qt.resolvedUrl("calendar-events.py").toString().replace(/^file:\/\//, "")

    property string _buf: ""

    // Process is declared as an explicit named property rather than a
    // default-property child — QtObject's QML-side default-property
    // declaration is finicky outside the Provider base class.
    property Process _proc: Process {
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root._buf += line
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if ((line || "").trim().length > 0)
                    console.warn("[Calendar] " + line);
            }
        }
        onRunningChanged: {
            if (running) return;
            root.loading = false;
            try {
                const events = JSON.parse(root._buf || "[]");
                const map = {};
                for (let i = 0; i < events.length; i++) {
                    const ev = events[i];
                    // Bucket by the LOCAL date of the start time. JS Date
                    // parses the ISO string (with offset) correctly; the
                    // formatDate then renders it in local tz.
                    const d = new Date(ev.start);
                    if (isNaN(d.getTime())) continue;
                    const key = Qt.formatDate(d, "yyyy-MM-dd");
                    (map[key] || (map[key] = [])).push(ev);
                }
                root.eventsByDate = map;
                root.lastRefreshIso = new Date().toISOString();
            } catch (e) {
                root.error = "" + e;
                console.warn("[Calendar] events JSON parse:", e,
                             "buf head:", (root._buf || "").slice(0, 120));
            }
        }
    }
}
