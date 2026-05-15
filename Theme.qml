import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: theme

    // Defaults (used until waybar.css loads, also fallbacks for missing entries).
    property color bg:     "#eff1f5"
    property color fg:     "#4c4f69"
    property color subFg:  "#6c6f85"
    property color accent: "#1e66f5"
    property color border: "#bcc0cc"
    property color danger: "#d20f39"
    property color warn:   "#df8e1d"

    // Watch the same theme stylesheet waybar imports. omarchy retargets the
    // `current` symlink on `omarchy theme set` → FileView re-reads.
    readonly property string _waybarCss: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const home = Quickshell.env("HOME");
        const base = xdg && xdg.length > 0 ? xdg : (home + "/.config");
        return base + "/omarchy/current/theme/waybar.css";
    }
    readonly property FileView _file: FileView {
        path: theme._waybarCss
        watchChanges: true
        onFileChanged: reload()
        onLoaded: theme._apply(text())
    }

    // omarchy retargets a symlink on `theme set`, so inotify on the resolved
    // file never fires. Poll every few seconds — file is tiny, cost is nil,
    // and this means no omarchy hook to maintain across updates.
    readonly property Timer _poll: Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: theme._file.reload()
    }

    // Manual trigger via `qs ipc call theme reload` when you don't want to wait.
    readonly property IpcHandler _ipc: IpcHandler {
        target: "theme"
        function reload(): void {
            theme._file.reload();
        }
    }

    function _apply(src) {
        if (!src) return;
        const re = /@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{3,8})/g;
        const map = {};
        let m;
        while ((m = re.exec(src)) !== null) map[m[1]] = m[2];

        if (map.foreground) fg = map.foreground;
        if (map.background) bg = map.background;

        // Derived tones: blend fg into bg by t (0..1)
        function blend(t) {
            return Qt.rgba(
                fg.r * t + bg.r * (1 - t),
                fg.g * t + bg.g * (1 - t),
                fg.b * t + bg.b * (1 - t),
                1.0
            );
        }
        border = blend(0.25);
        subFg  = blend(0.65);
    }
}
