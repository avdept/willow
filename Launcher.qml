// Launcher — floating, layer-shell window with a search input and a
// layered body:
//
//   • menu mode: the categories list spans the full body width.
//   • provider mode: the categories list shrinks to an icon-only rail on
//     the left, the active provider's results fill the rest. If the
//     provider opted into `detailsEnabled`, a third pane appears on the
//     right showing per-selection details (DetailsPane.qml).
//
// The categories-list right edge animates between modes (slides left on
// drill-in), and the card width/height animate with provider requests.
//
// Open / close via IPC:
//   qs ipc call launcher toggle
//   qs ipc call launcher show
//   qs ipc call launcher hide
//
// Adding a provider:
//   1. Drop a new QML file under launcher/ that inherits Provider.
//   2. Instantiate it in the Providers block below.
//   3. Add its id to the `providers` array in Component.onCompleted.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "launcher"
import "launcher/todos"

PanelWindow {
    id: launcher

    // ── Theme (set by parent) ────────────────────────────────────────────
    required property var theme
    required property string fontFamily

    // ── Layout constants ─────────────────────────────────────────────────
    readonly property int defaultCardWidth:  640
    readonly property int defaultCardHeight: 640
    readonly property int searchRowHeight:   56
    readonly property int footerHeight:      28
    readonly property int dividerHeight:     1
    readonly property int categoryRailWidth: 64      // narrowed-categories width
    readonly property int collapseAnimDuration: 260
    // Hard caps as a fraction of the screen (the launcher window covers
    // the whole screen, so width/height are the screen dimensions).
    // Anything a provider requests is clamped down to these.
    readonly property real maxWidthRatio:  0.70
    readonly property real maxHeightRatio: 0.80
    // Card background alpha (1.0 = opaque). Affects the popup card only,
    // not the layer-shell parent (which is always transparent).
    readonly property real cardAlpha: 0.95

    // Animated card size — bound below to either the defaults or the
    // active provider's `requestedWidth` / `requestedHeight`, clamped.
    property int cardWidth: defaultCardWidth
    property int cardHeight: defaultCardHeight

    // Animated width of the categories pane. Body width in menu mode (full),
    // categoryRailWidth in provider mode. Its right edge is the visible
    // divider that slides from right to left when drilling in.
    property real categoryListWidth: cardWidth        // overridden by binding below

    function _clampWidth(req)  { return Math.min(req, Math.round(width  * maxWidthRatio));  }
    function _clampHeight(req) { return Math.min(req, Math.round(height * maxHeightRatio)); }

    // ── State ────────────────────────────────────────────────────────────
    property bool open: false
    property string mode: "menu"          // "menu" | "provider"
    property int activeProvIdx: -1
    property string queryText: ""
    property int currentIndex: 0
    property var providers: []

    // Left pane: categories OR aggregated results (in menu mode with a query).
    property var leftModel: []
    // Right pane: active provider's results.
    property var rightModel: []

    // The list that owns the keyboard selection.
    readonly property var activeModel: mode === "provider" ? rightModel : leftModel

    // ── Window setup ─────────────────────────────────────────────────────
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // Namespace lets Hyprland match a `layerrule = blur, …` so the
    // compositor can backdrop-blur what's behind the popup. Pair this
    // with `cardAlpha < 1.0` to actually see the blur.
    WlrLayershell.namespace: "quickshell-launcher"
    color: "transparent"
    visible: open

    // ── IPC ──────────────────────────────────────────────────────────────
    IpcHandler {
        target: "launcher"
        function toggle() { launcher.open ? launcher.hide() : launcher.show() }
        function show()   { launcher.show() }
        function hide()   { launcher.hide() }
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
        // The provider flips `detailsEnabled` async after its `gh auth`
        // probe lands; re-sync the launcher's layout if we're showing
        // this category at that moment. (cardWidth is bound to
        // `requestedWidth` directly, so it doesn't need a handler.)
        onDetailsEnabledChanged: if (launcher.activeProvIdx === 4) launcher._syncRightLayout()
    }
    CalendarProvider { id: calProv; onResultsChanged: launcher._onProviderResults(5) }
    TodoProvider {
        id: todoProv
        onResultsChanged: launcher._onProviderResults(6)
        // When the new-todo form closes, the focused TextInput is hidden
        // and Qt drops focus entirely. Restore it to the launcher's
        // search field so the user can keep typing / hit Esc to leave.
        onFormOpenChanged: if (!formOpen) Qt.callLater(() => searchField.forceActiveFocus())
    }

    Component.onCompleted: {
        providers = [nowProv, appsProv, filesProv, styleProv, ghProv, calProv, todoProv];
        for (let i = 0; i < providers.length; i++) {
            const p = providers[i];
            if (!p) continue;
            // Any provider can ask the launcher to close itself (e.g.
            // after opening a URL externally).
            if (p.requestClose)
                p.requestClose.connect(launcher.hide);
            // Cross-provider drill-in: provider names map to indices
            // here, callLater so the requesting activate() finishes
            // before we mutate launcher state.
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

    // ── State transitions ────────────────────────────────────────────────
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

    // Drill into a provider directly (used by category clicks and by
    // typed-shortcut detection — see onQueryTextChanged below).
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
        _computeLeft();                   // rebuild left as static category list
        _refreshProviderResults();
    }

    // Returns { provIdx, rest, action? } if `text` matches one of any
    // provider's plain `shortcuts` (followed by a space) or
    // `actionShortcuts` (exact match OR followed by a space).
    // Action matches include `action: "<name>"` which the caller
    // forwards to `provider.invokeAction(name, rest)` after drill-in.
    function _matchShortcut(text) {
        const lc = (text || "").toLowerCase();
        for (let i = 0; i < providers.length; i++) {
            const p = providers[i];
            if (!p) continue;

            // Action shortcuts (exact match allowed since prefixes like
            // "+t" are intentional triggers, not query starts).
            const actions = p.actionShortcuts || {};
            for (const key in actions) {
                const sc = (key || "").toLowerCase();
                if (sc.length === 0) continue;
                if (lc === sc)
                    return { provIdx: i, rest: "", action: actions[key] };
                if (lc.startsWith(sc + " "))
                    return { provIdx: i, rest: text.slice(sc.length + 1), action: actions[key] };
            }

            // Plain drill-in shortcuts (trailing space required so
            // typing "t" alone doesn't hijack an actual query).
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

    // Warn (at startup) about any shortcut key declared by more than
    // one provider. Plain `shortcuts` and `actionShortcuts` keys share
    // a single case-insensitive namespace, since both feed
    // `_matchShortcut` and only the first hit wins. Warnings only —
    // first match still fires at runtime.
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
        // Preserve the highlight on the category we're returning from,
        // so escape / empty-backspace lands on the same row in the menu
        // instead of snapping back to the first category.
        const last = activeProvIdx;
        _resetState();
        _computeLeft();
        if (last >= 0 && last < leftModel.length) currentIndex = last;
    }

    function goBack() {
        if (mode === "provider") {
            // Let the active provider pop any internal sub-view first.
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
        // In menu mode a chevron row is a category — drill in.
        if (mode === "menu" && item.chevron) { enterProvider(currentIndex); return; }
        const p = providers[item._provIdx];
        // Providers can return truthy from activate() to keep us open
        // (e.g. live theme/font previews where the user is iterating).
        let keepOpen = false;
        if (p && item._result) keepOpen = !!p.activate(item._result);
        // Chevron rows inside a provider are sub-sections (e.g. Style →
        // Theme). Those keep the launcher open already; plus anything
        // the provider explicitly asked to hold open.
        if (!item.chevron && !keepOpen) hide();
    }

    // Active layout for the right pane. Set explicitly via
    // `_syncRightLayout()` whenever the active provider or its view
    // changes, since binding through `providers[activeProvIdx]` isn't a
    // reliable property-change dependency for QML's binding engine.
    property string rightLayout: "list"
    property int rightGridColumns: 1
    property int rightCellHeight: 160
    // Details-pane support — true when the active provider opts in.
    property bool detailsEnabled: false
    property int detailsWidth: 0
    // Mirrors active provider's `detail`, set explicitly via the
    // provider's onDetailChanged handler. Going through this stable
    // property avoids relying on `providers[activeProvIdx].detail` —
    // QML binding tracking through a `var` array lookup is unreliable.
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
        // Custom layouts handle their own selection; suppress details.
        detailsEnabled   = rightLayout !== "custom" && p.detailsEnabled === true;
        detailsWidth     = detailsEnabled ? Math.max(200, p.detailWidth || 380) : 0;
        currentDetail    = detailsEnabled ? p.detail : null;
    }

    // The active provider just pushed a new `detail` blob.
    function _onProviderDetailChanged(idx) {
        if (idx === activeProvIdx && detailsEnabled)
            currentDetail = providers[idx]?.detail ?? null;
    }

    // Whenever the highlighted result changes inside a details-enabled
    // provider, push the raw row data into the provider so it can fetch.
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

    // ── Model construction ───────────────────────────────────────────────

    function _resultRow(provIdx, p, r) {
        const isChev = r.chevron === true;
        return {
            title:       r.title,
            subtitle:    r.subtitle,
            iconUrl:     r.iconUrl,
            iconText:    r.iconText || p.iconText,
            // Live category icon — provider falls back to its own when the
            // row didn't bring one. Result rows in aggregated menu-mode
            // searches inherit the provider's component this way.
            iconComponent: r.iconComponent || p.iconComponent,
            // Chevron rows in provider results (e.g. Style → Theme) are
            // sub-section entries — render them as menu rows, not tagged
            // results.
            providerTag: isChev ? "" : (r.providerTag ?? p.tag),
            chevron:     isChev,
            // Optional per-row override for the title's font family
            // (e.g. the Font picker renders each name in its own font).
            // "" means use the launcher's default font.
            titleFont:   r.titleFont || "",
            // Optional pill color name — see ResultDelegate for the
            // supported strings. "" = muted default.
            tagColor:    r.tagColor || "",
            // Provider-private payload — read by grid delegates (e.g. to
            // mark the current theme) and dispatched back to `activate()`.
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
            // Aggregated results across all providers.
            for (let i = 0; i < providers.length; i++) {
                const p = providers[i];
                if (!p) continue;
                const rs = p.results || [];
                for (let j = 0; j < rs.length; j++) out.push(_resultRow(i, p, rs[j]));
            }
            out.sort((a, b) => b._score - a._score);
        } else {
            // Categories — always rendered, even in provider mode (clipped
            // to icon-only because the pane is narrow there).
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

    // A provider with internal sub-views just switched view — clear the
    // query so the new view starts empty, and re-fetch its results.
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
            // Typed-shortcut drill-in: "<sc> <rest>" auto-enters that
            // provider with `<rest>` as the initial query. Action
            // shortcuts additionally invoke a provider-defined action
            // and pass `rest` to it (rather than using it as a filter).
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

    // ── UI ───────────────────────────────────────────────────────────────

    // Click-outside dismiss
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

        // Drive the animated categoryListWidth: full body width in menu mode,
        // categoryRailWidth in provider mode. The Behavior is what makes the
        // right edge of the categories pane slide leftward on drill-in.
        Binding {
            target: launcher
            property: "categoryListWidth"
            value: launcher.mode === "provider" ? launcher.categoryRailWidth : body.width
        }

        // Drive cardWidth/cardHeight: the active provider may request a
        // wider or taller popup (e.g. Style → Theme wants room for a
        // preview grid). The Behaviors below keep the resize smooth.
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

            // ── Search row ───────────────────────────────────────────────
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
                        // Custom layouts intercept first — they own arrow
                        // keys (calendar date nav, etc). Escape still
                        // falls through to the launcher.
                        if (launcher.mode === "provider"
                            && launcher.rightLayout === "custom"
                            && event.key !== Qt.Key_Escape) {
                            const cp = launcher.providers[launcher.activeProvIdx];
                            if (cp && cp.handleKey && cp.handleKey(event)) {
                                event.accepted = true;
                                return;
                            }
                        }
                        // In grid layout, Up/Down jump by a full row and
                        // Left/Right step through cells. In list layout,
                        // Left/Right pass through to the text cursor.
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

                    delegate: ResultDelegate {
                        width: ListView.view.width - 12
                        x: 6
                        // In menu mode the keyboard selection lives here; in
                        // provider mode the row matching the active category
                        // stays highlighted instead.
                        currentIndex: launcher.mode === "menu"
                            ? launcher.currentIndex
                            : launcher.activeProvIdx
                        theme: launcher.theme
                        fontFamily: launcher.fontFamily
                        onActivated: function (i) {
                            if (launcher.mode === "menu") {
                                launcher.currentIndex = i;
                                launcher.activateCurrent();
                            } else {
                                // In provider mode, clicking a category icon
                                // switches to that provider.
                                const item = launcher.leftModel[i];
                                if (item && item.chevron) launcher.switchToCategory(item._provIdx);
                            }
                        }
                        onHovered: function (i) {
                            if (launcher.mode === "menu" && launcher.currentIndex !== i)
                                launcher.currentIndex = i;
                        }
                    }

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
