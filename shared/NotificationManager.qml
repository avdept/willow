pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

NotificationServer {
    id: server

    bodySupported: true
    bodyMarkupSupported: true
    bodyImagesSupported: true
    imageSupported: true
    actionsSupported: true
    actionIconsSupported: true
    keepOnReload: true
    persistenceSupported: true

    signal newNotification(var notif)

    property var _timestamps: ({})
    property int _revision: 0
    // Drawer-visible count (transient notifications are toast-only).
    readonly property int count: {
        const v = server.trackedNotifications.values;
        let n = 0;
        for (let i = 0; i < v.length; i++)
            if (v[i] && !v[i].transient) n++;
        return n;
    }
    readonly property var groups: {
        server.count;
        server._revision;
        return server.groupedByApp();
    }

    onNotification: function (notif) {
        notif.tracked = true;
        _revision++;
        // Notifications carried over by keepOnReload re-fire this signal on
        // reload — keep them in the drawer but don't re-toast or reset age.
        if (notif.lastGeneration) {
            console.warn("[notif] lastGeneration, no toast:", notif.id, notif.appName);
            if (_timestamps[notif.id] === undefined)
                _timestamps[notif.id] = Date.now();
            return;
        }
        const firstSeen = _timestamps[notif.id] === undefined;
        // Genuinely received (new OR a replace/update): stamp as latest.
        _timestamps[notif.id] = Date.now();
        // Don't spam toasts for progress updaters — only the first emit of a
        // notification carrying a `value` hint pops; later ticks update the
        // drawer silently.
        if (!firstSeen && progressOf(notif) >= 0) {
            console.warn("[notif] progress update, no toast:", notif.id, notif.appName);
            return;
        }
        console.warn("[notif] emit newNotification:", notif.id, notif.appName,
                     "transient=" + notif.transient, "expire=" + notif.expireTimeout);
        newNotification(notif);
    }

    function isTransient(notif) {
        return !!(notif && notif.transient);
    }

    function timestampOf(notif) {
        return _timestamps[notif.id] || Date.now();
    }

    function formatAge(ts, now) {
        const diff = Math.max(0, (now || Date.now()) - ts);
        const sec = Math.floor(diff / 1000);
        if (sec < 60) return "now";
        const min = Math.floor(sec / 60);
        if (min < 60) return min + "m";
        const hr = Math.floor(min / 60);
        if (hr < 24) return hr + "h";
        const day = Math.floor(hr / 24);
        if (day < 7) return day + "d";
        return new Date(ts).toLocaleDateString(Qt.locale(), "d MMM");
    }

    // Turn an icon name or path into a URL IconImage can load.
    function iconUrl(raw) {
        if (!raw) return "";
        if (raw.indexOf("/") >= 0 || raw.indexOf(":") >= 0) return raw;
        return Quickshell.iconPath(raw, "");
    }

    // Per fd.o spec the "default" action is invoked by activating the
    // notification body (not rendered as a button).
    function defaultActionOf(notif) {
        if (!notif || !notif.actions) return null;
        const list = notif.actions;
        for (let i = 0; i < list.length; i++)
            if (list[i].identifier === "default")
                return list[i];
        return null;
    }

    function nonDefaultActions(notif) {
        if (!notif || !notif.actions) return [];
        return notif.actions.filter(a => a.identifier !== "default");
    }

    function actionText(action) {
        if (!action) return "";
        return action.text || action.identifier || "";
    }

    // Returns 0..100 if the notification carries a `value` hint (download
    // progress etc.), or -1 if absent.
    function progressOf(notif) {
        if (!notif || !notif.hints) return -1;
        const v = notif.hints["value"];
        if (v === undefined || v === null || v === "") return -1;
        const n = parseInt(v, 10);
        if (isNaN(n)) return -1;
        return Math.max(0, Math.min(100, n));
    }

    // Toast lifetime in ms; 0 = sticky (never expire). expireTimeout is in
    // seconds (-1 = default, 0 = never, >0 = that many); Critical stays sticky.
    function toastDurationOf(notif, defaultMs) {
        if (!notif) return defaultMs;
        if (notif.urgency === NotificationUrgency.Critical) return 0;
        const t = notif.expireTimeout;
        if (t === 0) return 0;
        if (t > 0) return Math.round(t * 1000);
        return defaultMs;
    }

    function invokeAction(notif, action) {
        if (!notif || !action) return false;
        action.invoke();
        return true;
    }

    // Human-friendly app name: match hint/app_name/key against installed
    // .desktop entries, else prettify the last dotted segment.
    function resolveAppName(notif, key) {
        const apps = DesktopEntries.applications.values;
        const hint = notif && notif.hints && notif.hints["desktop-entry"] !== undefined
            ? String(notif.hints["desktop-entry"]).trim() : "";
        const candidates = [];
        if (hint) candidates.push(hint);
        if (notif && notif.appName) candidates.push(String(notif.appName).trim());
        if (key) candidates.push(key);

        for (let c = 0; c < candidates.length; c++) {
            const cl = candidates[c].toLowerCase().replace(/\.desktop$/, "");
            for (let i = 0; i < apps.length; i++) {
                const id = String(apps[i].id || "").toLowerCase().replace(/\.desktop$/, "");
                if (id && id === cl)
                    return apps[i].name || apps[i].id;
            }
        }

        const name = notif && notif.appName ? String(notif.appName).trim() : "";
        if (name && name.indexOf(".") < 0) return name;

        const segs = String(key || name || "").split(".");
        const last = segs[segs.length - 1];
        if (last) return last.charAt(0).toUpperCase() + last.slice(1);
        return name || key;
    }

    function groupKey(notif) {
        if (!notif) return "";
        let desktop = "";
        if (notif.hints && notif.hints["desktop-entry"] !== undefined)
            desktop = String(notif.hints["desktop-entry"]).trim();
        if (desktop) return desktop;
        return String(notif.appName || "").trim();
    }

    function groupedByApp() {
        const all = server.trackedNotifications.values;
        const map = {};
        for (let i = 0; i < all.length; i++) {
            const n = all[i];
            if (isTransient(n)) continue;   // toast-only, never in the drawer
            const k = groupKey(n);
            if (!map[k]) {
                map[k] = {
                    key: k,
                    appName: resolveAppName(n, k),
                    appIcon: n.appIcon || "",
                    notifs: [],
                    latestTs: 0
                };
            }
            const g = map[k];
            g.notifs.push(n);
            const ts = timestampOf(n);
            if (ts >= g.latestTs) {
                g.latestTs = ts;
                g.appName = resolveAppName(n, k);
                g.appIcon = n.appIcon || g.appIcon;
            }
        }
        const groups = Object.values(map);
        for (let i = 0; i < groups.length; i++)
            groups[i].notifs.sort((a, b) => timestampOf(b) - timestampOf(a));
        groups.sort((a, b) => b.latestTs - a.latestTs);
        return groups;
    }

    function dismissGroup(key) {
        const all = server.trackedNotifications.values.slice();
        for (let i = 0; i < all.length; i++)
            if (groupKey(all[i]) === key)
                all[i].dismiss();
    }

    function clearAll() {
        const list = server.trackedNotifications.values;
        for (let i = list.length - 1; i >= 0; i--)
            list[i].dismiss();
    }
}
