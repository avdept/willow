#!/usr/bin/env python3
"""Walk vdirsyncer's local calendar cache and emit events as JSON.

Usage:
    calendar-events.py --start YYYY-MM-DD --end YYYY-MM-DD [--path DIR]

`--end` is exclusive. `--path` defaults to vdirsyncer's standard cache
(`~/.local/share/vdirsyncer/calendars`). Each event is rendered as:

    {
      "uid": "...",
      "summary": "Standup",
      "start": "2026-05-21T09:00:00+02:00",   # date-only when allDay
      "end":   "2026-05-21T09:30:00+02:00",
      "allDay": false,
      "calendar": "Work",                      # displayname or dir name
      "color":   "#4285f4",                    # or null
      "location": "",
      "description": ""
    }

JSON is written compact to stdout; parse errors and warnings go to
stderr. Exit code 2 means a required Python dep is missing.
"""

import argparse
import json
import sys
from datetime import date, datetime
from pathlib import Path

try:
    import icalendar
    import recurring_ical_events
    from dateutil.tz import tzlocal
except ImportError as e:
    sys.stderr.write(
        f"calendar-events: missing dep {e.name!r}; "
        "install python-icalendar python-recurring-ical-events "
        "python-dateutil\n"
    )
    sys.exit(2)


def _iso(dt):
    """ISO 8601 for a date or datetime, normalising naive dts to local tz."""
    if isinstance(dt, datetime):
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=tzlocal())
        return dt.isoformat()
    return dt.isoformat()  # date — "YYYY-MM-DD"


def _person(value):
    """Normalise a vCalAddress (ATTENDEE / ORGANIZER) to a plain dict.

    Returns None when the value can't be read. Output keys:
      { name, email, status, role }
    `status` is the PARTSTAT (NEEDS-ACTION / ACCEPTED / DECLINED /
    TENTATIVE / DELEGATED) — meaningful for attendees, "" for organizer.
    """
    if value is None:
        return None
    try:
        raw = str(value)
    except Exception:
        return None
    email = raw[len("mailto:"):] if raw.lower().startswith("mailto:") else raw
    params = getattr(value, "params", {}) or {}
    name = str(params.get("CN", "")).strip() or email
    return {
        "name":   name,
        "email":  email,
        "status": str(params.get("PARTSTAT", "")).upper(),
        "role":   str(params.get("ROLE", "")).upper(),
    }


def _attendees(ev):
    raw = ev.get("ATTENDEE")
    if not raw:
        return []
    if not isinstance(raw, list):
        raw = [raw]
    out = []
    for a in raw:
        p = _person(a)
        if p:
            out.append(p)
    return out


def _organizer(ev):
    return _person(ev.get("ORGANIZER"))


def _scan_calendar(cal_dir: Path, start: date, end: date):
    """Yield event dicts for every .ics file under one calendar dir."""
    color_file = cal_dir / "color"
    name_file = cal_dir / "displayname"
    color = color_file.read_text().strip() if color_file.is_file() else None
    name = (
        name_file.read_text().strip()
        if name_file.is_file()
        else cal_dir.name
    )

    for ics in cal_dir.glob("*.ics"):
        try:
            cal = icalendar.Calendar.from_ical(ics.read_bytes())
        except Exception as e:
            sys.stderr.write(f"calendar-events: parse {ics}: {e}\n")
            continue

        try:
            occurrences = recurring_ical_events.of(cal).between(start, end)
        except Exception as e:
            sys.stderr.write(f"calendar-events: expand {ics}: {e}\n")
            continue

        for ev in occurrences:
            dts = ev.get("DTSTART").dt if ev.get("DTSTART") else None
            dte = ev.get("DTEND").dt if ev.get("DTEND") else dts
            if dts is None:
                continue
            all_day = isinstance(dts, date) and not isinstance(dts, datetime)
            yield {
                "uid":         str(ev.get("UID", "")),
                "summary":     str(ev.get("SUMMARY", "")),
                "start":       _iso(dts),
                "end":         _iso(dte) if dte else _iso(dts),
                "allDay":      all_day,
                "calendar":    name,
                "color":       color,
                "location":    str(ev.get("LOCATION", "")),
                "description": str(ev.get("DESCRIPTION", "")),
                "organizer":   _organizer(ev),
                "attendees":   _attendees(ev),
            }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", required=True, help="inclusive, YYYY-MM-DD")
    ap.add_argument("--end",   required=True, help="exclusive, YYYY-MM-DD")
    ap.add_argument(
        "--path",
        default=str(Path.home() / ".local/share/vdirsyncer/calendars"),
        help="vdirsyncer calendar root",
    )
    args = ap.parse_args()

    start = datetime.strptime(args.start, "%Y-%m-%d").date()
    end   = datetime.strptime(args.end,   "%Y-%m-%d").date()

    root = Path(args.path)
    if not root.is_dir():
        json.dump([], sys.stdout)
        return

    events = []
    # Layout: root / <account> / <calendar> / *.ics
    for cal_dir in sorted(root.glob("*/*")):
        if cal_dir.is_dir():
            events.extend(_scan_calendar(cal_dir, start, end))

    events.sort(key=lambda e: e["start"])
    json.dump(events, sys.stdout, separators=(",", ":"))


if __name__ == "__main__":
    main()
