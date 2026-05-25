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
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
    }

    Workspaces {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }

    NetBubble {
        id: netBubble
        anchors.right: audioBubble.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        onPopupToggleRequested: netPopup.open = !netPopup.open
    }

    AudioBubble {
        id: audioBubble
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        onPopupToggleRequested: audioPopup.open = !audioPopup.open
    }

    AudioPopup {
        id: audioPopup
        barWindow: bar
        bubbleRight: audioBubble.x + audioBubble.width
    }

    NetPopup {
        id: netPopup
        barWindow: bar
        bubbleRight: netBubble.x + netBubble.width
        connType: netBubble.connType
        connName: netBubble.connName
        onConnectionChanged: netBubble.refresh()
    }

    HyprlandFocusGrab {
        windows: [audioPopup]
        active: audioPopup.open
        onCleared: audioPopup.open = false
    }

    HyprlandFocusGrab {
        windows: [netPopup]
        active: netPopup.open
        onCleared: netPopup.open = false
    }
}
