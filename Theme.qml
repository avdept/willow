import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: theme

    // Defaults (used until colors.toml loads, also fallbacks for missing keys).
    property color bg:     "#eff1f5"
    property color fg:     "#4c4f69"
    property color subFg:  "#6c6f85"
    property color accent: "#1e66f5"
    property color border: "#bcc0cc"
    property color danger: "#d20f39"
    property color warn:   "#df8e1d"

    // omarchy stores the active theme's palette under a symlinked path. The
    // colors file's resolved inode changes on `theme set`, which inotify on
    // the resolved path doesn't catch. We watch `theme.name` (a real file
    // that omarchy rewrites on every theme change) as a trigger to reload
    // colors.toml.
    readonly property string _omarchyBase: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const home = Quickshell.env("HOME");
        const base = xdg && xdg.length > 0 ? xdg : (home + "/.config");
        return base + "/omarchy/current";
    }

    readonly property FileView _file: FileView {
        path: theme._omarchyBase + "/theme/colors.toml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: theme._apply(text())
    }

    // Stable file: omarchy rewrites this on every theme change.
    readonly property FileView _themeMarker: FileView {
        path: theme._omarchyBase + "/theme.name"
        watchChanges: true
        onFileChanged: {
            reload();
            theme._file.reload();   // pick up the freshly retargeted colors.toml
        }
    }

    function _apply(src) {
        if (!src) return;
        // TOML keys (alphanumeric + underscores) = "#hex"
        const re = /^\s*([A-Za-z0-9_]+)\s*=\s*"(#[0-9a-fA-F]{3,8})"/gm;
        const map = {};
        let m;
        while ((m = re.exec(src)) !== null) map[m[1]] = m[2];

        if (map.background) bg     = map.background;
        if (map.foreground) fg     = map.foreground;
        if (map.accent)     accent = map.accent;
        if (map.color0)     border = map.color0;
        if (map.color1)     danger = map.color1;
        if (map.color3)     warn   = map.color3;
        if (map.color15)    subFg  = map.color15;
    }
}
