# bjak

Six-deck blackjack as a Quickshell widget. Quickshell/QML, one file, no
dependencies beyond what you already have installed.

The good rule set — **S17**, blackjack pays **3:2**, double on any two cards
including after a split. About **0.46%** house edge, measured rather than
claimed; see [Tests](#tests).

## Run

```sh
qs -p ~/cloon/widgames/bjak/blackjack.qml
```

It opens as a normal 726×598 desktop window. It is not on a layer shell yet —
that comes when it goes into [edge](../edge).

**Closing quits it.** `esc`, the compositor's close and `ipc call blackjack hide`
all end the process rather than hiding the window, so a shut widget costs
nothing — no engine, no shoe, no memory. Opening it again is the command above.

## Playing

Click the circle to put the selected chip down, then deal. Hold the button and
the chips keep coming — left stacks them up, right takes them back off. There is
a pause first, long enough to tell a click from a hold, and then it runs. It
stops itself the moment a chip will not move, so a held button cannot sit there
failing against an empty bank or an empty circle.

Once the cards are out the buttons swap from the betting row to the playing row,
because the betting keys are dead by then and the playing keys were dead before.

| input             | action                          |
|-------------------|---------------------------------|
| left click circle | place a chip · hold to keep going |
| right click       | take one back · hold to keep going |
| `1`–`9`           | select a chip off the rack      |
| `space`           | deal                            |
| `h`               | hit                             |
| `s`               | stand                           |
| `d`               | double down                     |
| `p`               | split                           |
| `u`               | undo the last chip              |
| `c`               | clear the bet                   |
| `r`               | rebet the last hand             |
| `esc`             | quit                            |

Splitting stacks the hands side by side, and the one being played is the bright
one. Each keeps its own chip, so a doubled or split stake is always visible as
what is actually at risk.

Two things happen on their own, because there is no decision left in them: a
hand that reaches 21 stands itself, and a hand that busts is over. Everything
else waits for you.

## Chips

The chips are drawn rather than drawn on — a coloured body, eight spots cut into
the rim, the ring they stop at, and the denomination in the middle. Every
measurement is a fraction of the radius, so the 26px chip under a hand and the
52px one in the rack are the same component and neither is a scaled bitmap. The
denominations run the house progression: white, red, green, black.

The rack grows with you. The base four — 1, 5, 25, 100 — are always out; above
them a denomination appears once your bankroll covers it, so the thousand
arrives the moment you are worth one, and the ladder carries on 5k, 25k, 100k.
Everything above the hundred wears the hundred's colours with a bigger number on
the face, because a fifth and sixth invented colour would say less than the
number already does. Lose it back and the rack shrinks again, taking the
selection down with it rather than leaving it pointing past the end.

Bankroll here means the whole round's money — chips move between the bank, the
circle and the hands, so no single one of those is the figure, but the pair that
is live in each phase always sums to what the round opened on. That is what
stops the rack gaining and losing a chip as you place them.

A bet is shown as the chips it is **made of**, not as one disc with the total
printed on it — a stack per denomination, largest first, resting on a common
line. Past four chips a column stops growing and states its count, which is the
only way a bet of 400 fits under a hand.

What is in the circle is what you actually put there, so three twenty-fives stay
three twenty-fives rather than colouring themselves up into a hundred behind
your back. A hand's bet is a number by the time it has been split or doubled, so
that one is broken down the way a dealer would pay it: biggest first, down to
the ones.

## Rules

| rule                | this table                             |
|---------------------|----------------------------------------|
| decks               | 6, shuffled together                   |
| dealer              | stands on all 17s, soft included       |
| blackjack           | pays 3:2                               |
| double              | any two cards, and after a split       |
| split               | any equal-value pair, up to four hands |
| split aces          | one card each, no resplit              |
| insurance           | not offered                            |
| surrender           | not offered                            |

A split hand that makes 21 on two cards is a 21, not a blackjack — it pays even
money and loses to a dealer natural. That is the rule everywhere, and it is the
one software gets wrong most often, so there is a test with its name on it.

The dealer peeks. Showing a ten or an ace, the hole card is checked before you
act, so a dealer blackjack ends the round then and there and can never take a
doubled or split stake down with it.

Insurance is missing on purpose. It is a side bet on the hole card being a ten,
paying 2:1 on a proposition that is worse than 2:1, and taking it is a mistake
in every hand you will ever be dealt here. Leaving it off costs you nothing.

The 3:2 bonus **rounds up**. On a stake of 25 a blackjack pays 38 rather than
37.5, because the smallest chip is 1 and rounding the other way would pay 1:1 on
a stake of 1 — which reads as a broken payout rather than as rounding. It is a
few hundredths of a percent in your favour on odd stakes and nothing at all on
even ones.

## Credits

Start at 200, separate from the poker and roulette banks, and kept across
closings in

```
~/.local/state/quickshell/by-shell/<id>/bank.json
```

which is the one thing in the widget that touches disk. It is written whenever
the figure moves and read before the first frame, so closing mid-session and
reopening lands you back on the same number rather than on 200.

The path comes from `Quickshell.statePath`, which hashes the *canonical* config
path — so it is the same file whether the widget is launched as
`bjak/blackjack.qml` or as `edge/../widgames/bjak/blackjack.qml`.

Busting is not a dead end: an empty bank refills to 200 at the end of the round,
since the smallest chip is 1 and a bank of nothing is a widget you cannot play.
`ipc call blackjack reset` puts it back to 200 deliberately, and deleting
`bank.json` is the same thing.

Every one of those refills is counted, and the tally sits in the header as
**REBUYS** — grey at nothing, red once there is something to say. It rides in
`bank.json` beside the credits, because a counter that reset every launch would
only ever read 0 or 1.

It counts being wiped out, not losing a hand. A deliberate `reset` is not a
rebuy and does not add to it; the only thing that does is the bank reaching
exactly nothing. Launching onto a bank that is already empty — the widget killed
mid-round after the last chip went — counts once, on the refill, which is the
same event arriving a session late. Deleting `bank.json` clears the tally along
with the money.

## The shoe

312 cards, six decks shuffled together as one block rather than deck by deck,
which is what a shuffle machine does. The cut card sits at 75%: the shoe goes
back in the shuffler at the top of the first round that finds it past that mark,
never mid-hand. A shoe that reshuffled between your cards and the dealer's would
be a different game.

The header counts down what is left in it, so the deck is at least honest about
where it is even though nothing in here counts it for you.

## IPC

```sh
qs -p ~/cloon/widgames/bjak/blackjack.qml ipc call blackjack <fn>
```

| function        | effect                                        |
|-----------------|-----------------------------------------------|
| `toggle`/`hide` | quit — a reachable widget is an open one      |
| `show`          | no-op; it is already open if you can call it  |
| `deal`          | deal, if there is anything in the circle      |
| `hit`           | take a card                                   |
| `stand`         | stand the active hand                         |
| `double`        | double the stake, take exactly one card       |
| `split`         | split the active pair                         |
| `bet <n>`       | stake `n`, ignoring the chip rack             |
| `chip <n>`      | select a chip denomination                    |
| `undo`          | lift the last chip                            |
| `clear`         | clear the bet                                 |
| `reset`         | put the bank back to 200                      |
| `rebet`         | replay the last hand's bet                    |
| `status`        | JSON: visible, credits, rebuys, wagered, staked, chip, phase, message, lastWin, cardsLeft, dealer, hands |

So a whole hand is scriptable:

```sh
B="qs -p ~/cloon/widgames/bjak/blackjack.qml ipc call blackjack"
$B bet 25
$B deal
$B status | jq -r '.hands[0].cards | join(" ")'
$B hit
$B stand
```

`status` withholds the hole card while it is face down — it is a readout of the
table, not of the engine, and a status call that answered what the dealer has
would be a cheat with a JSON interface.

It is also how you ask whether the widget is up at all: a reply means it is
running, and `ipc call` exiting 255 with nothing on stdout means it is not. That
single question is enough to drive a toggle button — no reply, start the
process; a reply, send `hide`. Which is what the poker tab's service already
does, minus the third case.

(As with poker and roulette, `qs ipc call blackjack show` is unreachable from
the CLI anyway — the `qs ipc show` subcommand swallows it, prints the interface
and exits 0 without calling anything. It is a no-op here regardless.)

## Theming

Everything visual is in the `theme` block at the top of `blackjack.qml` —
colors, felt, card size, font. It ships matching your bar's palette (`#16161e`
base, JetBrainsMono Nerd Font).

