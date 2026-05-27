// System provider — mirrors `show_system_menu` from `omarchy-menu`.
// Flat list of seven session actions. Suspend hidden when
// `omarchy-toggle-enabled suspend-off` is set; Hibernate hidden when
// `omarchy-hibernation-available` exits non-zero. Both states are
// re-probed each time the launcher opens so they stay current.

import QtQuick
import Quickshell.Io

Provider {
    id: prov

    name: "System"
    tag: "system"
    iconText: ""
    description: "Power and session actions"
    shortcuts: ["system", "sys"]

    property bool _suspendDisabled: false
    property bool _hibernationAvailable: false

    Component.onCompleted: _probe()
    onLauncherOpenChanged: if (launcherOpen) _probe()

    function _probe() {
        if (suspendStateProc.running)   suspendStateProc.running   = false;
        if (hibernateStateProc.running) hibernateStateProc.running = false;
        suspendStateProc.running   = true;
        hibernateStateProc.running = true;
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

    function _rows() {
        const out = [];
        out.push({ title: "Screensaver", iconText: "󱄄", score: 1000,
                   data: { argv: ["omarchy-launch-screensaver", "force"] } });
        out.push({ title: "Lock",        iconText: "",        score:  990,
                   data: { argv: ["omarchy-system-lock"] } });
        if (!_suspendDisabled)
            out.push({ title: "Suspend", iconText: "󰒲",   score: 980,
                       data: { argv: ["systemctl", "suspend"] } });
        if (_hibernationAvailable)
            out.push({ title: "Hibernate", iconText: "󰤁", score: 970,
                       data: { argv: ["systemctl", "hibernate"] } });
        out.push({ title: "Logout",   iconText: "󰍃",   score: 960,
                   data: { argv: ["omarchy-system-logout"] } });
        out.push({ title: "Restart",  iconText: "󰜉",  score: 950,
                   data: { argv: ["omarchy-system-reboot"] } });
        out.push({ title: "Shutdown", iconText: "󰐥", score: 940,
                   data: { argv: ["omarchy-system-shutdown"] } });
        return out;
    }

    function search(text) {
        const q = norm(text);
        const rows = _rows().map(r => Object.assign({}, r, {
            subtitle: (r.data?.argv || []).join(" ")
        }));
        if (q.length === 0) {
            results = rows;
            return;
        }
        const filtered = [];
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            const s = scoreText(q, norm(r.title), norm(r.subtitle));
            if (s <= 0) continue;
            filtered.push(Object.assign({}, r, { score: s }));
        }
        filtered.sort((a, b) => b.score - a.score);
        results = filtered;
    }

    function activate(result) {
        const argv = result?.data?.argv;
        if (argv) openExternal(argv);
    }
}
