// Password-only session lock — Wayland ext-session-lock-v1 via WlSessionLock,
// PAM auth via PamContext. Trigger manually for now via:
//   qs -p <path-to-shell.qml> ipc call lock lock
// Not yet wired into hypridle/omarchy-system-lock — hyprlock stays the
// automatic lock for now until this has been tested end-to-end.
//
// Requires /etc/pam.d/willow-lock to exist (mirrors /etc/pam.d/hyprlock's
// `auth include login`). Locking is refused if that file is missing so we
// never show a password prompt with no way to authenticate against it.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

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

    readonly property string home: Quickshell.env("HOME")
    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
    readonly property string backgroundLink: home + "/.config/omarchy/current/background"

    property bool lockRequested: false
    property bool authenticating: false
    property bool passwordPamConfigured: false
    property string enteredPassword: ""
    property string pendingPassword: ""
    property string failureMessage: ""
    property int failedAttempts: 0
    property string backgroundPath: ""

    readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure

    function refreshBackground() {
        if (!readlinkProc.running)
            readlinkProc.running = true;
    }

    function resetAuthenticationState() {
        enteredPassword = "";
        pendingPassword = "";
        failureMessage = "";
        failedAttempts = 0;
        authenticating = false;
        if (passwordPam.active)
            passwordPam.abort();
    }

    function beginLock() {
        if (!passwordPamConfigured) {
            console.log("willow lock: refused — /etc/pam.d/willow-lock missing");
            return false;
        }
        resetAuthenticationState();
        lockRequested = true;
        refreshBackground();
        sessionLock.locked = true;
        return true;
    }

    function finishUnlock() {
        lockRequested = false;
        resetAuthenticationState();
        sessionLock.locked = false;
    }

    function submitPassword(value) {
        const password = String(value || "");
        if (!lockRequested || authenticating || password.length === 0)
            return;
        pendingPassword = password;
        failureMessage = "";
        authenticating = true;
        if (!passwordPam.start()) {
            handlePasswordFailure();
            return;
        }
        Qt.callLater(respondToPasswordPrompt);
    }

    function respondToPasswordPrompt() {
        if (!authenticating || !passwordPam.active || !passwordPam.responseRequired)
            return;
        passwordPam.respond(pendingPassword);
    }

    function handlePasswordFailure() {
        if (!lockRequested)
            return;
        authenticating = false;
        enteredPassword = "";
        pendingPassword = "";
        failedAttempts += 1;
        failureMessage = "Authentication failed (" + failedAttempts + ")";
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        onLockStateChanged: {
            if (!locked && root.lockRequested) {
                // Compositor cleared the lock out from under us (e.g. failsafe).
                root.lockRequested = false;
                root.resetAuthenticationState();
            }
        }

        WlSessionLockSurface {
            color: root.bgColor

            LockView {
                anchors.fill: parent
                bgColor: root.bgColor
                fgColor: root.fgColor
                accentColor: root.accentColor
                borderColor: root.borderColor
                dangerColor: root.dangerColor
                warnColor: root.warnColor
                cornerRadius: root.cornerRadius
                fontFamily: root.fontFamily
                backgroundPath: root.backgroundPath
                authenticating: root.authenticating
                failureMessage: root.failureMessage
                inputEnabled: root.lockRequested
                passwordText: root.enteredPassword
                onPasswordTextEdited: password => root.enteredPassword = password
                onSubmitPassword: password => root.submitPassword(password)
                onClearFailureRequested: root.failureMessage = ""
            }
        }
    }

    PamContext {
        id: passwordPam
        config: "willow-lock"
        user: root.userName

        onResponseRequiredChanged: root.respondToPasswordPrompt()
        onPamMessage: root.respondToPasswordPrompt()

        onCompleted: function (result) {
            root.authenticating = false;
            root.pendingPassword = "";
            if (!root.lockRequested)
                return;
            if (result === PamResult.Success)
                root.finishUnlock();
            else
                root.handlePasswordFailure();
        }

        onError: function (error) {
            root.handlePasswordFailure();
        }
    }

    Process {
        id: readlinkProc
        command: ["readlink", "-f", root.backgroundLink]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.backgroundPath = this.text.trim()
        }
    }

    FileView {
        path: "/etc/pam.d/willow-lock"
        watchChanges: true
        printErrors: false
        onLoaded: root.passwordPamConfigured = true
        onLoadFailed: root.passwordPamConfigured = false
    }

    Component.onCompleted: refreshBackground()

    IpcHandler {
        target: "lock"

        function lock(): string {
            if (!root.passwordPamConfigured)
                return "missing-pam";
            if (!root.locked && !root.beginLock())
                return "failed";
            return "ok";
        }

        function isLocked(): string {
            return root.locked ? "true" : "false";
        }
    }
}
