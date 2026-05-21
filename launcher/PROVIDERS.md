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
- `activate(result)` — called when the user picks this row.

Opt-in extensions:

- **Internal sub-views** — set `view`/`currentTitle` from `_setView()`,
  emit `viewChanged()`, override `goBack()` and `reset()`.
- **Custom layout** — set `resultsLayout: "grid"` plus `gridColumns` /
  `cellHeight` to render a tiled grid (e.g. theme picker).
- **Wider/taller popup** — set `requestedWidth` / `requestedHeight`.
  Clamped to `maxWidthRatio`/`maxHeightRatio` of the screen.
- **Side-by-side details pane** — set `detailsEnabled: true` and
  `detailWidth`, observe `selectedRow`, push a `detail` blob shaped per
  `DetailsPane.qml`.

Higher `score` ranks higher in the merged list. Use ~1000 for "perfect
match", ~500 for prefix, ~100 for substring, ~20 for fuzzy.

---

## Shipped

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

---

## TODO — providers to add next

Filling in the specs as you decide on the behavior you want; the
skeleton/contract is the same for each.

### CalcProvider — inline calculator

- **Trigger**: detect when the query parses as math (regex on digits +
  operators, or just try-parse). Probably always-on with a high score so
  results jump to the top.
- **Backend**: `qalc -t` if installed (preferred — handles units), else
  `python3 -c "print(<expr>)"` with a strict allowlist of characters
  (`0-9 + - * / . ( ) ^ %`).
- **Activate**: copy the result to the clipboard via `wl-copy`.
- **Score**: ~10000 (always tops the list when active).

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