The rules are a block of their own just below it: `decks`, `maxHands`,
`bjNum`/`bjDen`, `penetration` and the one-line `dealerHits` are the whole rule
set. Turning this into the H17 game is a single `return`, and the comment above
it says which one.

## Tests

```sh
node test-blackjack.js
```

Reads the hand math, the dealer policy, the settlement and the shoe straight out
of `blackjack.qml`, so it tests the shipped code rather than a copy.

```
card values            13 ranks         ok
hand totals            11 cases         ok
soft never busts       2197 hands       ok
naturals               8 of 169         ok
dealer S17             stands 17-21     ok
bust never pays        399,854 pairs    ok
equal totals push      exact stake      ok
naturals pay 3:2       and push each other ok
dealer bust pays       2x stake         ok
split 21 is not BJ     pays even money  ok
higher never worse     monotone         ok
labels match money     every pair       ok
shoe size              312 cards        ok
shoe composition       24 per rank      ok
shuffle preserves      100 shoes        ok
shuffle mixes          13 first ranks   ok
dealer dist sums       10 upcards       ok
dealer exact vs shoe   0.24% at 7/bust  ok
dealer bust overall    30.24%           ok
rounds played          4,000,000        ok
splits taken           111,657          ok
doubles taken          415,685          ok
shoes used             92,373           ok
house edge             0.461%           ok
------------------------------------------------
house edge: 0.46%  (expect 0.3-0.8%)
per unit wagered: 0.41%  · 1.1318355 units staked per round
```

