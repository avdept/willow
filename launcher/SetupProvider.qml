// Setup provider — mirrors the "Setup" section of `omarchy-menu`.
// Static leaves (Audio, Wifi, Bluetooth, Monitors, DNS, Keybindings,
// Input, individual config files) drill or spawn directly. Dynamic
// sub-views (Power Profile, System Sleep, Defaults) re-probe state on
// entry so the "current" indicator stays honest after toggling.

import QtQuick
import Quickshell
import Quickshell.Io

Provider {
    id: prov

    name: "Setup"
    tag: "setup"
    iconText: ""
    description: "Audio, network, defaults, configs"
    shortcuts: ["setup"]

    // "" = root. Sub-views: power, system, defaults,
    // defaults_browser, defaults_terminal, defaults_editor,
    // security, config.
    property string view: ""

    readonly property var _viewParent: ({
        "defaults_browser":  "defaults",
        "defaults_terminal": "defaults",
        "defaults_editor":   "defaults"
    })

    readonly property var _viewTitle: ({
        "":                   "",
        "power":              "power profile",
        "system":             "system sleep",
        "defaults":           "defaults",
        "defaults_browser":  "defaults / browser",
        "defaults_terminal": "defaults / terminal",
        "defaults_editor":   "defaults / editor",
        "security":           "security",
        "config":             "config"
    })

    // ── Dynamic state probed by Processes below ──────────────────────────
    property var _powerProfiles: []
    property string _currentPowerProfile: ""

    // omarchy-toggle-enabled exits 0 when the toggle is *enabled* (i.e.
    // suspend-off ⇒ suspend is currently disabled). Mirrors omarchy-menu.
    property bool _suspendDisabled: false
    property bool _hibernationAvailable: false

    property string _defaultBrowser: ""
    property string _defaultTerminal: ""
    property string _defaultEditor: ""

    property var _availableBrowsers: []   // entries: { id, name, iconText }
    property var _availableTerminals: []
    property var _availableEditors: []

    // Catalog of browsers/terminals/editors omarchy knows about. Filtered
    // by availability probes below.
    readonly property var _browserCatalog: [
        { id: "chromium",     name: "Chromium",     iconText: "",  desktop: "chromium.desktop" },
        { id: "chrome",       name: "Chrome",       iconText: "󰊯", desktop: "google-chrome.desktop" },
        { id: "brave",        name: "Brave",        iconText: "󰖟", desktop: "brave-browser.desktop" },
        { id: "brave-origin", name: "Brave Origin", iconText: "󰖟", desktop: "brave-origin-beta.desktop" },
        { id: "edge",         name: "Edge",         iconText: "󰇩", desktop: "microsoft-edge.desktop" },
        { id: "firefox",      name: "Firefox",      iconText: "󰈹", desktop: "firefox.desktop" },
        { id: "zen",          name: "Zen",          iconText: "󰖟", desktop: "zen.desktop" }
    ]
    readonly property var _terminalCatalog: [
        { id: "alacritty", name: "Alacritty", iconText: "", cmd: "alacritty" },
        { id: "foot",      name: "Foot",      iconText: "", cmd: "foot" },
        { id: "ghostty",   name: "Ghostty",   iconText: "", cmd: "ghostty" },
        { id: "kitty",     name: "Kitty",     iconText: "", cmd: "kitty" }
    ]
    readonly property var _editorCatalog: [
        { id: "nvim",         name: "Neovim",       iconText: "", cmd: "nvim" },
        { id: "code",         name: "VSCode",       iconText: "", cmd: "code" },
        { id: "cursor",       name: "Cursor",       iconText: "", cmd: "cursor" },
        { id: "zed",          name: "Zed",          iconText: "", cmd: "zeditor" },
        { id: "sublime_text", name: "Sublime Text", iconText: "", cmd: "sublime_text" },
        { id: "helix",        name: "Helix",        iconText: "", cmd: "helix" },
        { id: "vim",          name: "Vim",          iconText: "", cmd: "vim" },
        { id: "emacs",        name: "Emacs",        iconText: "", cmd: "emacs" }
    ]

    Component.onCompleted: {
        // Probe everything once at startup. Re-probed lazily on viewChanged.
        powerListProc.running = true;
        powerCurrentProc.running = true;
        suspendStateProc.running = true;
        hibernateStateProc.running = true;
        defaultBrowserProc.running = true;
        defaultTerminalProc.running = true;
        defaultEditorProc.running = true;
        browserAvailProc.running = true;
        terminalAvailProc.running = true;
        editorAvailProc.running = true;
    }

    // ── Probes ───────────────────────────────────────────────────────────
    property var _powerBuf: []
    Process {
        id: powerListProc
        running: false
        command: ["omarchy-powerprofiles-list"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s) prov._powerBuf.push(s);
            }
        }
        onRunningChanged: if (!running) {
            prov._powerProfiles = prov._powerBuf;
            prov._powerBuf = [];
            prov.refresh();
        }
    }
    Process {
        id: powerCurrentProc
        running: false
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s) prov._currentPowerProfile = s;
            }
        }
        onRunningChanged: if (!running) prov.refresh()
    }

    Process {
        id: suspendStateProc
        running: false
        command: ["sh", "-c", "omarchy-toggle-enabled suspend-off && echo 1 || echo 0"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s === "1" || s === "0") prov._suspendDisabled = (s === "1");
            }
        }
        onRunningChanged: if (!running) prov.refresh()
    }
    Process {
        id: hibernateStateProc
        running: false
        command: ["sh", "-c", "omarchy-hibernation-available && echo 1 || echo 0"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s === "1" || s === "0") prov._hibernationAvailable = (s === "1");
            }
        }
        onRunningChanged: if (!running) prov.refresh()
    }

    Process {
        id: defaultBrowserProc
        running: false
        command: ["omarchy-default-browser"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s) prov._defaultBrowser = s;
            }
        }
        onRunningChanged: if (!running) prov.refresh()
    }
    Process {
        id: defaultTerminalProc
        running: false
        command: ["omarchy-default-terminal"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s) prov._defaultTerminal = s;
            }
        }
        onRunningChanged: if (!running) prov.refresh()
    }
    Process {
        id: defaultEditorProc
        running: false
        command: ["omarchy-default-editor"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s) prov._defaultEditor = s;
            }
        }
        onRunningChanged: if (!running) prov.refresh()
    }

    // Each line of stdout = a present browser id (matches catalog ids).
    property var _browserBuf: []
    Process {
        id: browserAvailProc
        running: false
        command: ["sh", "-c", `
            check() {
                [ -f "$HOME/.local/share/applications/$2" ] || \\
                [ -f "$HOME/.nix-profile/share/applications/$2" ] || \\
                [ -f "/usr/share/applications/$2" ] && echo "$1"
            }
            check chromium chromium.desktop
            check chrome google-chrome.desktop
            check brave brave-browser.desktop
            check brave-origin brave-origin-beta.desktop
            check edge microsoft-edge.desktop
            check firefox firefox.desktop
            check zen zen.desktop
        `]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s) prov._browserBuf.push(s);
            }
        }
        onRunningChanged: if (!running) {
            const set = {};
            for (let i = 0; i < prov._browserBuf.length; i++) set[prov._browserBuf[i]] = true;
            prov._browserBuf = [];
            prov._availableBrowsers = prov._browserCatalog.filter(b => set[b.id]);
            prov.refresh();
        }
    }

    property var _terminalBuf: []
    Process {
        id: terminalAvailProc
        running: false
        command: ["sh", "-c", `
            for c in alacritty foot ghostty kitty; do
                omarchy-cmd-present "$c" && echo "$c"
            done
        `]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s) prov._terminalBuf.push(s);
            }
        }
        onRunningChanged: if (!running) {
            const set = {};
            for (let i = 0; i < prov._terminalBuf.length; i++) set[prov._terminalBuf[i]] = true;
            prov._terminalBuf = [];
            prov._availableTerminals = prov._terminalCatalog.filter(t => set[t.cmd]);
            prov.refresh();
        }
    }

    property var _editorBuf: []
    Process {
        id: editorAvailProc
        running: false
        command: ["sh", "-c", `
            for c in nvim code cursor zeditor sublime_text helix vim emacs; do
                omarchy-cmd-present "$c" && echo "$c"
            done
        `]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const s = (line || "").trim();
                if (s) prov._editorBuf.push(s);
            }
        }
        onRunningChanged: if (!running) {
            const set = {};
            for (let i = 0; i < prov._editorBuf.length; i++) set[prov._editorBuf[i]] = true;
            prov._editorBuf = [];
            prov._availableEditors = prov._editorCatalog.filter(e => set[e.cmd]);
            prov.refresh();
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────
    function _restartProc(proc) {
        if (proc.running) proc.running = false;
        proc.running = true;
    }

    function _editAndRestart(path, restartCmd) {
        const q = s => "'" + String(s).replace(/'/g, "'\\''") + "'";
        const line = restartCmd
            ? "omarchy-launch-editor " + q(path) + " && " + restartCmd
            : "omarchy-launch-editor " + q(path);
        return ["sh", "-c", line];
    }

    // ── Row builders ─────────────────────────────────────────────────────
    readonly property string _hyprDir: (Quickshell.env("HOME") || "") + "/.config/hypr"

    function _rootRows() {
        const rows = [
            { title: "Audio",        subtitle: "wiremix",               iconText: "", score: 1300,
              data: { kind: "spawn", argv: ["omarchy-launch-audio"] } },
            { title: "Wifi",         subtitle: "impala",                iconText: "", score: 1290,
              data: { kind: "spawn", argv: ["omarchy-launch-wifi"] } },
            { title: "Bluetooth",    subtitle: "bluetui",               iconText: "󰂯", score: 1280,
              data: { kind: "spawn", argv: ["omarchy-launch-bluetooth"] } },
            { title: "Power Profile", subtitle: _currentPowerProfile ? ("Current: " + _currentPowerProfile) : "performance / balanced / power-saver",
              iconText: "󱐋", chevron: true, score: 1270,
              data: { kind: "drill", view: "power" } },
            { title: "System Sleep", subtitle: "Suspend and hibernate", iconText: "", chevron: true, score: 1260,
              data: { kind: "drill", view: "system" } },
            { title: "Monitors",     subtitle: "~/.config/hypr/monitors.conf", iconText: "󰍹", score: 1250,
              data: { kind: "spawn", argv: ["omarchy-launch-editor", _hyprDir + "/monitors.conf"] } }
        ];
        rows.push({ title: "Keybindings", subtitle: "~/.config/hypr/bindings.conf",
            iconText: "", score: 1240,
            data: { kind: "spawn", argv: ["omarchy-launch-editor", _hyprDir + "/bindings.conf"] } });
        rows.push({ title: "Input", subtitle: "~/.config/hypr/input.conf",
            iconText: "", score: 1230,
            data: { kind: "spawn", argv: ["omarchy-launch-editor", _hyprDir + "/input.conf"] } });
        rows.push({ title: "Defaults", subtitle: "Browser, terminal, editor", iconText: "", chevron: true, score: 1220,
            data: { kind: "drill", view: "defaults" } });
        rows.push({ title: "DNS", subtitle: "Set system DNS", iconText: "󰱔", score: 1210,
            data: { kind: "present", cmd: "omarchy-setup-dns" } });
        rows.push({ title: "Security", subtitle: "Fingerprint, Fido2", iconText: "", chevron: true, score: 1200,
            data: { kind: "drill", view: "security" } });
        rows.push({ title: "Config", subtitle: "Edit Hyprland, Waybar, Walker…", iconText: "", chevron: true, score: 1190,
            data: { kind: "drill", view: "config" } });
        return rows;
    }

    function _powerRows() {
        const out = [];
        for (let i = 0; i < _powerProfiles.length; i++) {
            const name = _powerProfiles[i];
            const isCurrent = name === _currentPowerProfile;
            out.push({
                title:    name,
                subtitle: isCurrent ? "current" : "",
                iconText: "󱐋",
                score:    1000 - i,
                data:     { kind: "power-set", profile: name, isCurrent: isCurrent }
            });
        }
        return out;
    }

    function _systemRows() {
        const out = [];
        out.push({
            title:    _suspendDisabled ? "Enable Suspend" : "Disable Suspend",
            iconText: "󰒲",
            score:    1000,
            data:     { kind: "spawn", argv: ["omarchy-toggle-suspend"], refreshView: "system" }
        });
        out.push({
            title:    _hibernationAvailable ? "Disable Hibernate" : "Enable Hibernate",
            iconText: "󰤁",
            score:    990,
            data:     { kind: "present",
                        cmd: _hibernationAvailable ? "omarchy-hibernation-remove" : "omarchy-hibernation-setup" }
        });
        return out;
    }

    function _defaultsRows() {
        return [
            { title: "Browser",  subtitle: _defaultBrowser  ? ("Current: " + _defaultBrowser)  : "Pick a default browser",
              iconText: "", chevron: true, score: 1000,
              data: { kind: "drill", view: "defaults_browser" } },
            { title: "Terminal", subtitle: _defaultTerminal ? ("Current: " + _defaultTerminal) : "Pick a default terminal",
              iconText: "", chevron: true, score: 990,
              data: { kind: "drill", view: "defaults_terminal" } },
            { title: "Editor",   subtitle: _defaultEditor   ? ("Current: " + _defaultEditor)   : "Pick a default editor",
              iconText: "", chevron: true, score: 980,
              data: { kind: "drill", view: "defaults_editor" } }
        ];
    }

    function _defaultsBrowserRows() {
        const out = [];
        for (let i = 0; i < _availableBrowsers.length; i++) {
            const b = _availableBrowsers[i];
            const isCurrent = b.id === _defaultBrowser;
            out.push({
                title:    b.name,
                subtitle: isCurrent ? "current" : "",
                iconText: b.iconText,
                score:    1000 - i,
                data:     { kind: "default-set", domain: "browser", id: b.id, name: b.name, isCurrent: isCurrent }
            });
        }
        return out;
    }
    function _defaultsTerminalRows() {
        const out = [];
        for (let i = 0; i < _availableTerminals.length; i++) {
            const t = _availableTerminals[i];
            const isCurrent = t.id === _defaultTerminal;
            out.push({
                title:    t.name,
                subtitle: isCurrent ? "current" : "",
                iconText: t.iconText,
                score:    1000 - i,
                data:     { kind: "default-set", domain: "terminal", id: t.id, name: t.name, isCurrent: isCurrent }
            });
        }
        return out;
    }
    function _defaultsEditorRows() {
        const out = [];
        for (let i = 0; i < _availableEditors.length; i++) {
            const e = _availableEditors[i];
            // omarchy-default-editor stores "zed" but cmd is zeditor — match
            // either form so the indicator works regardless of how it's set.
            const isCurrent = e.id === _defaultEditor || (e.id === "zed" && _defaultEditor === "zeditor");
            out.push({
                title:    e.name,
                subtitle: isCurrent ? "current" : "",
                iconText: e.iconText,
                score:    1000 - i,
                data:     { kind: "default-set", domain: "editor", id: e.id, name: e.name, isCurrent: isCurrent }
            });
        }
        return out;
    }

    readonly property var _securityRows: [
        { title: "Fingerprint", iconText: "󰈷", score: 1000,
          data: { kind: "present", cmd: "omarchy-setup-security-fingerprint" } },
        { title: "Fido2",       iconText: "", score: 990,
          data: { kind: "present", cmd: "omarchy-setup-security-fido2" } }
    ]

    readonly property var _configRows: [
        { title: "Hyprland",  subtitle: "~/.config/hypr/hyprland.conf",  iconText: "", score: 1000,
          data: { kind: "spawn", argv: ["omarchy-launch-editor", (Quickshell.env("HOME") || "") + "/.config/hypr/hyprland.conf"] } },
        { title: "Hypridle",  subtitle: "~/.config/hypr/hypridle.conf",  iconText: "", score: 990,
          data: { kind: "edit-restart", path: (Quickshell.env("HOME") || "") + "/.config/hypr/hypridle.conf", restart: "omarchy-restart-hypridle" } },
        { title: "Hyprlock",  subtitle: "~/.config/hypr/hyprlock.conf",  iconText: "", score: 980,
          data: { kind: "spawn", argv: ["omarchy-launch-editor", (Quickshell.env("HOME") || "") + "/.config/hypr/hyprlock.conf"] } },
        { title: "Hyprsunset", subtitle: "~/.config/hypr/hyprsunset.conf", iconText: "", score: 970,
          data: { kind: "edit-restart", path: (Quickshell.env("HOME") || "") + "/.config/hypr/hyprsunset.conf", restart: "omarchy-restart-hyprsunset" } },
        { title: "Swayosd",   subtitle: "~/.config/swayosd/config.toml", iconText: "", score: 960,
          data: { kind: "edit-restart", path: (Quickshell.env("HOME") || "") + "/.config/swayosd/config.toml", restart: "omarchy-restart-swayosd" } },
        { title: "Walker",    subtitle: "~/.config/walker/config.toml",  iconText: "󰌧", score: 950,
          data: { kind: "edit-restart", path: (Quickshell.env("HOME") || "") + "/.config/walker/config.toml", restart: "omarchy-restart-walker" } },
        { title: "Waybar",    subtitle: "~/.config/waybar/config.jsonc", iconText: "󰍜", score: 940,
          data: { kind: "edit-restart", path: (Quickshell.env("HOME") || "") + "/.config/waybar/config.jsonc", restart: "omarchy-restart-waybar" } },
        { title: "XCompose",  subtitle: "~/.XCompose",                   iconText: "󰞅", score: 930,
          data: { kind: "edit-restart", path: (Quickshell.env("HOME") || "") + "/.XCompose", restart: "omarchy-restart-xcompose" } }
    ]

    function _rowsForView(v) {
        switch (v) {
        case "":                  return _rootRows();
        case "power":             return _powerRows();
        case "system":            return _systemRows();
        case "defaults":          return _defaultsRows();
        case "defaults_browser":  return _defaultsBrowserRows();
        case "defaults_terminal": return _defaultsTerminalRows();
        case "defaults_editor":   return _defaultsEditorRows();
        case "security":          return _securityRows;
        case "config":            return _configRows;
        }
        return [];
    }

    function search(text) {
        const q = norm(text);
        if (view === "") {
            results = q.length === 0 ? _rootRows() : _searchAllLeaves(q);
        } else {
            results = _filter(_rowsForView(view), q);
        }
    }

    // Flat fuzzy search across every leaf so `setup wifi` works without
    // drilling. Mirrors InstallProvider._searchAllLeaves.
    function _searchAllLeaves(q) {
        const views = ["", "power", "system", "defaults",
                       "defaults_browser", "defaults_terminal", "defaults_editor",
                       "security", "config"];
        const seen = {};
        const leaves = [];
        for (let v = 0; v < views.length; v++) {
            const rows = _rowsForView(views[v]);
            for (let i = 0; i < rows.length; i++) {
                const r = rows[i];
                if (r.data && r.data.kind === "drill") continue;
                const key = r.title + "|" + ((r.data && r.data.cmd)
                    || ((r.data && r.data.argv) || []).join(" ")
                    || (r.data && r.data.profile)
                    || (r.data && r.data.id) || "");
                if (seen[key]) continue;
                seen[key] = true;
                leaves.push(r);
            }
        }
        return _filter(leaves, q);
    }

    function _filter(rows, q) {
        if (q.length === 0) return rows.slice();
        const out = [];
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            const s = scoreText(q, norm(r.title), norm(r.subtitle || ""));
            if (s <= 0) continue;
            out.push(Object.assign({}, r, { score: s }));
        }
        out.sort((a, b) => b.score - a.score);
        return out;
    }

    function activate(result) {
        const d = result?.data;
        if (!d) return;

        if (d.kind === "drill") {
            _setView(d.view);
            // Lazily refresh dynamic state for the sub-view we're entering.
            if (d.view === "power") {
                _restartProc(powerCurrentProc);
                _restartProc(powerListProc);
            } else if (d.view === "system") {
                _restartProc(suspendStateProc);
                _restartProc(hibernateStateProc);
            } else if (d.view === "defaults_browser") {
                _restartProc(defaultBrowserProc);
            } else if (d.view === "defaults_terminal") {
                _restartProc(defaultTerminalProc);
            } else if (d.view === "defaults_editor") {
                _restartProc(defaultEditorProc);
            }
            return true;
        }

        if (d.kind === "spawn" && d.argv) {
            openExternal(d.argv);
            // For in-place toggles (suspend), re-probe to flip the label.
            if (d.refreshView === "system") {
                Qt.callLater(() => _restartProc(suspendStateProc));
                return true;
            }
            return;
        }

        if (d.kind === "present" && d.cmd) {
            openExternal(["omarchy-launch-floating-terminal-with-presentation", d.cmd]);
            return;
        }

        if (d.kind === "edit-restart" && d.path) {
            openExternal(_editAndRestart(d.path, d.restart));
            return;
        }

        if (d.kind === "power-set" && d.profile) {
            openExternal(["powerprofilesctl", "set", d.profile]);
            // Update indicator instantly; keep launcher open so the user
            // can A/B another profile without reopening.
            _currentPowerProfile = d.profile;
            refresh();
            return true;
        }

        if (d.kind === "default-set" && d.id && d.domain) {
            const cmd = "omarchy-default-" + d.domain;
            openExternal([cmd, d.id]);
            if (d.domain === "browser")  { _defaultBrowser  = d.id; }
            if (d.domain === "terminal") { _defaultTerminal = d.id; }
            if (d.domain === "editor")   { _defaultEditor   = d.id; }
            refresh();
            return true;
        }
    }

    function _setView(v) {
        if (view === v) return;
        view = v;
        currentTitle = _viewTitle[v] || "";
        viewChanged();
    }

    function goBack() {
        if (view !== "") {
            _setView(_viewParent[view] || "");
            return true;
        }
        return false;
    }

    function reset() {
        if (view !== "") {
            view = "";
            currentTitle = "";
        }
    }
}
