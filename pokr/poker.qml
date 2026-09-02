//  poker.qml — the standalone entry point.
//
//  run:     qs -p ~/cloon/widgames/pokr/poker.qml
//
//  The game is Poker.qml next door, and everything worth reading is in there.
//  This wrapper exists so the game can also be a component — see blackjack.qml
//  for that and for what `standalone` is doing.

import Quickshell

ShellRoot {
    Poker {
        standalone: true
        open: true
    }
}
