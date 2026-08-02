//  blackjack.qml — the standalone entry point.
//
//  run:     qs -p ~/cloon/widgames/bjak/blackjack.qml
//  toggle:  qs -p ~/cloon/widgames/bjak/blackjack.qml ipc call blackjack toggle
//
//  The game is Blackjack.qml next door, and everything worth reading is in
//  there. This exists so it can also be a component: edge instantiates
//  Blackjack directly, inside its own ShellRoot, and a config can only have
//  one of those.
//
//  `standalone` is what keeps closing it a quit here and only a hide in edge —
//  this process has nothing to do once the widget is down, and the shell has
//  everything else.

import Quickshell

ShellRoot {
    Blackjack {
        standalone: true
        open: true
    }
}
