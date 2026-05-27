# Launcher providers — roadmap

Each provider is a QML file in this dir that inherits `Provider` (see
`Provider.qml`). To wire one up, drop the file in here, then:

1. add an instance to `Launcher.qml` next to the existing providers,
   forwarding `onResultsChanged` (and any other signals the provider
   raises — e.g. `onViewChanged`, `onDetailChanged`) to the launcher,
2. include its id in the `providers = [...]` array in
   `Component.onCompleted`.

Core provider contract (read `Provider.qml` for full details):

- `name`, `tag`, `iconText`, `description` — identity. `tag` is shown
  on each row's pill; `description` is the subtitle in the top menu.
- `prefix` — empty = always-on; otherwise the provider only runs when
  the query is exactly `<prefix>` or starts with `<prefix> ` (e.g.
  `f foo` for files).
- `search(text)` — called when the (effective, prefix-stripped) query
  changes. Update `results` with objects shaped like:
  `{ title, subtitle, iconUrl, iconText, providerTag, tagColor,
  titleFont, score, data }`. Everything except `title` and `score` is
  optional. `tagColor` is one of `"success" | "info" | "purple" |
  "warn" | "danger" | "cyan" | "accent"`; missing = muted default.
- `activate(result)` — called when the user picks this row. Use
  `openExternal(argv, opts?)` to launch external commands: by default
  the call is routed through `hyprctl dispatch exec` so the spawned
  process is reparented to Hyprland and survives `killall qs`. Pass
  `{ detach: "none" }` only when the command already handles its own
  detach (rare), and `{ cwd }` for a working directory.

Opt-in extensions:

- **Internal sub-views** — set `view`/`currentTitle` from `_setView()`,
  emit `viewChanged()`, override `goBack()` and `reset()`.
- **Custom layout** — set `resultsLayout: "grid"` plus `gridColumns` /
  `cellHeight` to render a tiled grid (e.g. theme picker).
- **Fully custom pane** — set `resultsLayout: "custom"` and provide a
  `customComponent: Component { … }`. The launcher renders it into the
  right pane and injects `theme`, `fontFamily`, and `provider` (this
  object) as properties on the root item. Override `handleKey(event)`
  to intercept arrow/page keys before the launcher's defaults — return
  `true` when consumed. Escape always falls through to the launcher.
- **Live category icon** — set `iconComponent: Component { … }`. The
  launcher renders it in place of `iconText` in the icon slot of the
  provider's category row (and as the per-row fallback). `theme` and
  `fontFamily` are injected; the component should anchor.fill its
  parent (the icon box, 48×48 by default).
- **Wider/taller popup** — set `requestedWidth` / `requestedHeight`.
  Clamped to `maxWidthRatio`/`maxHeightRatio` of the screen.
- **Side-by-side details pane** — set `detailsEnabled: true` and
  `detailWidth`, observe `selectedRow`, push a `detail` blob shaped per
  `DetailsPane.qml`.

Higher `score` ranks higher in the merged list. Provider exposes a
shared scorer — use it instead of rolling your own ladder:

```js
const q = norm(text);
const s = scoreText(q, primaryLower, secondaryLower, ...);   // 1+ fields
const s = scorePath(q, pathLower);                            // filesystem-shaped
```

Bands returned by `scoreText()`: 1000 exact, 500+ prefix, 200+ word-
initials, 100 substring, 20 subsequence, 0 no-match. Multiply to bias
(`× 0.3` for completed/secondary, `× 1.5` for "current") but never
invent new band magnitudes — cross-provider menu aggregation depends
on the ladder staying stable.

All inputs MUST be pre-lowercased+trimmed via `norm()`; the scorer
skips that work for hot loops.

Per-provider weight for the merged list comes from `scoreMultiplier`
(default `1.0`). Bump on providers the user expects to dominate
(`AppsProvider` ships at `1.5`); drop on rarely-targeted ones. Only
applied during menu-mode aggregation — within-provider ordering is
decided before the multiplier touches the row. Multipliers preserve
band shape: same-band ties go to the higher-weight provider, but a
lower-band match in a heavily-weighted provider still loses to a
higher-band match elsewhere unless you crank the weight well past 2×.

---

## Shipped

- **NowProvider** — at-a-glance dashboard. Grid of tiles for weather,
  CPU%, memory used/total, volume, battery (when present) and quick
  links (Lock / Power / Bluetooth / Wi-Fi). Each tile renders a
  nerd-font glyph + a live value via `ResultGridCell`'s `iconText`
  fallback (no preview image). Sources: a single `/proc/stat` +
  `/proc/meminfo` sampler shell every 3s, `omarchy-weather-icon` and
  `omarchy-weather-status` every 5 min, Pipewire / UPower services
  (reactive). Activations are routed through `hyprctl dispatch exec` so
  detach-sensitive scripts (e.g. `omarchy-system-lock`, which forks a
  backgrounded subshell holding hyprlock) survive the Process teardown.
  Targets match the top bar: btop, `omarchy-launch-audio`,
  `omarchy-menu power`, `omarchy-system-lock`, …
- **AppsProvider** — `.desktop` apps via `Quickshell.DesktopEntries`.
  Always-on. Fuzzy scoring: exact > prefix > word-initials > substring >
  subsequence. Activation runs the entry via `uwsm-app`.
- **FilesProvider** — `fd`-backed file search. Prefix `f `. Debounced
  180ms. Activation opens via `xdg-open`.
