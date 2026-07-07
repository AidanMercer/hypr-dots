import QtQuick
import Quickshell
import Quickshell.Wayland
import "../common"

// Standalone, NON-locking preview of the lock UI. Run in isolation with:
//   qs -p ~/dotfiles/.config/quickshell/modules/lock/PreviewLock.qml
// It's just an overlay window (no WlSessionLock, no PAM), so it can't lock you
// out — kill the qs process to dismiss. Used to iterate on the look safely.
ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell-lockpreview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        color: ThemeConfig.glass

        LockStage {
            id: content
            anchors.fill: parent
            screenName: ""
            // no real auth in preview — Enter plays the unlock exit, then quits
            onSubmitted: content.unlocking = true
            onOutDone: Qt.quit()
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
        }
    }
}
