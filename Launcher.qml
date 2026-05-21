// Launcher — floating, layer-shell window with a search input and either a
// top-level provider menu (Apps, Files, …) or, after drilling in, that
// provider's results.
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
    required property color bgColor
    required property color fgColor
    required property color subFgColor
    required property color accentColor
    required property color borderColor
    required property string fontFamily

    // ── State ────────────────────────────────────────────────────────────
    property bool open: false
    property string mode: "menu"          // "menu" | "provider"
    property int activeProvIdx: -1
    property string queryText: ""
    property int currentIndex: 0
    property var providers: []
    property var displayModel: []

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
        // Add/remove entries here to control which providers appear in the
        // top-level menu. (FilesProvider is built but not yet exposed.)
        providers = [appsProv /*, filesProv */];
        _computeMenu();
    }

    // ── State transitions ────────────────────────────────────────────────
    function show() {
        mode = "menu";
        activeProvIdx = -1;
        queryText = "";
        currentIndex = 0;
        _computeMenu();
        open = true;
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    function hide() {
        open = false;
        mode = "menu";
        activeProvIdx = -1;
        queryText = "";
        currentIndex = 0;
    }

    function enterProvider(displayIdx) {
        if (mode !== "menu" || displayIdx < 0 || displayIdx >= displayModel.length) return;
        const provIdx = displayModel[displayIdx]._provIdx;
        const p = providers[provIdx];
        if (!p) return;
        activeProvIdx = provIdx;
        mode = "provider";
        queryText = "";
        currentIndex = 0;
        p.query = "";
        p.refresh();                  // guaranteed search call (signal-safe)
        _refreshProviderResults();
    }

    function backToMenu() {
        mode = "menu";
        activeProvIdx = -1;
        queryText = "";
        currentIndex = 0;
        _computeMenu();
    }

    function goBack() {
        if (mode === "provider") backToMenu();
        else hide();
    }

    function activateCurrent() {
        if (currentIndex < 0 || currentIndex >= displayModel.length) return;
        const item = displayModel[currentIndex];
        if (item.chevron) { enterProvider(currentIndex); return; }
        const p = providers[item._provIdx];
        if (p && item._result) p.activate(item._result);
        hide();
    }

    function moveSelection(delta) {
        const n = displayModel.length;
        if (n === 0) return;
        currentIndex = ((currentIndex + delta) % n + n) % n;
        resultsList.positionViewAtIndex(currentIndex, ListView.Contain);
    }

    // ── Model computation ────────────────────────────────────────────────

    // Build a display-row from a provider's result.
    function _resultRow(provIdx, p, r) {
        return {
            title:       r.title,
            subtitle:    r.subtitle,
            iconUrl:     r.iconUrl,
            iconText:    r.iconText || p.iconText,
            providerTag: p.tag,
            chevron:     false,
            _provIdx:    provIdx,
            _result:     r,
            _score:      r.score ?? 0
        };
    }

    // Build a display-row for a top-level category entry.
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

    function _computeMenu() {
        if (mode !== "menu") return;
        const out = [];
        if (queryText.trim().length === 0) {
            // Empty query → category list.
            for (let i = 0; i < providers.length; i++)
                if (providers[i]) out.push(_categoryRow(i, providers[i]));
        } else {
            // Non-empty query → aggregated results across all providers.
            for (let i = 0; i < providers.length; i++) {
                const p = providers[i];
                if (!p) continue;
                const rs = p.results || [];
                for (let j = 0; j < rs.length; j++) out.push(_resultRow(i, p, rs[j]));
            }
            out.sort((a, b) => b._score - a._score);
        }
        _setDisplay(out);
    }

    function _refreshProviderResults() {
        if (mode !== "provider") return;
        const p = providers[activeProvIdx];
        if (!p) { _setDisplay([]); return; }
        const rs = (p.results || []).slice().sort((a, b) => (b.score ?? 0) - (a.score ?? 0));
        _setDisplay(rs.map(r => _resultRow(activeProvIdx, p, r)));
    }

    function _setDisplay(model) {
        displayModel = model;
        if (currentIndex >= model.length) currentIndex = Math.max(0, model.length - 1);
    }

    function _onProviderResults(idx) {
        if (mode === "provider" && idx === activeProvIdx) _refreshProviderResults();
        else if (mode === "menu" && queryText.length > 0) _computeMenu();
    }

    onQueryTextChanged: {
        currentIndex = 0;
        if (mode === "menu") {
            // Broadcast to every provider so the aggregated view has data.
            // Skip on empty query — the menu shows categories then, and
            // stale provider results don't matter.
            if (queryText.length > 0) {
                for (let i = 0; i < providers.length; i++)
                    if (providers[i]) providers[i].query = queryText;
            }
            _computeMenu();
        } else if (activeProvIdx >= 0 && providers[activeProvIdx]) {
            providers[activeProvIdx].query = queryText;
        }
    }

    // ── UI ───────────────────────────────────────────────────────────────

    // Click-outside dismiss
    MouseArea { anchors.fill: parent; onClicked: launcher.hide() }

    Rectangle {
        id: card
        width: 640
        height: 460
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(64, parent.height * 0.18)
        radius: 10
        color: launcher.bgColor
        border.color: launcher.borderColor
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

        // Swallow clicks so the outer dismiss-area doesn't fire.
        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            anchors.fill: parent

            // ── Search row ───────────────────────────────────────────────
            Item {
                width: parent.width
                height: 56

                Text {
                    id: searchIcon
                    text: ""
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    color: launcher.subFgColor
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
                    color: launcher.fgColor
                    font.family: launcher.fontFamily
                    font.pixelSize: 16
                    selectByMouse: true
                    clip: true
                    selectionColor: launcher.accentColor
                    text: launcher.queryText
                    onTextChanged: launcher.queryText = text

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        text: launcher.mode === "menu"
                            ? "Search apps, files, …"
                            : ("Search " + (launcher.providers[launcher.activeProvIdx]?.name ?? "") + "…")
                        color: launcher.subFgColor
                        font: parent.font
                        opacity: 0.5
                        visible: searchField.text.length === 0
                    }

                    Keys.onPressed: function (event) {
                        switch (event.key) {
                        case Qt.Key_Escape:    launcher.goBack();        event.accepted = true; break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:     launcher.activateCurrent(); event.accepted = true; break;
                        case Qt.Key_Down:      launcher.moveSelection(1);  event.accepted = true; break;
                        case Qt.Key_Up:        launcher.moveSelection(-1); event.accepted = true; break;
                        case Qt.Key_PageDown:  launcher.moveSelection(5);  event.accepted = true; break;
                        case Qt.Key_PageUp:    launcher.moveSelection(-5); event.accepted = true; break;
                        case Qt.Key_Backspace:
                            // Backspace on an empty input inside a provider
                            // pops back to the menu.
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
                height: 1
                color: launcher.borderColor
                opacity: 0.6
            }

            // ── Drill-down breadcrumb (provider mode only) ───────────────
            Item {
                visible: launcher.mode === "provider"
                width: parent.width
                height: visible ? 28 : 0

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launcher.backToMenu()
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    spacing: 8

                    Text {
                        text: ""
                        color: launcher.subFgColor
                        font.family: launcher.fontFamily
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: launcher.providers[launcher.activeProvIdx]?.name ?? ""
                        color: launcher.subFgColor
                        font.family: launcher.fontFamily
                        font.pixelSize: 10
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.2
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // ── Results / menu ───────────────────────────────────────────
            ListView {
                id: resultsList
                width: parent.width
                height: parent.height - 56 - 1 - (launcher.mode === "provider" ? 28 : 0) - 28
                clip: true
                model: launcher.displayModel
                spacing: 2
                topMargin: 6
                bottomMargin: 6
                boundsBehavior: Flickable.StopAtBounds

                delegate: ResultDelegate {
                    width: ListView.view.width - 12
                    x: 6
                    // `modelData` and `index` are auto-filled by ListView.
                    currentIndex: launcher.currentIndex
                    bgColor: launcher.bgColor
                    fgColor: launcher.fgColor
                    subFgColor: launcher.subFgColor
                    accentColor: launcher.accentColor
                    borderColor: launcher.borderColor
                    fontFamily: launcher.fontFamily
                    onActivated: function (i) {
                        launcher.currentIndex = i;
                        launcher.activateCurrent();
                    }
                    onHovered: function (i) {
                        if (launcher.currentIndex !== i) launcher.currentIndex = i;
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: launcher.displayModel.length === 0
                    text: launcher.mode === "menu"
                        ? (launcher.queryText.length === 0 ? "No categories" : "No results")
                        : (launcher.queryText.length === 0 ? "Start typing…" : "No results")
                    color: launcher.subFgColor
                    font.family: launcher.fontFamily
                    font.pixelSize: 13
                    opacity: 0.7
                }
            }

            // ── Footer hints ─────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: 28
                color: Qt.rgba(launcher.borderColor.r, launcher.borderColor.g, launcher.borderColor.b, 0.2)

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    spacing: 14

                    Text { text: "↑↓ navigate"; color: launcher.subFgColor; font.family: launcher.fontFamily; font.pixelSize: 10 }
                    Text { text: launcher.mode === "menu" ? "↵ open" : "↵ launch"; color: launcher.subFgColor; font.family: launcher.fontFamily; font.pixelSize: 10 }
                    Text { text: launcher.mode === "menu" ? "esc close" : "esc back"; color: launcher.subFgColor; font.family: launcher.fontFamily; font.pixelSize: 10 }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    text: {
                        const n = launcher.displayModel.length;
                        const inMenuEmpty = launcher.mode === "menu" && launcher.queryText.length === 0;
                        const noun = inMenuEmpty
                            ? (n === 1 ? "category" : "categories")
                            : (n === 1 ? "result"   : "results");
                        return n + " " + noun;
                    }
                    color: launcher.subFgColor
                    font.family: launcher.fontFamily
                    font.pixelSize: 10
                }
            }
        }
    }
}
