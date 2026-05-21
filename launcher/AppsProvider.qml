// Apps provider — lists `.desktop` apps via Quickshell.DesktopEntries
// and fuzzy-matches against the query. Activation runs the app.

import QtQuick
import Quickshell
import Quickshell.Io

Provider {
    id: prov

    name: "Apps"
    tag: "app"
    iconText: ""
    description: "Search and launch applications"
    prefix: ""   // always-on

    // Tunables — walker uses 256; we cap searches but show all apps on empty.
    property int maxResults: 256

    // Cached snapshot of [{ entry, name, comment, iconUrl }] to avoid
    // scanning .desktop entries and resolving icons on every keystroke.
    property var _entries: []

    // Index of icons that live OUTSIDE of any theme tree:
    // /usr/share/icons/<name>.<ext> and /usr/share/pixmaps/<name>.<ext>.
    // Quickshell.iconPath only resolves themed icons, so we probe these
    // legacy locations ourselves at startup.
    property var _extraIconIndex: ({})
    property bool _extraIconsReady: false

    // Set of .desktop file IDs (basename without extension) that contain
    // `Hidden=true`. XDG spec says such entries must be treated as if absent.
    // Used by omarchy to mask system apps it doesn't want in the launcher.
    property var _hiddenIds: ({})

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
        command: ["sh", "-c", "for f in " + "~/.local/share/applications/*.desktop " + "/usr/local/share/applications/*.desktop " + "/usr/share/applications/*.desktop; do " + "  [ -f \"$f\" ] || continue; " + "  if grep -qE '^Hidden=true' \"$f\"; then " + "    b=${f##*/}; printf '%s\\n' \"${b%.desktop}\"; " + "  fi; " + "done 2>/dev/null | sort -u"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                if (!line)
                    return;
                prov._hiddenIds[line] = true;
            }
        }
        onRunningChanged: {
            if (!running)
                prov._rebuildEntries();
        }
    }

    Process {
        id: extraIconScan
        running: false
        command: ["sh", "-c", "find /usr/share/icons /usr/share/pixmaps " + "~/.local/share/icons ~/.icons " + "-maxdepth 1 -type f " + "\\( -name '*.png' -o -name '*.svg' -o -name '*.xpm' \\) 2>/dev/null"]
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
        onRunningChanged: {
            if (!running) {
                prov._extraIconsReady = true;
                prov._rebuildEntries();
            }
        }
    }

    function _placeholderUrl() {
        // Use the themed generic if it resolves; otherwise let the delegate
        // fall through to the nerd-font glyph (empty source → not Ready).
        return Quickshell.iconPath("application-x-executable", true) || "";
    }

    function _resolveIconUrl(raw) {
        // .desktop Icon= can be: empty, an absolute path, or a name.
        if (!raw || raw.length === 0)
            return _placeholderUrl();
        if (raw.charAt(0) === "/")
            return "file://" + raw;

        // 1. Unthemed file index (probed at startup from /usr/share/icons/*,
        //    /usr/share/pixmaps/*, ~/.local/share/icons/*, ~/.icons/*).
        const ix = _extraIconIndex;
        if (ix[raw])
            return "file://" + ix[raw];
        const lc = raw.toLowerCase();
        if (ix[lc])
            return "file://" + ix[lc];

        // 2. Try stripping a trailing extension and re-checking the index.
        const dot = raw.lastIndexOf(".");
        if (dot > 0) {
            const stripped = raw.slice(0, dot);
            if (ix[stripped])
                return "file://" + ix[stripped];
            const sl = stripped.toLowerCase();
            if (ix[sl])
                return "file://" + ix[sl];
        }

        // 3. Active icon theme — the (name, check: bool) overload actually
        //    verifies the icon exists and returns "" if not (vs. the plain
        //    `iconPath(name)` which always returns "image://icon/<name>"
        //    even for unknown names, producing WARN spam on load).
        const themed = Quickshell.iconPath(raw, true);
        if (themed && themed.length > 0)
            return themed;

        // 4. Nothing resolved — placeholder.
        return _placeholderUrl();
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
            if (nm.length === 0)
                continue;
            const iconName = (e.icon || "").trim();
            const iconUrl = _resolveIconUrl(iconName);
            out.push({
                entry: e,
                name: nm,
                nameLower: nm.toLowerCase(),
                comment: (e.comment || e.genericName || "").trim(),
                commentLower: (e.comment || e.genericName || "").toLowerCase(),
                iconName: iconName,
                iconUrl: iconUrl
            });
        }
        // Stable alphabetical order, so empty-query lists are predictable.
        out.sort((a, b) => a.nameLower.localeCompare(b.nameLower));
        _entries = out;
        // Re-run search if there's a live query
        if (query.length > 0)
            search(effectiveQuery() ?? "");
        else
            search("");
    }

    function search(text) {
        const q = (text || "").toLowerCase().trim();

        if (q.length === 0) {
            // Empty query: show the full app list (entries are already sorted).
            const out = new Array(_entries.length);
            for (let i = 0; i < _entries.length; i++)
                out[i] = _toResult(_entries[i], 0);
            results = out;
            return;
        }

        const scored = [];
        for (let i = 0; i < _entries.length; i++) {
            const it = _entries[i];
            const s = _score(it, q);
            if (s > 0)
                scored.push({
                    it: it,
                    s: s
                });
        }
        scored.sort((a, b) => b.s - a.s);
        const out = [];
        for (let i = 0; i < scored.length && i < maxResults; i++) {
            out.push(_toResult(scored[i].it, scored[i].s));
        }
        results = out;
    }

    function _toResult(it, score) {
        return {
            title: it.name,
            subtitle: it.comment,
            iconName: it.iconName,
            iconUrl: it.iconUrl,
            iconText: "",
            score: score,
            data: {
                entry: it.entry
            }
        };
    }

    // Score: higher = better. 0 = no match.
    function _score(it, q) {
        const n = it.nameLower;
        const c = it.commentLower;
        if (n === q)
            return 1000;
        if (n.startsWith(q))
            return 500 + (50 - Math.min(n.length, 50));
        const wb = _wordBoundaryMatch(n, q);
        if (wb > 0)
            return 200 + wb;
        if (n.indexOf(q) !== -1)
            return 100;
        if (c.indexOf(q) !== -1)
            return 40;
        if (_subseq(n, q))
            return 20;
        return 0;
    }

    function _wordBoundaryMatch(name, q) {
        // Score initials: "Visual Studio Code" + "vsc" => match
        const parts = name.split(/[\s\-_./]+/);
        if (parts.length === 0)
            return 0;
        let qi = 0;
        let hit = 0;
        for (let i = 0; i < parts.length && qi < q.length; i++) {
            if (parts[i].length === 0)
                continue;
            if (parts[i][0] === q[qi]) {
                qi++;
                hit++;
            }
        }
        return qi === q.length ? hit * 10 : 0;
    }

    function _subseq(haystack, needle) {
        let i = 0;
        for (let j = 0; j < haystack.length && i < needle.length; j++) {
            if (haystack[j] === needle[i])
                i++;
        }
        return i === needle.length;
    }

    function activate(result) {
        const entry = result?.data?.entry;
        if (!entry) {
            console.warn("[AppsProvider] activate called with no entry");
            return;
        }
        const cmd = entry.command || [];
        if (cmd.length === 0) {
            try {
                entry.execute();
            } catch (e) {
                console.warn("[AppsProvider] entry.execute failed:", e);
            }
            return;
        }
        const argv = entry.runInTerminal ? ["uwsm-app", "--", "xdg-terminal-exec", "--"].concat(cmd) : ["uwsm-app", "--"].concat(cmd);
        if (launchProc.running)
            launchProc.running = false;
        launchProc.command = argv;
        launchProc.workingDirectory = entry.workingDirectory || "";
        launchProc.running = true;
    }

    Process {
        id: launchProc
        running: false
    }
}
