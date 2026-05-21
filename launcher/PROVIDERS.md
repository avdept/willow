# Launcher providers — roadmap

Each provider is a QML file in this dir that inherits `Provider` (see
`Provider.qml`). To wire one up, drop the file in here, then:

1. add a `<Name>Provider { id: <id>; onResultsChanged: launcher._aggregate() }`
   line inside `Launcher.qml` next to the existing providers,
2. include `<id>` in the `providers = [...]` array in `Component.onCompleted`.

The provider contract (read `Provider.qml` for full details):

- `name`, `tag`, `iconText` — identity. `tag` is shown on each row.
- `prefix` — empty = always-on; otherwise the provider only runs when the
  query is exactly `<prefix>` or starts with `<prefix> ` (e.g. `pr foo` for
  GitHub PRs).
- `search(text)` — called when the (effective, prefix-stripped) query
  changes. Update `results` (a JS array of `{title, subtitle, iconName,
  iconPath, iconText, score, data}` objects).
- `activate(result)` — called when the user picks this row.

Higher `score` ranks higher in the merged list. Use ~1000 for "perfect
match", ~500 for prefix, ~100 for substring, ~20 for fuzzy.

---

## v1 (shipped)

- **AppsProvider** — `.desktop` apps via `Quickshell.DesktopEntries`.
  Always-on. Fuzzy scoring: exact > prefix > word-initials > substring >
  subsequence. Activation calls `entry.execute()`.
- **FilesProvider** — `fd`-backed file search. Prefix `f `. Debounced
  180ms. Activation opens via `xdg-open`.

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
- **Open question**: do we want unit conversion / variable assignment
  shown inline?

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

### GithubProvider — pull requests via `gh` CLI

- **Trigger**: prefix `pr ` (or `gh `).
- **Backend**: spawn `gh pr list --json number,title,url,author,state,repository --limit 30`
  on first activation; cache for 60s. On `pr foo`, fuzzy-match locally
  against the cached list. Also expose:
  - `pr review` — `gh pr list --search "review-requested:@me" --json ...`
  - `pr mine`   — `gh pr list --author @me ...`
- **Activate**: `xdg-open <url>`.
- **Open question**: scope to current repo when invoked inside one, or
  always cross-repo? Show drafts?

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
