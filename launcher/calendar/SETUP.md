# Calendar setup — vdirsyncer + khal

The Calendar launcher provider reads events from a **local on-disk
calendar cache**. `vdirsyncer` keeps that cache in sync with remote
calendars (Google, iCloud, Fastmail, any CalDAV server); `khal` is the
CRUD tool used to create / edit / delete events from the CLI. Edits
made through `khal` land in the local cache and `vdirsyncer` pushes
them back to the remote on the next sync.

```
  ┌──────────────┐   sync    ┌─────────────────────────────────┐
  │ Google /     │ ◀──────▶  │ ~/.local/share/vdirsyncer/      │
  │ iCloud / …   │           │ calendars/<account>/<calendar>/ │
  └──────────────┘           │   *.ics                         │
                             └──────────────┬──────────────────┘
                                            │ read / write
                                            ▼
                              ┌──────────────────────────┐
                              │ khal  (CLI CRUD)         │
                              │ Quickshell launcher      │
                              └──────────────────────────┘
```

Everything runs offline once synced. The launcher never sees an OAuth
token; that lives entirely on the vdirsyncer side.

---

## 1. Install

### vdirsyncer + khal (system tools)

```bash
sudo pacman -S vdirsyncer khal python-aiohttp-oauthlib
```

`python-aiohttp-oauthlib` is required for the `google_calendar`
storage type. CalDAV-only setups (iCloud, Fastmail, Nextcloud, …)
don't need it.

### Python deps for the event-reader helper

The launcher's `calendar-events.py` helper expands recurring events
and surfaces them on day cells. Pick **one** path:

**Option A — Arch packages (preferred on Arch):**

```bash
sudo pacman -S python-icalendar python-recurring-ical-events python-dateutil
```

**Option B — pip (any distro, including non-Arch):**

```bash
# system-wide, or run inside a venv first to keep it isolated
pip install -r launcher/calendar/requirements.txt
```

The pip route needs `python-pip` installed (`sudo pacman -S
python-pip` on Arch) — but if you're on Arch, Option A skips that
step entirely. The two are equivalent; do not run both.

If these deps are missing the launcher still works — the month grid
just renders without event chips until they're installed.

---

## 2. Google OAuth credentials

Google's CalDAV access requires OAuth. The vdirsyncer maintainers
keep current screenshots for the Cloud Console steps — follow:

  <https://vdirsyncer.pimutils.org/en/stable/config.html#google>

The result is a `client_id` and `client_secret`. Stash them
somewhere; we paste them into the vdirsyncer config next.

> Note: Google's UI changes often. If the screenshots above are
> stale, the keywords you're looking for in Cloud Console are
> *Create credentials → OAuth client ID → Desktop app*, plus
> *Enable APIs and Services → Google Calendar API* on the same
> project.

---

## 3. vdirsyncer config

`~/.config/vdirsyncer/config`:

```ini
[general]
status_path = "~/.local/share/vdirsyncer/status/"

# ── Remote: Google ───────────────────────────────────────────
[storage google_remote]
type = "google_calendar"
token_file = "~/.config/vdirsyncer/google_token"
client_id = "<paste from step 2>"
client_secret = "<paste from step 2>"

# ── Local: plain .ics files ──────────────────────────────────
[storage google_local]
type = "filesystem"
path = "~/.local/share/vdirsyncer/calendars/google/"
fileext = ".ics"

# ── Pair the two ─────────────────────────────────────────────
[pair google]
a = "google_remote"
b = "google_local"
collections = ["from a", "from b"]
conflict_resolution = "a wins"     # remote wins on conflict
metadata = ["displayname", "color"]
```

`collections = ["from a", "from b"]` auto-discovers every calendar
on the remote. `conflict_resolution = "a wins"` means Google's copy
wins if a row was edited on both sides — switch to `b wins` if you
trust local edits more.

Add more `[storage …]` + `[pair …]` blocks for additional
backends (iCloud, Fastmail, Nextcloud, …); the local storage type
stays the same `filesystem`, just point each pair at its own
sub-directory under `calendars/`.

---

## 4. First-time discovery + sync

```bash
vdirsyncer discover     # opens a browser; sign in to Google
vdirsyncer sync         # pulls everything into ~/.local/share/...
```

