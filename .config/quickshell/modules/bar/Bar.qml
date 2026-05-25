import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "../common"

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell-bar"

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: "transparent"

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    DateBubble {
        id: dateBubble
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
    }

    UptimeBubble {
        anchors.left: dateBubble.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
    }

    Workspaces {
        monitor: Hyprland.monitorFor(bar.screen)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }

    ControlBubble {
        id: controlBubble
        anchors.right: powerButton.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        onPopupToggleRequested: controlPopup.open = !controlPopup.open
    }

    PowerButton {
        id: powerButton
        active: powerMenu.open
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        onToggleRequested: powerMenu.open = !powerMenu.open
    }

    ControlPopup {
        id: controlPopup
        barWindow: bar
        anchorRight: controlBubble.x + controlBubble.width
        connType: controlBubble.connType
        connName: controlBubble.connName
        onConnectionChanged: controlBubble.refresh()
    }

    PowerMenu {
        id: powerMenu
        barWindow: bar
        anchorRight: powerButton.x + powerButton.width
    }

    HyprlandFocusGrab {
        windows: [controlPopup]
        active: controlPopup.open
        onCleared: controlPopup.open = false
    }

    HyprlandFocusGrab {
        windows: [powerMenu]
        active: powerMenu.open
        onCleared: powerMenu.open = false
    }
}
