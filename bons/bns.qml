//  bns.qml — the standalone entry point.
//
//  run:     qs -p ~/cloon/widgames/bons/bns.qml
//  toggle:  qs -p ~/cloon/widgames/bons/bns.qml ipc call bones toggle
//
//  The game is Bones.qml next door, and everything worth reading is in there.
//  This exists so it can also be a component: edge instantiates Bones
//  directly, inside its own ShellRoot, and a config can only have one of
//  those.
//
//  `standalone` is what keeps closing it a quit here and only a hide in edge —
//  this process has nothing to do once the widget is down, and the shell has
//  everything else.

import Quickshell

ShellRoot {
    Bones {
        standalone: true
        open: true
    }
}