- **StyleProvider** — wraps the omarchy "Style" menu. Drills into
  internal sub-views (Theme grid with preview images, Font list rendered
  in each font's own family, Unlock plymouth picker). Uses the launcher's
  internal sub-view machinery (`goBack()` / `reset()`).
- **GithubProvider** — flat search of your PRs, issues, projects, and
  repos via `gh`. Tag pills color-code each kind (green/yellow/purple/
  blue). Owner avatars via `https://github.com/<login>.png`. Opts into
  the side-by-side details pane (PR/issue body, repo stats, …) with a
  per-URL detail cache. Activation opens the item URL via `xdg-open`.
- **CalcProvider** — inline math evaluator. Triggers on a leading `=`
  in the query (`=5+5` → `10`); rejects anything outside a strict
  allowlist of digits + math operators so eval is fast enough to run
  on every keystroke without spawning a subprocess. Score `10000`
  pins the result to the top of the aggregated list. Activation
  copies the result via `wl-copy`. Hidden from the sidebar category
  list (`showAsCategory: false`) since it's query-driven.
- **SystemProvider** — mirrors `show_system_menu` from `omarchy-menu`.
  Flat list of seven session actions (Screensaver, Lock, Suspend,
  Hibernate, Logout, Restart, Shutdown). Suspend hidden when
  `omarchy-toggle-enabled suspend-off` is set; Hibernate hidden when
  `omarchy-hibernation-available` exits non-zero. Both states are
  re-probed each time the launcher opens.
- **SetupProvider** — mirrors the "Setup" section of `omarchy-menu`.
  Static leaves (Audio/Wifi/Bluetooth, Monitors, Keybindings, Input, DNS,
  individual config files) drill or spawn directly; dynamic sub-views
  (Power Profile, System Sleep, Defaults) re-probe state on entry so the
  "current" indicator stays honest after toggling. Power profile + default
  browser/terminal/editor return `true` from `activate()` to keep the
  launcher open for A/B selection. Edit-then-restart configs are wrapped
  in a single `sh -c "omarchy-launch-editor X && omarchy-restart-Y"`.
- **CalendarProvider** — owns calendar state (current month/year,
  focused day) and delegates rendering to per-view components under
  `launcher/calendar/`. Today: `MonthComponent` (Apple-style 6×7 grid
  backed by `QtQuick.Controls`'s `MonthGrid` + `DayOfWeekRow`,
  locale-aware). Uses the `resultsLayout: "custom"` hook to draw the
  whole right pane; the category icon is a live `CalendarIcon`
  (tear-off page showing today's weekday + date). Cells render up to
  3 event chips from `EventsModel`, which shells out to
  `calendar-events.py` against vdirsyncer's local cache
  (`~/.local/share/vdirsyncer/calendars/`). Today is a filled circle
  in `theme.danger`; the focused day gets a tinted background.
  Arrow keys move the focused day; PgUp/PgDn flip month; Home jumps
  to today. Setup (Google OAuth → vdirsyncer → khal → systemd timer):
  see [`calendar/SETUP.md`](calendar/SETUP.md).

---

## TODO — providers to add next

Filling in the specs as you decide on the behavior you want; the
skeleton/contract is the same for each.

### SystemProvider — power / session actions

- **Trigger**: always-on; filters its static list (lock, suspend,
  reboot, shutdown, logout) by fuzzy match.
- **Backend**: hard-coded list. Activations:
  - lock → `omarchy-lock` (or `loginctl lock-session`)
  - suspend → `systemctl suspend`
  - reboot → `systemctl reboot`
  - shutdown → `systemctl poweroff`
  - logout → `uwsm stop` (or `hyprctl dispatch exit`)
- **Open question**: confirmation dialog for shutdown/reboot? Or trust
  the user (it's a launcher)?

### CalendarProvider — next steps

- Week + day modes (toggle in the header). Reuse `MonthGrid`'s data for
  the week strip; render the day view as a vertical timeline.
- New-event UI — small inline form on the focused day that runs
  `khal new …`; vdirsyncer pushes on the next sync.
- Date jump from the search input — typing "may 25" or "next thu"
  moves `focusedDate`. Until then, the search field is inert in this
  provider.
- "Stale cache" indicator in the header when the newest mtime under
  `~/.local/share/vdirsyncer/calendars/` is older than ~2× the
  configured sync interval (see [`calendar/SETUP.md`](calendar/SETUP.md) § 6).
- Multi-day events as horizontal bars spanning cells (currently they
  show as a chip on the start day only).

### ClipboardProvider — cliphist history

- **Trigger**: prefix `c `.
- **Backend**: `cliphist list` → each line is `<id>\t<preview>`; parse
  to results. Activation: `cliphist decode <id> | wl-copy` and then
  optionally re-type / paste via wtype or hyprctl.
- **Open question**: also show images (cliphist stores them)? Need to
  decide on a preview format.

---

## Cross-cutting things still TODO

- **Recency / frecency** — boost recently-activated items. Store a small
  JSON in `~/.cache/quickshell-launcher/history.json`.
- **Per-provider hotkey** — `Tab` could cycle the prefix-active provider
  (e.g. empty query + Tab → cycle through `f `, `pr `, `c `).
- **Result icons** — `IconImage` uses XDG icon names; falls back to
  `iconText` (nerd-font glyph). For Files we default to
  `text-x-generic`; could mime-sniff and pick better icons.
- **Theme polish** — animations are minimal; consider input-focused
  border glow, smoother list transitions, blur backdrop (MultiEffect).
