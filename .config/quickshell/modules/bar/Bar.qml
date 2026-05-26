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

    // Top-right: live CPU / RAM / GPU usage, mirroring the date bubble's margin.
    ResourceBubble {
        id: resourceBubble
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
    }

    Workspaces {
        id: workspaces
        monitor: Hyprland.monitorFor(bar.screen)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }

    // Single status button just right of the workspaces. Opens the ControlPopup
    // (network / sound / bluetooth / power) and owns the uptime + network status
    // the popup displays.
    StatusButton {
        id: statusButton
        active: controlPopup.open
        anchors.left: workspaces.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        onPopupToggleRequested: ControlBus.toggle(bar.screen ? bar.screen.name : "")
    }

    ControlPopup {
        id: controlPopup
        barWindow: bar
        anchorCenterX: statusButton.x + statusButton.width / 2
        connType: statusButton.connType
        connName: statusButton.connName
        uptimeText: statusButton.uptimeText
        onConnectionChanged: statusButton.refresh()
    }
}
