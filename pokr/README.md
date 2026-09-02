# pokr

Jacks or Better video poker as a Hyprland widget. Quickshell/QML, one file, no
dependencies beyond what you already have installed.

Standard **9/6** pay table (the good one — 9× full house, 6× flush).

## Run

```sh
qs -p ~/cloon/newdot/games/pokr/poker.qml
```

It appears as a centered layer-shell overlay. Launching it shows it; after that,
drive it over IPC.

## Controls

| key       | action                  |
|-----------|-------------------------|
| `1`–`5`   | hold / unhold a card    |
| `space`   | deal, then draw         |
| `b`       | bet one (cycles 1→5→1)  |
| `m`       | max bet + deal          |
| `esc`     | hide                    |

Clicking a card toggles its hold. The widget only takes keyboard focus once you
click it (`keyboardFocus: OnDemand`), so it won't steal input while it sits idle.

## Hyprland

Add to `hyprland.conf`:

```conf
exec-once = qs -p ~/cloon/newdot/games/pokr/poker.qml

# toggle with SUPER+P
bind = SUPER, P, exec, qs -p ~/cloon/newdot/games/pokr/poker.qml ipc call poker toggle

# optional: blur behind it (the layer namespace is "poker")
layerrule = blur, poker
layerrule = ignorealpha 0.3, poker
```

If you autostart it, it comes up visible — press `esc` or hit the toggle bind
once to tuck it away.

## IPC

```sh
qs -p ~/cloon/newdot/games/pokr/poker.qml ipc call poker <fn>
```

| function      | effect                                    |
|---------------|-------------------------------------------|
| `toggle`      | show/hide                                 |
| `show`/`hide` | explicit                                  |
| `play`        | deal, or draw — whichever the phase wants  |
| `hold <n>`    | toggle hold on card `n` (1-indexed)        |
| `betOne`      | bump the bet                               |
| `maxBet`      | bet 5 and deal                             |
| `status`      | JSON: visible, credits, bet, phase, lastWin, hand |

`visible` reports whether the widget is on screen rather than merely running.
Note that `show` is unreachable over the CLI — `qs ipc call poker show` is
swallowed by the `qs ipc show` subcommand, which prints the interface and exits 0
without calling anything. Read `visible` and send `toggle` instead; that is what
the pit in [house](../../house/README.md) does.

`status` is there so you can surface credits elsewhere — e.g. in waybar:

```json
"custom/poker": {
  "exec": "qs -p ~/cloon/newdot/games/pokr/poker.qml ipc call poker status | jq -r '\"\\(.credits)c\"'",
  "interval": 5
}
```

## Credits

Start at 200, held in memory. They persist while the Quickshell process lives
(including across hide/show), and reset to 200 when you restart it.

## Theming

Everything visual is in the `theme` block at the top of `poker.qml` — colors,
card size, spacing, font. It ships matching your bar's palette (`#16161e`
base, JetBrainsMono Nerd Font).

## Tests

The hand evaluator is checked by exhaustive enumeration — all 2,598,960 possible
five-card hands, with the category counts compared against the known exact poker
distribution. It reads `evaluate()` straight out of `poker.qml`, so it tests the
shipped code rather than a copy.

```sh
node test-eval.js
```

```
Royal Flush                 4          4  ok
Straight Flush             36         36  ok
Four of a Kind            624        624  ok
Full House               3744       3744  ok
Flush                    5108       5108  ok
Straight                10200      10200  ok
Three of a Kind         54912      54912  ok
Two Pair               123552     123552  ok
Jacks or Better        337920     337920  ok
(no win)              2062860    2062860  ok
```
