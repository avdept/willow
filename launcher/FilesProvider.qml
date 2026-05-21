// Files provider — backed by `fd`. Debounced; activation opens via xdg-open.
// Each result is shown with a nerd-font glyph (no image lookup).

import QtQuick
import Quickshell
import Quickshell.Io

Provider {
    id: prov

    name: "Files"
    tag: "file"
    iconText: "󰉋"
    description: "Search files in your home directory"
    shortcuts: ["f", "files"]

    property int maxResults: 12
    property int debounceMs: 180
    property string searchRoot: Quickshell.env("HOME") || "/"

    // Per-result nerd-font glyphs. Override from Launcher.qml if you want
    // different icons.
    property string fileGlyph: "󰈔"
    property string folderGlyph: ""

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
        // We need both the cap (`--max-results`) and a per-path type marker.
        // fd rejects mixing `--max-results` with `--exec-batch`, so the
        // pipeline is: fd -0 → head -z (cap) → xargs ls -dF (mark dirs/etc).
        // q and searchRoot are passed as positional args ($1, $2) so the
        // shell doesn't need to quote anything.
        const script =
            "fd --hidden --no-ignore-vcs " +
            "--exclude .git --exclude node_modules --exclude .cache " +
            "-0 -- \"$1\" \"$2\" 2>/dev/null | " +
            "head -zn " + maxResults + " | " +
            "xargs -0 -r ls -d -F -- 2>/dev/null";
        fdProc.command = ["sh", "-c", script, "fd-runner", q, searchRoot];
        fdProc.running = true;
    }

    function _flush() {
        const out = [];
        for (let i = 0; i < _pendingBuf.length; i++) {
            const raw = _pendingBuf[i];
            // fd outputs a trailing slash for directories, and `ls -F` adds
            // another type indicator (`/`, `*`, `@`, `=`, `|`). Strip any
            // run of those from the end.
            const m = raw.match(/[\/*@=|]+$/);
            const indicator = m ? m[0] : "";
            const isDir = indicator.indexOf("/") !== -1;
            const clean = indicator.length > 0 ? raw.slice(0, -indicator.length) : raw;
            const slash = clean.lastIndexOf("/");
            const base = slash >= 0 ? clean.slice(slash + 1) : clean;
            const dir  = slash >= 0 ? clean.slice(0, slash)  : "";
            out.push({
                title:       base,
                subtitle:    dir,
                iconText:    isDir ? folderGlyph : fileGlyph,
                providerTag: isDir ? "folder" : "file",
                score:       maxResults - i,         // preserve fd's relevance order
                data:        { path: clean }
            });
        }
        results = out;
    }

    function activate(result) {
        const path = result?.data?.path;
        if (!path) return;
        openProc.command = ["xdg-open", path];
        openProc.running = true;
    }

    Process {
        id: openProc
        running: false
    }
}
