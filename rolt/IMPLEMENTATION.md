# rolt — implementation

European single-zero roulette as a Quickshell/QML widget. One file, matching
`pokr`'s shape: everything visual in a `theme` block at the top, game logic as
plain functions on the root object, an `IpcHandler` for outside control, and a
Node test that reads the logic straight out of the QML rather than a copy.

Built first as a standalone `FloatingWindow`. The game panel is a single
self-contained component so the later swap to a layer-shell `PanelWindow` — with
poker's `open`/`showing` slide machinery — touches only the window block.

```
rolt/
  roulette.qml        the widget
  test-roulette.js    node test-roulette.js
  README.md           written last, once the thing runs
```

---

## 1. Data

### 1.1 Wheel

The real European pocket sequence, clockwise from 0:

```
0, 32, 15, 19,  4, 21,  2, 25, 17, 34,  6, 27, 13, 36, 11, 30,  8, 23,
10,  5, 24, 16, 33,  1, 20, 14, 31,  9, 22, 18, 29,  7, 28, 12, 35,  3, 26
```

37 pockets. `POCKET = 360 / 37 = 9.7297°`. Pocket `i` in that array is drawn
`i * POCKET` clockwise from the 12 o'clock marker, so the ball sits over pocket
`i` when its screen angle ≡ `wheelAngle + i * POCKET` (mod 360).

`pocketAngle(n)` = `WHEEL_ORDER.indexOf(n) * POCKET`.

### 1.2 Colors

Red: `1 3 5 7 9 12 14 16 18 19 21 23 25 27 30 32 34 36` (18 of them). Every
other number 1–36 is black; 0 is green. Stored as a `Set`-like lookup, and the
test asserts the partition rather than trusting the literal.

### 1.3 Payouts

| kind | pays | numbers covered |
|---|---|---|
| straight | 35:1 | 1 |
| split | 17:1 | 2 |
| street | 11:1 | 3 |
| trio | 11:1 | 3 |
| corner | 8:1 | 4 |
| first four | 8:1 | 4 |
| six-line | 5:1 | 6 |
| column | 2:1 | 12 |
| dozen | 2:1 | 12 |
| red / black / odd / even / 1-18 / 19-36 | 1:1 | 18 |

Zero loses all outside bets — no la partage, no en prison.

Note the invariant that falls out of single-zero: for **every** bet,
`(pays + 1) * count == 36`, so every bet returns exactly 36/37 of stake. Section
6 leans on this hard.

---

## 2. Felt geometry

```
        ┌──┬────┬────┬────┬─── … ───┬────┐────┐
        │  │ 3  │ 6  │ 9  │         │ 36 │2:1 │
        │0 ├────┼────┼────┼─── … ───┼────┤────┤
        │  │ 2  │ 5  │ 8  │         │ 35 │2:1 │
        │  ├────┼────┼────┼─── … ───┼────┤────┤
        │  │ 1  │ 4  │ 7  │         │ 34 │2:1 │
        └──┴────┴────┴────┴─── … ───┴────┘────┘
           │  1st 12  │  2nd 12  │  3rd 12  │
           │1-18│EVEN│RED│BLACK│ODD│19-36│
```

Number grid: 12 columns `c = 0..11`, 3 rows `r = 0..2`, cell `W × H`.

```
numberAt(r, c) = 3 * c + (3 - r)
```

Grid origin `(gx, gy)` is the top-left of cell `(0,0)`. The zero cell sits to
its left, spanning all three rows.

### 2.1 Bet spots

Every bet is generated as data — `{ kind, numbers[], pays, x, y }` — from that
geometry, and the same records drive hit-testing, chip rendering, and payout.
Placement and display cannot disagree because there is only one list.