`discover` runs the OAuth flow once and writes the refresh token to
`~/.config/vdirsyncer/google_token`. After that, all syncs are
non-interactive.

---

## 5. khal config

`~/.config/khal/config`:

```ini
[calendars]
[[google]]
path = ~/.local/share/vdirsyncer/calendars/google/*
type = discover

[locale]
local_timezone = Europe/Berlin       # set to yours
default_timezone = Europe/Berlin
timeformat = %H:%M
dateformat = %Y-%m-%d
longdateformat = %Y-%m-%d %a
datetimeformat = %Y-%m-%d %H:%M
longdatetimeformat = %Y-%m-%d %H:%M
firstweekday = 0                     # 0 = Monday

[default]
default_calendar = <name of the calendar khal lists after the next step>
timedelta = 2d
```

Then:

```bash
khal printcalendars      # confirm calendars are visible
khal list today 7d       # show next week
```

---

## 6. Automatic sync (systemd user timer)

`~/.config/systemd/user/vdirsyncer.service`:

```ini
[Unit]
Description=Sync calendars via vdirsyncer

[Service]
Type=oneshot
ExecStart=/usr/bin/vdirsyncer sync
```

`~/.config/systemd/user/vdirsyncer.timer`:

```ini
[Unit]
Description=Run vdirsyncer every 15 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Unit=vdirsyncer.service

[Install]
WantedBy=timers.target
```

Enable:

```bash
systemctl --user daemon-reload
systemctl --user enable --now vdirsyncer.timer
systemctl --user list-timers | grep vdirsyncer
```

15 min is a sensible default. Drop to 5 min if you frequently create
events from a phone and expect them to land in the launcher quickly;
push longer (30 min – 1h) on a metered connection.

---

## 7. Creating / editing events

`khal` does the work; vdirsyncer pushes on the next tick.

```bash
khal new tomorrow 10:00 11:00 Standup
khal new 2026-06-04 09:00 12:00 :: "Design review" :: "Notes here"
khal edit <pattern>            # interactive
khal delete <pattern>          # interactive
```

To push immediately instead of waiting for the timer:

```bash
vdirsyncer sync && systemctl --user start vdirsyncer.service
```

(Either one — the second form just reuses the systemd unit.)

---

## 8. What the launcher reads

The CalendarProvider consumes the local cache at
`~/.local/share/vdirsyncer/calendars/`. Each calendar is a directory
of `.ics` files; one `.ics` per event series.

The bridge is `launcher/calendar/calendar-events.py`. It's invoked
by `EventsModel.qml` with a date window:

```
calendar-events.py --start 2026-05-01 --end 2026-07-01
```

…and emits a JSON array of event records (one entry per occurrence;
recurrences are pre-expanded via `recurring-ical-events`). The
launcher buckets them by local start-date and renders up to three
chips per cell with a "+N more" indicator beyond that. Each chip's
colour comes from the calendar's `color` metadata file (vdirsyncer
populates this on `metasync`); missing → the theme accent.

Refresh fires when the displayed month changes and once at startup;
sync-driven updates rely on the systemd timer (§ 6). Nothing in QML
talks to Google.

You can run the helper directly to debug:

```bash
./launcher/calendar/calendar-events.py \
    --start 2026-05-01 --end 2026-06-01 | jq .
```

Empty output means either no events in window or the vdirsyncer dir
isn't where the script expects — pass `--path` to point elsewhere.

---

## Troubleshooting

- **"invalid_grant" on sync** — the refresh token expired (Google
  expires them after 6 months of disuse, or when the OAuth app is
  in *Testing* mode for >7 days). Delete `~/.config/vdirsyncer/
  google_token` and re-run `vdirsyncer discover`. Move the OAuth
  app to *In production* in Cloud Console to stop the 7-day clock.
- **`discover` opens a browser but nothing happens after sign-in** —
  ensure the Google Cloud OAuth client is a **Desktop app** type,
  not a Web app.
- **Events appear in `~/.local/share/vdirsyncer/…` but not in khal**
  — re-run `khal printcalendars`; if a calendar is missing, check
  that its directory contains a `displayname` file (vdirsyncer
  creates these automatically; if not, `vdirsyncer metasync`).
- **Conflicts** — vdirsyncer prints them on stderr. Resolve by
  editing the affected `.ics` in the local dir (or deleting one
  side) and re-syncing.
