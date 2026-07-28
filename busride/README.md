# Ride the Bus

Four calls off one shuffled deck, each one on a card you have not seen. Get a
call wrong and the ride is over and the stake is gone. Get it right and the
stake rides at a bigger multiplier — which you may take at any point, or push.

```
qs -p ~/cloon/widgames/busride/ridethebus.qml
```

The game is `RideTheBus.qml`. `ridethebus.qml` is a four-line wrapper that puts
it in a `ShellRoot` so it can run as its own process; edge instantiates
`RideTheBus` directly, so the shell and the standalone widget are the same code
rather than two copies of it.

## The rungs

| # | Call | Pays | Notes |
|---|------|------|-------|
| 1 | **RED or BLACK** | ×2 | a straight coin flip, 26 against 26 |
| 2 | **HIGHER or LOWER** than card 1 | ×4 | equal to card 1 loses |
| 3 | **INSIDE or OUTSIDE** cards 1–2 | ×8 | equal to either bound loses |
| 4 | **PICK THE SUIT** | ×10 | one in four, less what is showing |

The multipliers are **cumulative and stake-inclusive**: clearing rung 3 and
cashing returns eight times the stake in total, not eight times on top. Rung 0 —
busting on the first card — returns nothing, which is what busting is.

Aces are high and there is no wraparound. Higher-than-an-ace and lower-than-a-two
are legal calls that cannot win, and the felt says so: every call button carries
its own true count, `outs/remaining`, so a dead call reads `0/51`.

Clearing rung 4 is not a decision. There is no fifth rung to ride, so it pays
where it stands.

### Ties lose

On both middle rungs. A card equal to the first is neither higher nor lower, and
a card equal to either bound is neither inside nor outside — the house takes
both. This is where nearly all of the house's money in a normally-priced version
of this game comes from, and it is why rung 2 is a 72% shot rather than a 50%
one: you pick the better side, but three cards in the deck beat you either way.

A pair on the first two cards makes INSIDE a call with no card that can win it.
That falls out of the tie rule rather than being special-cased, and the button
reads `0/50` when it happens.

## The odds, and a warning about this ladder

`test-ridethebus.js` computes these exactly — it walks every ordered first three
cards and closes rung four analytically, so these are not simulated figures.
They assume you always take the side with more outs, which is what the counts on
the buttons are there to let you do.

```
stop at   chance      pays     returns   house edge
---------------------------------------------------
colour     50.00%      ×2     100.00%       0.00%
high/low   36.20%      ×4     144.80%     -44.80%
in/out     23.77%      ×8     190.17%     -90.17%
the suit    6.31%     ×10      63.07%      36.93%
---------------------------------------------------
```

**The 2/4/8/10 ladder is not a house ladder.** Riding to INSIDE/OUTSIDE and
cashing returns 190% of every stake — a coin-flip rung followed by two rungs
where you get to pick the better side, paid as though you did not. A player who
never touches rung 4 roughly doubles their money per ride, forever. The bank
file will grow without bound.

Rung 4 is the only stop with a real edge, and it is a big one: 6.31% at ×10 is
37% to the house. So the ladder is not merely generous, it is inconsistent —
it pays you to stop at rung 3 every single time, which makes the last rung
decoration.

The lever is `ladder` at the top of `RideTheBus.qml`:

```qml
readonly property var ladder: [2, 4, 8, 10]
```

To put the house ~3% ahead at *every* stop, so that no rung is the obviously
correct place to get off:

```qml
readonly property var ladder: [1.94, 2.68, 4.08, 15.38]
```

Those are `0.97 / chance` at each rung, which the test prints for you as an
advisory whenever it finds a stop the player is ahead on. Rounded, `2 / 2.7 / 4
/ 15` is close enough and reads better on the felt. Note that rung 1 cannot be
priced above ×2 without the multiplier going *down*, since it is a genuine coin
flip — anything at or above ×2 there is a free bet.

`value()` multiplies and does not round, so fractional multipliers pay
fractional credits; make them integers, or add a `Math.floor` there, if that
matters to you.