Three of those carry most of the weight.

**settlement invariants** state the payout rules as properties and check them
against every player hand of two or three cards crossed with every dealer hand
of two — 399,854 pairs. A bust must return nothing, equal totals must return the
stake exactly, a natural must return 3:2, a dealer bust must return double, and
a better hand must never return less than a worse one. A wrong comparison or a
misplaced blackjack arm breaks one of those by construction rather than by luck.

**dealer exact vs shoe** computes the dealer's outcome distribution twice. Once
exactly, by recursion over an infinite deck, where the probabilities are not
written down anywhere — they fall out of `handValue`, `dealerHits` and the
definition of a deck. Once by dealing the real six-deck shoe two million times
and playing it out. They agree to a quarter of a percent, which is about what
six decks rather than infinite ones should cost, and it is the check that says
the shoe, the draw and the dealer's loop all do what the recursion says.

**house edge** plays four million rounds of basic strategy against the shipped
engine and measures what comes back. It is the test that catches what the unit
checks cannot — an ace mishandled inside a split, a doubled stake settled at
single, a dealer that draws when every hand has already busted — because all of
those move this figure by whole percentage points.

Its band is deliberately wide, and the number is a regression anchor rather than
a precision claim. The 0.43% usually quoted for six-deck S17 is the game that
also resplits aces, which this one does not, and the strategy chart in the test
is the total-dependent one rather than the composition-dependent ideal. 0.46% is
where those land; what is being asserted is the shape of it.

The QML flow above the math was checked separately, by temporarily giving the
widget an IPC hook that stacked the shoe and running nine rigged hands through
the live window — natural against 20, natural against natural, the dealer's peek
from both a ten and an ace, a double that wins and one that loses, split aces,
a dealer standing pat on soft 17, and a bust the dealer doesn't draw against.
All nine paid what they should. The hook is not in the shipped file; a widget
that can be told what to deal itself is not a widget you can lose money on.

## Next

Moving onto a layer shell for the edge bar. Everything below `frame` in
`blackjack.qml` is self-contained, so that is a swap of the window block for
poker's `PanelWindow` plus its `open`/`showing` slide, and nothing else.
