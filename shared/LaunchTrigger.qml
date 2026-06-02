pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    property Process _proc: Process { command: ["true"] }

    function launch(argv) {
        const arr = Array.isArray(argv) ? argv : [argv];
        const q = s => "'" + String(s).replace(/'/g, "'\\''") + "'";
        if (_proc.running) _proc.running = false;
        _proc.command = ["hyprctl", "dispatch", "exec", arr.map(q).join(" ")];
        _proc.running = true;
    }
}
