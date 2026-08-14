// Battery — iOS/macOS-style body with a fill level + pct overlaid on top.
// Left click: power menu. Right click: notify current status. Hover: rate tooltip.

import QtQuick
import Quickshell.Services.UPower
import "shared"

MouseArea {
    id: batteryArea

    required property var bar
    required property color fgColor
    required property color bgColor
    required property color borderColor
    required property color successColor
    required property color warnColor
    required property color dangerColor

    anchors.verticalCenter: parent.verticalCenter
    width: batteryBody.width
    height: 22
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    visible: UPower.displayDevice && UPower.displayDevice.isPresent

    onClicked: function (mouse) {
        LaunchTrigger.launch(mouse.button === Qt.RightButton ? ["sh", "-c", "notify-send -u low \"$(omarchy-battery-status)\""] : ["omarchy-menu", "power"]);
    }
    onEntered: tooltip.open = true
    onExited: tooltip.open = false

    property var dev: UPower.displayDevice
    property int pct: dev ? Math.round(dev.percentage * 100) : 0
    readonly property bool charging: !UPower.onBattery
    readonly property color fillColor: pct <= 10 && UPower.onBattery ? dangerColor : pct <= 40 && UPower.onBattery ? warnColor : successColor

    BatteryIcon {
        id: batteryBody
        anchors.verticalCenter: parent.verticalCenter
        fgColor: batteryArea.fgColor
        fillColor: batteryArea.fillColor
        pct: batteryArea.pct
    }

    Tooltip {
        id: tooltip
        bar: batteryArea.bar
        anchorItem: batteryArea
        bgColor: batteryArea.bgColor
        borderColor: batteryArea.borderColor
        fgColor: batteryArea.fgColor

        readonly property var _dev: UPower.displayDevice
        property int _tick: 0
        Timer {
            interval: 2500
            running: tooltip.open
            repeat: true
            triggeredOnStart: true
            onTriggered: tooltip._tick++
        }

        text: {
            _tick;
            return _dev ? Math.round(_dev.changeRate) + "W" : "";
        }
        rightText: {
            _tick;
            return _dev ? Math.round(_dev.percentage * 100) + "%" : "";
        }
        arrowVisible: !!_dev
        arrowUp: batteryArea.charging
        arrowColor: batteryArea.charging ? batteryArea.successColor : batteryArea.dangerColor
    }
}
