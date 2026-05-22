// Now provider — at-a-glance dashboard: weather, CPU, memory, volume,
// battery and a few quick-launch tiles. Renders as a grid (3 cols).
//
// Each tile is a regular Provider result; its `iconText` is the
// nerd-font glyph drawn at 32px by ResultGridCell, and its `title` is
// the live value (e.g. "21°C", "23%"). Activating a tile typically
// launches the matching omarchy tool — same targets the top bar uses.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Provider {
    id: prov

    name: "Now"
    tag: "now"
    iconText: "󱎫"
    description: "System stats and quick links"
    resultsLayout: "grid"
    gridColumns: 4
    cellHeight: 120
    requestedWidth: 1120

    // Live readings. _publish() rebuilds `results` whenever any of these change.
    property string _weatherIcon: ""
    property string _weatherTemp: ""
    property int _cpuPct: -1
    property real _memUsedGiB: 0
    property real _memTotalGiB: 0

    readonly property var _sink: Pipewire.defaultAudioSink
    readonly property var _batt: UPower.displayDevice

    Component.onCompleted: {
        _publish();
        weatherIconProc.running = true;
        weatherStatusProc.running = true;
        statsProc.running = true;
    }

    // ── Weather (glyph + temp) ───────────────────────────────────────────
    // The bar uses the same two commands; refresh every 5 minutes.
    Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            if (!weatherIconProc.running)
                weatherIconProc.running = true;
            if (!weatherStatusProc.running)
                weatherStatusProc.running = true;
        }
    }
    Process {
        id: weatherIconProc
        command: ["omarchy-weather-icon"]
        stdout: StdioCollector {
            onStreamFinished: {
                prov._weatherIcon = this.text.trim();
                prov._publish();
            }
        }
    }
    Process {
        id: weatherStatusProc
        command: ["omarchy-weather-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "    Cherkasy  ·  Temp 21°C  ·  Wind …" → "21°C"
                const m = this.text.match(/Temp\s+([^\s·]+)/);
                prov._weatherTemp = m ? m[1] : "";
                prov._publish();
            }
        }
    }

    // ── CPU + memory sampler (single shell) ──────────────────────────────
    // 1s tick — the script itself adds a 200ms sleep between /proc/stat
    // samples to compute the delta, so effective CPU coverage is ~80%.
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: if (!statsProc.running)
            statsProc.running = true
    }
    Process {
        id: statsProc
        command: ["sh", "-c", "read _ u1 n1 s1 i1 io1 _ < /proc/stat; sleep 0.2; read _ u2 n2 s2 i2 io2 _ < /proc/stat; busy=$(( (u2+n2+s2) - (u1+n1+s1) )); total=$(( busy + (i2+io2) - (i1+io1) )); [ $total -le 0 ] && cpu=0 || cpu=$(( busy * 100 / total )); mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo); ma=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo); printf 'cpu=%s\\nmem_used_kb=%s\\nmem_total_kb=%s\\n' \"$cpu\" \"$((mt-ma))\" \"$mt\""]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                if (!line)
                    return;
                const eq = line.indexOf("=");
                if (eq < 0)
                    return;
                const k = line.slice(0, eq), v = line.slice(eq + 1);
                if (k === "cpu")
                    prov._cpuPct = parseInt(v, 10) || 0;
                else if (k === "mem_used_kb")
                    prov._memUsedGiB = (parseInt(v, 10) || 0) / 1024 / 1024;
                else if (k === "mem_total_kb")
                    prov._memTotalGiB = (parseInt(v, 10) || 0) / 1024 / 1024;
            }
        }
        onRunningChanged: if (!running)
            prov._publish()
    }

    // Volume / battery come from Quickshell services — react via on*Changed.
    Connections {
        target: prov._sink ? prov._sink.audio : null
        function onVolumeChanged() {
            prov._publish();
        }
        function onMutedChanged() {
            prov._publish();
        }
    }
    Connections {
        target: prov._batt
        function onPercentageChanged() {
            prov._publish();
        }
        function onStateChanged() {
            prov._publish();
        }
    }

    // ── Tile builders ────────────────────────────────────────────────────

    function _volTile() {
        const a = prov._sink ? prov._sink.audio : null;
        if (!a)
            return {
                glyph: "󰖁",
                title: "—",
                id: "volume"
            };
        const pct = Math.round(a.volume * 100);
        const muted = a.muted;
        return {
            glyph: muted ? "󰝟" : (pct >= 66 ? "󰕾" : pct >= 33 ? "󰖀" : "󰕿"),
            title: muted ? "Muted" : (pct + "%"),
            id: "volume"
        };
    }

    function _batteryTile() {
        const d = prov._batt;
        if (!d || !d.isPresent)
            return null;
        const pct = Math.round(d.percentage);
        // Discharging vs charging glyph runs, matching shell.qml.
        const dis = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"];
        const chg = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"];
        const idx = Math.min(9, Math.max(0, Math.floor(pct / 10)));
        const charging = !UPower.onBattery;
        return {
            glyph: charging ? chg[idx] : dis[idx],
            title: pct + "%",
            id: "battery"
        };
    }

    function _publish() {
        const tiles = [];

        tiles.push({
            glyph: prov._weatherIcon || "󰖕",
            title: prov._weatherTemp || "Weather",
            id: "weather"
        });

        tiles.push({
            glyph: "󰍛",
            title: prov._cpuPct < 0 ? "CPU" : (prov._cpuPct + "%"),
            id: "cpu"
        });

        tiles.push({
            glyph: "",
            title: prov._memTotalGiB > 0 ? (prov._memUsedGiB.toFixed(1) + " / " + Math.round(prov._memTotalGiB) + "G") : "Memory",
            id: "memory"
        });

        tiles.push(_volTile());

        const bt = _batteryTile();
        if (bt)
            tiles.push(bt);

        // Quick links — keep these last so stats own the top row(s).
        tiles.push({
            glyph: "",
            title: "Lock",
            id: "lock"
        });
        tiles.push({
            glyph: "󰐥",
            title: "Power",
            id: "power"
        });
        tiles.push({
            glyph: "󰂯",
            title: "Bluetooth",
            id: "bluetooth"
        });
        tiles.push({
            glyph: "󰖩",
            title: "Wi-Fi",
            id: "wifi"
        });

        // Map to provider result objects. `score` descending preserves order.
        const out = new Array(tiles.length);
        for (let i = 0; i < tiles.length; i++) {
            const t = tiles[i];
            out[i] = {
                title: t.title,
                iconUrl: ""          // no preview image → cell falls back to iconText
                ,
                iconText: t.glyph,
                score: tiles.length - i,
                data: {
                    id: t.id
                }
            };
        }
        results = out;
    }

    // ── Search (always returns the full grid; query is ignored) ──────────
    function search(_text) {
        _publish();
    }

    // ── Activation ───────────────────────────────────────────────────────
    // Anything that needs to outlive our Process (long-running GUIs, the
    // hyprlock surface, etc.) is routed through `hyprctl dispatch exec` —
    // that's the same path the SUPER+CTRL+L keybind uses, so it's known
    // to detach cleanly under this compositor.
    function activate(result) {
        const id = result?.data?.id;
        if (!id)
            return;
        let cmd;
        switch (id) {
        case "weather":
            cmd = ["sh", "-c", "notify-send -u low \"$(omarchy-weather-status)\""];
            break;
        case "cpu":
        case "memory":
            cmd = _hyprExec("omarchy-launch-or-focus-tui btop");
            break;
        case "volume":
            cmd = _hyprExec("omarchy-launch-audio");
            break;
        case "battery":
        case "power":
            cmd = _hyprExec("omarchy-menu power");
            break;
        case "lock":
            cmd = _hyprExec("omarchy-system-lock");
            break;
        case "bluetooth":
            cmd = _hyprExec("omarchy-launch-bluetooth");
            break;
        case "wifi":
            cmd = _hyprExec("omarchy-launch-wifi");
            break;
        default:
            return;
        }
        actProc.command = cmd;
        if (actProc.running)
            actProc.running = false;
        actProc.running = true;
    }

    function _hyprExec(line) {
        return ["hyprctl", "dispatch", "exec", line];
    }

    Process {
        id: actProc
        running: false
    }
}
