//  bns.qml — the standalone entry point.
//
//  run:     qs -p ~/cloon/widgames/bons/bns.qml
//  toggle:  qs -p ~/cloon/widgames/bons/bns.qml ipc call bones toggle
//
//  The game is Bones.qml next door, and everything worth reading is in there.
//  This wrapper exists so the game can also be a component — see blackjack.qml
//  for that and for what `standalone` is doing.

import Quickshell

ShellRoot {
    Bones {
        standalone: true
        open: true
    }
}
