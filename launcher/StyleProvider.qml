// Style provider — mirrors the "Style" section of `omarchy-menu`.
//
// Top-level view shows one row per style section (Theme, Font, Unlock).
// Each section drills into a sub-view:
//   "themes"  — grid of preview thumbnails (omarchy-theme-{list,current,set})
//   "fonts"   — list of monospace fonts, each rendered in its own family
//               (omarchy-font-{list,current,set})
//   "unlocks" — grid of themes that ship a preview-unlock.png; activation
//               opens a floating terminal and runs the plymouth set
//               (needs sudo). Plus a "Default" entry that resets to the
//               omarchy-shipped Plymouth.
//
// Backspace from an empty query in a sub-view returns to the Style
// root (handled by `goBack()` and the launcher's backspace handler).

import QtQuick
import Quickshell
import Quickshell.Io

Provider {
    id: prov

    name: "Style"
    tag: "style"
    iconText: "󰴒"
    description: "Themes, fonts, and visuals"
    shortcuts: ["style", "theme"]

    // ── Sub-view state ───────────────────────────────────────────────────
    // "" = root menu. Other values: "themes", "fonts", "unlocks".
    property string view: ""

    // Cached data for sub-views.
    property var _themes: []
    property string _currentTheme: ""
    property var _fonts: []
    property string _currentFont: ""
    // Unlock styling: list of {dir, display, previewUrl} for every theme
    // that ships a preview-unlock.png. Populated by unlockPreviewProc.
    property var _unlocks: []
    // Map: display-name → file:// URL of preview image. Populated by
    // themePreviewProc on startup; mirrors the path-resolution logic from
    // omarchy's `omarchy_themes.lua` (preview.png > preview.jpg > first
    // file in backgrounds/), with user-dir overrides winning.
    property var _themePreviews: ({})

    // Directories that may hold a `<theme>/preview.png`. User overrides
    // win — same precedence as `omarchy-theme-list`.
    readonly property string _userThemesDir: (Quickshell.env("HOME") || "") + "/.config/omarchy/themes"
    readonly property string _sysThemesDir: Quickshell.env("OMARCHY_PATH") || ""

    Component.onCompleted: {
        themeListProc.running = true;
        themeCurrentProc.running = true;
        themePreviewProc.running = true;
        fontListProc.running = true;
        fontCurrentProc.running = true;
        unlockPreviewProc.running = true;
    }

    // ── Data fetches (run once at startup) ───────────────────────────────

    property var _themeBuf: []
    Process {
        id: themeListProc
        running: false
        command: ["omarchy-theme-list"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s)
                    prov._themeBuf.push(s);
            }
        }
        onRunningChanged: if (!running) {
            prov._themes = prov._themeBuf;
            prov._themeBuf = [];
            prov.refresh();
        }
    }

    Process {
        id: themeCurrentProc
        running: false
        command: ["omarchy-theme-current"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s)
                    prov._currentTheme = s;
            }
        }
        onRunningChanged: if (!running)
            prov.refresh()
    }

    // Watch omarchy's theme marker so the "current theme" indicator in
    // the picker refreshes when the theme is changed from elsewhere
    // (e.g. another hotkey, or the launcher itself when we don't reset
    // state on close). Mirrors the watcher in Theme.qml — `reload()`
    // re-establishes the watch after omarchy's atomic dir-swap.
    readonly property string _themeMarkerPath: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const home = Quickshell.env("HOME");
        const base = xdg && xdg.length > 0 ? xdg : (home + "/.config");
        return base + "/omarchy/current/theme.name";
    }

    FileView {
        path: prov._themeMarkerPath
        watchChanges: true
        onFileChanged: {
            reload();
            if (themeCurrentProc.running) themeCurrentProc.running = false;
            themeCurrentProc.running = true;
        }
    }

    // Emits `<display-name>\t<preview-path>` for every theme. Mirrors
    // omarchy_themes.lua: preview.png > preview.jpg > first file in
    // backgrounds/. User-dir entries win over $OMARCHY_PATH defaults.
    property var _previewBuf: ({})
    Process {
        id: themePreviewProc
        running: false
        command: ["sh", "-c", `
            cap() {
                printf '%s' "$1" | sed -E 's/(^|-)([a-z])/\\1\\u\\2/g; s/-/ /g'
            }
            emit() {
                d="$1"; n="\${d##*/}"
                disp=$(cap "$n")
                if   [ -f "$d/preview.png" ]; then p="$d/preview.png"
                elif [ -f "$d/preview.jpg" ]; then p="$d/preview.jpg"
                else
                    bg=$(ls -1 "$d/backgrounds" 2>/dev/null | head -n 1)
                    [ -n "$bg" ] && p="$d/backgrounds/$bg" || p=""
                fi
                [ -n "$p" ] && printf '%s\\t%s\\n' "$disp" "$p"
            }
            seen=":"
            scan() {
                [ -d "$1" ] || return
                for d in "$1"/*; do
                    [ -d "$d" ] || continue
                    n="\${d##*/}"
                    case "$seen" in *":$n:"*) continue ;; esac
                    seen="\${seen}$n:"
                    emit "$d"
                done
            }
            scan "$HOME/.config/omarchy/themes"
            scan "$OMARCHY_PATH/themes"
        `]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                if (!line)
                    return;
                const tab = line.indexOf("\t");
                if (tab <= 0)
                    return;
                const disp = line.slice(0, tab);
                const path = line.slice(tab + 1);
                prov._previewBuf[disp] = "file://" + path;
            }
        }
        onRunningChanged: if (!running) {
            prov._themePreviews = prov._previewBuf;
            prov._previewBuf = ({});
            prov.refresh();
        }
    }

    // ── Font list / current-font processes ───────────────────────────────

    property var _fontBuf: []
    Process {
        id: fontListProc
        running: false
        command: ["omarchy-font-list"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s)
                    prov._fontBuf.push(s);
            }
        }
        onRunningChanged: if (!running) {
            prov._fonts = prov._fontBuf;
            prov._fontBuf = [];
            prov.refresh();
        }
    }

    Process {
        id: fontCurrentProc
        running: false
        command: ["omarchy-font-current"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s)
                    prov._currentFont = s;
            }
        }
        onRunningChanged: if (!running)
            prov.refresh()
    }

    // ── Unlock styles (themes that ship preview-unlock.png) ──────────────

    // Emits `<dir-name>\t<preview-unlock-path>` for every theme that has
    // one. User overrides win, same precedence as the theme picker.
    property var _unlockBuf: []
    Process {
        id: unlockPreviewProc
        running: false
        command: ["sh", "-c", `
            emit() {
                d="$1"; n="\${d##*/}"
                p="$d/preview-unlock.png"
                [ -f "$p" ] && printf '%s\\t%s\\n' "$n" "$p"
            }
            seen=":"
            scan() {
                [ -d "$1" ] || return
                for d in "$1"/*; do
                    [ -d "$d" ] || continue
                    n="\${d##*/}"
                    case "$seen" in *":$n:"*) continue ;; esac
                    seen="\${seen}$n:"
                    emit "$d"
                done
            }
            scan "$HOME/.config/omarchy/themes"
            scan "$OMARCHY_PATH/themes"
        `]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                if (!line) return;
                const tab = line.indexOf("\t");
                if (tab <= 0) return;
                const dir  = line.slice(0, tab);
                const path = line.slice(tab + 1);
                prov._unlockBuf.push({
                    dir:        dir,
                    display:    prov._displayFromDir(dir),
                    previewUrl: "file://" + path
                });
            }
        }
        onRunningChanged: if (!running) {
            prov._unlocks = prov._unlockBuf;
            prov._unlockBuf = [];
            prov.refresh();
        }
    }

    // "tokyo-night" → "Tokyo Night" — matches omarchy's capitalize logic.
    function _displayFromDir(dir) {
        return (dir || "").split("-").map(w =>
            w.length === 0 ? "" : (w[0].toUpperCase() + w.slice(1).toLowerCase())
        ).join(" ");
    }

    // ── Search dispatch ──────────────────────────────────────────────────

    function search(text) {
        const q = (text || "").toLowerCase().trim();
        if (view === "themes")
            results = _themeResults(q);
        else if (view === "fonts")
            results = _fontResults(q);
        else if (view === "unlocks")
            results = _unlockResults(q);
        else
            results = _rootResults(q);
    }

    function _rootResults(q) {
        const rows = [
            {
                title: "Theme",
                subtitle: _currentTheme ? ("Current: " + _currentTheme) : "Choose a system theme",
                iconText: "󰸌",
                providerTag: "",
                chevron: true,
                score: 1000,
                data: {
                    kind: "section",
                    section: "themes"
                }
            },
            {
                title: "Font",
                subtitle: _currentFont ? ("Current: " + _currentFont) : "Pick a monospace font",
                iconText: "󰊄",
                providerTag: "",
                chevron: true,
                score: 900,
                data: {
                    kind: "section",
                    section: "fonts"
                }
            },
            {
                title: "Unlock",
                subtitle: "Plymouth boot/unlock style",
                iconText: "󰟵",
                providerTag: "",
                chevron: true,
                score: 800,
                data: {
                    kind: "section",
                    section: "unlocks"
                }
            }
        ];
        if (q.length === 0)
            return rows;
        return rows.filter(r => r.title.toLowerCase().indexOf(q) !== -1);
    }

    function _themeResults(q) {
        const out = [];
        for (let i = 0; i < _themes.length; i++) {
            const name = _themes[i];
            const lc = name.toLowerCase();
            const isCurrent = name === _currentTheme;
            let score;
            if (q.length === 0) {
                score = isCurrent ? 1000 : (500 - i);
            } else {
                if (lc === q)
                    score = 1000;
                else if (lc.startsWith(q))
                    score = 500;
                else if (lc.indexOf(q) !== -1)
                    score = 100;
                else
                    continue;
                if (isCurrent)
                    score += 1;
            }
            out.push({
                title: name,
                iconUrl: _previewUrlFor(name),
                iconText: "󰸌",
                score: score,
                data: {
                    kind: "theme",
                    name: name,
                    isCurrent: isCurrent
                }
            });
        }
        out.sort((a, b) => b.score - a.score);
        return out;
    }

    // Preview URL resolved by `themePreviewProc` at startup, or "" when
    // the theme has no preview file at all (the grid cell falls back to
    // a glyph placeholder in that case).
    function _previewUrlFor(displayName) {
        return _themePreviews[displayName] || "";
    }

    function _fontResults(q) {
        const out = [];
        for (let i = 0; i < _fonts.length; i++) {
            const name = _fonts[i];
            const lc = name.toLowerCase();
            const isCurrent = name === _currentFont;
            let score;
            if (q.length === 0) {
                score = isCurrent ? 1000 : (500 - i);
            } else {
                if (lc === q)
                    score = 1000;
                else if (lc.startsWith(q))
                    score = 500;
                else if (lc.indexOf(q) !== -1)
                    score = 100;
                else
                    continue;
                if (isCurrent)
                    score += 1;
            }
            out.push({
                title: name,
                subtitle: isCurrent ? "current" : "",
                iconText: "",
                // Render the name in its own face for a built-in preview.
                titleFont: name,
                score: score,
                data: {
                    kind: "font",
                    name: name,
                    isCurrent: isCurrent
                }
            });
        }
        out.sort((a, b) => b.score - a.score);
        return out;
    }

    function _unlockResults(q) {
        // "Default" pseudo-entry — restores omarchy-shipped Plymouth.
        const defaultPreview = _sysThemesDir.length > 0
            ? "file://" + _sysThemesDir + "/default/plymouth/preview-unlock.png"
            : "";
        const rows = [{
            title:    "Default",
            iconUrl:  defaultPreview,
            iconText: "󰟵",
            score:    10000,                       // always last in display
            data:     { kind: "unlock-default", isCurrent: false }
        }];
        for (let i = 0; i < _unlocks.length; i++) {
            const u = _unlocks[i];
            const lc = u.display.toLowerCase();
            let score;
            if (q.length === 0) {
                score = 500 - i;
            } else {
                if (lc === q)                  score = 1000;
                else if (lc.startsWith(q))     score = 500;
                else if (lc.indexOf(q) !== -1) score = 100;
                else continue;
            }
            rows.push({
                title:    u.display,
                iconUrl:  u.previewUrl,
                iconText: "󰟵",
                score:    score,
                data: {
                    kind: "unlock",
                    dir:  u.dir,
                    name: u.display,
                    isCurrent: false
                }
            });
        }
        // Filter the default entry by query like everything else.
        const filtered = q.length === 0
            ? rows
            : rows.filter(r => r.title.toLowerCase().indexOf(q) !== -1);
        // Put Default last regardless of score.
        filtered.sort((a, b) => {
            if (a.data.kind === "unlock-default") return 1;
            if (b.data.kind === "unlock-default") return -1;
            return b.score - a.score;
        });
        return filtered;
    }

    // ── Activation ───────────────────────────────────────────────────────

    function activate(result) {
        const d = result?.data;
        if (!d)
            return;
        if (d.kind === "section") {
            _setView(d.section);
            return;
        }
        // Theme + font activations keep the launcher open (return true)
        // so the user can preview the change live and pick another one
        // without having to reopen.
        if (d.kind === "theme" && d.name) {
            themeSetProc.command = ["omarchy-theme-set", d.name];
            if (themeSetProc.running)
                themeSetProc.running = false;
            themeSetProc.running = true;
            _currentTheme = d.name;
            return true;
        }
        if (d.kind === "font" && d.name) {
            fontSetProc.command = ["omarchy-font-set", d.name];
            if (fontSetProc.running)
                fontSetProc.running = false;
            fontSetProc.running = true;
            _currentFont = d.name;
            return true;
        }
        if (d.kind === "unlock" && d.dir) {
            // sudo prompt — must run in a floating terminal so the user
            // can type the password. Mirrors omarchy_unlocks.lua.
            unlockSetProc.command = [
                "omarchy-launch-floating-terminal-with-presentation",
                "omarchy-plymouth-set-by-theme " + d.dir
            ];
            if (unlockSetProc.running)
                unlockSetProc.running = false;
            unlockSetProc.running = true;
            return;
        }
        if (d.kind === "unlock-default") {
            unlockSetProc.command = [
                "omarchy-launch-floating-terminal-with-presentation",
                "omarchy-plymouth-reset"
            ];
            if (unlockSetProc.running)
                unlockSetProc.running = false;
            unlockSetProc.running = true;
            return;
        }
    }

    Process {
        id: themeSetProc
        running: false
    }

    Process {
        id: fontSetProc
        running: false
    }

    Process {
        id: unlockSetProc
        running: false
    }

    // ── View navigation ──────────────────────────────────────────────────

    // Card dimensions the themes sub-view wants. 0 = launcher default.
    // Height is left at default; 3×2 cells fit without scrolling.
    readonly property int _themesViewWidth: 1080
    readonly property int _themesViewHeight: 0

    // Grid params for the themes view. 3 columns × 2 visible rows.
    readonly property int _themesGridColumns: 3
    readonly property int _themesCellHeight: 230

    function _setView(v) {
        if (view === v)
            return;
        view = v;
        if (v === "themes" || v === "unlocks") {
            currentTitle = v;
            requestedWidth = _themesViewWidth;
            requestedHeight = _themesViewHeight;
            resultsLayout = "grid";
            gridColumns = _themesGridColumns;
            cellHeight = _themesCellHeight;
        } else if (v === "fonts") {
            currentTitle = "fonts";
            requestedWidth = 0;
            requestedHeight = 0;
            resultsLayout = "list";
        } else {
            currentTitle = "";
            requestedWidth = 0;
            requestedHeight = 0;
            resultsLayout = "list";
        }
        viewChanged();
    }

    function goBack() {
        if (view !== "") {
            _setView("");
            return true;
        }
        return false;
    }

    function reset() {
        if (view !== "") {
            view = "";
            currentTitle = "";
            requestedWidth = 0;
            requestedHeight = 0;
            resultsLayout = "list";
        }
    }
}
