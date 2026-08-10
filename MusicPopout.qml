// Music popout — album art, track meta, progress bar, controls, audio visualizer.
// Sections stack inside the Popout's Column (no fixed popupHeight).

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.Mpris

Popout {
    id: musicPopout

    popupWidth: 340
    contentSpacing: 10
    contentPaddingBottom: 0    // visualizer sits flush with the popup's bottom edge

    readonly property var player: {
        const list = Mpris.players.values;
        for (let i = 0; i < list.length; i++)
            if (list[i].playbackState === MprisPlaybackState.Playing)
                return list[i];
        for (let i = 0; i < list.length; i++)
            if (list[i].playbackState === MprisPlaybackState.Paused)
                return list[i];
        for (let i = 0; i < list.length; i++)
            if (list[i].trackTitle)
                return list[i];
        return null;
    }

    // Local position ticker — MPRIS pushes `position` infrequently, so we
    // increment it locally every second and resync whenever the player
    // actually pushes (seek, track change, sporadic update).
    property real displayedPosition: 0

    Timer {
        interval: 1000
        running: musicPopout.open && (musicPopout.player?.isPlaying ?? false)
        repeat: true
        onTriggered: musicPopout.displayedPosition += 1
    }

    Connections {
        target: musicPopout.player
        function onPositionChanged() {
            if (musicPopout.player)
                musicPopout.displayedPosition = musicPopout.player.position;
        }
        function onTrackTitleChanged() {
            if (musicPopout.player)
                musicPopout.displayedPosition = musicPopout.player.position;
        }
    }

    Connections {
        target: musicPopout
        function onOpenChanged() {
            if (musicPopout.open && musicPopout.player)
                musicPopout.displayedPosition = musicPopout.player.position;
        }
    }

    // ── Top row: album art + track meta ──────────────────────────────────
    Row {
        id: topRow
        width: parent.width
        height: 60
        spacing: 12

        Rectangle {
            id: artBox
            width: 60
            height: 60
            radius: musicPopout.cornerRadius
            color: musicPopout.borderColor
            clip: true

            Image {
                id: art
                anchors.fill: parent
                source: musicPopout.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: !art.visible
                text: "󰝚"
                color: musicPopout.bgColor
                font.pixelSize: 28
            }
        }

        Column {
            width: topRow.width - artBox.width - topRow.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                width: parent.width
                text: musicPopout.player?.trackTitle ?? "Nothing playing"
                color: musicPopout.fgColor
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: musicPopout.player?.trackArtist ?? ""
                color: musicPopout.fgColor
                font.pixelSize: 12
                elide: Text.ElideRight
                visible: text.length > 0
            }
            Text {
                width: parent.width
                text: musicPopout.player?.trackAlbum ?? ""
                color: musicPopout.fgColor
                font.pixelSize: 11
                opacity: 0.65
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }
    }

    // ── Progress: [elapsed]  [bar]  [total] ──────────────────────────────
    RowLayout {
        width: parent.width
        spacing: 8

        function fmtTime(s) {
            if (!s || s < 0 || !isFinite(s))
                return "0:00";
            const total = Math.floor(s);
            const m = Math.floor(total / 60);
            const sec = total % 60;
            return m + ":" + (sec < 10 ? "0" + sec : sec);
        }

        Text {
            text: parent.fmtTime(musicPopout.displayedPosition)
            color: musicPopout.fgColor
            opacity: 0.7
            font.pixelSize: 11
            Layout.alignment: Qt.AlignVCenter
        }

        MouseArea {
            id: progressArea
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            Layout.alignment: Qt.AlignVCenter
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: musicPopout.player?.canSeek ?? false

            onClicked: function (mouse) {
                const p = musicPopout.player;
                if (!p || !p.canSeek || !p.length || p.length <= 0)
                    return;
                const ratio = Math.max(0, Math.min(1, mouse.x / width));
                const targetSec = ratio * p.length;
                const offset = targetSec - p.position;
                p.seek(offset);
                musicPopout.displayedPosition = targetSec;
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: musicPopout.borderColor
                opacity: 0.55
            }
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: height / 2
                color: musicPopout.fgColor
                width: {
                    const p = musicPopout.player;
                    if (!p || !p.length || p.length <= 0)
                        return 0;
                    return parent.width * Math.max(0, Math.min(1, musicPopout.displayedPosition / p.length));
                }
            }
        }

        Text {
            text: parent.fmtTime(musicPopout.player?.length ?? 0)
            color: musicPopout.fgColor
            opacity: 0.7
            font.pixelSize: 11
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // ── Controls ─────────────────────────────────────────────────────────
    Item {
        width: parent.width
        height: 36

        Row {
            anchors.centerIn: parent
            spacing: 14

            MouseArea {
                width: 28
                height: 28
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: musicPopout.player?.canGoPrevious ?? false
                onClicked: musicPopout.player?.previous()

                Text {
                    anchors.centerIn: parent
                    text: "󰒮"
                    color: musicPopout.fgColor
                    font.pixelSize: 18
                    opacity: parent.enabled ? 1.0 : 0.3
                }
            }

            MouseArea {
                width: 36
                height: 36
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: musicPopout.player?.canTogglePlaying ?? false
                onClicked: musicPopout.player?.togglePlaying()

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: musicPopout.fgColor
                    opacity: parent.enabled ? 1.0 : 0.3
                }
                Text {
                    anchors.centerIn: parent
                    text: musicPopout.player?.isPlaying ? "󰏤" : "󰐊"
                    color: musicPopout.bgColor
                    font.pixelSize: 16
                }
            }

            MouseArea {
                width: 28
                height: 28
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: musicPopout.player?.canGoNext ?? false
                onClicked: musicPopout.player?.next()

                Text {
                    anchors.centerIn: parent
                    text: "󰒭"
                    color: musicPopout.fgColor
                    font.pixelSize: 18
                    opacity: parent.enabled ? 1.0 : 0.3
                }
            }
        }
    }

    // ── Audio visualizer (cava) ──────────────────────────────────────────
    Item {
        id: visualizerRow
        width: parent.width
        height: 22

        property var values: []
        readonly property int barCount: 32
        readonly property real barWidth: (width - (barCount - 1) * 2) / barCount

        Row {
            anchors.fill: parent
            spacing: 2

            Repeater {
                model: visualizerRow.barCount
                delegate: Rectangle {
                    id: bar
                    required property int index
                    readonly property real value: Math.min(1, (visualizerRow.values[index] ?? 0) / 100)

                    width: visualizerRow.barWidth
                    anchors.bottom: parent.bottom
                    radius: 2
                    height: Math.max(1, bar.value * visualizerRow.height)

                    color: {
                        const v = bar.value;
                        const lo = musicPopout.accentColor;
                        const hi = musicPopout.dangerColor;
                        return Qt.rgba(lo.r * (1 - v) + hi.r * v, lo.g * (1 - v) + hi.g * v, lo.b * (1 - v) + hi.b * v, 1.0);
                    }
                    opacity: 0.25 + bar.value * 0.75

                    Behavior on height {
                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 90
                        }
                    }
                }
            }
        }
    }

    // ── cava process: only runs while the popup is open ──────────────────
    Process {
        id: cavaProc
        running: musicPopout.open
        command: ["cava", "-p", "/home/avdept/.config/quickshell/cava.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const t = line.trim();
                if (!t)
                    return;
                const arr = t.split(";").map(parseFloat).filter(n => !isNaN(n));
                if (arr.length > 0)
                    visualizerRow.values = arr;
            }
        }
    }
}
