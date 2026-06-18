import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam

// The real session lock. Idle (locked=false) until something calls
//   qs ipc call lock lock
// (hypridle's lock_cmd / loginctl lock-session, same triggers hyprlock used).
// WlSessionLock engages the ext-session-lock protocol and spawns one
// WlSessionLockSurface per monitor; each shows LockContent (blurred wallpaper +
// the theme's animated clock + passcode dots). Typing a password and pressing
// Enter runs it through PAM using the existing /etc/pam.d/hyprlock stack; on
// success we drop the lock. If this ever wedges, recover from a TTY with
// `loginctl unlock-session`.
Scope {
    id: root

    property bool locked: false
    property bool authBusy: false
    property bool authFailed: false
    property int resetNonce: 0
    property string pending: ""

    function tryAuth(pw) {
        if (authBusy || pw.length === 0) return
        pending = pw
        authFailed = false
        authBusy = true
        if (!pam.start()) {       // couldn't even start the conversation
            authBusy = false
            authFailed = true
            resetNonce++
        }
    }

    PamContext {
        id: pam
        config: "hyprlock"        // reuse hyprlock's known-good PAM stack

        // PAM drives the conversation through pamMessage; when it wants input
        // (responseRequired) we feed our pending password.
        onPamMessage: if (responseRequired) respond(root.pending)

        onCompleted: function(result) {
            root.authBusy = false
            root.pending = ""
            if (result === PamResult.Success) {
                root.authFailed = false
                root.locked = false        // tears down the lock surfaces
            } else {
                root.authFailed = true
                root.resetNonce++          // clear the field, show "wrong"
            }
        }
        onError: {
            root.authBusy = false
            root.pending = ""
            root.authFailed = true
            root.resetNonce++
        }
    }

    WlSessionLock {
        id: session
        locked: root.locked

        WlSessionLockSurface {
            id: surface
            color: "black"

            LockContent {
                anchors.fill: parent
                screenName: surface.screen ? surface.screen.name : ""
                failed: root.authFailed
                busy: root.authBusy
                resetNonce: root.resetNonce
                onSubmitted: pw => root.tryAuth(pw)
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.locked = true }
        function isLocked(): bool { return root.locked }
    }
}
