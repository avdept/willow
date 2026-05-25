// Base type for a launcher provider. Subclass this in its own .qml file and
// override `search()` and `activate()`. The Launcher binds `query` to the
// search input and reads `results` whenever it changes.
//
// Result schema (each entry in `results`):
//   {
//     title:    "Visible name",
//     subtitle: "Path / description",
//     iconUrl:  "file:///… or image://icon/…",  // ready-to-bind Image source
//     iconText: "",                              // optional nerd-font fallback
//     score:    0.0,                             // higher = better; sorted desc
//     data:     { ... }                          // provider-private payload
//   }

import QtQuick

QtObject {
    id: provider

    // QtObject has no default child property; declare one so subclasses can
    // include `Timer {}`, `Process {}`, `Connections {}`, etc. as children.
    default property list<QtObject> _children

    // ── Identity ─────────────────────────────────────────────────────────
    property string name: "Provider"
    property string tag: name           // short label shown on result rows
    property string iconText: ""        // nerd-font glyph for menu/fallback
    property string description: ""     // subtitle in the top-level menu

    // Optional live category icon. When set, the launcher renders this
    // Component in the icon slot of category rows (and as the per-row
    // fallback) instead of the static `iconText` glyph. The component
    // gets `theme` and `fontFamily` injected on load and is expected to
    // anchor.fill its parent (the icon box, default 48×48).
    property Component iconComponent: null

    // If non-empty, the provider only runs when the query is exactly `prefix`
    // or starts with `prefix + " "` (e.g. "f foo"). Empty = always active.
    property string prefix: ""

    // Drill-in shortcuts. When the launcher is in menu mode and the
    // user types `<shortcut> <rest>` (or just `<shortcut> `), it
    // enters this provider with `<rest>` as the initial query. Useful
    // for keyboard-only navigation. Each shortcut is matched
    // case-insensitively. Empty list = no shortcuts.
    property list<string> shortcuts: []

    // Action shortcuts: typed prefix → action name. When the
    // launcher input matches one of these keys (exactly OR followed
    // by a space), it drills into this provider AND calls
    // `invokeAction(name, rest)` so the provider can do something
    // beyond just opening its view. Keys are case-insensitive and
    // share a namespace with `shortcuts` across all providers — the
    // launcher warns at startup if any key is declared twice.
    //
    // Example (subclass):
    //   actionShortcuts: ({ "+t": "new" })
    //   function invokeAction(name, rest) {
    //       if (name === "new") openForm(...);
    //   }
    property var actionShortcuts: ({})

    // Optional override of the search placeholder when in this provider.
    // Useful for providers with internal sub-views (e.g. Style → Theme).
    // When empty, the launcher falls back to `name`.
    property string currentTitle: ""

    // Optional override for the empty-state message shown in the right
    // pane when `results` is empty. Use this for loading / error states
    // (e.g. "Loading PRs…" while a `gh` call is in flight). When empty,
    // the launcher uses its default "Start typing…" / "No results".
    property string emptyStateText: ""

    // Optional: opt-in to a side-by-side details pane in the right area.
    // When true, the launcher splits the results pane: list on the left,
    // details on the right. The provider writes `detail` (see schema in
    // DetailsPane.qml) and observes `selectedRow` to know what to fetch.
    property bool detailsEnabled: false
    property int detailWidth: 380         // px reserved for the details pane
    // Provider populates this with the loaded detail (see DetailsPane.qml
    // for the expected shape). Empty / null = nothing selected.
    property var detail: null
    // Launcher writes the raw provider result (`r`, as returned by
    // search()) of the currently highlighted row whenever the selection
    // changes. Providers should override `onSelectedRowChanged` to fetch
    // details for that row.
    property var selectedRow: null

    // Optional: providers (or their sub-views) can request a different
    // popup width/height. 0 means "use the launcher default". The
    // launcher animates between values so changing these on a view
    // switch is fine.
    property int requestedWidth: 0
    property int requestedHeight: 0

    // Optional: how the launcher should render this provider's results
    // in the right pane.
    //   "list"   — vertical list of rows (default; uses ResultDelegate)
    //   "grid"   — tiled cells with preview + label (uses ResultGridCell)
    //   "custom" — provider draws the whole right pane via `customComponent`
    property string resultsLayout: "list"

    // Grid params — read only when resultsLayout === "grid".
    property int gridColumns: 4
    property int cellHeight: 160

    // When `resultsLayout === "custom"`, the launcher renders this
    // Component into the right pane and passes `theme`, `fontFamily`,
    // and `provider` (this object) through to it. The component drives
    // its own layout, keyboard handling, and activation.
    property Component customComponent: null

    // ── Wiring ───────────────────────────────────────────────────────────
    property string query: ""       // set by Launcher
    property var results: []        // populated by subclass

    // Emitted by providers that manage internal sub-views, when they push
    // or pop a view. The launcher listens and clears the search query so
    // each view starts fresh.
    signal viewChanged()

    // Emitted when the provider wants the launcher to fully close (e.g.
    // a calendar event chip's URL was just opened — keeping the launcher
    // around would steal focus from the browser). The launcher wires
    // this to `hide()` at construction time.
    signal requestClose()

    // Ask the launcher to drill into a sibling provider by `name` (the
    // value of that provider's `name` property), with an optional
    // initial query. The launcher wires this generically — useful for
    // dashboard tiles (NowProvider → Todos) or search activations that
    // should hand off to another provider's view.
    signal requestEnter(string providerName, string initialQuery)

    // ── Contract (override in subclass) ──────────────────────────────────
    function search(text) {}
    // Return a truthy value to keep the launcher open after activation
    // (e.g. theme picks where you want to see the new colors live).
    // Return falsy / nothing for the default behaviour: launcher hides.
    function activate(result) {}

    // Override to handle an action shortcut. `name` is the value of
    // the matched key in `actionShortcuts`; `rest` is whatever the
    // user typed after the shortcut (useful as a draft name, etc.).
    function invokeAction(name, rest) {}

    // Optional: providers with internal sub-views override this. Return
    // true when the back was handled internally (the launcher then just
    // refreshes results); return false to let the launcher exit the
    // provider and return to the category menu.
    function goBack() { return false }

    // Optional: clear any internal sub-view state. Called by the launcher
    // when it returns to the category menu or closes, so the next
    // drill-in starts at the provider's root view.
    function reset() {}

    // Optional: intercept keyboard input before the launcher's default
    // arrow/enter/escape handling. Only called when this provider is
    // active and uses a custom layout. Return true if the event was
    // handled (the launcher will mark it accepted).
    function handleKey(event) { return false }

    // ── Helpers (do not override) ────────────────────────────────────────

    // Returns the query stripped of this provider's prefix, or null when the
    // current query doesn't match the prefix gate.
    function effectiveQuery() {
        const q = (query || "").trim();
        if (prefix.length === 0) return q;
        if (q === prefix) return "";
        const p = prefix + " ";
        return q.indexOf(p) === 0 ? q.slice(p.length) : null;
    }

    // Force a search with the current query, even if the value hasn't
    // changed. Used by Launcher when entering a provider, to guarantee a
    // populated result set.
    function refresh() {
        const eq = effectiveQuery();
        if (eq === null) { results = []; return; }
        search(eq);
    }

    onQueryChanged: refresh()
}
