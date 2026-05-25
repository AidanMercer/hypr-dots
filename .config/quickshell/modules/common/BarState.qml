pragma Singleton
import QtQuick

// Small shared bit of UI state. There is one Bar (and one Workspaces strip)
// per monitor via Variants, so transient global state like "is the user
// holding Super to reveal workspace numbers" lives here, where every bar can
// read it, rather than being duplicated or prop-drilled through Bar.
QtObject {
    // True while Super has been held long enough to reveal the workspace
    // numbers. Flipped over IPC from the Super keybind (see shell.qml).
    property bool showNumbers: false
}
