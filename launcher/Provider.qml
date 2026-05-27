// Base type for a launcher provider. Subclass, override `search()` and
// `activate()`. See PROVIDERS.md for the result schema and contract.

import QtQuick
import Quickshell.Io

QtObject {
    id: provider

    // Default children list lets subclasses add Timer / Process / Connections
    // — QtObject has no default property otherwise.
    default property list<QtObject> _children

    property Process _extProc: Process { running: false }

    property string name: "Provider"
    property string tag: name
    property string iconText: ""
    property string description: ""

    property Component iconComponent: null

    // Empty = always active. Otherwise the provider only runs when the
    // query is exactly `prefix` or starts with `prefix + " "`.
    property string prefix: ""

    // Typed shortcuts that drill into this provider from menu mode.
    // `shortcuts` triggers on `<sc> <rest>`; `actionShortcuts` also
    // invokes `invokeAction(name, rest)` (matches exactly OR with a
    // trailing space — "+t" alone fires "new"). Case-insensitive.
    // Both keys share a namespace; launcher warns on collision.
    property list<string> shortcuts: []
    property var actionShortcuts: ({})

    property string currentTitle: ""
    property string emptyStateText: ""

    // Opt-in side-by-side details pane. Provider writes `detail` (shape
    // in DetailsPane.qml) on `selectedRow` change.
    property bool detailsEnabled: false
    property int detailWidth: 380
    property var detail: null
    property var selectedRow: null

    // 0 = launcher default. Animated by the launcher on change.
    property int requestedWidth: 0
    property int requestedHeight: 0

    //   "list"   — ResultDelegate rows (default)
    //   "grid"   — ResultGridCell tiles
    //   "custom" — provider draws the whole right pane via customComponent
    property string resultsLayout: "list"
    property int gridColumns: 4
    property int cellHeight: 160
    property Component customComponent: null

    property string query: ""
    property var results: []

    // Cross-provider ranking weight. Only applied in menu-mode aggregated
    // search; within-provider ordering is decided by `score` before this
    // multiplier ever touches the row. Bump for providers the user
    // expects to dominate (apps), drop for rarely-targeted ones (setup).
    property real scoreMultiplier: 1.0

    // Whether this provider contributes rows to menu-mode aggregated
    // search. Dashboard providers (NowProvider) emit results on a timer
    // even when their content doesn't reflect the query — re-aggregating
    // on each tick churns the merged list and resets the user's scroll.
    // Set false to exclude entirely from the aggregated view.
    property bool aggregateInSearch: true

    // Whether this provider appears as a browseable category in the
    // root menu (empty query). Query-driven providers like Calc
    // (`=5+5`) have nothing to show when entered without input.
    property bool showAsCategory: true

    // Bound by Launcher.qml. Providers should gate background
    // timers/process spawns on this for laptop power.
    property bool launcherOpen: false

    signal viewChanged()
    signal requestClose()
    signal requestEnter(string providerName, string initialQuery)

    function search(text) {}
    // Return truthy to keep the launcher open after activation.
    function activate(result) {}
    function invokeAction(name, rest) {}
    // Return true if the back was handled internally (launcher just
    // refreshes); false to exit the provider.
    function goBack() { return false }
    function reset() {}
    // Return true to consume the key before the launcher's defaults.
    // Only called for `resultsLayout: "custom"` providers.
    function handleKey(event) { return false }

    // Launch an external command that survives `killall qs`. Default
    // routes through `hyprctl dispatch exec` so the spawn is reparented
    // to Hyprland. `opts.detach: "none"` skips that wrap; `opts.cwd`
    // sets a working directory.
    function openExternal(argv, opts) {
        const o = opts || {};
        const detach = o.detach || "hypr";
        const cwd = o.cwd || "";
        const arr = Array.isArray(argv) ? argv : [argv];
        const q = s => "'" + String(s).replace(/'/g, "'\\''") + "'";

        if (_extProc.running) _extProc.running = false;

        if (detach === "hypr") {
            const inner = arr.map(q).join(" ");
            const line = cwd ? ("cd " + q(cwd) + " && exec " + inner) : inner;
            _extProc.workingDirectory = "";
            _extProc.command = ["hyprctl", "dispatch", "exec", line];
        } else {
            _extProc.workingDirectory = cwd;
            _extProc.command = arr;
        }
        _extProc.running = true;
    }

    // ── Scoring helpers (shared ladder for cross-provider ranking) ──────
    //
    // CONTRACT: callers MUST pre-norm inputs (toLowerCase().trim()).
    // BANDS: 1000 exact, 500-549 prefix, 200-280 word-initials,
    //        100 substring, 20 subsequence, 0 no-match.
    // Multiply (×0.4 for secondary fields, ×1.5 for "current") but
    // never invent new band magnitudes.

    function norm(s) { return (s || "").toString().toLowerCase().trim(); }

    function scoreText(q, primary) {
        if (!q) return 0;
        let best = _scoreOne(primary || "", q);
        for (let i = 2; i < arguments.length; i++) {
            const s = _scoreOne(arguments[i] || "", q) * 0.4;
            if (s > best) best = s;
        }
        return best;
    }

    function scorePath(q, path) {
        if (!q || !path) return 0;
        const slash = path.lastIndexOf("/");
        const base = slash >= 0 ? path.slice(slash + 1) : path;
        const primary = _scoreOne(base, q);
        const fallback = _scoreOne(path, q) * 0.3;
        return primary > fallback ? primary : fallback;
    }

    function _scoreOne(h, q) {
        if (h.length === 0) return 0;
        if (h === q) return 1000;
        if (h.startsWith(q)) {
            const len = h.length < 50 ? h.length : 50;
            return 500 + (50 - len);
        }
        const wb = _wordInitials(h, q);
        if (wb > 0) return 200 + wb;
        if (h.indexOf(q) !== -1) return 100;
        if (_isSubsequence(h, q)) return 20;
        return 0;
    }

    function _wordInitials(name, q) {
        const parts = name.split(/[\s\-_./]+/);
        let qi = 0, hit = 0;
        for (let i = 0; i < parts.length && qi < q.length; i++) {
            if (parts[i].length === 0) continue;
            if (parts[i][0] === q[qi]) { qi++; hit++; }
        }
        return qi === q.length ? hit * 10 : 0;
    }

    function _isSubsequence(haystack, needle) {
        let i = 0;
        for (let j = 0; j < haystack.length && i < needle.length; j++)
            if (haystack[j] === needle[i]) i++;
        return i === needle.length;
    }

    // HTML-escape `text` and wrap http(s) URLs in <a> tags so a Text
    // with `textFormat: RichText` renders them as clickable links.
    function linkify(text) {
        if (!text) return "";
        const esc = text.toString()
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
        return esc.replace(/(https?:\/\/[^\s<>"']+)/g, '<a href="$1">$1</a>');
    }

    // Strips this provider's prefix from `query`. Returns null when the
    // current query doesn't match the prefix gate.
    function effectiveQuery() {
        const q = (query || "").trim();
        if (prefix.length === 0) return q;
        if (q === prefix) return "";
        const p = prefix + " ";
        return q.indexOf(p) === 0 ? q.slice(p.length) : null;
    }

    function refresh() {
        const eq = effectiveQuery();
        if (eq === null) { results = []; return; }
        search(eq);
    }

    onQueryChanged: refresh()
}
