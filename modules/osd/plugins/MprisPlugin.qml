// OSD plugin: media play/pause + current track, via MPRIS.
//
// The media keys drive playerctl, which changes MPRIS playback state / track,
// which we observe here — so the OSD shows on key presses and on changes made
// from any other source (the player UI, another keybind, etc.).
//
// Plugin contract: assign `osd`. The plugin calls osd.show(...) on changes and
// respects osd.ready (the startup-suppression gate). `osd` is typed `var` to
// avoid a circular import back onto Osd.qml.

import QtQuick
import Quickshell.Services.Mpris

QtObject {
    id: plugin

    required property var osd

    // Active player: prefer one that's playing, then paused, then anything
    // that at least has a track. Mirrors the music popout's selection.
    readonly property var player: {
        const list = Mpris.players.values;
        for (let i = 0; i < list.length; i++)
            if (list[i].playbackState === MprisPlaybackState.Playing) return list[i];
        for (let i = 0; i < list.length; i++)
            if (list[i].playbackState === MprisPlaybackState.Paused) return list[i];
        for (let i = 0; i < list.length; i++)
            if (list[i].trackTitle) return list[i];
        return null;
    }

    property Connections _conn: Connections {
        target: plugin.player
        function onPlaybackStateChanged() { plugin._present() }  // play / pause
        function onTrackTitleChanged()    { plugin._present() }  // next / prev
    }

    function _present() {
        if (!plugin.osd || !plugin.osd.ready) return;
        const p = plugin.player;
        if (!p) return;
        const title = p.trackTitle || "";
        const artist = p.trackArtist || "";
        if (!title && !artist) return;
        const label = artist ? (title + " — " + artist) : title;
        plugin.osd.show(p.isPlaying ? "󰐊" : "󰏤", label, 0, false, false);
    }
}