Change the ladder and re-run the test — the table above is regenerated from
whatever is in the file.

## Controls

| | |
|---|---|
| `1`–`9` | pick a chip off the rack (while betting) |
| click circle | place it · right-click to undo |
| `space` | ride |
| `u` `c` `r` | undo · clear · rebet |
| `r` / `b` | red · black |
| `h` / `l` | higher · lower |
| `i` / `o` | inside · outside |
| `1`–`4` | ♠ ♥ ♦ ♣ on the last rung |
| `←` / `→` | the left or right call, whatever rung you are on |
| `x` | cash out |
| `esc` | close |

`r` is rebet in the circle and red on the first rung; the phase tells them
apart. Digits are the chip rack while betting and the suits once the stake is
out of the circle, which never overlap — there is no rack to drive mid-ride.

## IPC

```
qs -p ridethebus.qml ipc call ridethebus status
qs -p ridethebus.qml ipc call ridethebus bet 25
qs -p ridethebus.qml ipc call ridethebus ride
qs -p ridethebus.qml ipc call ridethebus call higher
qs -p ridethebus.qml ipc call ridethebus cash
```

`status` returns the table as JSON, including an `options` array giving the true
outs for every call on offer — so a script can play the widget without
reimplementing `outs()`:

```json
{"phase":"riding","stage":1,"stake":25,"riding":50,"profit":25,
 "cards":["9♥"],"calls":["red"],
 "options":[{"key":"higher","outs":20,"of":51},
            {"key":"lower","outs":28,"of":51}]}
```

Also `toggle` · `show` · `hide` · `chip` · `undo` · `clear` · `rebet` · `reset`.

## The bank

200 credits, kept in `bank.json` under
`~/.local/state/quickshell/by-shell/<id>/`, written synchronously on every
change — closing the standalone widget quits the process, so a buffered write
would be a lost one.

Empty the bank and it refills to 200 and the rebuy counter goes up. `reset` over
IPC also refills it but does *not* count a rebuy: the tally is a record of being
wiped out, and topping yourself up on purpose is the opposite.

## Tests

```
node test-ridethebus.js
```

Extracts `winsGuess`, `outs`, `value`, `buildDeck` and the ladder straight out of
the `.qml` and checks the shipped code rather than a transcription of it:

- every call is a win, a loss or a tie and never both — exhaustively, over all
  52×51 ordered pairs for high/low and all 52×51×50 triples for inside/outside
- `outs` recounted independently, without going through `winsGuess`, so a wrong
  tie rule cannot agree with itself into a pass
- the dead calls: higher-than-an-ace, lower-than-a-two, inside a pair, inside
  touching ranks
- rung 4 is always exactly 13/49 — only three cards are gone, so at most three
  suits are short of thirteen and the fullest suit is always a full thirteen
- the exact return table above

Whether a stop is a good bet is a property of the ladder, which is a choice, so
the test reports it as an advisory rather than failing on it.

## Structure

`RideTheBus.qml` is one `Scope`, in the same order as `bjak/Blackjack.qml`:

1. **theme** — the only block you normally touch, blackjack's palette to the
   letter so the two land in the same corner looking like siblings
2. **rules** — the ladder and the rank constants
3. **the calls** — `winsGuess`, `outs`, `value`: pure functions over cards with
   no reference to the widget's state, which is what makes them testable
4. **the deck**, **game state**, **the bank on disk**, **betting**
5. **the ride** — `board` → `guess` → `settle` → `finish`, with a 760ms reveal
   beat between a call and its verdict
6. **components** — `PlayingCard`, `Chip`, `ChipStack`, `Btn`
7. **IPC**, then the **window**: a layer surface in the bottom-right that slides
   up, destroyed when it lands at the bottom

The four card seats are laid out once and outlive every ride, which is the one
real structural difference from blackjack, where the row *is* the hand and gets
rebuilt per card. It means a card cannot animate itself in on creation — see the
note on `seated` in `PlayingCard`.
