//  ridethebus.qml — the standalone entry point.
//
//  run:     qs -p ~/cloon/widgames/busride/ridethebus.qml
//  toggle:  qs -p ~/cloon/widgames/busride/ridethebus.qml ipc call ridethebus toggle
//
//  The game is RideTheBus.qml next door, and everything worth reading is in
//  there. This wrapper exists so the game can also be a component — see
//  blackjack.qml for that and for what `standalone` is doing.

import Quickshell

ShellRoot {
    RideTheBus {
        standalone: true
        open: true
    }
}
