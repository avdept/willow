// Apps provider — lists `.desktop` apps via Quickshell.DesktopEntries and
// fuzzy-matches against the query. Activation launches via `uwsm-app` so
// the process gets a proper systemd user scope.

import QtQuick
import Quickshell
import Quickshell.Io

Provider {
    id: prov

    name: "Apps"
    tag: "app"
    iconText: "󰘳"
    description: "Search and launch applications"
    scoreMultiplier: 1.5

    // Walker uses 256 as its cap; we follow.
    property int maxResults: 256

    // Cached entry snapshot, sorted alphabetically.
    property var _entries: []

    // name -> absolute file path, for icons that live OUTSIDE any icon theme
    // tree (e.g. /usr/share/icons/zed.png). Built at startup since
    // Quickshell.iconPath only knows about themed icons.
    property var _extraIconIndex: ({})

    // Set of .desktop file ids (basename minus extension) containing
    // `Hidden=true`. Per XDG spec, such entries must be treated as absent.
    // Omarchy uses this to mask system apps from the launcher.
    property var _hiddenIds: ({})

    readonly property string _genericIconUrl: Quickshell.iconPath("application-x-executable", true) || ""

    Component.onCompleted: {
        extraIconScan.running = true;
        hiddenScan.running = true;
        _rebuildEntries();
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            prov._rebuildEntries();
        }
    }

    Process {
        id: hiddenScan
        running: false
        command: ["sh", "-c", `
            for f in ~/.local/share/applications/*.desktop \\
                     /usr/local/share/applications/*.desktop \\
                     /usr/share/applications/*.desktop; do
                [ -f "$f" ] || continue
                if grep -qE '^Hidden=true' "$f"; then
                    b=\${f##*/}; printf '%s\\n' "\${b%.desktop}"
                fi
            done 2>/dev/null | sort -u
        `]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                if (line)
                    prov._hiddenIds[line] = true;
            }
        }
        onRunningChanged: if (!running)
            prov._rebuildEntries()
    }

    Process {
        id: extraIconScan
        running: false
        command: ["sh", "-c", `
            find /usr/share/icons /usr/share/pixmaps \\
                 ~/.local/share/icons ~/.icons \\
                 -maxdepth 1 -type f \\
                 \\( -name '*.png' -o -name '*.svg' -o -name '*.xpm' \\) \\
                 2>/dev/null
        `]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                if (!line)
                    return;
                const slash = line.lastIndexOf("/");
                const base = slash >= 0 ? line.slice(slash + 1) : line;
                const dot = base.lastIndexOf(".");
                const name = dot >= 0 ? base.slice(0, dot) : base;
                const ix = prov._extraIconIndex;
                if (!ix[name])
                    ix[name] = line;
                const lc = name.toLowerCase();
                if (!ix[lc])
                    ix[lc] = line;
            }
        }
        onRunningChanged: if (!running)
            prov._rebuildEntries()
    }

    function _resolveIconUrl(raw) {
        if (!raw)
            return _genericIconUrl;
        if (raw.charAt(0) === "/")
            return "file://" + raw;

        const fromIndex = _lookupExtra(raw);
        if (fromIndex)
            return "file://" + fromIndex;

        // The (name, check: bool) overload returns "" when the icon isn't
        // resolvable — that's the gate we need to avoid handing the provider
        // a name that would WARN-spam on load.
        const themed = Quickshell.iconPath(raw, true);
        if (themed)
            return themed;

        return _genericIconUrl;
    }

    function _lookupExtra(raw) {
        const ix = _extraIconIndex;
        if (ix[raw])
            return ix[raw];
        const lc = raw.toLowerCase();
        if (ix[lc])
            return ix[lc];
        // Some Icon= values carry an extension; strip and retry.
        const dot = raw.lastIndexOf(".");
        if (dot > 0) {
            const stripped = raw.slice(0, dot);
            if (ix[stripped])
                return ix[stripped];
            const sl = stripped.toLowerCase();
            if (ix[sl])
                return ix[sl];
        }
        return "";
    }

    function _rebuildEntries() {
        const out = [];
        const list = DesktopEntries.applications.values;
        for (let i = 0; i < list.length; i++) {
            const e = list[i];
            if (!e || e.noDisplay)
                continue;
            if (e.id && _hiddenIds[e.id])
                continue;
            const nm = (e.name || "").trim();
            if (!nm)
                continue;
            const comment = (e.comment || e.genericName || "").trim();
            out.push({
                entry: e,
                name: nm,
                nameLower: nm.toLowerCase(),
                comment: comment,
                commentLower: comment.toLowerCase(),
                iconUrl: _resolveIconUrl((e.icon || "").trim())
            });
        }
        out.sort((a, b) => a.nameLower.localeCompare(b.nameLower));
        _entries = out;
        refresh();
    }

    function search(text) {
        const q = norm(text);
        if (q.length === 0) {
            results = _entries.map(it => _toResult(it, 0));
            return;
        }
        const scored = [];
        for (let i = 0; i < _entries.length; i++) {
            const it = _entries[i];
            const s = scoreText(q, it.nameLower, it.commentLower);
            if (s > 0) scored.push({ it: it, s: s });
        }
        scored.sort((a, b) => b.s - a.s);
        if (scored.length > maxResults)
            scored.length = maxResults;
        results = scored.map(x => _toResult(x.it, x.s));
    }

    function _toResult(it, score) {
        return {
            title: it.name,
            subtitle: it.comment,
            iconUrl: it.iconUrl,
            score: score,
            data: {
                entry: it.entry
            }
        };
    }

    function activate(result) {
        const entry = result?.data?.entry;
        if (!entry)
            return;
        const cmd = entry.command || [];
        if (cmd.length === 0) {
            try {
                entry.execute();
            } catch (e) {
                console.warn("[AppsProvider] entry.execute failed:", e);
            }
            return;
        }
        const argv = entry.runInTerminal
            ? ["uwsm-app", "--", "xdg-terminal-exec", "--"].concat(cmd)
            : ["uwsm-app", "--"].concat(cmd);
        openExternal(argv, { cwd: entry.workingDirectory || "" });
    }
}
