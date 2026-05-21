// Launcher — floating, layer-shell window with a search input and a
// two-pane body: the categories list on the left, and (after drilling in)
// the active provider's results on the right.
//
// In menu mode the categories list spans the full body width. When the user
// drills into a category, the categories list shrinks to icon-only width
// (its right edge slides leftward, sweeping over each row's name/chevron)
// and the provider-results list animates in to fill the remaining space.
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

PanelWindow {
    id: launcher

    // ── Theme (set by parent) ────────────────────────────────────────────
    required property var theme
    required property string fontFamily

    // ── Layout constants ─────────────────────────────────────────────────
    readonly property int cardWidth: 640
    readonly property int cardHeight: 460
    readonly property int searchRowHeight: 56
    readonly property int footerHeight: 28
    readonly property int dividerHeight: 1
    readonly property int categoryRailWidth: 64       // narrowed-categories width
    readonly property int collapseAnimDuration: 260

    // Animated width of the categories pane. Body width in menu mode (full),
    // categoryRailWidth in provider mode. Its right edge is the visible
    // divider that slides from right to left when drilling in.
    property real categoryListWidth: cardWidth        // overridden by binding below

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
    AppsProvider  { id: appsProv;  onResultsChanged: launcher._onProviderResults(0) }
    FilesProvider { id: filesProv; onResultsChanged: launcher._onProviderResults(1) }

    Component.onCompleted: {
        providers = [appsProv, filesProv];
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
    }

    function enterProvider(displayIdx) {
        if (mode !== "menu" || displayIdx < 0 || displayIdx >= leftModel.length) return;
        const item = leftModel[displayIdx];
        if (!item.chevron) return;        // aggregated result, not a category
        const provIdx = item._provIdx;
        const p = providers[provIdx];
        if (!p) return;
        activeProvIdx = provIdx;
        mode = "provider";
        queryText = "";
        currentIndex = 0;
        p.query = "";
        p.refresh();
        _computeLeft();                   // rebuild left as static category list
        _refreshProviderResults();
    }

    function switchToCategory(provIdx) {
        if (provIdx === activeProvIdx) return;
        const p = providers[provIdx];
        if (!p) return;
        activeProvIdx = provIdx;
        queryText = "";
        currentIndex = 0;
        p.query = "";
        p.refresh();
        _refreshProviderResults();
    }

    function backToMenu() {
        _resetState();
        _computeLeft();
    }

    function goBack() {
        if (mode === "provider") backToMenu();
        else hide();
    }

    function activateCurrent() {
        const model = activeModel;
        if (currentIndex < 0 || currentIndex >= model.length) return;
        const item = model[currentIndex];
        if (item.chevron) { enterProvider(currentIndex); return; }
        const p = providers[item._provIdx];
        if (p && item._result) p.activate(item._result);
        hide();
    }

    function moveSelection(delta) {
        const n = activeModel.length;
        if (n === 0) return;
        currentIndex = ((currentIndex + delta) % n + n) % n;
        const list = mode === "provider" ? rightList : leftList;
        list.positionViewAtIndex(currentIndex, ListView.Contain);
    }

    // ── Model construction ───────────────────────────────────────────────

    function _resultRow(provIdx, p, r) {
        return {
            title:       r.title,
            subtitle:    r.subtitle,
            iconUrl:     r.iconUrl,
            iconText:    r.iconText || p.iconText,
            providerTag: r.providerTag ?? p.tag,           // result may override
            chevron:     false,
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

    onQueryTextChanged: {
        currentIndex = 0;
        if (mode === "menu") {
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
        color: launcher.theme.bg
        border.color: launcher.theme.border
        border.width: 1

        opacity: launcher.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

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
                        text: launcher.mode === "menu"
                            ? "Search apps, files, …"
                            : ("Search " + (launcher.providers[launcher.activeProvIdx]?.name ?? "") + "…")
                        color: launcher.theme.subFg
                        font: parent.font
                        opacity: 0.5
                        visible: searchField.text.length === 0
                    }

                    Keys.onPressed: function (event) {
                        switch (event.key) {
                        case Qt.Key_Escape:    launcher.goBack();          event.accepted = true; break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:     launcher.activateCurrent(); event.accepted = true; break;
                        case Qt.Key_Down:      launcher.moveSelection(1);  event.accepted = true; break;
                        case Qt.Key_Up:        launcher.moveSelection(-1); event.accepted = true; break;
                        case Qt.Key_PageDown:  launcher.moveSelection(5);  event.accepted = true; break;
                        case Qt.Key_PageUp:    launcher.moveSelection(-5); event.accepted = true; break;
                        case Qt.Key_Backspace:
                            if (launcher.mode === "provider" && searchField.text.length === 0) {
                                launcher.backToMenu();
                                event.accepted = true;
                            }
                            break;
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

                // Provider results pane — empty/hidden in menu mode.
                ListView {
                    id: rightList
                    anchors.left: leftList.right
                    anchors.leftMargin: launcher.dividerHeight
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    clip: true
                    model: launcher.rightModel
                    spacing: 2
                    topMargin: 6
                    bottomMargin: 6
                    boundsBehavior: Flickable.StopAtBounds
                    visible: launcher.mode === "provider"

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
                        visible: launcher.rightModel.length === 0
                        text: launcher.queryText.length === 0 ? "Start typing…" : "No results"
                        color: launcher.theme.subFg
                        font.family: launcher.fontFamily
                        font.pixelSize: 13
                        opacity: 0.7
                    }
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
