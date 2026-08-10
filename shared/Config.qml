// Persisted user settings — font, appearance, and behavior tunables that used
// to be hardcoded across the shell. Backed by a JSON file at
// $XDG_CONFIG_HOME/quickshell/settings.json (created on first run).
//
// Edited through the Settings window (SettingsWindow.qml); writes land
// immediately via writeAdapter(). Consumers bind to these properties:
//   - Theme.qml      → radius, surfaceOpacity
//   - shell.qml      → fontFamily, reminderLeadsMin
//   - Osd.qml        → osdHideMs
//   - NotificationToasts.qml → toastDurationMs
//
// watchChanges is on, so an external edit to the file is picked up live.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: config

    // ── Appearance ────────────────────────────────────────────────────────
    property alias fontFamily:     adapter.fontFamily
    property alias radius:         adapter.radius
    property alias surfaceOpacity: adapter.surfaceOpacity

    // ── Behavior ──────────────────────────────────────────────────────────
    property alias toastDurationMs:  adapter.toastDurationMs
    property alias osdHideMs:        adapter.osdHideMs
    property alias reminderLeadsMin: adapter.reminderLeadsMin

    // Persist the current values to disk. Call after mutating any property.
    function save() { _file.writeAdapter(); }

    // IMPORTANT: this lives under XDG_STATE_HOME, NOT the config dir.
    // ~/.config/quickshell is a symlink to the project, which Quickshell's file
    // watcher monitors — writing settings.json there would trigger a full
    // config reload on every save (e.g. while dragging a slider). Settings
    // apply live via the in-memory adapter bindings; this file is only for
    // persistence across restarts.
    readonly property string _dir: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        const home = Quickshell.env("HOME");
        const base = xdg && xdg.length > 0 ? xdg : (home + "/.local/state");
        return base + "/quickshell";
    }
    readonly property string _path: config._dir + "/settings.json"

    // Ensure the state dir exists before the FileView tries to create the file.
    property Process _mkdir: Process {
        command: ["mkdir", "-p", config._dir]
        onExited: config._file.reload()   // retry load/create now the dir exists
    }
    Component.onCompleted: _mkdir.running = true

    // Declared as a named property (not a default child) — QtObject's QML-side
    // default property is finicky; same pattern as Theme._file.
    readonly property FileView _file: FileView {
        path: config._path
        watchChanges: true
        onFileChanged: reload()
        // First run: the file (and likely its directory) doesn't exist yet.
        // Writing the adapter creates it with the defaults below.
        onLoadFailed: function (error) {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }

        adapter: JsonAdapter {
            id: adapter
            property string fontFamily: "JetBrainsMono Nerd Font Mono"
            property int radius: 4
            property real surfaceOpacity: 0.92
            property int toastDurationMs: 5000
            property int osdHideMs: 5000
            property var reminderLeadsMin: [60, 15, 5, 1]
        }
    }
}
