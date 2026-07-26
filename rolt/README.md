# rolt

European single-zero roulette as a Quickshell widget. Quickshell/QML, one file,
no dependencies beyond what you already have installed.

Single zero — 37 pockets, **2.70%** house edge. Full inside betting: straights,
splits, streets, trios, corners, the first four, six-lines, plus every outside
bet.

## Run

```sh
qs -p ~/cloon/widgames/rolt/roulette.qml
```

It opens as a normal 708×682 desktop window. It is not on a layer shell yet —
that comes when it goes into [edge](../edge).

**Closing quits it.** `esc`, the compositor's close and `ipc call roulette hide`
all end the process rather than hiding the window, so a shut widget costs
nothing — no engine, no wheel, no memory. Opening it again is the command above.

## Playing

Click the felt to put the selected chip down. The chip lands on the **nearest
bet spot**, so lines and intersections work exactly as they do on a real felt:
the middle of a cell is a straight, the line between two is a split, a corner
where four meet is a corner, and the line under a column of three is a street.

Hovering lights up the spot *and every number it covers* — the easiest way to
find corners and six-lines without counting squares.

| input             | action                          |
|-------------------|---------------------------------|
| left click        | place a chip                    |
| right click       | take one chip back off that spot|
| `1`–`4`           | select chip: 1 / 5 / 25 / 100   |
| `space`           | spin                            |
| `u`               | undo the last chip              |
| `c`               | clear the felt                  |
| `r`               | rebet the last round            |
| `esc`             | quit                            |

## Payouts

| bet         | pays | bet          | pays |
|-------------|------|--------------|------|
| straight    | 35:1 | first four   | 8:1  |
| split       | 17:1 | six-line     | 5:1  |
| street      | 11:1 | column/dozen | 2:1  |
| trio        | 11:1 | red · black · odd · even · 1-18 · 19-36 | 1:1 |
| corner      | 8:1  |              |      |

Zero takes every outside bet — no la partage, no en prison. There is no table
minimum or maximum.

## The spin

The winning pocket is drawn before the wheel starts turning and the motion is
solved to arrive there, which is the only way the ball is guaranteed to land on
the number the RNG actually picked.

It still moves like a real one. Both the wheel and the ball run under
exponential friction, and the ball leaves the track only once its speed relative
to the wheel has bled off. The handoff from free motion to the solved landing
picks the moment when the two already agree, so the ball's speed changes by
under 3% as it happens — no visible kick. It then scatters across the frets and
drops, seats about 0.7s before the wheel stops, and rides the rest of the coast
locked to its pocket.

About 5 seconds, and you cannot read the result until the last of it.

## Credits

Start at 200, separate from the poker bank, and kept across closings in

```
~/.local/state/quickshell/by-shell/<id>/bank.json
```

which is the one thing in the widget that touches disk. It is written whenever
the figure moves and read before the first frame, so closing mid-session and
reopening lands you back on the same number rather than on 200.

The path comes from `Quickshell.statePath`, which hashes the *canonical* config
path — so it is the same file whether the widget is launched as
`rolt/roulette.qml` or as `edge/../widgames/rolt/roulette.qml`.

Busting is not a dead end: an empty bank refills to 200 at the end of the round,
since the smallest chip is 1 and a bank of nothing is a widget you cannot play.
`ipc call roulette reset` puts it back to 200 deliberately, and deleting
`bank.json` is the same thing.

## IPC

```sh
qs -p ~/cloon/widgames/rolt/roulette.qml ipc call roulette <fn>
```

| function        | effect                                        |
|-----------------|-----------------------------------------------|
| `toggle`/`hide` | quit — a reachable widget is an open one      |
| `show`          | no-op; it is already open if you can call it  |
| `spin`          | spin, if there is anything on the felt        |
| `bet <id> <n>`  | stake `n` on a spot, ignoring the chip rack   |
| `chip <n>`      | select a chip denomination                    |
| `undo`          | lift the last chip                            |
| `clear`         | clear the felt                                |
| `reset`         | put the bank back to 200                      |
| `rebet`         | replay the last round's bets                  |
| `status`        | JSON: visible, credits, wagered, chip, phase, lastNumber, lastWin, history, bets |

Spot ids are what `status` reports — `straight:17`, `corner:8-9-11-12`,
`street:16-17-18`, `red:1-3-5-…`. So a whole round is scriptable:

```sh
R="qs -p ~/cloon/widgames/rolt/roulette.qml ipc call roulette"
$R bet straight:17 25
$R bet corner:8-9-11-12 5
$R spin
```

`status` is also how you ask whether the widget is up at all: a reply means it
is running, and `ipc call` exiting 255 with nothing on stdout means it is not.
That single question is enough to drive a toggle button — no reply, start the
process; a reply, send `hide`. Which is what the poker tab's service already
does, minus the third case.

(As with poker, `qs ipc call roulette show` is unreachable from the CLI anyway —
the `qs ipc show` subcommand swallows it, prints the interface and exits 0
without calling anything. It is a no-op here regardless.)

## Theming

Everything visual is in the `theme` block at the top of `roulette.qml` — colors,
felt, wheel, fonts. It ships matching your bar's `#16161e` base.

Two faces, split by job:

| | | |
|---|---|---|
| `font` | Open Sans | every word — labels, messages, buttons, outside bets |
| `display` | DejaVu Sans | every figure — the winning number, the bank, the meters, the chips, the felt cells, the wheel |

The numbers get the heaviest sans available, because one face has to carry both
10px wheel pockets and the 46px result badge. It also keeps `1` and `7` apart,
which a geometric face does not, and "17" has to be readable at 13px in a cell.

The felt's proportions live in `geo` just below it. Changing a cell size moves
the bet spots with it, because both come off the same numbers.

## Tests

```sh
node test-roulette.js
```

Reads the wheel, the bet-spot generator, the payout resolver and the spin
solver straight out of `roulette.qml`, so it tests the shipped code rather than
a copy.

```
wheel order          37 pockets     ok
red/black split      18 / 18        ok
spot counts          157 spots      ok
spot shapes          numbers valid  ok
spot ids             unique         ok
spot spacing         min 22.0px     ok
outside bets         sets correct   ok
dozens/columns       partition 1-36 ok
payout invariant     157 spots      ok
expected return      5652/5809      ok
mixed board          23 bets        ok
spin lands           2220 spins     ok
ball seats           in the pocket  ok
handoff smooth       2.9% max       ok
spin length          5.0-5.6s       ok
crossing found       2220/2220      ok
------------------------------------------------
house edge: 2.70%  (expect 2.70%)
```

Two of those carry most of the weight.

**expected return** stakes 1 on each of the 157 spots and runs all 37 outcomes
against `resolve()`. In single zero every bet returns exactly 36/37, so a wrong
17:1, a miscounted corner or an off-by-one in a number set all fail the same
assertion — and it names the spot that did it.

**spin lands** pulls the integrator and the solved settle out of the QML and
runs 2,220 spins headless at 60fps, checking where the ball actually comes to
rest. It has to be the chosen pocket every time, to within a millionth of a
degree.

## Next

Moving onto a layer shell for the edge bar. Everything below `frame` in
`roulette.qml` is self-contained, so that is a swap of the window block for
poker's `PanelWindow` plus its `open`/`showing` slide, and nothing else.
