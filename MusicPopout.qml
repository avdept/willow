// Music popout — album art, track meta, prev/play-pause/next controls.

import QtQuick
import Quickshell.Services.Mpris

Popout {
    id: musicPopout

    popupWidth: 340
    popupHeight: 115

    // Pick the most relevant player: prefer Playing, then Paused, then any with a title.
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

    // ── Top row: album art + track meta ──────────────────────────────────
    Row {
        id: topRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 12

        // Album art (60×60). Falls back to a music-note glyph.
        Rectangle {
            id: artBox
            width: 60
            height: 60
            radius: 6
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

        // Meta — title / artist / album, all elided
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

    // ── Controls: prev / play-pause / next, centered in the space below topRow
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        // parent.verticalCenter is the middle of contentArea; offset by half
        // of topRow.height so the Row centers in the space *below* topRow.
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: topRow.height / 2 + 8
        spacing: 14

        // Prev
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

        // Play / Pause (filled circle)
        MouseArea {
            width: 36
            height: 36
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: musicPopout.player?.canTogglePlaying ?? false
            onClicked: musicPopout.player?.togglePlaying()

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: musicPopout.accentColor
                opacity: parent.enabled ? 1.0 : 0.3
            }
            Text {
                anchors.centerIn: parent
                text: musicPopout.player?.isPlaying ? "󰏤" : "󰐊"
                color: musicPopout.bgColor
                font.pixelSize: 16
            }
        }

        // Next
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
