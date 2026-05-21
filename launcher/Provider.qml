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

    // If non-empty, the provider only runs when the query is exactly `prefix`
    // or starts with `prefix + " "` (e.g. "f foo"). Empty = always active.
    property string prefix: ""

    // ── Wiring ───────────────────────────────────────────────────────────
    property string query: ""       // set by Launcher
    property var results: []        // populated by subclass

    // ── Contract (override in subclass) ──────────────────────────────────
    function search(text) {}
    function activate(result) {}

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
