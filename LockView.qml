// Lock screen UI — blurred wallpaper + a themed password field.
// Password-only (no fingerprint). Drawn once per output by Lock.qml's WlSessionLockSurface.

import QtQuick
import QtQuick.Effects
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import "shared"

Item {
    id: root

    required property color bgColor
    required property color fgColor
    required property color accentColor
    required property color borderColor
    required property color dangerColor
    required property color warnColor
    required property int cornerRadius
    required property string fontFamily

    property string backgroundPath: ""
    property bool authenticating: false
    property string failureMessage: ""
    property bool inputEnabled: true
    property string passwordText: ""
    property bool syncingPasswordText: false

    readonly property string placeholderText: "Enter Password"
    readonly property int fieldWidth: 320
    readonly property int fieldHeight: 52
    readonly property bool errorState: failureMessage.length > 0

    signal submitPassword(string password)
    signal passwordTextEdited(string password)
    signal clearFailureRequested

    function forcePasswordFocus() {
        passwordInput.forceActiveFocus();
    }

    function syncPasswordText() {
        if (passwordInput.text === passwordText)
            return;
        syncingPasswordText = true;
        passwordInput.text = passwordText;
        syncingPasswordText = false;
    }

    onPasswordTextChanged: syncPasswordText()
    onInputEnabledChanged: if (inputEnabled)
        Qt.callLater(forcePasswordFocus)
    Component.onCompleted: {
        syncPasswordText();
        if (inputEnabled)
            Qt.callLater(forcePasswordFocus);
    }

    Rectangle {
        anchors.fill: parent
        color: root.bgColor

        Image {
            id: wallpaper
            anchors.fill: parent
            source: root.backgroundPath ? "file://" + root.backgroundPath : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: width
            sourceSize.height: height
        }

        MultiEffect {
            anchors.fill: wallpaper
            source: wallpaper
            autoPaddingEnabled: false
            blurEnabled: wallpaper.status === Image.Ready
            blur: 1.0
            blurMax: 96
            blurMultiplier: 1.2
        }

        Rectangle {
            id: inputField
            width: root.fieldWidth
            height: root.fieldHeight
            anchors.centerIn: parent
            radius: root.cornerRadius
            color: Qt.rgba(root.bgColor.r, root.bgColor.g, root.bgColor.b, 0.85)
            border.width: 2
            border.color: root.errorState ? root.dangerColor : root.accentColor

            TextInput {
                id: passwordInput
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                activeFocusOnPress: true
                clip: true
                enabled: root.inputEnabled && !root.authenticating
                readOnly: root.authenticating
                echoMode: TextInput.Password
                passwordCharacter: "●"
                inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                passwordMaskDelay: 0
                color: root.fgColor
                selectionColor: root.accentColor
                selectedTextColor: root.fgColor
                font.family: root.fontFamily
                font.pixelSize: 16
                font.letterSpacing: 4

                onTextChanged: {
                    if (!root.syncingPasswordText)
                        root.passwordTextEdited(text);
                    if (text.length > 0 && root.failureMessage.length > 0)
                        root.clearFailureRequested();
                }

                onAccepted: {
                    const submitted = root.passwordText;
                    root.passwordTextEdited("");
                    if (submitted.length > 0)
                        root.submitPassword(submitted);
                }

                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                        root.passwordTextEdited("");
                        event.accepted = true;
                    }
                }
            }

            Text {
                anchors.fill: passwordInput
                text: root.authenticating ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
                visible: passwordInput.text.length === 0
                color: root.authenticating ? root.fgColor : (root.failureMessage.length > 0 ? root.dangerColor : root.fgColor)
                opacity: root.authenticating || root.failureMessage.length > 0 ? 1.0 : 0.5
                font.family: root.fontFamily
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: inputField.top
            anchors.bottomMargin: 24
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.fgColor
                font.family: root.fontFamily
                font.pixelSize: 56
                text: root.now.toLocaleTimeString(Qt.locale(), "HH:mm")
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.fgColor
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: 16
                text: root.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
            }
        }

        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 20
            spacing: 14

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                visible: NotificationManager.count > 0

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.fgColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    text: "󰂚"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.fgColor
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    text: NotificationManager.count.toString()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: root.fgColor
                font.family: root.fontFamily
                font.pixelSize: 19
                text: root.netIcon
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: root.batteryDev !== null

                BatteryIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    fgColor: root.fgColor
                    fillColor: {
                        if (!root.batteryDev)
                            return root.fgColor;
                        const pct = Math.round(root.batteryDev.percentage * 100);
                        if (pct <= 10 && UPower.onBattery)
                            return root.dangerColor;
                        if (pct <= 40 && UPower.onBattery)
                            return root.warnColor;
                        return root.fgColor;
                    }
                    pct: root.batteryDev ? Math.round(root.batteryDev.percentage * 100) : 0
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.fgColor
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    text: root.batteryDev ? Math.round(root.batteryDev.percentage * 100) + "%" : ""
                }
            }
        }

        Column {
            id: nowPlayingCard
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 20
            width: 282
            spacing: 10
            visible: root.nowPlayingPlayer !== null

            Row {
                spacing: 10

                Rectangle {
                    id: artBox
                    width: 52
                    height: 52
                    radius: root.cornerRadius
                    color: root.borderColor
                    clip: true

                    Image {
                        id: art
                        anchors.fill: parent
                        source: root.nowPlayingPlayer ? (root.nowPlayingPlayer.trackArtUrl ?? "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !art.visible
                        text: "󰝚"
                        color: root.bgColor
                        font.pixelSize: 24
                    }
                }

                Column {
                    anchors.verticalCenter: artBox.verticalCenter
                    spacing: 1

                    Text {
                        color: root.fgColor
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        width: 220
                        text: root.nowPlayingPlayer ? root.nowPlayingPlayer.trackTitle : ""
                    }

                    Text {
                        color: root.fgColor
                        opacity: 0.7
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        width: 220
                        text: root.nowPlayingPlayer ? root.nowPlayingPlayer.trackArtist : ""
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                MouseArea {
                    id: prevBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: root.nowPlayingPlayer?.canGoPrevious ?? false
                    onClicked: root.nowPlayingPlayer?.previous()

                    scale: containsMouse && enabled ? 1.15 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutQuad
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒮"
                        color: root.fgColor
                        font.family: root.fontFamily
                        font.pixelSize: 17
                        opacity: parent.enabled ? 1.0 : 0.3
                    }
                }

                MouseArea {
                    id: playPauseBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: root.nowPlayingPlayer?.canTogglePlaying ?? false
                    onClicked: root.nowPlayingPlayer?.togglePlaying()

                    scale: containsMouse && enabled ? 1.1 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutQuad
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: root.fgColor
                        opacity: parent.enabled ? 1.0 : 0.3
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.nowPlayingPlayer?.isPlaying ? "󰏤" : "󰐊"
                        color: root.bgColor
                        font.family: root.fontFamily
                        font.pixelSize: 15
                    }
                }

                MouseArea {
                    id: nextBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: root.nowPlayingPlayer?.canGoNext ?? false
                    onClicked: root.nowPlayingPlayer?.next()

                    scale: containsMouse && enabled ? 1.15 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutQuad
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒭"
                        color: root.fgColor
                        font.family: root.fontFamily
                        font.pixelSize: 17
                        opacity: parent.enabled ? 1.0 : 0.3
                    }
                }
            }
        }
    }

    readonly property var nowPlayingPlayer: {
        const list = Mpris.players.values;
        for (let i = 0; i < list.length; i++)
            if (list[i].playbackState === MprisPlaybackState.Playing)
                return list[i];
        for (let i = 0; i < list.length; i++)
            if (list[i].playbackState === MprisPlaybackState.Paused)
                return list[i];
        for (let i = 0; i < list.length; i++)
            if (list[i].trackTitle)
                return list[i];
        return null;
    }

    readonly property var batteryDev: UPower.displayDevice && UPower.displayDevice.isPresent ? UPower.displayDevice : null
    property var now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    property string netIcon: "󰀂"

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!netProc.running)
            netProc.running = true
    }
    Process {
        id: netProc
        command: ["sh", "-c", "dev=$(ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"dev\"){print $(i+1); exit}}'); if [ -z \"$dev\" ]; then for d in /sys/class/net/*/; do n=$(basename \"$d\"); [ \"$n\" = lo ] && continue; c=$(cat \"$d\"carrier 2>/dev/null); [ \"$c\" = 1 ] && { dev=$n; break; }; done; fi; if [ -z \"$dev\" ]; then echo off; exit; fi; if [ -d \"/sys/class/net/$dev/wireless\" ]; then sig=$(iw dev \"$dev\" link 2>/dev/null | awk '/signal:/{print $2; exit}'); if [ -z \"$sig\" ]; then echo off; else pct=$(( (sig + 100) * 2 )); [ \"$pct\" -lt 0 ] && pct=0; [ \"$pct\" -gt 100 ] && pct=100; echo \"wifi:$pct\"; fi; else echo ethernet; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t === "ethernet") {
                    root.netIcon = "󰤮";
                    return;
                }
                if (t === "off" || t === "") {
                    root.netIcon = "󰀂";
                    return;
                }
                if (t.indexOf("wifi:") === 0) {
                    const sig = parseInt(t.substring(5), 10) || 0;
                    const icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"];
                    const idx = Math.min(4, Math.floor(sig / 20));
                    root.netIcon = icons[idx];
                }
            }
        }
    }
}
