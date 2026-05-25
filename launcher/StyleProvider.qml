// Style provider — mirrors the "Style" section of `omarchy-menu`.
// Three sub-views: themes (preview-thumb grid), fonts (each rendered
// in its own family), unlocks (Plymouth styles, sudo via floating
// terminal). Backed by `omarchy-theme-list` / `omarchy-font-list` etc.

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

    // "" = root menu. Other values: "themes", "fonts", "unlocks".
    property string view: ""

    property var _themes: []
    property string _currentTheme: ""
    property var _fonts: []
    property string _currentFont: ""
    // One entry per theme that ships a preview-unlock.png.
    property var _unlocks: []
    // Map of theme display-name → file:// URL of preview image. Mirrors
    // omarchy_themes.lua's resolution: preview.png > preview.jpg > first
    // file in backgrounds/. User dir wins over $OMARCHY_PATH.
    property var _themePreviews: ({})

    // User overrides win — same precedence as `omarchy-theme-list`.
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

    // Emits `<dir-name>\t<preview-unlock-path>` for every theme that ships
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

    function search(text) {
        const q = norm(text);
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
            const isCurrent = name === _currentTheme;
            let score;
            if (q.length === 0) {
                score = isCurrent ? 1000 : (500 - i);
            } else {
                score = scoreText(q, norm(name));
                if (score <= 0) continue;
                if (isCurrent) score *= 1.5;
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
            const isCurrent = name === _currentFont;
            let score;
            if (q.length === 0) {
                score = isCurrent ? 1000 : (500 - i);
            } else {
                score = scoreText(q, norm(name));
                if (score <= 0) continue;
                if (isCurrent) score *= 1.5;
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
            let score;
            if (q.length === 0) {
                score = 500 - i;
            } else {
                score = scoreText(q, norm(u.display));
                if (score <= 0) continue;
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
            openExternal(["omarchy-theme-set", d.name]);
            _currentTheme = d.name;
            return true;
        }
        if (d.kind === "font" && d.name) {
            openExternal(["omarchy-font-set", d.name]);
            _currentFont = d.name;
            return true;
        }
        if (d.kind === "unlock" && d.dir) {
            // sudo prompt — must run in a floating terminal so the user
            // can type the password. Mirrors omarchy_unlocks.lua.
            openExternal([
                "omarchy-launch-floating-terminal-with-presentation",
                "omarchy-plymouth-set-by-theme " + d.dir
            ]);
            return;
        }
        if (d.kind === "unlock-default") {
            openExternal([
                "omarchy-launch-floating-terminal-with-presentation",
                "omarchy-plymouth-reset"
            ]);
            return;
        }
    }

    // Themes sub-view: 3 columns × 2 visible rows fit without scrolling.
    // Height stays at launcher default (0).
    readonly property int _themesViewWidth: 1080
    readonly property int _themesViewHeight: 0
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
