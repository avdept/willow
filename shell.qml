//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import "shared"
import "modules/osd"

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
    readonly property color cSuccess: theme.success
    // Font is user-configurable via the Settings window (Config singleton).
    readonly property string fontFamily: Config.fontFamily

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    // Password-only QuickShell lock screen (WlSessionLock + PAM), trigger
    // manually for now via: qs ipc call lock lock — see Lock.qml for status.
    Lock {
        bgColor: root.cBg
        fgColor: root.cFg
        accentColor: root.cAccent
        borderColor: root.cBorder
        dangerColor: root.cDanger
        warnColor: root.cWarn
        cornerRadius: theme.radius
        fontFamily: root.fontFamily
    }

    // Spotlight-style launcher (single instance across all screens).
    // Toggle via: qs ipc call launcher toggle
    Launcher {
        id: launcher
        theme: theme
        fontFamily: root.fontFamily
        onSettingsRequested: settingsWindow.open = true
    }

    // Notification drawer (right-side panel) + transient toasts.
    // Toggle drawer via: qs ipc call notifs toggle
    // The drawer reads from the FDN daemon in shared/NotificationManager.qml;
    // while swaync is running it will own the bus and no notifications will
    // reach the QS daemon — the UI still renders for visual review.
    NotificationDrawer {
        id: notificationDrawer
        theme: theme
        fontFamily: root.fontFamily
    }
    NotificationToasts {
        id: notificationToasts
        theme: theme
        fontFamily: root.fontFamily
        drawerOpen: notificationDrawer.open
        toastDurationMs: Config.toastDurationMs
    }

    // Volume / mic / brightness / lock OSD (bottom-center). Replaces swayosd.
    // Brightness is driven by `qs ipc call osd brightness` from the media keys.
    Osd {
        id: osd
        theme: theme
        fontFamily: root.fontFamily
        hideMs: Config.osdHideMs
    }

    // Fires a desktop notification ahead of timed calendar events (same
    // vdirsyncer source as the launcher calendar). Sticky by default, so an
    // upcoming-event reminder stays on screen until dismissed. Tune lead times
    // here, e.g. leadsMin: [60, 10, 0].
    CalendarReminders {
        id: calendarReminders
        leadsMin: Config.reminderLeadsMin
    }

    // Standalone settings window (real floating window, not a layer-shell
    // popup). Toggle via `qs ipc call settings toggle` or the bar gear icon.
    SettingsWindow {
        id: settingsWindow
        theme: theme
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
                cornerRadius: theme.radius
                bgColor: root.cBg
                borderColor: root.cBorder
                fgColor: root.cFg
                accentColor: root.cAccent
                dangerColor: root.cDanger
            }

            Tooltip {
                id: cpuTooltip
                bar: bar
                anchorItem: cpuArea
                bgColor: root.cBg
                borderColor: root.cBorder
                fgColor: root.cFg
                text: cpuProc.pct >= 0 ? "CPU " + cpuProc.pct + "%" : ""

                Timer {
                    interval: 2500
                    running: cpuTooltip.open
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: if (!cpuProc.running)
                        cpuProc.running = true
                }
                Process {
                    id: cpuProc
                    property int pct: -1
                    property var perCore: []
                    command: ["sh", "-c", "t1=$(mktemp); t2=$(mktemp); grep '^cpu' /proc/stat > \"$t1\"; sleep 0.3; grep '^cpu' /proc/stat > \"$t2\"; paste \"$t1\" \"$t2\" | awk '{ total1=$2+$3+$4+$5+$6+$7+$8+$9; idle1=$5+$6; total2=$11+$12+$13+$14+$15+$16+$17+$18; idle2=$14+$15; dt=total2-total1; di=idle2-idle1; pct=(dt>0)?int(100*(dt-di)/dt):0; print $1, pct }'; rm -f \"$t1\" \"$t2\""]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const cores = [];
                            let total = -1;
                            const lines = this.text.trim().split("\n");
                            for (const line of lines) {
                                const parts = line.trim().split(/\s+/);
                                if (parts.length < 2)
                                    continue;
                                const val = parseInt(parts[1], 10) || 0;
                                if (parts[0] === "cpu")
                                    total = val;
                                else
                                    cores.push(val);
                            }
                            cpuProc.pct = total;
                            cpuProc.perCore = cores;
                        }
                    }
                }

                Grid {
                    columns: Math.max(1, Math.ceil(Math.sqrt(cpuProc.perCore.length)))
                    rowSpacing: 2
                    columnSpacing: 10

                    Repeater {
                        model: cpuProc.perCore
                        Text {
                            width: 46
                            color: root.cFg
                            font.pixelSize: 11
                            text: "C" + index + "  " + modelData + "%"
                        }
                    }
                }
            }

            Tooltip {
                id: wifiTooltip
                bar: bar
                anchorItem: netArea
                bgColor: root.cBg
                borderColor: root.cBorder
                fgColor: root.cFg
                text: wifiProc.ssid.length > 0 ? wifiProc.ssid + " (" + wifiProc.freqGhz + ")" : ""

                Timer {
                    interval: 2500
                    running: wifiTooltip.open
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: if (!wifiProc.running)
                        wifiProc.running = true
                }
                Process {
                    id: wifiProc
                    property string ssid: ""
                    property string freqGhz: ""
                    property string rateMbps: ""
                    command: ["sh", "-c", "dev=$(ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"dev\"){print $(i+1); exit}}'); if [ -z \"$dev\" ]; then for d in /sys/class/net/*/; do n=$(basename \"$d\"); [ \"$n\" = lo ] && continue; c=$(cat \"$d\"carrier 2>/dev/null); [ \"$c\" = 1 ] && { dev=$n; break; }; done; fi; if [ -z \"$dev\" ]; then echo off; exit; fi; if [ -d \"/sys/class/net/$dev/wireless\" ]; then info=$(iw dev \"$dev\" link 2>/dev/null); ssid=$(echo \"$info\" | awk -F': ' '/SSID:/{print $2; exit}'); freq=$(echo \"$info\" | awk '/freq:/{print $2; exit}'); rate=$(echo \"$info\" | awk '/rx bitrate:/{print $3; exit}'); echo \"wifi|$ssid|$freq|$rate\"; else echo \"ethernet|$dev\"; fi"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const t = this.text.trim();
                            const parts = t.split("|");
                            if (parts[0] === "wifi" && parts.length === 4) {
                                wifiProc.ssid = parts[1];
                                wifiProc.freqGhz = (parseFloat(parts[2]) / 1000).toFixed(1) + " GHz";
                                wifiProc.rateMbps = Math.round(parseFloat(parts[3])) + " Mbps";
                            } else {
                                wifiProc.ssid = "";
                                wifiProc.freqGhz = "";
                                wifiProc.rateMbps = "";
                            }
                        }
                    }
                }

                Text {
                    visible: wifiProc.ssid.length > 0
                    color: root.cFg
                    font.pixelSize: 11
                    text: "Up to " + wifiProc.rateMbps
                }
            }

            Tooltip {
                id: audioTooltip
                bar: bar
                anchorItem: audioArea
                bgColor: root.cBg
                borderColor: root.cBorder
                fgColor: root.cFg

                readonly property var sink: Pipewire.defaultAudioSink
                readonly property string deviceLabel: {
                    const s = sink;
                    if (!s)
                        return "";
                    if (s.nickname && s.nickname.length > 0)
                        return s.nickname;
                    if (s.description && s.description.length > 0)
                        return s.description;
                    return s.name || "";
                }
                text: {
                    const s = sink;
                    if (!s || deviceLabel.length === 0)
                        return "";
                    if (!s.audio)
                        return deviceLabel;
                    if (s.audio.muted)
                        return deviceLabel + " - muted";
                    return deviceLabel + " at " + Math.round(s.audio.volume * 100) + "%";
                }
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
                        LaunchTrigger.launch(mouse.button === Qt.RightButton ? ["xdg-terminal-exec"] : ["omarchy-menu"]);
                    }

                    Text {
                        id: omarchyIcon
                        anchors.centerIn: parent
                        color: root.cFg
                        font.family: "omarchy"
                        font.pixelSize: 14
                        text: ""
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

                    onClicked: LaunchTrigger.launch(["sh", "-c", "notify-send -u low \"$(omarchy-weather-status)\""])

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
                        LaunchTrigger.launch(["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"]);
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
                }

                // Screen recording indicator — visible only while gpu-screen-recorder runs.
                MouseArea {
                    id: recordingBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    cursorShape: Qt.PointingHandCursor
                    visible: recordingProc.active

                    onClicked: LaunchTrigger.launch(["omarchy-capture-screenrecording"])

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
                }

                MouseArea {
                    id: bellArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: bellRow.implicitWidth + 4
                    height: 22
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    readonly property int unread: NotificationManager.count

                    onClicked: function (mouse) {
                        if (mouse.button === Qt.RightButton)
                            NotificationManager.clearAll();
                        else
                            notificationDrawer.open = !notificationDrawer.open;
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
                            text: bellArea.unread > 0 ? "󰂚" : "󰂜"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.cFg
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            text: bellArea.unread > 0 ? bellArea.unread.toString() : ""
                            visible: bellArea.unread > 0
                        }
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
                    spacing: 0

                    property bool expanded: false
                    readonly property int drawerGap: 6

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
                        width: trayContainer.expanded ? trayItems.implicitWidth + trayContainer.drawerGap : 0
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
                            anchors.left: parent.left
                            anchors.leftMargin: trayContainer.drawerGap
                            spacing: 14

                            Repeater {
                                model: SystemTray.items

                                delegate: MouseArea {
                                    id: trayItem
                                    required property var modelData
                                    width: 12
                                    height: 12
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                                    function _openMenu() {
                                        if (!modelData.hasMenu) return;
                                        trayMenu.anchor.rect.x = trayItem.mapToItem(bar.contentItem, 0, 0).x;
                                        trayMenu.open();
                                    }

                                    onClicked: function (mouse) {
                                        if (mouse.button === Qt.LeftButton) {
                                            if (modelData.onlyMenu) _openMenu();
                                            else                    modelData.activate();
                                        } else if (mouse.button === Qt.MiddleButton) {
                                            modelData.secondaryActivate();
                                        } else if (mouse.button === Qt.RightButton) {
                                            _openMenu();
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
                                        anchor.rect.width: trayItem.width
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

                    onClicked: LaunchTrigger.launch(["omarchy-launch-bluetooth"])

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
                }

                // Network — wifi signal / ethernet / off; click: open wifi picker
                MouseArea {
                    id: netArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    property string mode: "off"

                    onClicked: LaunchTrigger.launch(["omarchy-launch-wifi"])
                    onEntered: if (netArea.mode === "wifi")
                        wifiTooltip.open = true
                    onExited: wifiTooltip.open = false

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
                        command: ["sh", "-c", "dev=$(ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"dev\"){print $(i+1); exit}}'); if [ -z \"$dev\" ]; then for d in /sys/class/net/*/; do n=$(basename \"$d\"); [ \"$n\" = lo ] && continue; c=$(cat \"$d\"carrier 2>/dev/null); [ \"$c\" = 1 ] && { dev=$n; break; }; done; fi; if [ -z \"$dev\" ]; then echo off; exit; fi; if [ -d \"/sys/class/net/$dev/wireless\" ]; then sig=$(iw dev \"$dev\" link 2>/dev/null | awk '/signal:/{print $2; exit}'); if [ -z \"$sig\" ]; then echo off; else pct=$(( (sig + 100) * 2 )); [ \"$pct\" -lt 0 ] && pct=0; [ \"$pct\" -gt 100 ] && pct=100; echo \"wifi:$pct\"; fi; else echo ethernet; fi"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const t = this.text.trim();
                                if (t === "ethernet") {
                                    netArea.mode = "ethernet";
                                    netIcon.text = "󰀂";
                                    return;
                                }
                                if (t === "off" || t === "") {
                                    netArea.mode = "off";
                                    netIcon.text = "󰤮";
                                    return;
                                }
                                if (t.indexOf("wifi:") === 0) {
                                    netArea.mode = "wifi";
                                    const sig = parseInt(t.substring(5), 10) || 0;
                                    const icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"];
                                    const idx = Math.min(4, Math.floor(sig / 20));
                                    netIcon.text = icons[idx];
                                }
                            }
                        }
                    }
                }

                // Audio (pulseaudio) — icon only, tiered by level; left: audio manager, right: mute, scroll: volume
                MouseArea {
                    id: audioArea
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true

                    onClicked: function (mouse) {
                        if (mouse.button === Qt.RightButton) {
                            const s = Pipewire.defaultAudioSink;
                            if (s && s.audio)
                                s.audio.muted = !s.audio.muted;
                        } else {
                            LaunchTrigger.launch(["omarchy-launch-audio"]);
                        }
                    }
                    onWheel: function (wheel) {
                        const s = Pipewire.defaultAudioSink;
                        if (!s || !s.audio)
                            return;
                        const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                        s.audio.volume = Math.max(0, Math.min(1, s.audio.volume + step));
                    }
                    onEntered: audioTooltip.open = true
                    onExited: audioTooltip.open = false

                    Text {
                        id: audioText
                        anchors.centerIn: parent
                        color: {
                            const s = Pipewire.defaultAudioSink;
                            return (s && s.audio && s.audio.muted) ? root.cDanger : root.cFg;
                        }
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        text: {
                            const s = Pipewire.defaultAudioSink;
                            if (!s || !s.audio || s.audio.muted)
                                return "󰝟";
                            const pct = s.audio.volume * 100;
                            if (pct <= 33)
                                return "󰕿";
                            if (pct <= 66)
                                return "󰖀";
                            return "󰕾";
                        }
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
                    hoverEnabled: true

                    onClicked: function (mouse) {
                        LaunchTrigger.launch(mouse.button === Qt.RightButton ? ["alacritty"] : ["omarchy-launch-or-focus-tui", "btop"]);
                    }
                    onEntered: cpuTooltip.open = true
                    onExited: cpuTooltip.open = false

                    Text {
                        anchors.centerIn: parent
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        text: "󰍛"
                    }
                }

                Battery {
                    bar: bar
                    fgColor: root.cFg
                    bgColor: root.cBg
                    borderColor: root.cBorder
                    successColor: root.cSuccess
                    warnColor: root.cWarn
                    dangerColor: root.cDanger
                }
            }
        }
    }
}
// qmllint disable uncreatable-type
