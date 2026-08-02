# bons

Bones — the mines game — as a Quickshell widget. Quickshell/QML, one file, no
dependencies beyond what you already have installed.

A 5×5 field of boxes. You choose how many of them hide **dynamite** (1–24);
every other box hides a **poker chip** (`pokchip.png`, swap the file to
reskin it). Stake your bet, then turn boxes one at a time: every chip
re-prices the stake upward and you can take the money whenever you like; one
stick of dynamite and the stake is gone. Turn every chip on the field and it
pays out on its own — the only boxes left are the ones that lose. (The code
and IPC call the killers *bones* throughout — that is the game's name; the
icons are a skin, swapped in one place.)

## Run

```sh
qs -p ~/cloon/widgames/bons/bns.qml
```

**Closing quits it.** `esc`, the compositor's close and `ipc call bones hide`
all end the process rather than hiding the window. Opening it again is the
command above.

## Playing

Click the circle to put the selected chip down, then **PLAY**. Click boxes —
or aim with the arrows and press enter — until you either take the money
(**CASHOUT**, `x`) or find out where the bones were.

The bones count is the risk dial: set it with the −/+ stepper (or `-`/`=`,
`[`/`]`) while betting. It is remembered between sittings.

| key | does |
| --- | --- |
| `1`–`9` | pick a chip off the rack |
| `-`/`=` or `[`/`]` | fewer / more bones |
| `space` | play |
| arrows + `enter` | aim and turn a box |
| `x` | cash out |
| `u` / `c` / `r` | undo / clear / rebet |
| `esc` | close |

## The price

There is no multiplier table in the file. Each pick survives with
`(safe − i)` chances in `(25 − i)`, so the price of `p` chips against `m`
bones is fair odds times the house factor:

```
multiplier(m, p) = 0.99 × Π (25 − i) / (25 − m − i)   for i = 0 … p−1
```

Every strategy — any bones count, cashing after any number of chips — returns
exactly **99%** of the stake in expectation, which the tests verify cell by
cell rather than take on faith. The spec's table agrees with this formula
everywhere except a couple of its own typos, which the tests document.

The bank starts at 200, persists in
`~/.local/state/quickshell/by-shell/<id>/bank.json`, and refills itself (and
counts the rebuy) when you lose the lot. Hit **PAY BACK** beside the tally (or `payback`
over IPC) to hand 200 back and strike one rebuy off the tally — allowed only
while the bank holds more than 200.

## Tests

```sh
node test-bns.js
```

The suite evals `multiplier`, `payout` and `buildField` out of `Bones.qml`
itself and checks: the field always carries exactly the requested bones and
every box is equally deadly over 20,000 deals; the price matches the
binomial closed form and the published table's spot values; more chips and
more bones both always raise the price; zero picks pay zero; and expected
return is 0.99 for every `(m, p)` to within floating-point noise.
