import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris

Scope {
    id: root

    // Colors follow the active omarchy theme (parsed from waybar.css).
    // Defaults + derivations live in Theme.qml; edit there to change them.
    Theme { id: theme }

    readonly property color cBg:     theme.bg
    readonly property color cFg:     theme.fg
    readonly property color cSubFg:  theme.subFg
    readonly property color cAccent: theme.accent
    readonly property color cBorder: theme.border
    readonly property color cDanger: theme.danger
    readonly property color cWarn:   theme.warn
    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    // Spotlight-style launcher (single instance across all screens).
    // Toggle via: qs ipc call launcher toggle
    Launcher {
        id: launcher
        theme: theme
        fontFamily: root.fontFamily
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 32
            color: root.cBg

            // ───── Drawers / popouts (separate windows attached to the bar) ─────
            MusicPopout {
                id: musicPopout
                bar: bar
                anchorItem: mprisArea
                bgColor: root.cBg
                borderColor: root.cBorder
                fgColor: root.cFg
                accentColor: root.cAccent
                dangerColor: root.cDanger
            }

            // ───── LEFT: omarchy logo + workspaces ─────
            Row {
                id: leftRow
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                MouseArea {
                    anchors.verticalCenter: parent.verticalCenter
                    width: omarchyIcon.implicitWidth
                    height: 18
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function (mouse) {
                        const cmd = mouse.button === Qt.RightButton ? ["xdg-terminal-exec"] : ["omarchy-menu"];
                        omarchyTrig.command = cmd;
                        if (!omarchyTrig.running)
                            omarchyTrig.running = true;
                    }

                    Text {
                        id: omarchyIcon
                        anchors.centerIn: parent
                        color: root.cFg
                        font.family: "omarchy"
                        font.pixelSize: 14
                        text: ""
                    }

                    Process {
                        id: omarchyTrig
                        command: ["true"]
                    }
                }

                Row {
                    id: workspacesRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    property var workspaceIds: {
                        const ids = new Set([1, 2, 3, 4, 5]);
                        const list = Hyprland.workspaces.values;
                        for (let i = 0; i < list.length; i++)
                            if (list[i].id > 0)
                                ids.add(list[i].id);
                        return Array.from(ids).sort((a, b) => a - b);
                    }

                    Repeater {
                        model: workspacesRow.workspaceIds

                        delegate: Item {
                            id: wsItem
                            required property var modelData
                            readonly property int wsId: modelData
                            readonly property var ws: {
                                const list = Hyprland.workspaces.values;
                                for (let i = 0; i < list.length; i++)
                                    if (list[i].id === wsId)
                                        return list[i];
                                return null;
                            }
                            readonly property bool isFocused: ws !== null && ws.focused

                            width: 22
                            height: 22
                            opacity: ws === null ? 0.4 : 1.0

                            Text {
                                anchors.centerIn: parent
                                text: wsItem.isFocused ? "󱓻" : (wsItem.wsId === 10 ? "0" : wsItem.wsId)
                                color: root.cFg
                                font.family: root.fontFamily
                                font.pixelSize: 12
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wsItem.ws ? wsItem.ws.activate() : Hyprland.dispatch("workspace " + wsItem.wsId)
                            }
                        }
                    }
                }

                // Spacer between workspaces and MPRIS
                Item {
                    width: 24
                    height: 1
                }

                // MPRIS — currently playing (click = play/pause, right-click = next)
                MouseArea {
                    id: mprisArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: mprisText.implicitWidth
                    height: 22

                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    visible: mprisText.text.length > 0

                    readonly property var activePlayer: {
                        const list = Mpris.players.values;
                        for (let i = 0; i < list.length; i++)
                            if (list[i].playbackState === MprisPlaybackState.Playing)
                                return list[i];
                        for (let i = 0; i < list.length; i++)
                            if (list[i].trackTitle)
                                return list[i];
                        return null;
                    }

                    onClicked: function (mouse) {
                        const p = mprisArea.activePlayer;
                        if (!p)
                            return;
                        if (mouse.button === Qt.RightButton) {
                            if (p.canGoNext)
                                p.next();
                        } else {
                            // Left click toggles the music popout
                            musicPopout.open = !musicPopout.open;
                        }
                    }

                    Text {
                        id: mprisText
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        text: {
                            const p = mprisArea.activePlayer;
                            if (!p)
                                return "";
                            const status = p.playbackState === MprisPlaybackState.Playing ? "▶" : p.playbackState === MprisPlaybackState.Paused ? "⏸" : "⏹";
                            const artist = p.trackArtist || "";
                            const title = p.trackTitle || "";
                            const meta = artist ? artist + " - " + title : title;
                            const max = 55;
                            const trunc = meta.length > max ? meta.substring(0, max - 1) + "…" : meta;
                            return status + " " + trunc;
                        }
                    }
                }
            }

            // ───── CENTER: weather · clock · update · bell · language ─────
            Row {
                id: centerRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                MouseArea {
                    id: weatherArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: weatherText.implicitWidth
                    height: 22
                    cursorShape: Qt.PointingHandCursor
                    visible: weatherText.text.length > 0

                    onClicked: {
                        weatherStatus.command = ["sh", "-c", "notify-send -u low \"$(omarchy-weather-status)\""];
                        if (!weatherStatus.running)
                            weatherStatus.running = true;
                    }

                    Text {
                        id: weatherText
                        anchors.centerIn: parent
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 22
                        text: ""
                    }

                    Timer {
                        interval: 60000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: if (!weatherProc.running)
                            weatherProc.running = true
                    }
                    Process {
                        id: weatherProc
                        command: ["omarchy-weather-icon"]
                        stdout: StdioCollector {
                            onStreamFinished: weatherText.text = this.text.trim()
                        }
                    }
                    Process {
                        id: weatherStatus
                        command: ["true"]
                    }
                }

                Text {
                    id: clock
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.cFg
                    font.family: root.fontFamily
                    font.pixelSize: 12

                    property string nowText: ""
                    text: nowText

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: {
                            const d = new Date();
                            const date = d.toLocaleDateString(Qt.locale(), "dddd d");
                            const time = d.toLocaleTimeString(Qt.locale(), "HH:mm");
                            clock.nowText = " " + date + " " + time;
                        }
                    }
                }

                MouseArea {
                    id: updateBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    cursorShape: Qt.PointingHandCursor
                    visible: updateProc.available

                    onClicked: {
                        updateTrig.command = ["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"];
                        if (!updateTrig.running)
                            updateTrig.running = true;
                        // Recheck every 30s for 5 min after click so the icon
                        // disappears soon after the user finishes updating.
                        updateRecheckTimer.attemptsLeft = 10;
                        updateRecheckTimer.restart();
                    }

                    Text {
                        anchors.centerIn: parent
                        color: root.cWarn
                        font.family: root.fontFamily
                        font.pixelSize: 16
                        text: ""
                    }

                    // Slow background poll — 10 min (waybar's 6h relied on signal-driven refresh, which qs can't catch).
                    Timer {
                        interval: 600000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: if (!updateProc.running)
                            updateProc.running = true
                    }
                    // Fast post-click rechecker — 10×30s = 5 min.
                    Timer {
                        id: updateRecheckTimer
                        interval: 30000
                        repeat: true
                        property int attemptsLeft: 0
                        onTriggered: {
                            if (!updateProc.running)
                                updateProc.running = true;
                            attemptsLeft--;
                            if (attemptsLeft <= 0 || !updateProc.available)
                                stop();
                        }
                    }
                    Process {
                        id: updateProc
                        property bool available: false
                        command: ["omarchy-update-available"]
                        onExited: function (code, _status) {
                            updateProc.available = (code === 0);
                        }
                    }
                    Process {
                        id: updateTrig
                        command: ["true"]
                    }
                }

                // Screen recording indicator — visible only while gpu-screen-recorder runs.
                MouseArea {
                    id: recordingBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    cursorShape: Qt.PointingHandCursor
                    visible: recordingProc.active

                    onClicked: {
                        recordingTrig.command = ["omarchy-capture-screenrecording"];
                        if (!recordingTrig.running)
                            recordingTrig.running = true;
                    }

                    Text {
                        anchors.centerIn: parent
                        color: root.cDanger
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        text: "󰻂"
                    }

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: if (!recordingProc.running)
                            recordingProc.running = true
                    }
                    Process {
                        id: recordingProc
                        property bool active: false
                        command: ["sh", "-c", "pgrep -f '^gpu-screen-recorder' >/dev/null && echo 1 || echo 0"]
                        stdout: StdioCollector {
                            onStreamFinished: recordingProc.active = (this.text.trim() === "1")
                        }
                    }
                    Process {
                        id: recordingTrig
                        command: ["true"]
                    }
                }

                MouseArea {
                    anchors.verticalCenter: parent.verticalCenter
                    width: bellRow.implicitWidth + 4
                    height: 22
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: function (mouse) {
                        const args = mouse.button === Qt.RightButton ? ["swaync-client", "-d", "-sw"] : ["swaync-client", "-t", "-sw"];
                        bellTrig.command = args;
                        if (!bellTrig.running)
                            bellTrig.running = true;
                        if (!bellProc.running)
                            bellProc.running = true;
                    }

                    Row {
                        id: bellRow
                        anchors.centerIn: parent
                        spacing: 3

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.cFg
                            font.family: root.fontFamily
                            font.pixelSize: 15
                            text: bellCount.unread > 0 ? "󰂚" : "󰂜"
                        }
                        Text {
                            id: bellCount
                            anchors.verticalCenter: parent.verticalCenter
                            property int unread: 0
                            color: root.cFg
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            text: unread > 0 ? unread.toString() : ""
                            visible: unread > 0
                        }
                    }

                    Timer {
                        interval: 2000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: if (!bellProc.running)
                            bellProc.running = true
                    }
                    Process {
                        id: bellProc
                        command: ["swaync-client", "-c"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const n = parseInt(this.text.trim(), 10);
                                bellCount.unread = isNaN(n) ? 0 : n;
                            }
                        }
                    }
                    Process {
                        id: bellTrig
                        command: ["true"]
                    }
                }

                MouseArea {
                    id: langArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: langText.implicitWidth + 6
                    height: 22
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("switchxkblayout current next")

                    Text {
                        id: langText
                        anchors.centerIn: parent
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                        text: "--"
                    }

                    function applyLayout(raw) {
                        const t = (raw || "").trim();
                        if (!t)
                            return;
                        const map = {
                            "english": "EN",
                            "ukrainian": "UA"
                        };
                        const first = t.toLowerCase().split(/[\s(]/)[0];
                        langText.text = map[first] || first.substring(0, 2).toUpperCase();
                    }

                    Process {
                        running: true
                        command: ["sh", "-c", "hyprctl -j devices 2>/dev/null | jq -r '.keyboards[] | select(.main==true) | .active_keymap'"]
                        stdout: StdioCollector {
                            onStreamFinished: langArea.applyLayout(this.text)
                        }
                    }

                    Connections {
                        target: Hyprland
                        function onRawEvent(event) {
                            if (event.name !== "activelayout")
                                return;
                            const idx = event.data.indexOf(",");
                            if (idx < 0)
                                return;
                            langArea.applyLayout(event.data.substring(idx + 1));
                        }
                    }
                }
            }

            // ───── RIGHT: tray · bluetooth · network · audio · cpu · battery ─────
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                // System tray with collapsible drawer (hover chevron to expand; collapses 3s after mouse leaves)
                Row {
                    id: trayContainer
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    property bool expanded: false

                    HoverHandler {
                        id: trayHover
                        onHoveredChanged: {
                            if (hovered) {
                                collapseTimer.stop();
                                trayContainer.expanded = true;
                            } else {
                                collapseTimer.restart();
                            }
                        }
                    }

                    Timer {
                        id: collapseTimer
                        interval: 3000
                        onTriggered: trayContainer.expanded = false
                    }

                    // Chevron toggle
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        text: ""
                        rotation: trayContainer.expanded ? 180 : 0
                        Behavior on rotation {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }

                    // Tray drawer
                    Item {
                        id: trayDrawer
                        anchors.verticalCenter: parent.verticalCenter
                        height: 18
                        clip: true
                        width: trayContainer.expanded ? trayItems.implicitWidth : 0
                        opacity: trayContainer.expanded ? 1 : 0

                        Behavior on width {
                            NumberAnimation {
                                duration: 250
                                easing.type: Easing.InOutQuad
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                            }
                        }

                        Row {
                            id: trayItems
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Repeater {
                                model: SystemTray.items

                                delegate: MouseArea {
                                    required property var modelData
                                    width: 12
                                    height: 12
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                                    onClicked: function (mouse) {
                                        if (mouse.button === Qt.LeftButton) {
                                            if (modelData.onlyMenu)
                                                trayMenu.open();
                                            else
                                                modelData.activate();
                                        } else if (mouse.button === Qt.MiddleButton) {
                                            modelData.secondaryActivate();
                                        } else if (mouse.button === Qt.RightButton) {
                                            if (modelData.hasMenu)
                                                trayMenu.open();
                                        }
                                    }
                                    onWheel: function (wheel) {
                                        modelData.scroll(wheel.angleDelta.y, false);
                                    }

                                    IconImage {
                                        anchors.fill: parent
                                        source: modelData.icon
                                        smooth: true
                                    }

                                    QsMenuAnchor {
                                        id: trayMenu
                                        menu: modelData.menu
                                        anchor.window: bar
                                        anchor.rect.y: bar.implicitHeight
                                        anchor.edges: Edges.Bottom
                                    }
                                }
                            }
                        }
                    }
                }

                // Bluetooth — click: open bluetooth manager
                MouseArea {
                    id: btArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    cursorShape: Qt.PointingHandCursor
                    visible: btProc.state !== "none"

                    onClicked: {
                        btTrig.command = ["omarchy-launch-bluetooth"];
                        if (!btTrig.running)
                            btTrig.running = true;
                    }

                    Text {
                        anchors.centerIn: parent
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        text: {
                            switch (btProc.state) {
                            case "off":
                                return "󰂲";
                            case "connected":
                                return "󰂱";
                            case "on":
                                return "";
                            default:
                                return "";
                            }
                        }
                    }

                    Timer {
                        interval: 5000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: if (!btProc.running)
                            btProc.running = true
                    }
                    Process {
                        id: btProc
                        property string state: "none"
                        command: ["sh", "-c", "command -v bluetoothctl >/dev/null || { echo none; exit; }; out=$(bluetoothctl show 2>/dev/null); [ -z \"$out\" ] && { echo none; exit; }; p=$(echo \"$out\" | awk '/Powered:/{print $2;exit}'); [ \"$p\" = \"no\" ] && { echo off; exit; }; n=$(bluetoothctl devices Connected 2>/dev/null | wc -l); [ \"$n\" -gt 0 ] && echo connected || echo on"]
                        stdout: StdioCollector {
                            onStreamFinished: btProc.state = this.text.trim()
                        }
                    }
                    Process {
                        id: btTrig
                        command: ["true"]
                    }
                }

                // Network — wifi signal / ethernet / off; click: open wifi picker
                MouseArea {
                    id: netArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        netTrig.command = ["omarchy-launch-wifi"];
                        if (!netTrig.running)
                            netTrig.running = true;
                    }

                    Text {
                        id: netIcon
                        anchors.centerIn: parent
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 16
                        text: "󰤮"
                    }

                    Timer {
                        interval: 3000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: if (!netProc.running)
                            netProc.running = true
                    }
                    Process {
                        id: netProc
                        command: ["sh", "-c", "type=$(nmcli -t -f STATE,TYPE device 2>/dev/null | awk -F: '$1==\"connected\"{print $2; exit}'); case \"$type\" in wifi) sig=$(nmcli -t -f IN-USE,SIGNAL dev wifi 2>/dev/null | awk -F: '/^\\*/{print $2; exit}'); echo \"wifi:${sig:-0}\";; ethernet) echo ethernet;; *) echo off;; esac"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const t = this.text.trim();
                                if (t === "ethernet") {
                                    netIcon.text = "󰀂";
                                    return;
                                }
                                if (t === "off" || t === "") {
                                    netIcon.text = "󰤮";
                                    return;
                                }
                                if (t.indexOf("wifi:") === 0) {
                                    const sig = parseInt(t.substring(5), 10) || 0;
                                    const icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"];
                                    const idx = Math.min(4, Math.floor(sig / 20));
                                    netIcon.text = icons[idx];
                                }
                            }
                        }
                    }
                    Process {
                        id: netTrig
                        command: ["true"]
                    }
                }

                // Audio (pulseaudio) — 󰋎 + vol%; left: audio manager, right: mute, scroll: volume
                MouseArea {
                    id: audioArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: audioText.implicitWidth
                    height: 12
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: function (mouse) {
                        if (mouse.button === Qt.RightButton) {
                            const s = Pipewire.defaultAudioSink;
                            if (s && s.audio)
                                s.audio.muted = !s.audio.muted;
                        } else {
                            audioTrig.command = ["omarchy-launch-audio"];
                            if (!audioTrig.running)
                                audioTrig.running = true;
                        }
                    }
                    onWheel: function (wheel) {
                        const s = Pipewire.defaultAudioSink;
                        if (!s || !s.audio)
                            return;
                        const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                        s.audio.volume = Math.max(0, Math.min(1, s.audio.volume + step));
                    }

                    Text {
                        id: audioText
                        anchors.verticalCenter: parent.verticalCenter
                        color: {
                            const s = Pipewire.defaultAudioSink;
                            return (s && s.audio && s.audio.muted) ? root.cDanger : root.cFg;
                        }
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        text: {
                            const s = Pipewire.defaultAudioSink;
                            if (!s || !s.audio)
                                return "󰋎 --";
                            return "󰋎 " + Math.round(s.audio.volume * 100) + "%";
                        }
                    }
                    Process {
                        id: audioTrig
                        command: ["true"]
                    }
                }

                // CPU — left: btop, right: terminal
                MouseArea {
                    id: cpuArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: function (mouse) {
                        const cmd = mouse.button === Qt.RightButton ? ["alacritty"] : ["omarchy-launch-or-focus-tui", "btop"];
                        cpuTrig.command = cmd;
                        if (!cpuTrig.running)
                            cpuTrig.running = true;
                    }

                    Text {
                        anchors.centerIn: parent
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        text: "󰍛"
                    }
                    Process {
                        id: cpuTrig
                        command: ["true"]
                    }
                }

                // Battery — pct% + level icon; left: power menu, right: notify status
                MouseArea {
                    id: batteryArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: batteryText.implicitWidth
                    height: 22
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    visible: UPower.displayDevice && UPower.displayDevice.isPresent

                    onClicked: function (mouse) {
                        const cmd = mouse.button === Qt.RightButton ? ["sh", "-c", "notify-send -u low \"$(omarchy-battery-status)\""] : ["omarchy-menu", "power"];
                        batTrig.command = cmd;
                        if (!batTrig.running)
                            batTrig.running = true;
                    }

                    Text {
                        id: batteryText
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        property var dev: UPower.displayDevice
                        property int pct: dev ? Math.round(dev.percentage) : 0
                        color: pct <= 10 && UPower.onBattery ? root.cDanger : pct <= 20 && UPower.onBattery ? root.cWarn : root.cFg
                        text: {
                            if (!dev)
                                return "";
                            const dischargingIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"];
                            const chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"];
                            const idx = Math.min(9, Math.max(0, Math.floor(pct / 10)));
                            const icon = UPower.onBattery ? dischargingIcons[idx] : chargingIcons[idx];
                            return pct + "% " + icon;
                        }
                    }
                    Process {
                        id: batTrig
                        command: ["true"]
                    }
                }
            }
        }
    }
}
// qmllint disable uncreatable-type
