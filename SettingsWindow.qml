// Standalone settings window — a real XDG toplevel (FloatingWindow), NOT a
// layer-shell popup like the launcher/drawer. The compositor manages it as an
// ordinary window: it has a title, can be moved/resized, and floats per the
// Hyprland windowrule suggested in the README.
//
// Toggle via: qs ipc call settings toggle   (also show / hide), or the gear
// icon in the top bar. All controls read/write the Config singleton, which
// persists to settings.json immediately on change.

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "shared"

FloatingWindow {
    id: win

    required property var theme
    readonly property string fontFamily: Config.fontFamily

    property bool open: false
    visible: open

    title: "Quickshell Settings"
    implicitWidth: 480
    implicitHeight: 600
    minimumSize: Qt.size(420, 480)
    color: theme.bg

    IpcHandler {
        target: "settings"
        function toggle() { win.open = !win.open }
        function show()   { win.open = true }
        function hide()   { win.open = false }
    }

    // ── Reusable themed slider ────────────────────────────────────────────
    component ValueSlider: Slider {
        id: s
        property color accentColor: "#1e66f5"
        property color trackColor: "#888888"
        property color knobBorder: "#ffffff"
        implicitWidth: 190
        implicitHeight: 22

        background: Rectangle {
            x: s.leftPadding
            y: s.topPadding + s.availableHeight / 2 - height / 2
            width: s.availableWidth
            height: 4
            radius: 2
            color: Qt.rgba(s.trackColor.r, s.trackColor.g, s.trackColor.b, 0.18)

            Rectangle {
                width: s.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: s.accentColor
            }
        }

        handle: Rectangle {
            x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
            y: s.topPadding + s.availableHeight / 2 - height / 2
            width: 14
            height: 14
            radius: 7
            color: s.accentColor
            border.color: s.knobBorder
            border.width: 2
        }
    }

    // ── Slider + right-aligned value readout, sized to the holder width so
    //    every control row lines up to the same width. ────────────────────
    component SliderControl: Item {
        id: sc
        property real from: 0
        property real to: 1
        property real value: 0
        property real stepSize: 0
        property bool snap: false
        property string valueText: ""
        signal moved(real v)

        width: parent ? parent.width : 0
        height: 22

        ValueSlider {
            id: innerSlider
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - valueLabel.width - 10
            from: sc.from
            to: sc.to
            stepSize: sc.stepSize
            snapMode: sc.snap ? Slider.SnapAlways : Slider.NoSnap
            accentColor: win.theme.accent
            trackColor: win.theme.fg
            knobBorder: win.theme.bg
            onMoved: sc.moved(value)

            // Keep the handle synced to the backing value even after a drag
            // breaks the plain binding (covers Reset to defaults).
            Binding {
                target: innerSlider
                property: "value"
                value: sc.value
            }
        }

        Text {
            id: valueLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            horizontalAlignment: Text.AlignRight
            text: sc.valueText
            color: win.theme.subFg
            font.family: win.fontFamily
            font.pixelSize: 11
        }
    }

    // ── Section header ────────────────────────────────────────────────────
    component SectionLabel: Text {
        color: win.theme.subFg
        font.family: win.fontFamily
        font.pixelSize: 11
        font.bold: true
        topPadding: 8
    }

    // ── A label + control row (control aligned to the right) ──────────────
    component RowLayoutShim: Item {
        id: rowItem
        // The right-hand control is assigned via `control:` (not the default
        // property) so the internal label column / holder below stay as this
        // item's own children rather than being redirected into the holder.
        property alias control: holder.data
        property string label: ""
        property string hint: ""
        width: parent ? parent.width : 0
        implicitHeight: Math.max(38, holder.childrenRect.height + 12)

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.45
            spacing: 2
            Text {
                text: rowItem.label
                color: win.theme.fg
                font.family: win.fontFamily
                font.pixelSize: 12
                width: parent.width
                elide: Text.ElideRight
            }
            Text {
                visible: rowItem.hint.length > 0
                text: rowItem.hint
                color: win.theme.subFg
                font.family: win.fontFamily
                font.pixelSize: 9
                opacity: 0.8
                width: parent.width
                wrapMode: Text.WordWrap
            }
        }

        Item {
            id: holder
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.5
            implicitHeight: childrenRect.height
        }
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        anchors.margins: 0
        contentHeight: body.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            x: 20
            y: 18
            width: scroll.width - 40
            spacing: 6

            Text {
                text: "Settings"
                color: win.theme.fg
                font.family: win.fontFamily
                font.pixelSize: 18
                font.bold: true
                bottomPadding: 6
            }

            // ── Appearance ────────────────────────────────────────────────
            SectionLabel { text: "APPEARANCE" }

            RowLayoutShim {
                label: "Font"
                hint: "Affects bar, launcher, notifications, OSD"

                control: Select {
                    id: fontSelect
                    anchors.right: parent.right
                    width: parent.width
                    theme: win.theme
                    fontFamily: win.fontFamily
                    model: win._fontList
                    popupMaxHeight: 280

                    // Apply immediately on selection — the whole window (and the
                    // rest of the shell) rebinds to Config.fontFamily live.
                    onActivated: (index) => {
                        Config.fontFamily = win._fontList[index];
                        Config.save();
                    }

                    // Keep the shown value in sync with Config (covers Reset to
                    // defaults and external edits); survives imperative
                    // currentIndex changes that a plain binding wouldn't.
                    Binding {
                        target: fontSelect
                        property: "currentIndex"
                        value: Math.max(0, win._fontList.indexOf(Config.fontFamily))
                    }
                }
            }

            RowLayoutShim {
                label: "Corner radius"
                hint: "Rounding of cards & buttons"

                control: SliderControl {
                    anchors.right: parent.right
                    from: 0
                    to: 20
                    stepSize: 1
                    snap: true
                    value: Config.radius
                    valueText: Config.radius + "px"
                    onMoved: (v) => { Config.radius = Math.round(v); Config.save(); }
                }
            }

            RowLayoutShim {
                label: "Surface opacity"
                hint: "Translucency of popouts (needs blur)"

                control: SliderControl {
                    anchors.right: parent.right
                    from: 0.5
                    to: 1.0
                    stepSize: 0.01
                    value: Config.surfaceOpacity
                    valueText: Math.round(Config.surfaceOpacity * 100) + "%"
                    onMoved: (v) => { Config.surfaceOpacity = v; Config.save(); }
                }
            }

            // ── Behavior ──────────────────────────────────────────────────
            SectionLabel { text: "BEHAVIOR" }

            RowLayoutShim {
                label: "Toast duration"
                hint: "How long notifications stay on screen"

                control: SliderControl {
                    anchors.right: parent.right
                    from: 1000
                    to: 15000
                    stepSize: 500
                    snap: true
                    value: Config.toastDurationMs
                    valueText: (Config.toastDurationMs / 1000).toFixed(1) + "s"
                    onMoved: (v) => { Config.toastDurationMs = Math.round(v); Config.save(); }
                }
            }

            RowLayoutShim {
                label: "OSD timeout"
                hint: "Auto-hide delay for the volume/brightness pill"

                control: SliderControl {
                    anchors.right: parent.right
                    from: 1000
                    to: 15000
                    stepSize: 500
                    snap: true
                    value: Config.osdHideMs
                    valueText: (Config.osdHideMs / 1000).toFixed(1) + "s"
                    onMoved: (v) => { Config.osdHideMs = Math.round(v); Config.save(); }
                }
            }

            RowLayoutShim {
                label: "Reminder lead times"
                hint: "Minutes before an event to notify (comma-separated)"

                control: Rectangle {
                    width: parent.width
                    height: 28
                    radius: win.theme.radius
                    color: Qt.rgba(win.theme.fg.r, win.theme.fg.g, win.theme.fg.b, 0.06)
                    border.color: leadsInput.activeFocus ? win.theme.accent : win.theme.border
                    border.width: 1

                    TextInput {
                        id: leadsInput
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: win.theme.fg
                        font.family: win.fontFamily
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true
                        selectionColor: win.theme.accent
                        text: (Config.reminderLeadsMin || []).join(", ")

                        // Parse "60, 15, 5" → [60,15,5]; drop blanks/non-numbers,
                        // sort descending so the earliest lead fires first.
                        function commit() {
                            const parts = text.split(",")
                                .map(s => parseInt(s.trim(), 10))
                                .filter(n => !isNaN(n) && n >= 0);
                            const uniq = Array.from(new Set(parts)).sort((a, b) => b - a);
                            Config.reminderLeadsMin = uniq;
                            Config.save();
                            text = uniq.join(", ");
                        }
                        onEditingFinished: commit()
                        Keys.onReturnPressed: { commit(); focus = false; }
                    }
                }
            }

            // ── Footer ────────────────────────────────────────────────────
            Item { width: 1; height: 12 }

            Row {
                spacing: 10
                anchors.right: parent.right

                Rectangle {
                    width: resetText.implicitWidth + 24
                    height: 30
                    radius: win.theme.radius
                    color: resetMa.containsMouse ? Qt.rgba(win.theme.fg.r, win.theme.fg.g, win.theme.fg.b, 0.10) : "transparent"
                    border.color: win.theme.border
                    border.width: 1

                    Text {
                        id: resetText
                        anchors.centerIn: parent
                        text: "Reset to defaults"
                        color: win.theme.fg
                        font.family: win.fontFamily
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.resetDefaults()
                    }
                }

                Rectangle {
                    width: closeText.implicitWidth + 24
                    height: 30
                    radius: win.theme.radius
                    color: closeMa.containsMouse ? Qt.darker(win.theme.accent, 1.1) : win.theme.accent

                    Text {
                        id: closeText
                        anchors.centerIn: parent
                        text: "Close"
                        color: win.theme.bg
                        font.family: win.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.open = false
                    }
                }
            }
        }
    }

    // Monospace fonts first (most relevant for this shell), then everything
    // else — both alphabetical. Computed once.
    readonly property var _fontList: {
        const all = Qt.fontFamilies();
        const mono = [], rest = [];
        for (let i = 0; i < all.length; i++) {
            const f = all[i];
            if (f.toLowerCase().indexOf("mono") >= 0) mono.push(f);
            else rest.push(f);
        }
        return mono.concat(rest);
    }

    function resetDefaults() {
        Config.fontFamily = "JetBrainsMono Nerd Font Mono";
        Config.radius = 4;
        Config.surfaceOpacity = 0.92;
        Config.toastDurationMs = 5000;
        Config.osdHideMs = 5000;
        Config.reminderLeadsMin = [60, 15, 5, 1];
        Config.save();
    }
}
