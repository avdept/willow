// On-screen display (replaces swayosd): a transient bottom-center pill for
// volume, mic mute, brightness, and caps/num lock. Volume/mic are reactive on
// Pipewire; brightness is IPC-triggered; lock state is polled from sysfs LEDs.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "plugins"

PanelWindow {
    id: osd

    required property var theme
    required property string fontFamily

    property int hideMs: 5000

    // Extra space the window reserves around the pill so the drop shadow has
    // room to render without being clipped at the surface edge.
    property int shadowMargin: 24
    property int pillHeight: 48

    // Bar indicators use a fixed width; text indicators size to their label,
    // both capped at half the screen width.
    property int minPillWidth: 180
    property int barModeWidth: 260
    readonly property int maxPillWidth: Math.round((screen ? screen.width : 1920) * 0.5)
    readonly property int pillWidth: {
        const content = _showBar
            ? barModeWidth
            : Math.ceil(16 + glyph.implicitWidth + 14 + mediaLabel.implicitWidth + 16);
        return Math.max(minPillWidth, Math.min(maxPillWidth, content));
    }

    // Keep the sink/source bound so their audio sub-objects stay populated.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    // Bottom-center overlay; anchoring only the bottom edge lets layer-shell
    // center it horizontally.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors.bottom: true
    margins.bottom: 90 - shadowMargin
    exclusiveZone: 0
    color: "transparent"
    implicitWidth: pillWidth + shadowMargin * 2
    implicitHeight: pillHeight + shadowMargin * 2

    // Only the pill and close button take input; the shadow headroom is
    // click-through.
    mask: Region {
        Region { item: pill }
        Region { item: closeBtn }
    }

    property string _icon: ""
    property string _label: ""
    property real _level: 0          // 0..1, drives the bar
    property bool _showBar: true     // false for mic / lock toggles
    property bool _danger: false     // muted / off → bar+icon use the danger color
    property string _mode: ""        // "volume" enables drag-to-set on the bar

    property bool _open: false
    property real _vis: _open ? 1 : 0
    Behavior on _vis {
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
    }
    visible: _vis > 0.001

    Timer {
        id: hideTimer
        interval: osd.hideMs
        onTriggered: osd._open = false
    }

    // Gate startup: suppress the settling burst so we don't flash on launch.
    property bool _ready: false
    Timer {
        id: readyTimer
        interval: 700
        running: true
        onTriggered: osd._ready = true
    }

    function _show(icon, label, level, showBar, danger, mode) {
        _icon = icon;
        _label = label;
        _level = level;
        _showBar = showBar;
        _danger = danger;
        _mode = mode || "";
        _open = true;
        // Pin open while hovered (reading / dragging the slider).
        if (hover.hovered) hideTimer.stop();
        else hideTimer.restart();
    }

    // Plugin contract: plugins under plugins/ call show(...) on change, gated
    // on `ready`. New indicators should be added as plugins.
    function show(icon, label, level, showBar, danger) {
        _show(icon, label, level, showBar, danger);
    }
    readonly property bool ready: _ready

    // Media play/pause + current track.
    MprisPlugin { osd: osd }

    // ── Volume / mute (reactive) ────────────────────────────────────────────
    readonly property var _sinkAudio: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio
        ? Pipewire.defaultAudioSink.audio : null

    Connections {
        target: osd._sinkAudio
        function onVolumeChanged() { if (osd._ready) osd._showVolume() }
        function onMutedChanged()  { if (osd._ready) osd._showVolume() }
    }

    function _showVolume() {
        const a = osd._sinkAudio;
        if (!a) return;
        const v = a.volume;
        const muted = a.muted;
        const icon = (muted || v <= 0.001) ? "󰝟"
            : (v < 0.34 ? "󰕿" : (v < 0.67 ? "󰖀" : "󰕾"));
        osd._show(icon, Math.round(v * 100) + "%", Math.min(1, v), true, muted, "volume");
    }

    // ── Mic mute (reactive) ─────────────────────────────────────────────────
    readonly property var _srcAudio: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio
        ? Pipewire.defaultAudioSource.audio : null

    Connections {
        target: osd._srcAudio
        function onMutedChanged() { if (osd._ready) osd._showMic() }
    }

    function _showMic() {
        const a = osd._srcAudio;
        if (!a) return;
        osd._show(a.muted ? "󰍭" : "󰍬",
                  a.muted ? "Mic muted" : "Mic on",
                  0, false, a.muted);
    }

    // ── Brightness (IPC-triggered) ──────────────────────────────────────────
    // Reads the first /sys/class/backlight device's current percentage. Empty
    // output (no backlight, e.g. a desktop) simply shows nothing.
    Process {
        id: brightnessProc
        command: ["sh", "-c",
            "dev=$(ls -1 /sys/class/backlight 2>/dev/null | head -n1); " +
            "[ -n \"$dev\" ] && brightnessctl -d \"$dev\" -m | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = parseInt(this.text.trim());
                if (!isNaN(p))
                    osd._show("󰃟", p + "%", Math.min(1, p / 100), true, false);
            }
        }
    }

    // ── Caps / Num lock (polled LED state) ──────────────────────────────────
    property int _capsState: -1
    property int _numState: -1

    Timer {
        interval: 350
        running: true
        repeat: true
        onTriggered: if (!lockProc.running) lockProc.running = true
    }

    Process {
        id: lockProc
        command: ["sh", "-c",
            "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | head -n1; " +
            "cat /sys/class/leds/*::numlock/brightness 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: osd._onLocks(this.text)
        }
    }

    function _onLocks(txt) {
        const parts = (txt || "").trim().split("\n");
        const caps = parseInt((parts[0] || "0").trim()) ? 1 : 0;
        const num  = parseInt((parts[1] || "0").trim()) ? 1 : 0;
        // First poll just records the baseline — never flashes on startup.
        if (osd._capsState === -1) {
            osd._capsState = caps;
            osd._numState = num;
            return;
        }
        if (caps !== osd._capsState) {
            osd._capsState = caps;
            osd._show("󰪛", "Caps Lock " + (caps ? "on" : "off"), 0, false, !caps);
        }
        if (num !== osd._numState) {
            osd._numState = num;
            osd._show("󰎠", "Num Lock " + (num ? "on" : "off"), 0, false, !num);
        }
    }

    // ── IPC surface ─────────────────────────────────────────────────────────
    IpcHandler {
        target: "osd"
        function brightness() { brightnessProc.running = true }
        function volume()     { osd._showVolume() }
        function mic()        { osd._showMic() }
    }

    // ── The pill ─────────────────────────────────────────────────────────────
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: osd.shadowMargin
        width: osd.pillWidth
        height: osd.pillHeight
        radius: osd.theme.radius
        color: Qt.rgba(osd.theme.bg.r, osd.theme.bg.g, osd.theme.bg.b, osd.theme.surfaceOpacity)
        border.color: osd.theme.border
        border.width: 1

        opacity: osd._vis
        transform: Translate { y: (1 - osd._vis) * 14 }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.18
            shadowBlur: 1.0
            shadowVerticalOffset: 6
            shadowHorizontalOffset: 0
        }

        readonly property color _fillColor: osd._danger ? osd.theme.danger : osd.theme.accent

        // Hovering pins the OSD open; leaving restarts the full auto-hide timer.
        HoverHandler {
            id: hover
            onHoveredChanged: {
                if (hovered) hideTimer.stop();
                else if (osd._open) hideTimer.restart();
            }
        }

        Text {
            id: glyph
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: osd._icon
            color: osd._danger ? osd.theme.danger : osd.theme.fg
            font.family: osd.fontFamily
            font.pixelSize: 22
        }

        // Percentage / state text on the right (bar mode only).
        Text {
            id: valueText
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: osd._label
            color: osd.theme.subFg
            font.family: osd.fontFamily
            font.pixelSize: 12
            horizontalAlignment: Text.AlignRight
            width: osd._showBar ? 38 : 0
            visible: osd._showBar
        }

        // Progress bar (volume / brightness).
        Rectangle {
            id: track
            visible: osd._showBar
            anchors.left: glyph.right
            anchors.leftMargin: 14
            anchors.right: valueText.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: osd.theme.radius
            color: osd.theme.border

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, Math.min(1, osd._level))
                radius: osd.theme.radius
                color: pill._fillColor
                Behavior on width {
                    NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                }
            }

            // Drag (or click) anywhere along the bar to set the volume. Only
            // active in volume mode — brightness/other bars stay read-only. The
            // hit area is taller than the 6px track so it's easy to grab.
            MouseArea {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 24
                enabled: osd._mode === "volume" && osd._sinkAudio
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: (mouse) => _setVolume(mouse.x)
                onPositionChanged: (mouse) => { if (pressed) _setVolume(mouse.x); }

                function _setVolume(x) {
                    const r = Math.max(0, Math.min(1, x / width));
                    if (osd._sinkAudio) osd._sinkAudio.volume = r;
                }
            }
        }

        // Message label (media / mic / lock) — replaces the bar. Its natural
        // implicitWidth drives the pill width (see osd.pillWidth) and it elides
        // once the pill hits the 50%-screen cap.
        Text {
            id: mediaLabel
            visible: !osd._showBar
            anchors.left: glyph.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: osd._label
            color: osd.theme.fg
            font.family: osd.fontFamily
            font.pixelSize: 13
            elide: Text.ElideRight
        }
    }

    HoverHandler { id: osdHover }

    Rectangle {
        id: closeBtn
        anchors.horizontalCenter: pill.right
        anchors.verticalCenter: pill.top
        width: 22
        height: 22
        radius: 11

        visible: opacity > 0.001
        opacity: (osd._open && osdHover.hovered) ? osd._vis : 0
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
        color: Qt.rgba(osd.theme.bg.r, osd.theme.bg.g, osd.theme.bg.b, 0.98)
        border.color: osd.theme.border
        border.width: 1
        z: 10

        Text {
            anchors.centerIn: parent
            text: "×"
            color: closeHover.hovered ? osd.theme.fg : osd.theme.subFg
            font.family: osd.fontFamily
            font.pixelSize: closeHover.hovered ? 17 : 16
            font.weight: closeHover.hovered ? Font.Bold : Font.Normal
            Behavior on font.pixelSize { NumberAnimation { duration: 120 } }
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        HoverHandler { id: closeHover }
        TapHandler {
            onTapped: {
                hideTimer.stop();
                osd._open = false;
            }
        }
    }
}
