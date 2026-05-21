import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: theme

    // Defaults (used until colors.toml loads, also fallbacks for missing keys).
    property color bg:      "#eff1f5"
    property color fg:      "#4c4f69"
    property color subFg:   "#6c6f85"
    property color accent:  "#1e66f5"
    property color border:  "#bcc0cc"
    property color danger:  "#d20f39"
    property color warn:    "#df8e1d"
    property color success: "#40a02b"     // color2 — green
    property color info:    "#1e66f5"     // color4 — blue (may match accent)
    property color purple:  "#8839ef"     // color5 — magenta/purple
    property color cyan:    "#04a5e5"     // color6 — cyan

    // omarchy's `theme set` does an atomic directory swap on
    // `current/theme/` (rm + mv), so an inotify watcher bound to
    // `colors.toml` loses its inode and ends up in a broken state — even
    // a later reload() doesn't recover, leaving the launcher stuck on the
    // old palette until a full restart. The fix: don't watch colors.toml
    // (watchChanges: false). Instead, watch the stable `theme.name` file
    // (omarchy rewrites it in place after the swap) and explicitly
    // reload colors.toml on every change.
    readonly property string _omarchyBase: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const home = Quickshell.env("HOME");
        const base = xdg && xdg.length > 0 ? xdg : (home + "/.config");
        return base + "/omarchy/current";
    }

    readonly property FileView _file: FileView {
        path: theme._omarchyBase + "/theme/colors.toml"
        watchChanges: false       // re-read is triggered from _themeMarker
        onLoaded: theme._apply(text())
    }

    readonly property FileView _themeMarker: FileView {
        path: theme._omarchyBase + "/theme.name"
        watchChanges: true
        onFileChanged: { reload(); theme._file.reload(); }
    }

    function _apply(src) {
        if (!src) return;
        // TOML keys (alphanumeric + underscores) = "#hex"
        const re = /^\s*([A-Za-z0-9_]+)\s*=\s*"(#[0-9a-fA-F]{3,8})"/gm;
        const map = {};
        let m;
        while ((m = re.exec(src)) !== null) map[m[1]] = m[2];

        if (map.background) bg      = map.background;
        if (map.foreground) fg      = map.foreground;
        if (map.accent)     accent  = map.accent;
        if (map.color0)     border  = map.color0;
        if (map.color1)     danger  = map.color1;
        if (map.color2)     success = map.color2;
        if (map.color3)     warn    = map.color3;
        if (map.color4)     info    = map.color4;
        if (map.color5)     purple  = map.color5;
        if (map.color6)     cyan    = map.color6;
        if (map.color15)    subFg   = map.color15;
    }
}
