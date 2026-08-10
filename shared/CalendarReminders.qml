// Calendar reminders — fires desktop notifications a configurable lead time
// before timed calendar events begin. This is an always-alive watcher
// (instantiated once in shell.qml), independent of whether the launcher
// calendar is open.
//
// It reuses the same data source as the launcher calendar — the sibling
// `launcher/calendar/calendar-events.py`, which walks vdirsyncer's local cache
// — but does its own periodic fetch of a today+tomorrow window so reminders
// keep working without the calendar UI ever being opened.
//
// Delivery goes through `notify-send`, so reminders land in the normal
// notification pipeline (toast + drawer). With `sticky` on they use
// `notify-send -t 0`, i.e. they stay on screen until dismissed (see
// NotificationManager.toastDurationOf) — Apple-Calendar style.

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: rem

    // ── Config ──────────────────────────────────────────────────────────
    // Minutes-before-start at which to fire. One notification per (event,
    // lead). e.g. [60, 10, 0] = an hour before, ten minutes before, and at
    // start. Default: a single 10-minute heads-up.
    property var leadsMin: [10]
    // Re-scan the calendar cache this often. Also advances the day window and
    // picks up edits synced by vdirsyncer in the background.
    property int refreshIntervalMs: 5 * 60 * 1000
    // How often to check whether any reminder has come due.
    property int tickMs: 30 * 1000
    // Sticky reminders stay until dismissed (notify-send -t 0); otherwise they
    // use the notification daemon's default timeout.
    property bool sticky: true
    property string appName: "Calendar"
    // Nerd-font calendar glyph passed via the `x-glyph` hint and rendered by
    // NotificationContent — avoids depending on a Qt icon theme (none is set
    // under bare Hyprland, so themed names like "calendar" don't resolve).
    property string glyph: ""
    // All-day events have no meaningful "starts soon"; skip them by default.
    property bool includeAllDay: false

    // ── State ───────────────────────────────────────────────────────────
    property var _events: []          // parsed event objects (see script docstring)
    property var _notified: ({})      // key "uid|startIso|lead" → true (fired)
    property string _buf: ""
    property string _dayKey: ""       // local date of the last refresh, for daily reset

    // Absolute path to the sibling calendar script, computed from this file's
    // URL so it works wherever the project is checked out.
    readonly property string _scriptPath:
        Qt.resolvedUrl("../launcher/calendar/calendar-events.py").toString().replace(/^file:\/\//, "")

    function _refresh() {
        const start = new Date();
        start.setHours(0, 0, 0, 0);
        const end = new Date(start);
        end.setDate(end.getDate() + 2);   // today + tomorrow (end is exclusive)

        // Reset the fired-set when the day rolls over so it can't grow without
        // bound and yesterday's keys can't suppress a same-uid event today.
        const dayKey = Qt.formatDate(start, "yyyy-MM-dd");
        if (dayKey !== rem._dayKey) {
            rem._dayKey = dayKey;
            rem._notified = ({});
        }

        rem._buf = "";
        _proc.command = [
            "python3", rem._scriptPath,
            "--start", Qt.formatDate(start, "yyyy-MM-dd"),
            "--end",   Qt.formatDate(end,   "yyyy-MM-dd")
        ];
        if (_proc.running) _proc.running = false;
        _proc.running = true;
    }

    function _check() {
        const now = Date.now();
        const leads = rem.leadsMin || [];
        if (leads.length === 0) return;

        for (let i = 0; i < rem._events.length; i++) {
            const ev = rem._events[i];
            if (!ev || !ev.start) continue;
            if (ev.allDay && !rem.includeAllDay) continue;

            const startMs = new Date(ev.start).getTime();
            if (isNaN(startMs)) continue;

            for (let j = 0; j < leads.length; j++) {
                const lead = leads[j];
                const targetMs = startMs - lead * 60000;
                // Due from the lead moment until just past start (the +60s lets
                // a 0-minute lead still fire within one tick of the start, and
                // bounds re-firing on reload to events that haven't started).
                if (now < targetMs || now > startMs + 60000) continue;

                const key = (ev.uid || ev.summary || "?") + "|" + ev.start + "|" + lead;
                if (rem._notified[key]) continue;
                rem._notified[key] = true;
                rem._fire(ev, lead, startMs);
            }
        }
    }

    function _fire(ev, lead, startMs) {
        const summary = ev.summary || "Event";
        const hhmm = Qt.formatTime(new Date(startMs), "HH:mm");

        let lede;
        if (lead <= 0)        lede = "Starting now";
        else if (lead === 1)  lede = "In 1 minute";
        else if (lead < 60)   lede = "In " + lead + " minutes";
        else                  lede = "In " + Math.round(lead / 60) + " hour" + (lead >= 120 ? "s" : "");

        let body = lede + " · " + hhmm;
        if (ev.location && ev.location.length > 0)
            body += " · " + ev.location;

        const cmd = ["notify-send", "-a", rem.appName];
        if (rem.sticky) cmd.push("-t", "0");
        if (rem.glyph.length > 0) cmd.push("-h", "string:x-glyph:" + rem.glyph);
        // Meeting link parsed from the event → rendered as a "Join" quick
        // action by NotificationContent (opens via xdg-open; see x-join-url).
        const url = rem._extractUrl(ev);
        if (url.length > 0) cmd.push("-h", "string:x-join-url:" + url);
        cmd.push(summary, body);
        Quickshell.execDetached(cmd);
    }

    // Find a meeting/join link in the event. Looks in location first (Google
    // often puts the Meet link there), then the description. Prefers known
    // conferencing providers; otherwise returns the first http(s) URL.
    function _extractUrl(ev) {
        if (!ev) return "";
        const hay = [ev.location || "", ev.description || ""].join("\n");
        const matches = hay.match(/https?:\/\/[^\s<>"')\]]+/g);
        if (!matches || matches.length === 0) return "";
        const providers = /(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|teams\.live|webex\.com|whereby\.com|meet\.jit\.si|chime\.aws|bluejeans\.com|gotomeeting\.com|around\.co)/i;
        for (let i = 0; i < matches.length; i++)
            if (providers.test(matches[i])) return rem._cleanUrl(matches[i]);
        return rem._cleanUrl(matches[0]);
    }

    function _cleanUrl(u) {
        // Undo HTML entity escaping common in calendar descriptions and drop
        // trailing sentence punctuation the regex may have swept up.
        return (u || "").replace(/&amp;/g, "&").replace(/[.,;]+$/, "");
    }

    // ── Plumbing ────────────────────────────────────────────────────────
    // Declared as named properties rather than default-property children:
    // QtObject's QML-side default property is finicky (same pattern as
    // EventsModel).
    property Process _proc: Process {
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => rem._buf += line
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if ((line || "").trim().length > 0)
                    console.warn("[CalendarReminders] " + line);
            }
        }
        onRunningChanged: {
            if (running) return;
            try {
                rem._events = JSON.parse(rem._buf || "[]");
            } catch (e) {
                console.warn("[CalendarReminders] events JSON parse:", e,
                             "buf head:", (rem._buf || "").slice(0, 120));
                rem._events = [];
            }
            // Check straight after a refresh so a just-loaded imminent event
            // isn't delayed by up to a full tick.
            rem._check();
        }
    }

    property Timer _refreshTimer: Timer {
        interval: rem.refreshIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: rem._refresh()
    }

    property Timer _tick: Timer {
        interval: rem.tickMs
        running: true
        repeat: true
        onTriggered: rem._check()
    }
}
