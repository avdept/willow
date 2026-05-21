// Files provider — backed by `fd`. Debounced; activation opens via xdg-open.
// Not yet wired into the launcher's `providers` array — add `filesProv` to
// the array in Launcher.qml when ready.

import QtQuick
import Quickshell
import Quickshell.Io

Provider {
    id: prov

    name: "Files"
    tag: "file"
    iconText: ""
    description: "Search files in your home directory"

    property int maxResults: 12
    property int debounceMs: 180
    property string searchRoot: Quickshell.env("HOME") || "/"

    property string _pending: ""
    property var _pendingBuf: []

    Timer {
        id: debounce
        interval: prov.debounceMs
        onTriggered: prov._run(prov._pending)
    }

    Process {
        id: fdProc
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                if (!line) return;
                if (prov._pendingBuf.length >= prov.maxResults) return;
                prov._pendingBuf.push(line);
            }
        }
        onRunningChanged: if (!running) prov._flush()
    }

    function search(text) {
        const q = (text || "").trim();
        if (q.length < 2) {
            if (fdProc.running) fdProc.running = false;
            results = [];
            return;
        }
        _pending = q;
        debounce.restart();
    }

    function _run(q) {
        if (fdProc.running) fdProc.running = false;
        _pendingBuf = [];
        busy = true;
        fdProc.command = [
            "fd", "--hidden", "--no-ignore-vcs",
            "--exclude", ".git",
            "--exclude", "node_modules",
            "--exclude", ".cache",
            "--max-results", String(maxResults),
            q, searchRoot
        ];
        fdProc.running = true;
    }

    function _flush() {
        const out = [];
        for (let i = 0; i < _pendingBuf.length; i++) {
            const path  = _pendingBuf[i];
            const slash = path.lastIndexOf("/");
            const base  = slash >= 0 ? path.slice(slash + 1) : path;
            const dir   = slash >= 0 ? path.slice(0, slash)  : "";
            out.push({
                title: base,
                subtitle: dir,
                iconUrl: Quickshell.iconPath("text-x-generic", true) || "",
                score: maxResults - i,         // preserve fd's relevance order
                data: { path: path }
            });
        }
        results = out;
        busy = false;
    }

    function activate(result) {
        const path = result?.data?.path;
        if (!path) return;
        openProc.command = ["xdg-open", path];
        openProc.running = true;
    }

    Process { id: openProc; running: false }
}