| kind | count | position |
|---|---|---|
| straight (1–36) | 36 | cell center `(gx + (c+½)W, gy + (r+½)H)` |
| straight (0) | 1 | zero cell center |
| split, vertical | 24 | `(gx + (c+½)W, gy + (r+1)H)`, r = 0,1 |
| split, horizontal | 33 | `(gx + (c+1)W, gy + (r+½)H)`, c = 0..10 |
| split, zero | 3 | `(gx, gy + (r+½)H)` → 0-3, 0-2, 0-1 |
| street | 12 | `(gx + (c+½)W, gy + 3H)` |
| trio | 2 | `(gx, gy + H)` → 0-2-3 · `(gx, gy + 2H)` → 0-1-2 |
| corner | 22 | `(gx + (c+1)W, gy + (r+1)H)`, r = 0,1 · c = 0..10 |
| first four | 1 | `(gx, gy)` — the 0/3 corner |
| six-line | 11 | `(gx + (c+1)W, gy + 3H)`, c = 0..10 |
| column | 3 | center of each `2:1` box |
| dozen | 3 | center of each dozen box |
| outside even-money | 6 | center of each box |

**157 spots total.** The counts are asserted in the test.

### 2.2 Hit-testing

One `MouseArea` across the whole felt. On move, find the nearest spot to the
cursor within a threshold (~⅔ of a cell's half-width) and make it the hover
target; on click, place a chip there.

This is why the spots are point-and-radius rather than per-cell edge regions:
one distance sweep over 157 records is trivial per frame, and it removes the
entire class of "which edge did I actually hit" bugs. Snap radius 30px.

**The dozen row has to be deep.** Street and six-line chips sit on the number
grid's bottom line, which is also the dozen boxes' top edge — so a shallow dozen
row hands half its own height away to those line bets. At the first geometry
tried (`dozenH: 34`) the nearest pair on the whole felt was a six-line and the
dozen centre 17px below it, and the top half of every dozen box was unclickable.
`dozenH: 46` puts it back to 23px. The test asserts a 20px floor on the minimum
pairwise distance and names the offending pair, which is how this was caught
before it ever reached the screen.

Final cell sizes: `cellW 48 · cellH 44 · zeroW 44 · colW 48 · dozenH 46 ·
outsideH 40`, giving a 668×218 felt. Tightest spacing is 22px.

Hovering highlights the spot **and every number it covers** on the felt — which
is how you learn where corners live without a diagram.

- left click — place one chip of the selected denomination
- right click — take one chip back off that spot

---

## 3. Spin

The whole point. A wheel that decelerates while a ball decelerates against it,
with the outcome unreadable until the last moment.

State: `wheelAngle`, `wheelVel`, `ballAngle`, `ballVel`, `ballRadius`. Driven by
a `FrameAnimation` during free spin, then by solved curves.

The winning number is drawn from the RNG **up front**. The motion is then solved
to arrive there — the only way the ball is guaranteed to land on the number the
RNG actually chose. It is a scripted spin with physical feel, not a rigid-body
sim.

### 3.1 Free spin (~2.6–3.2s)

Both bodies integrate under exponential friction, frame-rate independent:

```js
v *= Math.exp(-k * dt)
angle += v * dt
```

Wheel clockwise, ball counter-clockwise and faster, on the outer track radius
`R_track`. Nothing is committed yet.

Exponential decay has closed-form remaining travel — `v / k` — which section 3.2
needs.

### 3.2 The solve

Past `MIN_FREE` (2.0s) both bodies switch from integration to solved `OutCubic`
curves. Exactly *when* is the interesting part — see the trigger below.

`OutCubic` is `1 - (1-t)³`, whose derivative at `t = 0` is 3. So a curve of
range `R` over duration `T` leaves at speed `3R/T`, and matching the speed the
body already has makes the switch invisible.

That leaves one free parameter, and the obvious choice is a trap. Coasting to
the friction model's own natural stop means `range_w = wheelVel / k_wheel`,
hence `T = 3 / k_wheel` — a constant, independent of speed, and about 9.4s at
the friction the free spin wants. Far too slow.

So fix the duration and derive the range from it instead:

```
T_w     = 3.0s                    (chosen)
range_w = wheelVel * T_w / 3      (derived — matches current speed exactly)
W_f     = wheelAngle + range_w
```

Same zero-kink handoff; the wheel simply brakes harder through the settle than
free-spin friction alone would.

Ball: it must seat slightly **before** the wheel stops, so it visibly rides the
last stretch of coast. Given ball settle `T_b = T_w - 0.7s`, the wheel's
position at that moment is analytic:

```
W_at_Tb = wheelAngle + range_w * (1 - (1 - T_b/T_w)³)
```

and the ball's landing angle must satisfy

```
B_f ≡ W_at_Tb + pocketAngle(win)   (mod 360)
```

The naive way to meet that congruence is to snap `B_f` to the nearest whole-turn
solution. Don't: the correction is up to ±180°, and against a settle that only
travels 1.5–2 turns that is a ±25% change in the ball's speed at the handoff —
a visible kick, exactly the artifact this whole solve exists to avoid.

**Trigger on the error instead.** Every frame past `MIN_FREE`, ask what a
perfectly velocity-matched settle would do right now and how far it would miss:

```
range_b = ballVel * T_b / 3            (velocity-matched, no correction)
err     = norm180(ballAngle + range_b - target)
```

`err` sweeps through zero at the relative speed of ball against wheel — roughly
850°/s, so a zero-crossing comes around about every 0.4s. Fire on that crossing.
At that instant the velocity-matched settle *already* lands on the pocket, and
the residual snapped out of `range_b` is under one frame's worth of travel.

Measured over 2,220 simulated spins: worst-case speed change at the handoff
**2.9%**, and a crossing is found before the `MAX_FREE` (2.7s) fallback on every
single spin. Cost is up to 0.7s of extra free spin, which is why the total lands
at 5.0–5.6s rather than a fixed 5.0.

### 3.3 Scatter and drop

Over the last ~35% of the ball's settle:

- **radius** eases `R_track → R_pocket`, slightly overshooting inward as it
  crosses the deflector ring
- **scatter** is an additive angular offset — 2–3 decaying hops, roughly 1.5
  pocket widths at the first, as the ball crosses frets

The scatter is *additive on top of the solved curve and decays to exactly zero
at `t = 1`*. That property is what lets the spin look chaotic and still be
exact; the landing is never at the mercy of the scatter.

### 3.4 Seat

At `t = 1` of the ball's settle:

```qml
ballAngle: root.wheelAngle + root.pocketAngle(root.winNumber)
```

A binding, not an animation. The ball rides the wheel's remaining ~700ms of
coast and cannot drift off its number however the deceleration rounds out.

Total ≈ 5s, result genuinely unreadable until the last ~800ms.

### 3.5 Rendering

Wedges are painted **once** into a `Canvas`; the numbers are rotated `Text`
items over it. Both live inside one `Item` whose `rotation` is `wheelAngle`, so
the scene graph does all the spinning — no repaint per frame, 60fps regardless
of what is on the wheel. The ball is a small `Item` positioned from
`(ballAngle, ballRadius)`.

The scatter constants are the part cheap implementations get wrong, so they get
tuned against the running widget rather than guessed at here.

---

## 4. Round state machine

```
betting ──spin()──> spinning ──lands──> payout ──2.2s──> betting
```

- **betting** — chips placeable, `SPIN` enabled. Stakes leave `credits` as each
  chip is placed, so the bank always shows money actually available.
- **spinning** — felt locked, everything else inert.
- **payout** — winning number flashes on the wheel and joins the history strip;
  winning spots pulse on the felt; `credits` counts up; losing chips fade out.
  The round's bets are copied to `lastOrder` for `REBET`, then cleared.

**The result badge must not read `winNumber`.** It is drawn before the wheel
starts moving, so binding the badge to it prints the answer at the top of the
screen for the entire spin — which was exactly the bug the first build had. A
separate `shownNumber` is cleared on `spin()` and only set in `land()`. The
felt's winning-cell outline and the chip winner/loser states are already safe,
since they gate on `phase === "payout"`.

`resolve(bets, win)` returns total return: for each bet, `numbers.includes(win)`
pays `stake * (pays + 1)`, otherwise nothing. Pure function of its arguments —
this is what the test imports.

---

## 5. Chrome

**Chip rack** — 1 / 5 / 25 / 100 in the usual white / red / green / black. Chips
render as stacked discs with a count badge past two.

**Buttons** — `SPIN`, `CLEAR`, `UNDO`, `REBET`.

**Meters** — CREDITS, WAGERED, LAST WIN, in poker's three-up layout.

**History** — last ~12 results as colored pips, newest first.

**Keys** — `1`–`4` denomination · `space` spin · `u` undo · `c` clear · `r`
rebet · `esc` quit.

**IPC** — `target: "roulette"`, mirroring poker's surface:

| function | effect |
|---|---|
| `toggle` / `hide` | quit the process |
| `show` | no-op |
| `spin` | spin, if there are bets down |
| `clear` / `rebet` / `undo` | bet management |
| `reset` | bank back to 200 |
| `bet <id> <n>` | stake `n` on a spot, ignoring the chip rack |
| `chip <n>` | select a denomination |
| `status` | JSON: visible, credits, wagered, chip, phase, lastNumber, lastWin, history, bets |

`bet` and `chip` were not in the original plan; they make a whole round
scriptable, which is how the spin and the bank got exercised end-to-end without
a human clicking, and they are what the edge bar will drive. Spot ids are the
ones `status` reports, so the two halves round-trip.

All money goes through one `wager(spot, amount)`, so the bank and the chip list
cannot disagree about what is on the felt regardless of which path put it there.

---

## 6. Tests

`node test-roulette.js`, reading `buildSpots()`, `resolve()` and the spin solver
out of the QML the way `pokr/test-eval.js` reads `evaluate()` — so it tests the
shipped code, not a transcription of it.

1. **Wheel** — `wheelOrder` is a permutation of 0–36, length 37, and equals the
   known European sequence.
2. **Colors** — red and black partition 1–36 exactly, 18 each, no overlap, 0 in
   neither.
3. **Spots** — per-kind counts match §2.1 (157 total); every spot's `numbers`
   are in 0–36, duplicate-free, and the right length for its kind; no two spots
   share a position.
4. **Payouts** — for every spot, `(pays + 1) * numbers.length === 36`.
5. **Exhaustive resolve** — for all 37 outcomes × all 157 spots, stake 1 on each
   spot: every spot returns exactly `36/37` of stake in expectation, and the
   whole-felt total over all outcomes is exactly `157 * 36` against `157 * 37`
   staked.

(4) and (5) are the same invariant checked from both ends — one against the
declared payout, one against what `resolve()` actually hands back. A wrong 17:1,
a miscounted corner, or an off-by-one in the number sets fails immediately and
says which spot did it. It is the roulette analogue of poker's exhaustive
2,598,960-hand enumeration: cheap, total, and impossible to satisfy by accident.

6. **Spin landing** — the integrator, the solve, the scatter and the seat are
   pulled out too and run headless at 60fps, 60 reps × all 37 pockets. The ball
   must come to rest on the chosen pocket within 1e-6°, seated at `pocketR`;
   the handoff speed change must stay under 10%; the spin must last 4–7s; and
   the zero-crossing must be found before the `MAX_FREE` fallback on at least
   95% of spins.

That last one is what makes the animation section trustworthy rather than
merely plausible. The whole spin exists to arrive somewhere specific, and 2,220
headless spins say it always does — worst miss under a millionth of a degree,
worst handoff kick 2.9%, and the crossing found on 2,220 of 2,220.

Actual output:

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

---

## 7. Build order

1. Data + geometry + `buildSpots()` + `resolve()`, and `test-roulette.js`
   against them. Logic proven before any pixels.
2. Felt: grid, outside boxes, nearest-spot hit-testing, hover highlight
   including covered-number lighting.
3. Chips: rack, placement, undo, clear, rebet, credit accounting.
4. Wheel, static — Canvas wedges, numbers, marker, ball at rest.
5. Spin: free integration → solve → scatter → seat. Tune against the running
   widget.
6. Payout pass: highlights, count-up, history.
7. IPC, keys, README.

Steps 1–3 are playable without a wheel (spin resolves instantly against the
RNG), so the felt can be exercised well before the animation exists.

**As built.** All seven done. Three things worth knowing if you come back to
this:

- QML property names cannot begin with a capital, so the `SCREAMING_CASE`
  constants this document uses are `wheelOrder`, `pocketArc`, `geo`, `tWheel`,
  `trackR` and so on in the source.
- The scatter constants never needed tuning against the running widget — the
  first values (16° amplitude, 2.5 hops, from `t = 0.62`) read fine on screen
  and the headless test confirmed they cannot affect the landing. Section 3.3's
  zero-at-both-ends property is doing the work.
- `FloatingWindow` pins `minimumSize == maximumSize == implicitSize`. The felt
  is a fixed pixel size, so a resizable window only ever added dead space beside
  it, and Hyprland will otherwise happily stretch it to 1266px.
- **Closing quits.** The plan had `open`/`visible` hiding the window, poker's
  model. Measured, an idle open widget is ~350MB RSS and a couple of percent of
  a core, all of it to keep a QML engine and a painted wheel resident for a game
  nobody is looking at. So `esc`, `onVisibleChanged`, and IPC `hide`/`toggle`
  all land on one `root.quit()` → `Qt.quit()`, and `property bool open` is gone.
  Nothing here justified staying alive: the only state is a bank that starts at
  200 regardless.

  This also collapses the IPC. `visible` in `status` is now the constant `true`,
  which sounds useless and isn't — a caller learns what it needs from *whether
  the call answers at all*: no reply means not running (start it), a reply means
  running (send `hide`). That is poker's `Poker.qml` probe minus its third case.

---

## 8. Decided, so it doesn't get relitigated

- European single zero, 2.70% edge — not American.
- No la partage / en prison.
- No table minimum or maximum.
- No sound.
- Bank is 200 credits, own to this widget, no coupling to the poker bank. It is
  now persisted — `FileView` + `JsonAdapter` over `Quickshell.statePath`
  (`bank.json`), the one thing here that touches disk. That followed from
  closing quitting: without it the bank reset every time the window went away.

  Three things this cost, none of them obvious up front:

  1. **`blockLoading` does not mean loaded.** It blocks a read; it does not
     *start* one. FileView's load lands on `onLoaded`, which fires **after** the
     root component's `Component.onCompleted`, so seeding `credits` there read
     the default 200 and wrote it straight back over the saved figure. The bank
     reset on every launch while the file looked perfectly correct. Touching
     `bankFile.text()` first forces the blocking read. That call reads like dead
     code and is load-bearing — it is commented as such in the source.
  2. **Busting became permanent.** In-memory, a bank of 0 was escapable by
     restarting; persisted, it is a widget that cannot be played and has no way
     out. Hence `topUp()`, called only where the felt is already clear (startup
     and end of round) so it can never fund a stake mid-round, plus an explicit
     `reset`.
  3. **Writes are synchronous** (`blockWrites`, `atomicWrites`). Async writes
     raced each other on quick chip placement — Quickshell warns about dropped
     operations — and would have left the last one unlanded at `Qt.quit()`. The
     file is thirty bytes; blocking costs nothing.

  Verified against a saved bank, a busted one, a corrupt one, an empty one and a
  missing one. A corrupt file falls back to 200 and is rewritten at launch.
- Window lands around 720 × 660, proportioned so it drops into the corner slot
  later without a redesign.
