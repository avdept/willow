// Floating layer-shell launcher. Menu mode = full-width categories;
// provider mode = icon rail + results pane (+ optional details pane).
//
// IPC: `qs ipc call launcher toggle` (also `show` and `hide`).
//
// Adding a provider: drop a QML file under launcher/, instantiate it
// below, add to the `providers` array. See PROVIDERS.md for the
// subclass contract.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "launcher"
import "launcher/todos"

PanelWindow {
    id: launcher

    required property var theme
    required property string fontFamily

    readonly property int defaultCardWidth:  640
    readonly property int defaultCardHeight: 640
    readonly property int searchRowHeight:   56
    readonly property int footerHeight:      28
    readonly property int dividerHeight:     1
    readonly property int categoryRailWidth: 52
    readonly property int collapseAnimDuration: 260
    // Hard caps as a fraction of screen size; provider requests are clamped.
    readonly property real maxWidthRatio:  0.70
    readonly property real maxHeightRatio: 0.80
    readonly property real cardAlpha: 0.95

    property int cardWidth: defaultCardWidth
    property int cardHeight: defaultCardHeight
    property real categoryListWidth: cardWidth

    function _clampWidth(req)  { return Math.min(req, Math.round(width  * maxWidthRatio));  }
    function _clampHeight(req) { return Math.min(req, Math.round(height * maxHeightRatio)); }

    property bool open: false
    property string mode: "menu"          // "menu" | "provider"
    property int activeProvIdx: -1
    property string queryText: ""
    property int currentIndex: 0
    property var providers: []

    // leftModel = categories OR aggregated results (menu mode + query).
    // rightModel = active provider's results.
    property var leftModel: []
    property var rightModel: []
    readonly property var activeModel: mode === "provider" ? rightModel : leftModel

    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // Namespace lets Hyprland match a `layerrule = blur, …`. Pair with
    // cardAlpha < 1.0 to actually see the blur.
    WlrLayershell.namespace: "quickshell-launcher"
    color: "transparent"
    visible: open

    IpcHandler {
        target: "launcher"
        function toggle() { launcher.open ? launcher.hide() : launcher.show() }
        function show()   { launcher.show() }
        function hide()   { launcher.hide() }
        function showProvider(name: string) { launcher.showProvider(name) }
    }

    // ── Providers ────────────────────────────────────────────────────────
    // Now is registered first so it owns index 0 — `show()` auto-enters
    // that index, opening the launcher directly onto the dashboard.
    NowProvider {
        id: nowProv
        onResultsChanged: launcher._onProviderResults(0)
        unfinishedTodos: todoProv.unfinishedCount
    }
    AppsProvider  { id: appsProv;  onResultsChanged: launcher._onProviderResults(1) }
    FilesProvider { id: filesProv; onResultsChanged: launcher._onProviderResults(2) }
    StyleProvider {
        id: styleProv
        onResultsChanged: launcher._onProviderResults(3)
        onViewChanged: if (launcher.activeProvIdx === 3) launcher._onProviderViewChanged()
    }
    GithubProvider {
        id: ghProv
        onResultsChanged: launcher._onProviderResults(4)
        onDetailChanged:  launcher._onProviderDetailChanged(4)
        // detailsEnabled flips async after the `gh auth` probe lands;
        // resync layout if the user is on this category at that moment.
        onDetailsEnabledChanged: if (launcher.activeProvIdx === 4) launcher._syncRightLayout()
    }
    CalendarProvider { id: calProv; onResultsChanged: launcher._onProviderResults(5) }
    TodoProvider {
        id: todoProv
        onResultsChanged: launcher._onProviderResults(6)
        // When the form closes, the focused TextInput is hidden and Qt
        // drops focus entirely. Restore it to the search field.
        onFormOpenChanged: if (!formOpen) Qt.callLater(() => searchField.forceActiveFocus())
    }
    TriggerProvider {
        id: triggerProv
        onResultsChanged: launcher._onProviderResults(7)
        onViewChanged: if (launcher.activeProvIdx === 7) launcher._onProviderViewChanged()
    }

    Component.onCompleted: {
        providers = [nowProv, appsProv, filesProv, styleProv, ghProv, calProv, todoProv, triggerProv];
        for (let i = 0; i < providers.length; i++) {
            const p = providers[i];
            if (!p) continue;
            if (p.requestClose)
                p.requestClose.connect(launcher.hide);
            // callLater so the requesting activate() finishes before we
            // mutate launcher state.
            if (p.requestEnter)
                p.requestEnter.connect((name, query) => {
                    const idx = launcher.providers.findIndex(x => x && x.name === name);
                    if (idx >= 0)
                        Qt.callLater(() => launcher.enterProviderById(idx, query));
                });
        }
        _validateShortcuts();
        _computeLeft();
    }

    onOpenChanged: {
        for (let i = 0; i < providers.length; i++)
            if (providers[i]) providers[i].launcherOpen = open;
    }

    function show() {
        _resetState();
        _computeLeft();
        open = true;
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    function hide() {
        open = false;
        _resetState();
    }

    function showProvider(name) {
        const idx = providers.findIndex(p => p && p.name && p.name.toLowerCase() === (name || "").toLowerCase());
        if (idx < 0) { show(); return; }
        _resetState();
        _computeLeft();
        open = true;
        Qt.callLater(() => {
            enterProviderById(idx, "");
            searchField.forceActiveFocus();
        });
    }

    function _resetState() {
        mode = "menu";
        activeProvIdx = -1;
        queryText = "";
        currentIndex = 0;
        rightModel = [];
        for (let i = 0; i < providers.length; i++)
            if (providers[i] && providers[i].reset) providers[i].reset();
        _syncRightLayout();
    }

    function enterProvider(displayIdx) {
        if (mode !== "menu" || displayIdx < 0 || displayIdx >= leftModel.length) return;
        const item = leftModel[displayIdx];
        if (!item.chevron) return;        // aggregated result, not a category
        enterProviderById(item._provIdx, "");
    }

    function enterProviderById(provIdx, initialQuery) {
        const p = providers[provIdx];
        if (!p) return;
        activeProvIdx = provIdx;
        mode = "provider";
        queryText = initialQuery || "";
        currentIndex = 0;
        p.query = queryText;
        p.refresh();
        _syncRightLayout();
        _computeLeft();
        _refreshProviderResults();
    }

    // Returns { provIdx, rest, action? } for the first matching shortcut.
    // `actionShortcuts` allow exact match (so "+t" alone fires);
    // `shortcuts` require a trailing space (so "t" doesn't hijack queries).
    function _matchShortcut(text) {
        const lc = (text || "").toLowerCase();
        for (let i = 0; i < providers.length; i++) {
            const p = providers[i];
            if (!p) continue;

            const actions = p.actionShortcuts || {};
            for (const key in actions) {
                const sc = (key || "").toLowerCase();
                if (sc.length === 0) continue;
                if (lc === sc)
                    return { provIdx: i, rest: "", action: actions[key] };
                if (lc.startsWith(sc + " "))
                    return { provIdx: i, rest: text.slice(sc.length + 1), action: actions[key] };
            }

            const list = p.shortcuts;
            if (!list) continue;
            for (let j = 0; j < list.length; j++) {
                const sc = (list[j] || "").toLowerCase();
                if (sc.length === 0) continue;
                if (lc.startsWith(sc + " "))
                    return { provIdx: i, rest: text.slice(sc.length + 1) };
            }
        }
        return null;
    }

    // Warn at startup about shortcut keys claimed by multiple providers.
    // Plain and action shortcuts share a single namespace; first match
    // wins at runtime.
    function _validateShortcuts() {
        const seen = ({});
        for (let i = 0; i < providers.length; i++) {
            const p = providers[i];
            if (!p) continue;
            const provName = p.name || ("provider#" + i);
            const claim = (key, kind) => {
                const k = (key || "").toLowerCase().trim();
                if (!k.length) return;
                if (!seen[k]) seen[k] = [];
                seen[k].push(provName + " (" + kind + ")");
            };
            const list = p.shortcuts || [];
            for (let j = 0; j < list.length; j++) claim(list[j], "shortcut");
            const actions = p.actionShortcuts || {};
            for (const k in actions) claim(k, "action:" + actions[k]);
        }
        for (const key in seen) {
            const owners = seen[key];
            if (owners.length > 1)
                console.warn("Launcher: shortcut '" + key
                    + "' declared by multiple providers: " + owners.join(", ")
                    + " — first one wins at runtime.");
        }
    }

    function switchToCategory(provIdx) {
        if (provIdx === activeProvIdx) return;
        const p = providers[provIdx];
        if (!p) return;
        // Clean up the outgoing provider's state — same hook used on
        // back-to-menu / launcher close.
        const outgoing = providers[activeProvIdx];
        if (outgoing && outgoing.reset) outgoing.reset();
        activeProvIdx = provIdx;
        queryText = "";
        currentIndex = 0;
        p.query = "";
        p.refresh();
        _syncRightLayout();
        _refreshProviderResults();
    }

    function backToMenu() {
        // Preserve the highlight so escape lands on the same row.
        const last = activeProvIdx;
        _resetState();
        _computeLeft();
        if (last >= 0 && last < leftModel.length) currentIndex = last;
    }

    function goBack() {
        if (mode === "provider") {
            const p = providers[activeProvIdx];
            if (p && p.goBack && p.goBack()) return;
            backToMenu();
        } else {
            hide();
        }
    }

    function activateCurrent() {
        const model = activeModel;
        if (currentIndex < 0 || currentIndex >= model.length) return;
        const item = model[currentIndex];
        if (mode === "menu" && item.chevron) { enterProvider(currentIndex); return; }
        const p = providers[item._provIdx];
        let keepOpen = false;
        if (p && item._result) keepOpen = !!p.activate(item._result);
        if (!item.chevron && !keepOpen) hide();
    }

    // Explicit state instead of bindings through providers[activeProvIdx]
    // — QML can't reliably track property changes through a var-array lookup.
    property string rightLayout: "list"
    property int rightGridColumns: 1
    property int rightCellHeight: 160
    property bool detailsEnabled: false
    property int detailsWidth: 0
    property var currentDetail: null

    function _syncRightLayout() {
        if (mode !== "provider") {
            rightLayout = "list";
            rightGridColumns = 1;
            detailsEnabled = false;
            detailsWidth = 0;
            currentDetail = null;
            return;
        }
        const p = providers[activeProvIdx];
        if (!p) { rightLayout = "list"; rightGridColumns = 1; detailsEnabled = false; detailsWidth = 0; currentDetail = null; return; }
        rightLayout      = p.resultsLayout === "grid"   ? "grid"
                         : p.resultsLayout === "custom" ? "custom"
                         : "list";
        rightGridColumns = Math.max(1, p.gridColumns || 4);
        rightCellHeight  = Math.max(1, p.cellHeight  || 160);
        detailsEnabled   = rightLayout !== "custom" && p.detailsEnabled === true;
        detailsWidth     = detailsEnabled ? Math.max(200, p.detailWidth || 380) : 0;
        currentDetail    = detailsEnabled ? p.detail : null;
    }

    function _onProviderDetailChanged(idx) {
        if (idx === activeProvIdx && detailsEnabled)
            currentDetail = providers[idx]?.detail ?? null;
    }

    function _syncSelectedRow() {
        if (!detailsEnabled || mode !== "provider") return;
        const p = providers[activeProvIdx];
        if (!p) return;
        const m = rightModel;
        if (currentIndex < 0 || currentIndex >= m.length) { p.selectedRow = null; return; }
        p.selectedRow = m[currentIndex]?._result ?? null;
    }

    onCurrentIndexChanged: _syncSelectedRow()
    onRightModelChanged:   _syncSelectedRow()
    onDetailsEnabledChanged: _syncSelectedRow()

    function moveSelection(delta) {
        const n = activeModel.length;
        if (n === 0) return;
        currentIndex = ((currentIndex + delta) % n + n) % n;
        if (mode === "provider") {
            if (rightLayout === "grid") rightGrid.positionViewAtIndex(currentIndex, GridView.Contain);
            else                        rightList.positionViewAtIndex(currentIndex, ListView.Contain);
        } else {
            leftList.positionViewAtIndex(currentIndex, ListView.Contain);
        }
    }

    function _resultRow(provIdx, p, r) {
        const isChev = r.chevron === true;
        return {
            title:       r.title,
            subtitle:    r.subtitle,
            iconUrl:     r.iconUrl,
            iconText:    r.iconText || p.iconText,
            iconComponent: r.iconComponent || p.iconComponent,
            // Chevron rows are sub-sections (e.g. Style → Theme) — no tag pill.
            providerTag: isChev ? "" : (r.providerTag ?? p.tag),
            chevron:     isChev,
            titleFont:   r.titleFont || "",
            tagColor:    r.tagColor || "",
            data:        r.data,
            _provIdx:    provIdx,
            _result:     r,
            _score:      r.score ?? 0
        };
    }

    function _categoryRow(provIdx, p) {
        return {
            title:       p.name,
            subtitle:    p.description,
            iconUrl:     "",
            iconText:    p.iconText,
            iconComponent: p.iconComponent,
            providerTag: "",
            chevron:     true,
            _provIdx:    provIdx,
            _result:     null,
            _score:      0
        };
    }

    function _computeLeft() {
        const out = [];
        if (mode === "menu" && queryText.trim().length > 0) {
            for (let i = 0; i < providers.length; i++) {
                const p = providers[i];
                if (!p) continue;
                const rs = p.results || [];
                for (let j = 0; j < rs.length; j++) out.push(_resultRow(i, p, rs[j]));
            }
            out.sort((a, b) => b._score - a._score);
        } else {
            for (let i = 0; i < providers.length; i++)
                if (providers[i]) out.push(_categoryRow(i, providers[i]));
        }
        leftModel = out;
        _clampCurrent();
    }

    function _refreshProviderResults() {
        if (mode !== "provider" || activeProvIdx < 0) { rightModel = []; return; }
        const p = providers[activeProvIdx];
        if (!p) { rightModel = []; return; }
        const rs = (p.results || []).slice().sort((a, b) => (b.score ?? 0) - (a.score ?? 0));
        rightModel = rs.map(r => _resultRow(activeProvIdx, p, r));
        _clampCurrent();
    }

    function _clampCurrent() {
        if (currentIndex >= activeModel.length)
            currentIndex = Math.max(0, activeModel.length - 1);
    }

    function _onProviderResults(idx) {
        if (mode === "provider" && idx === activeProvIdx) _refreshProviderResults();
        else if (mode === "menu" && queryText.length > 0) _computeLeft();
    }

    function _onProviderViewChanged() {
        queryText = "";
        currentIndex = 0;
        const p = providers[activeProvIdx];
        if (p) {
            p.query = "";
            p.refresh();
        }
        _syncRightLayout();
        _refreshProviderResults();
    }

    onQueryTextChanged: {
        currentIndex = 0;
        if (mode === "menu") {
            const sc = _matchShortcut(queryText);
            if (sc) {
                enterProviderById(sc.provIdx, sc.action ? "" : sc.rest);
                if (sc.action) {
                    const p = providers[sc.provIdx];
                    if (p && p.invokeAction) p.invokeAction(sc.action, sc.rest);
                }
                return;
            }
            if (queryText.length > 0) {
                for (let i = 0; i < providers.length; i++)
                    if (providers[i]) providers[i].query = queryText;
            }
            _computeLeft();
        } else if (activeProvIdx >= 0 && providers[activeProvIdx]) {
            providers[activeProvIdx].query = queryText;
        }
    }

    MouseArea { anchors.fill: parent; onClicked: launcher.hide() }

    component HintText : Text {
        color: launcher.theme.subFg
        font.family: launcher.fontFamily
        font.pixelSize: 10
    }

    Rectangle {
        id: card
        width: launcher.cardWidth
        height: launcher.cardHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(64, parent.height * 0.18)
        color: Qt.rgba(launcher.theme.bg.r, launcher.theme.bg.g, launcher.theme.bg.b, launcher.cardAlpha)
        border.color: launcher.theme.border
        border.width: 1

        opacity: launcher.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on width  { NumberAnimation { duration: launcher.collapseAnimDuration; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: launcher.collapseAnimDuration; easing.type: Easing.OutCubic } }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.32
            shadowBlur: 1.0
            shadowVerticalOffset: 8
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Binding {
            target: launcher
            property: "categoryListWidth"
            value: launcher.mode === "provider" ? launcher.categoryRailWidth : body.width
        }

        Binding {
            target: launcher
            property: "cardWidth"
            value: {
                const def = launcher.defaultCardWidth;
                if (launcher.mode !== "provider") return launcher._clampWidth(def);
                const p = launcher.providers[launcher.activeProvIdx];
                const req = p ? p.requestedWidth : 0;
                return launcher._clampWidth(req > 0 ? req : def);
            }
        }
        Binding {
            target: launcher
            property: "cardHeight"
            value: {
                const def = launcher.defaultCardHeight;
                if (launcher.mode !== "provider") return launcher._clampHeight(def);
                const p = launcher.providers[launcher.activeProvIdx];
                const req = p ? p.requestedHeight : 0;
                return launcher._clampHeight(req > 0 ? req : def);
            }
        }

        Column {
            anchors.fill: parent

            Item {
                width: parent.width
                height: launcher.searchRowHeight

                Text {
                    id: searchIcon
                    text: ""
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    color: launcher.theme.subFg
                    font.family: launcher.fontFamily
                    font.pixelSize: 18
                }

                TextInput {
                    id: searchField
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: searchIcon.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    color: launcher.theme.fg
                    font.family: launcher.fontFamily
                    font.pixelSize: 16
                    selectByMouse: true
                    clip: true
                    selectionColor: launcher.theme.accent
                    text: launcher.queryText
                    onTextChanged: launcher.queryText = text

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        text: {
                            if (launcher.mode === "menu") return "Search apps, files, …";
                            const p = launcher.providers[launcher.activeProvIdx];
                            const label = (p?.currentTitle && p.currentTitle.length > 0)
                                ? p.currentTitle
                                : (p?.name ?? "");
                            return "Search " + label + "…";
                        }
                        color: launcher.theme.subFg
                        font: parent.font
                        opacity: 0.5
                        visible: searchField.text.length === 0
                    }

                    Keys.onPressed: function (event) {
                        // Custom layouts own arrow keys (calendar date nav etc).
                        // Escape still falls through to the launcher.
                        if (launcher.mode === "provider"
                            && launcher.rightLayout === "custom"
                            && event.key !== Qt.Key_Escape) {
                            const cp = launcher.providers[launcher.activeProvIdx];
                            if (cp && cp.handleKey && cp.handleKey(event)) {
                                event.accepted = true;
                                return;
                            }
                        }
                        const cols  = launcher.rightLayout === "grid" ? launcher.rightGridColumns : 1;
                        switch (event.key) {
                        case Qt.Key_Escape:    launcher.goBack();              event.accepted = true; break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:     launcher.activateCurrent();     event.accepted = true; break;
                        case Qt.Key_Down:      launcher.moveSelection(cols);   event.accepted = true; break;
                        case Qt.Key_Up:        launcher.moveSelection(-cols);  event.accepted = true; break;
                        case Qt.Key_Right:
                            if (launcher.rightLayout === "grid") {
                                launcher.moveSelection(1); event.accepted = true;
                            }
                            break;
                        case Qt.Key_Left:
                            if (launcher.rightLayout === "grid") {
                                launcher.moveSelection(-1); event.accepted = true;
                            }
                            break;
                        case Qt.Key_PageDown:  launcher.moveSelection(cols*5);  event.accepted = true; break;
                        case Qt.Key_PageUp:    launcher.moveSelection(-cols*5); event.accepted = true; break;
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: launcher.dividerHeight
                color: launcher.theme.border
                opacity: 0.6
            }

            // ── Body: categories pane (left) + provider results pane (right) ─
            Item {
                id: body
                width: parent.width
                height: parent.height - launcher.searchRowHeight - launcher.dividerHeight - launcher.footerHeight

                // Categories pane — width animates. Each row clips to icon
                // when the pane is narrow (provider mode).
                ListView {
                    id: leftList
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: launcher.categoryListWidth
                    clip: true
                    model: launcher.leftModel
                    spacing: 2
                    topMargin: 6
                    bottomMargin: 6
                    boundsBehavior: Flickable.StopAtBounds

                    Behavior on width { NumberAnimation { duration: launcher.collapseAnimDuration; easing.type: Easing.OutCubic } }

                    Component {
                        id: leftFullDelegate
                        ResultDelegate {
                            width: ListView.view.width - 12
                            x: 6
                            currentIndex: launcher.currentIndex
                            theme: launcher.theme
                            fontFamily: launcher.fontFamily
                            launcherOpen: launcher.open
                            onActivated: function (i) {
                                launcher.currentIndex = i;
                                launcher.activateCurrent();
                            }
                            onHovered: function (i) {
                                if (launcher.currentIndex !== i)
                                    launcher.currentIndex = i;
                            }
                        }
                    }

                    Component {
                        id: leftRailDelegate
                        RailDelegate {
                            width: ListView.view.width
                            currentIndex: launcher.activeProvIdx
                            theme: launcher.theme
                            fontFamily: launcher.fontFamily
                            launcherOpen: launcher.open
                            onActivated: function (i) {
                                const item = launcher.leftModel[i];
                                if (item && item.chevron) launcher.switchToCategory(item._provIdx);
                            }
                            onHovered: function (_i) {}
                        }
                    }

                    delegate: launcher.mode === "provider" ? leftRailDelegate : leftFullDelegate

                    // Empty state — only relevant in menu mode.
                    Text {
                        anchors.centerIn: parent
                        visible: launcher.mode === "menu" && launcher.leftModel.length === 0
                        text: launcher.queryText.length === 0 ? "No categories" : "No results"
                        color: launcher.theme.subFg
                        font.family: launcher.fontFamily
                        font.pixelSize: 13
                        opacity: 0.7
                    }
                }

                // Vertical divider on the right edge of the categories pane,
                // visible only in provider mode (acts as the gutter between
                // the two panes after the animation completes).
                Rectangle {
                    width: launcher.dividerHeight
                    height: parent.height
                    anchors.left: leftList.right
                    color: launcher.theme.border
                    visible: launcher.mode === "provider"
                }

                // Provider results pane — list layout (default).
                // When `detailsEnabled`, the right edge shrinks by
                // detailsWidth + divider, leaving room for the details pane.
                ListView {
                    id: rightList
                    anchors.left: leftList.right
                    anchors.leftMargin: launcher.dividerHeight
                    anchors.right: parent.right
                    anchors.rightMargin: launcher.detailsEnabled
                        ? (launcher.detailsWidth + launcher.dividerHeight)
                        : 0
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    clip: true
                    model: launcher.rightModel
                    spacing: 2
                    topMargin: 6
                    bottomMargin: 6
                    boundsBehavior: Flickable.StopAtBounds
                    visible: launcher.mode === "provider" && launcher.rightLayout === "list"

                    delegate: ResultDelegate {
                        width: ListView.view.width - 12
                        x: 6
                        currentIndex: launcher.mode === "provider" ? launcher.currentIndex : -1
                        theme: launcher.theme
                        fontFamily: launcher.fontFamily
                        launcherOpen: launcher.open
                        onActivated: function (i) {
                            launcher.currentIndex = i;
                            launcher.activateCurrent();
                        }
                        onHovered: function (i) {
                            if (launcher.mode === "provider" && launcher.currentIndex !== i)
                                launcher.currentIndex = i;
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 32
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        visible: launcher.rightModel.length === 0
                        text: {
                            const p = launcher.providers[launcher.activeProvIdx];
                            if (p && p.emptyStateText && p.emptyStateText.length > 0)
                                return p.emptyStateText;
                            return launcher.queryText.length === 0 ? "Start typing…" : "No results";
                        }
                        color: launcher.theme.subFg
                        font.family: launcher.fontFamily
                        font.pixelSize: 13
                        opacity: 0.7
                    }
                }

                // Provider results pane — grid layout (e.g. Theme picker).
                GridView {
                    id: rightGrid
                    anchors.left: leftList.right
                    anchors.leftMargin: launcher.dividerHeight
                    anchors.right: parent.right
                    anchors.rightMargin: launcher.detailsEnabled
                        ? (launcher.detailsWidth + launcher.dividerHeight)
                        : 0
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    clip: true
                    model: launcher.rightModel
                    topMargin: 6
                    bottomMargin: 6
                    boundsBehavior: Flickable.StopAtBounds
                    visible: launcher.mode === "provider" && launcher.rightLayout === "grid"

                    cellWidth: Math.max(1, Math.floor(width / launcher.rightGridColumns))
                    cellHeight: launcher.rightCellHeight

                    delegate: ResultGridCell {
                        width:  rightGrid.cellWidth
                        height: rightGrid.cellHeight
                        currentIndex: launcher.mode === "provider" ? launcher.currentIndex : -1
                        theme: launcher.theme
                        fontFamily: launcher.fontFamily
                        launcherOpen: launcher.open
                        onActivated: function (i) {
                            launcher.currentIndex = i;
                            launcher.activateCurrent();
                        }
                        onHovered: function (i) {
                            if (launcher.mode === "provider" && launcher.currentIndex !== i)
                                launcher.currentIndex = i;
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: launcher.rightModel.length === 0
                        text: launcher.queryText.length === 0 ? "Loading…" : "No results"
                        color: launcher.theme.subFg
                        font.family: launcher.fontFamily
                        font.pixelSize: 13
                        opacity: 0.7
                    }
                }

                // Provider results pane — fully custom (provider draws it all).
                Loader {
                    id: rightCustom
                    anchors.left: leftList.right
                    anchors.leftMargin: launcher.dividerHeight
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    visible: launcher.mode === "provider" && launcher.rightLayout === "custom"
                    active: visible
                    sourceComponent: {
                        if (!visible) return null;
                        const p = launcher.providers[launcher.activeProvIdx];
                        return p ? p.customComponent : null;
                    }
                    onLoaded: if (item) {
                        item.theme = launcher.theme;
                        item.fontFamily = launcher.fontFamily;
                        item.provider = launcher.providers[launcher.activeProvIdx];
                    }
                }

                // ── Details pane (opt-in via Provider.detailsEnabled) ────
                Rectangle {
                    id: detailsDivider
                    width: launcher.dividerHeight
                    height: parent.height
                    anchors.right: detailsPane.left
                    color: launcher.theme.border
                    visible: launcher.detailsEnabled
                }

                DetailsPane {
                    id: detailsPane
                    width: launcher.detailsWidth
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    visible: launcher.detailsEnabled
                    theme: launcher.theme
                    fontFamily: launcher.fontFamily
                    detail: launcher.currentDetail
                }
            }

            // ── Footer hints ─────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: launcher.footerHeight
                color: Qt.rgba(launcher.theme.border.r, launcher.theme.border.g, launcher.theme.border.b, 0.2)

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    spacing: 14

                    HintText { text: "↑↓ navigate" }
                    HintText { text: launcher.mode === "menu" ? "↵ open"    : "↵ launch" }
                    HintText { text: launcher.mode === "menu" ? "esc close" : "esc back"  }
                }

                HintText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    text: {
                        const n = launcher.activeModel.length;
                        const inMenuEmpty = launcher.mode === "menu" && launcher.queryText.length === 0;
                        const noun = inMenuEmpty
                            ? (n === 1 ? "category" : "categories")
                            : (n === 1 ? "result"   : "results");
                        return n + " " + noun;
                    }
                }
            }
        }
    }
}
