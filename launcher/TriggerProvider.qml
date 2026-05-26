// Trigger provider — mirrors the "Trigger" section of `omarchy-menu`.
// Currently only the Capture sub-items: screenshot, screenrecord, text
// extraction, and color picker. Screenrecord drills into a sub-view with
// the four audio variants (and a "Stop recording" row when one's live).
// Later this will grow to the rest of trigger (reminder, transcode, …).

import QtQuick
import Quickshell.Io

Provider {
    id: prov

    name: "Trigger"
    tag: "trigger"
    iconText: "󱓞"
    description: "Capture screen, video, text, or color"
    shortcuts: ["trigger", "capture"]

    // "" = root capture list, "screenrecord" = audio variants.
    property string view: ""
    property bool _recording: false

    readonly property var _rootRows: [
        {
            title: "Screenshot",
            subtitle: "Region or window",
            iconText: "",
            score: 1000,
            data: {
                kind: "spawn",
                argv: ["omarchy-capture-screenshot"]
            }
        },
        {
            title: "Screenrecord",
            subtitle: "Capture video",
            iconText: "",
            chevron: true,
            score: 900,
            data: {
                kind: "drill",
                view: "screenrecord"
            }
        },
        {
            title: "Text Extraction",
            subtitle: "OCR a region to clipboard",
            iconText: "󰴑",
            score: 800,
            data: {
                kind: "spawn",
                argv: ["omarchy-capture-text-extraction"]
            }
        },
        {
            title: "Color",
            subtitle: "Pick a color from the screen",
            iconText: "",
            score: 700,
            data: {
                kind: "spawn",
                argv: ["sh", "-c", "pkill hyprpicker || hyprpicker -a"]
            }
        }
    ]

    readonly property var _screenrecordRows: [
        {
            title: "With no audio",
            iconText: "",
            score: 1000,
            data: {
                kind: "spawn",
                argv: ["omarchy-capture-screenrecording"]
            }
        },
        {
            title: "With desktop audio",
            iconText: "",
            score: 900,
            data: {
                kind: "spawn",
                argv: ["omarchy-capture-screenrecording", "--with-desktop-audio"]
            }
        },
        {
            title: "With desktop + microphone audio",
            iconText: "",
            score: 800,
            data: {
                kind: "spawn",
                argv: ["omarchy-capture-screenrecording", "--with-desktop-audio", "--with-microphone-audio"]
            }
        },
        {
            title: "With desktop + microphone audio + webcam",
            iconText: "",
            score: 700,
            data: {
                kind: "spawn",
                argv: ["omarchy-capture-screenrecording", "--with-desktop-audio", "--with-microphone-audio", "--with-webcam"]
            }
        }
    ]

    // pgrep matches the recorder process — same detection the omarchy
    // script uses internally. Refresh on every entry to the sub-view.
    Process {
        id: recordingProbe
        command: ["pgrep", "-f", "^gpu-screen-recorder"]
        onExited: function (code, _status) {
            prov._recording = (code === 0);
            prov.refresh();
        }
    }

    function search(text) {
        const q = norm(text);
        results = view === "screenrecord" ? _screenrecordResults(q) : _rootResults(q);
    }

    function _rootResults(q) {
        return _filter(_rootRows, q);
    }

    function _screenrecordResults(q) {
        const rows = _screenrecordRows.slice();
        if (_recording) {
            rows.unshift({
                title: "Stop recording",
                subtitle: "End the current recording",
                iconText: "",
                score: 10000,
                data: {
                    kind: "spawn",
                    argv: ["omarchy-capture-screenrecording", "--stop-recording"]
                }
            });
        }
        return _filter(rows, q);
    }

    function _filter(rows, q) {
        if (q.length === 0)
            return rows.slice();
        const out = [];
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            const s = scoreText(q, norm(r.title), norm(r.subtitle || ""));
            if (s <= 0)
                continue;
            out.push(Object.assign({}, r, {
                score: s
            }));
        }
        out.sort((a, b) => b.score - a.score);
        return out;
    }

    // Defer the spawn so the launcher fades away first — otherwise the
    // screenshot/color tools capture the launcher itself.
    property var _pendingArgv: null
    Timer {
        id: activateTimer
        interval: 100
        repeat: false
        onTriggered: {
            const a = prov._pendingArgv;
            prov._pendingArgv = null;
            if (a)
                prov.openExternal(a);
        }
    }

    function activate(result) {
        const d = result?.data;
        if (!d)
            return;
        if (d.kind === "drill") {
            _setView(d.view);
            return true;
        }
        if (d.kind === "spawn" && d.argv) {
            _pendingArgv = d.argv;
            activateTimer.restart();
        }
    }

    function _setView(v) {
        if (view === v)
            return;
        view = v;
        currentTitle = v;
        if (v === "screenrecord") {
            if (recordingProbe.running)
                recordingProbe.running = false;
            recordingProbe.running = true;
        } else {
            _recording = false;
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
            _recording = false;
        }
    }
}
