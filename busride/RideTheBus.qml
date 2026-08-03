//  RideTheBus.qml — the four-card ladder, the whole widget in one component.
//
//  The game itself. ridethebus.qml wraps this in a ShellRoot to run it on its
//  own; edge instantiates it directly, so the shell and the standalone widget
//  are the same code rather than two copies of it.
//
//  run:     qs -p ~/cloon/widgames/busride/ridethebus.qml
//
//  keys:    1-9 chip · space ride · u undo · c clear · r rebet
//           r/b red-black · h/l higher-lower · i/o inside-outside
//           1-4 suit · ←/→ either option · x cash out · esc close
//
//  Colours follow the house's active table when there is a house; the
//  `theme` block below is the fallback, and the thing to edit to restyle a
//  standalone run.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // The screen to open on. Null takes the compositor's default, which is what
    // the standalone wrapper wants; edge binds it to the focused monitor.
    property var monitor: null

    // True only under ridethebus.qml, where this is the whole process: there,
    // closing is quitting. Inside edge the shell outlives the game, so closing
    // only hides it — and the window is destroyed either way, so the felt and
    // the deck stop costing anything the moment it goes.
    property bool standalone: false

    // ═══════════════════════════════════════════════════════════
    //  THEME — the table if one is set, these values if not
    //
    //  Blackjack's palette to the letter, including the two edge offsets: three
    //  widgets that share a corner should arrive in the same colours as well as
    //  the same place.
    // ═══════════════════════════════════════════════════════════
    //  THE ACTIVE TABLE
    //
    //  The house writes its chosen table to ~/.config/house/table.json whenever
    //  one is picked, and the theme block below reads through this — so
    //  switching tables in the bar retints the felt without restarting, even
    //  mid-hand. Every key falls back to the value it always had, so this file
    //  being absent is not a fault: it is what running the games on their own,
    //  with no house at all, looks like.
    property var table: ({})

    FileView {
        id: tableFile

        path: {
            const xdg = Quickshell.env("XDG_CONFIG_HOME");
            const dir = xdg && xdg.length > 0 ? xdg : `${Quickshell.env("HOME")}/.config`;
            return `${dir}/house/table.json`;
        }

        //  Read before the first frame, or the widget paints in the fallback
        //  palette and then snaps to the table's a frame later.
        blockLoading: true
        watchChanges: true
        printErrors: false

        onFileChanged: tableFile.reload()
        onLoaded: {
            //  A half-written file is a real possibility — apply-theme.sh is
            //  rewriting it at the exact moment the watch fires. Keep the last
            //  good palette rather than dropping to the fallback and flashing.
            try {
                root.table = JSON.parse(tableFile.text());
            } catch (e) {
                console.warn("table.json is not valid JSON, keeping current colours");
            }
        }

        //  No house, or no table chosen yet. The fallbacks below have it.
        onLoadFailed: root.table = ({})

        //  blockLoading blocks a *read*, but nothing has asked for one yet —
        //  same trick the bank uses. Without this the first paint is the
        //  fallback palette. See the note on bankFile.
        Component.onCompleted: tableFile.text()
    }

    property QtObject theme: QtObject {
        readonly property color bg:        root.table.bg ?? "#0e0b0d"
        readonly property color surface:   root.table.surface ?? "#1a1512"
        readonly property color raised:    root.table.raised ?? "#2a2320"
        readonly property color fg:        root.table.fg ?? "#e8ddc4"
        readonly property color muted:     root.table.muted ?? "#8a7f6d"
        readonly property color inactive:  root.table.inactive ?? "#6a6154"
        readonly property color blue:      root.table.blue ?? "#d4af5f"
        readonly property color red:       root.table.red ?? "#e05a6e"
        readonly property color green:     root.table.green ?? "#7fb069"
        readonly property color gold:      root.table.gold ?? "#f0d78c"

        readonly property color felt:      root.table.felt ?? "#142a20"
        readonly property color feltLine:  root.table.feltLine ?? "#274436"

        readonly property color cardFace:  root.table.cardFace ?? "#f0e8d8"
        readonly property color cardInk:   root.table.cardInk ?? "#0e0b0d"
        readonly property color cardRed:   root.table.cardRed ?? "#c13a4e"
        readonly property color cardBack:  root.table.cardBack ?? "#55432a"

        readonly property int    cardW:    62
        readonly property int    cardH:    88
        readonly property int    pad:      20
        readonly property int    gap:      10
        readonly property int    radius:   8
        readonly property string font:     "JetBrainsMono Nerd Font"

        readonly property int    edgeRight:  44 + 14
        readonly property int    edgeBottom: 10 + 14
        readonly property int    slideMs:    260
    }

    // ═══════════════════════════════════════════════════════════
    //  RULES
    //
    //  Four calls off one freshly shuffled deck, each on a card the player has
    //  not seen:
    //
    //      1  RED or BLACK
    //      2  HIGHER or LOWER   than the first card
    //      3  INSIDE or OUTSIDE the first two
    //      4  PICK THE SUIT
    //
    //  A wrong call ends the ride and the stake is gone. A right one clears the
    //  rung and the stake rides at the new multiplier, which the player may take
    //  at any point rather than push on with. Clearing the fourth rung is not a
    //  choice — there is nothing left to ride, so it pays out where it stands.
    //
    //  Ties lose, on both middle rungs: a card equal to the first is neither
    //  higher nor lower, and one equal to either bound is neither inside nor
    //  outside. That is where most of the house's money is — see README.
    //
    //  The deck is shuffled at the top of every ride and the four cards come off
    //  it without replacement, so the odds of each rung move with what is
    //  already face up. `outs` below is what the felt reads them off.
    // ═══════════════════════════════════════════════════════════
    //  Cumulative, not per-rung: clearing rung n pays the stake back `ladder[n-1]`
    //  times over, stake included. A flat ladder rather than a priced one, so the
    //  felt can state it in four numbers — which does mean the rungs are not
    //  equally good bets, and the odds readout on each button is there to say so.
    readonly property var ladder: [2, 4, 8, 16]

    readonly property int stages: 4

    readonly property var suitGlyph: ["♠", "♥", "♦", "♣"]
    readonly property var suitKey:   ["spades", "hearts", "diamonds", "clubs"]
    readonly property var rankName: ["", "", "2", "3", "4", "5", "6", "7", "8",
                                     "9", "10", "J", "Q", "K", "A"]

    //  Ace is 14 and high on every rung. There is no wraparound and no low ace:
    //  higher-than-an-ace is a dead call, and the felt shows it as 0 outs rather
    //  than forbidding it.
    readonly property int lowRank:  2
    readonly property int highRank: 14

    // ═══════════════════════════════════════════════════════════
    //  THE CALLS
    //
    //  Pure functions over cards, with no reference to the widget's state. The
    //  ride below is built entirely out of these, and so are the tests — which
    //  is the point of keeping them free of it.
    // ═══════════════════════════════════════════════════════════
    function isRed(card) { return card.suit === 1 || card.suit === 2; }

    //  What can be called on rung `stage`, in the order the buttons sit in.
    //  Everything else keys off this list, so adding a rung is a matter of
    //  extending it and `winsGuess` together.
    function stageOptions(stage) {
        if (stage === 1) return [{ key: "red",    label: "RED"    },
                                 { key: "black",  label: "BLACK"  }];
        if (stage === 2) return [{ key: "higher", label: "HIGHER" },
                                 { key: "lower",  label: "LOWER"  }];
        if (stage === 3) return [{ key: "inside", label: "INSIDE" },
                                 { key: "outside",label: "OUTSIDE"}];
        if (stage === 4) return [{ key: "spades",   label: "♠" },
                                 { key: "hearts",   label: "♥" },
                                 { key: "diamonds", label: "♦" },
                                 { key: "clubs",    label: "♣" }];
        return [];
    }

    function stageName(stage) {
        return stage === 1 ? "COLOUR"
             : stage === 2 ? "HIGH OR LOW"
             : stage === 3 ? "IN OR OUT"
             : stage === 4 ? "THE SUIT"
                           : "";
    }

    //  Whether `card` settles rung `stage` in the caller's favour, given the
    //  cards already face up. The single arbiter: the ride, the odds readout and
    //  the tests all go through this, so none of them can disagree about a tie.
    function winsGuess(stage, prior, card, guess) {
        if (stage === 1)
            return guess === (root.isRed(card) ? "red" : "black");

        if (stage === 2) {
            //  Equal is neither, and the house keeps it.
            if (card.rank === prior[0].rank) return false;
            return guess === "higher" ? card.rank > prior[0].rank
                                      : card.rank < prior[0].rank;
        }

        if (stage === 3) {
            const lo = Math.min(prior[0].rank, prior[1].rank);
            const hi = Math.max(prior[0].rank, prior[1].rank);
            //  On the bound, and the bound is the house's. A pair on the first
            //  two cards makes lo === hi, which is how INSIDE ends up with no
            //  card that can win it — correctly, and without a special case.
            if (card.rank === lo || card.rank === hi) return false;
            return guess === "inside" ? (card.rank > lo && card.rank < hi)
                                      : (card.rank < lo || card.rank > hi);
        }

        return guess === root.suitKey[card.suit];
    }

    //  How many of the cards still in the deck settle `guess` in the player's
    //  favour. Counted over a full 52 with the face-up cards struck out, which
    //  is exactly the deck the next card comes off — so this is the true count,
    //  not an approximation of one, and `outs / unseen` is the real chance.
    function outs(stage, prior, guess) {
        let n = 0;
        for (let s = 0; s < 4; s++)
            for (let r = root.lowRank; r <= root.highRank; r++) {
                let seen = false;
                for (let i = 0; i < prior.length; i++)
                    if (prior[i].rank === r && prior[i].suit === s) seen = true;
                if (seen) continue;
                if (root.winsGuess(stage, prior, { rank: r, suit: s }, guess)) n++;
            }
        return n;
    }

    function unseen(prior) { return 52 - prior.length; }

    //  What a stake is worth having cleared `stage` rungs — stake included. The
    //  stake left the bank when the chip went down, so rung zero is worth
    //  nothing: a ride that busts on the first card returns none of it.
    function value(bet, stage) {
        return stage <= 0 ? 0 : bet * root.ladder[Math.min(stage, root.stages) - 1];
    }

    // ═══════════════════════════════════════════════════════════
    //  THE DECK
    // ═══════════════════════════════════════════════════════════
    //  Fisher-Yates over all 52. Shuffled at the top of each ride rather than
    //  dealt down like a shoe: four cards is not enough of a deck to count, and
    //  a fresh one per ride is what makes `outs` the honest number.
    function buildDeck() {
        const d = [];
        for (let s = 0; s < 4; s++)
            for (let r = 2; r <= 14; r++)
                d.push({ rank: r, suit: s });
        for (let i = d.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const t = d[i]; d[i] = d[j]; d[j] = t;
        }
        return d;
    }

    property var deck:    []
    property int deckPos: 0

    function newDeck(): void {
        root.deck = root.buildDeck();
        root.deckPos = 0;
    }

    //  The only way a card comes off the deck. The bounds check is a backstop
    //  that a four-card ride can never reach.
    function draw() {
        if (root.deckPos >= root.deck.length) root.newDeck();
        const c = root.deck[root.deckPos];
        root.deckPos += 1;
        return c;
    }

    function cardName(c) {
        return c ? root.rankName[c.rank] + root.suitGlyph[c.suit] : "";
    }

    // ═══════════════════════════════════════════════════════════
    //  GAME STATE
    // ═══════════════════════════════════════════════════════════
    //  The house progression — white, red, green, black — which is what these
    //  denominations are on a real floor. `chipSpot` is the colour of the edge
    //  spots and the inner ring: white against every body except the white one,
    //  which takes navy, because white spots on a white chip are no spots.
    readonly property var chipColor: ["#e8e8ee", "#c13a4e", "#2f9e5a", "#22222c"]
    readonly property var chipSpot:  ["#55432a", "#e8ddc4", "#e8ddc4", "#e8ddc4"]
    readonly property var chipInk:   ["#0e0b0d", "#e8ddc4", "#e8ddc4", "#e8ddc4"]

    readonly property var chipLadder: [1, 5, 25, 100, 1000, 5000, 25000, 100000]

    //  What the ride has to play with. The stake sits in the circle during
    //  betting and out on the ride after that, so no single figure is the
    //  bankroll — but the pair that is live in each phase always sums to what
    //  the ride opened on.
    readonly property int bankroll: root.phase === "betting"
                                    ? root.credits + root.wagered
                                    : root.credits + root.stake

    //  The rack. The base four are always out; above them a denomination
    //  appears once the bankroll covers it.
    readonly property var chips: {
        const out = [];
        for (let i = 0; i < root.chipLadder.length; i++)
            if (i < 4 || root.chipLadder[i] <= root.bankroll)
                out.push(root.chipLadder[i]);
        return out;
    }

    onChipsChanged: if (root.chipIndex >= root.chips.length)
                        root.chipIndex = root.chips.length - 1;

    property int  credits:   200
    property int  chipIndex: 1

    //  How many times the bank has been emptied and put back. Kept beside the
    //  credits on disk, because a tally that reset every launch would only ever
    //  read 0 or 1.
    property int  rebuys:    0

    //  betting · riding · reveal · payout
    //
    //  `reveal` is the beat between a call and its verdict — the card is face up
    //  and nothing is settled yet. It is a phase of its own rather than a flag
    //  because every button in the widget is dead during it.
    property string phase:   "betting"
    property string message: "PLACE YOUR BET"

    //  The cards face up on the felt, in the order they came off the deck, and
    //  the call each one was turned on. Kept in step: `calls[i]` is what was
    //  said before `cards[i]` was seen, which is what lets the row still read as
    //  a record of the whole ride once it is over.
    property var cards:  []
    property var calls:  []

    //  Rungs cleared. 0 is on the kerb, 4 is off the bus with the money.
    property int stage:  0

    //  The stake, once it is out of the circle and riding.
    property int stake:  0

    //  How the call being settled went. Read during the reveal beat only —
    //  `settle` is what acts on it, one beat after `guess` writes it.
    property bool lastRight: false

    //  How the ride ended, for the card marks and the message: "" · "cash" ·
    //  "bust" · "home" (all four rungs cleared).
    property string outcome: ""

    property int lastWin: 0

    //  Chips in the circle, in the order they went down — so undo is a pop and
    //  the total is a sum.
    property var betOrder:  []
    property var lastOrder: []

    readonly property int wagered: {
        let t = 0;
        for (let i = 0; i < root.betOrder.length; i++) t += root.betOrder[i];
        return t;
    }

    //  What is on the felt — which is not the same as what it would pay out.
    //  On the kerb with no rung cleared the stake is still sitting there in
    //  chips, and `value` correctly says it is worth nothing: getting off at
    //  rung zero is what busting *is*. So the two part company for exactly one
    //  rung, and this is the one the circle and the header read, because a
    //  stake that vanished from the felt the moment the bus pulled away would
    //  look like the widget had eaten it.
    //
    //  Once the ride is over this is what came back rather than what was on
    //  offer — a busted ride reads 0, not the rung it died one card after
    //  clearing. Without that the header sits there claiming the stake is still
    //  riding while the felt says it just went under.
    //
    //  Nothing pays out of here. Every ending goes through `value`.
    readonly property int riding: root.phase === "betting" ? root.wagered
                                : root.phase === "payout"  ? root.lastWin
                                : root.stage > 0           ? root.value(root.stake, root.stage)
                                                           : root.stake

    //  What taking it now would add to the bank over walking away from the
    //  stake — the number that makes cashing out a decision.
    readonly property int profit: root.riding - root.stake

    //  The meter reads this rather than `credits` directly, so a payout counts
    //  up instead of snapping to the new total.
    property real creditsShown: credits
    Behavior on creditsShown {
        NumberAnimation { duration: 520; easing.type: Easing.OutCubic }
    }

    // ═══════════════════════════════════════════════════════════
    //  THE BANK ON DISK
    //
    //  Closing quits the process, so without this the bank would reset to 200
    //  every time the window went away. One small JSON file under
    //  `~/.local/state/quickshell/by-shell/<id>/`, holding the only thing worth
    //  carrying between sittings.
    // ═══════════════════════════════════════════════════════════
    FileView {
        id: bankFile

        path: Quickshell.statePath("bank.json")

        //  Read before the first frame — a bank that arrives a frame late shows
        //  200 and then flickers to the real figure.
        blockLoading: true

        //  And written synchronously. The file is thirty bytes, so the cost is
        //  nothing, and the last write is on disk before `Qt.quit()` returns.
        blockWrites: true
        atomicWrites: true

        //  A missing file is the first run, not a fault: say nothing, write the
        //  defaults, carry on. Anything else is a real error and should be loud.
        printErrors: false
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) bankFile.writeAdapter();
            else console.warn("busride: could not read bank:", error);
        }

        JsonAdapter {
            id: bank
            property int credits: 200
            property int rebuys:  0
        }
    }

    //  Explicit copy rather than `credits: bank.credits`, which would be a
    //  binding that silently dies at the first wager. The file is the source at
    //  startup and a mirror from then on.
    Component.onCompleted: {
        //  This `text()` looks pointless and is not — do not delete it.
        //  `blockLoading` blocks a read, but nothing has *asked* for one yet at
        //  this point: FileView's own load lands on `onLoaded`, which fires
        //  after this handler. Read `bank.credits` here without forcing the load
        //  and it is still the default 200, which then gets written straight
        //  back over the real figure.
        bankFile.text();
        root.credits = bank.credits;
        //  Read before topUp(), which is the thing that increments it — a launch
        //  onto an empty bank is a wipeout like any other, and it has to count
        //  from the figure on disk rather than from zero.
        root.rebuys = bank.rebuys;
        root.topUp();
        bankFile.writeAdapter();

        root.newDeck();
    }
    onCreditsChanged: {
        bank.credits = root.credits;
        bankFile.writeAdapter();
    }
    onRebuysChanged: {
        bank.rebuys = root.rebuys;
        bankFile.writeAdapter();
    }

    //  The smallest chip is 1, so an empty bank is not a low score — it is a
    //  widget that cannot be played and has no way back. Only called where the
    //  circle is already clear, so it can never top up mid-ride and pay out on a
    //  stake the player didn't have.
    function topUp(): bool {
        if (root.credits > 0) return false;
        root.credits = 200;
        root.rebuys += 1;
        root.message = "BANK EMPTY — BACK TO 200";
        return true;
    }

    //  Deliberate, so it does not count as a rebuy. The tally is a record of
    //  being wiped out, and topping yourself up on purpose is the opposite.
    function resetBank(): void {
        root.credits = 200;
        root.message = "BANK RESET";
    }

    //  The opposite gesture: hand 200 back to the house and strike one rebuy
    //  off the tally. Must leave money to play with — paying down to zero
    //  would only trip the next top-up and put the rebuy straight back.
    function payBack(): bool {
        if (root.rebuys < 1)     { root.message = "NO REBUYS TO PAY BACK";  return false; }
        if (root.credits <= 200) { root.message = "NEED 200 SPARE TO PAY BACK"; return false; }
        root.credits -= 200;
        root.rebuys  -= 1;
        root.message  = "REBUY PAID BACK";
        return true;
    }

    // ═══════════════════════════════════════════════════════════
    //  BETTING
    //
    //  Everything that moves money goes through `wager`, so the bank and the
    //  chip list can never disagree about what is down.
    // ═══════════════════════════════════════════════════════════
    function wager(amount): bool {
        if (root.phase !== "betting" || amount <= 0) return false;
        if (root.credits < amount) { root.message = "NOT ENOUGH CREDITS"; return false; }
        root.credits -= amount;
        root.betOrder = root.betOrder.concat([amount]);
        return true;
    }

    function placeBet(): void {
        if (root.wager(root.chips[root.chipIndex])) root.message = "PLACE YOUR BET";
    }

    function undo(): void {
        if (root.phase !== "betting" || root.betOrder.length === 0) return;
        const next = root.betOrder.slice();
        root.credits += next.pop();
        root.betOrder = next;
    }

    function clearBets(): void {
        if (root.phase !== "betting") return;
        root.credits += root.wagered;
        root.betOrder = [];
    }

    function rebet(): void {
        if (root.phase !== "betting" || root.lastOrder.length === 0) return;
        let need = 0;
        for (let i = 0; i < root.lastOrder.length; i++) need += root.lastOrder[i];
        if (root.credits < need) { root.message = "NOT ENOUGH CREDITS"; return; }
        root.credits += root.wagered;
        root.credits -= need;
        root.betOrder = root.lastOrder.slice();
    }

    function cycleChip(): void {
        root.chipIndex = (root.chipIndex + 1) % root.chips.length;
    }

    //  Which of the four palettes a chip wears. Everything from the hundred up
    //  wears the hundred's — a black chip carrying a bigger number.
    function chipTier(amount) {
        if (amount >= 100) return 3;
        if (amount >= 25)  return 2;
        if (amount >= 5)   return 1;
        return 0;
    }

    function chipLabel(amount) {
        if (amount >= 1000000) return (amount / 1000000) + "M";
        if (amount >= 1000)    return (amount / 1000) + "k";
        return String(amount);
    }

    //  A bet is shown as the chips it is made of rather than as one disc with
    //  the total printed on it — a stack per denomination, largest first. Both
    //  functions below return the same shape, [{ value, count }, …].

    //  What is in the circle: the chips actually placed, so three twenty-fives
    //  stay three twenty-fives. Colouring them up behind the player's back would
    //  make undo look broken.
    function betStacks() {
        const counts = {};
        for (let i = 0; i < root.betOrder.length; i++)
            counts[root.betOrder[i]] = (counts[root.betOrder[i]] || 0) + 1;
        const out = [];
        //  Over the whole ladder rather than the current rack: a chip already in
        //  the circle must keep being drawn even if the bankroll it bought has
        //  since dropped below its denomination.
        for (let i = root.chipLadder.length - 1; i >= 0; i--) {
            const d = root.chipLadder[i];
            if (counts[d]) out.push({ value: d, count: counts[d] });
        }
        return out;
    }

    //  What is riding. The multiplier turns the stake into a figure rather than
    //  a pile of chips, so this one breaks it down the way a dealer would pay
    //  it: biggest denomination first, down to the ones.
    function chipStacks(amount) {
        const out = [];
        let left = amount;
        for (let i = root.chipLadder.length - 1; i >= 0; i--) {
            const d = root.chipLadder[i];
            const n = Math.floor(left / d);
            if (n > 0) { out.push({ value: d, count: n }); left -= n * d; }
        }
        return out;
    }

    // ═══════════════════════════════════════════════════════════
    //  THE RIDE
    // ═══════════════════════════════════════════════════════════
    function board(): void {
        if (root.phase !== "betting") return;
        if (root.wagered === 0) { root.message = "PLACE A BET FIRST"; return; }

        root.newDeck();

        root.stake   = root.wagered;
        root.cards   = [];
        root.calls   = [];
        root.stage   = 0;
        root.outcome = "";
        root.lastWin = 0;
        root.phase   = "riding";
        root.message = "";
    }

    //  Whether a call can be made at all. The reveal beat and the payout both
    //  fail it, which is what stops a second card being turned over the top of
    //  one still being read.
    function canGuess(): bool {
        return root.phase === "riding" && root.stage < root.stages;
    }

    //  The whole of the game, in one function: turn a card, settle it against
    //  the call, and let the timer below say which way it went. Nothing is paid
    //  here — busting is silent until `settle`, so the card has a moment face up
    //  before the felt reacts to it.
    function guess(key): void {
        if (!root.canGuess()) return;

        const stageNo = root.stage + 1;
        const opts = root.stageOptions(stageNo);
        let known = false;
        for (let i = 0; i < opts.length; i++) if (opts[i].key === key) known = true;
        if (!known) return;

        const card = root.draw();
        //  Settled against the cards that were already down, so this has to be
        //  read before the new one joins them.
        root.lastRight = root.winsGuess(stageNo, root.cards, card, key);
        root.calls     = root.calls.concat([key]);
        root.cards     = root.cards.concat([card]);
        root.phase     = "reveal";
        root.message   = "";
        revealTimer.restart();
    }

    Timer {
        id: revealTimer
        interval: 760
        onTriggered: root.settle()
    }

    function settle(): void {
        if (root.phase !== "reveal") return;

        if (!root.lastRight) {
            root.outcome = "bust";
            root.finish(0);
            return;
        }

        root.stage += 1;

        //  Four for four: there is no fifth rung to ride, so the money comes
        //  down whether the player asked for it or not.
        if (root.stage >= root.stages) {
            root.outcome = "home";
            root.finish(root.value(root.stake, root.stage));
            return;
        }

        root.phase   = "riding";
        root.message = "";
    }

    function canCash(): bool {
        return root.phase === "riding" && root.stage > 0;
    }

    function cash(): void {
        if (!root.canCash()) return;
        root.outcome = "cash";
        root.finish(root.value(root.stake, root.stage));
    }

    //  Every ending goes through here: the bank moves once, the message is
    //  written once, and the clear-down is one timer rather than three.
    function finish(ret): void {
        revealTimer.stop();

        root.credits += ret;
        root.lastWin  = ret;
        root.phase    = "payout";

        const net = ret - root.stake;
        root.message = root.outcome === "bust"
                       ? (root.stage === 0 ? "OFF AT THE FIRST STOP  " + (-root.stake)
                                           : "BUSTED ON " + root.stageName(root.stage + 1)
                                             + "  " + (-root.stake))
                     : root.outcome === "home" ? "RODE IT HOME  +" + net
                     : net > 0                 ? "CASHED OUT  +" + net
                                               : "CASHED OUT";
        payoutTimer.restart();
    }

    Timer {
        id: payoutTimer
        interval: 2600
        onTriggered: {
            root.lastOrder = root.betOrder.slice();
            root.betOrder  = [];
            root.cards     = [];
            root.calls     = [];
            root.stage     = 0;
            root.stake     = 0;
            root.outcome   = "";
            root.phase     = "betting";
            //  topUp() writes its own message when it fires, so don't stomp it.
            if (!root.topUp()) root.message = "PLACE YOUR BET";
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  CARD
    // ═══════════════════════════════════════════════════════════
    component PlayingCard: Item {
        id: card
        property var  model: null
        property bool faceUp: true

        readonly property bool isRed: model !== null && root.isRed(model)

        implicitWidth: root.theme.cardW
        implicitHeight: root.theme.cardH

        //  A card animates in when one *lands in it*, not when the delegate is
        //  built. The distinction matters here and does not in blackjack: there
        //  the row is the hand, so a new card means a new delegate and
        //  `Component.onCompleted` is the moment the card arrives. Here the four
        //  seats are built once and outlive every ride — by the time a card
        //  lands, its seat has existed for minutes — so keying the entry off
        //  creation fires it for nobody, and keying the *opacity* off "am I the
        //  newest card" leaves the card that just turned sitting at zero with
        //  nothing left to bring it back.
        //
        //  `seated` is the previous occupant, so the empty-to-holding edge can
        //  be told apart from the array being reassigned around a card that was
        //  already there — which happens on every single call.
        property var seated: null
        onModelChanged: {
            if (model !== null && seated === null) entry.restart();
            seated = model;
        }

        //  The seat positions cards by x alone, so y is always 0 and the drop
        //  can be written as a literal. It has to be: binding `to` to `card.y`
        //  would point the animation at the property it is animating, and the
        //  card would chase its own target and stop somewhere above the felt.
        ParallelAnimation {
            id: entry
            NumberAnimation { target: card; property: "opacity"; to: 1; duration: 170 }
            NumberAnimation {
                target: card; property: "y"; from: -16; to: 0
                duration: 210; easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: root.theme.radius
            color: card.faceUp ? root.theme.cardFace : root.theme.cardBack
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.35)

            Behavior on color { ColorAnimation { duration: 150 } }

            // ── face-down lattice ──
            Item {
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                opacity: card.faceUp ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Repeater {
                    model: 12
                    Rectangle {
                        required property int index
                        width: 1
                        height: parent.height * 2
                        x: index * 9 - 16
                        y: -parent.height / 2
                        rotation: 30
                        color: Qt.lighter(root.theme.cardBack, 1.5)
                        opacity: 0.6
                    }
                }
            }

            // ── face ──
            Item {
                anchors.fill: parent
                opacity: card.faceUp ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Column {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: 5
                    anchors.leftMargin: 7
                    spacing: -3

                    Text {
                        text: card.model ? root.rankName[card.model.rank] : ""
                        font.family: root.theme.font
                        font.pixelSize: 15
                        font.bold: true
                        color: card.isRed ? root.theme.cardRed : root.theme.cardInk
                    }
                    Text {
                        text: card.model ? root.suitGlyph[card.model.suit] : ""
                        font.family: root.theme.font
                        font.pixelSize: 12
                        color: card.isRed ? root.theme.cardRed : root.theme.cardInk
                    }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 8
                    anchors.horizontalCenterOffset: 6
                    text: card.model ? root.suitGlyph[card.model.suit] : ""
                    font.pixelSize: 32
                    color: card.isRed ? root.theme.cardRed : root.theme.cardInk
                    opacity: 0.92
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  CHIP
    //
    //  A real clay chip: a coloured body, eight edge spots cut into the rim, the
    //  ring those spots stop at, a dark edge, and the denomination in the
    //  middle. Every measurement is a fraction of the radius, so the same
    //  component is the 26px chip under the ride and the 52px one in the rack.
    // ═══════════════════════════════════════════════════════════
    component Chip: Item {
        id: chip
        property int  amount: 0
        property real dim: 26
        property bool selected: false

        readonly property int   tier: root.chipTier(amount)
        readonly property color body: root.chipColor[tier]
        readonly property color spot: root.chipSpot[tier]

        width: dim
        height: dim
        visible: amount > 0

        Canvas {
            id: clay
            anchors.fill: parent

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();

                const r = width / 2, cx = r, cy = r;
                const edge = Math.max(1.25, r * 0.09);
                const rim  = r - edge / 2;          // the body, inside the edge
                const stop = rim * 0.70;            // how deep the spots cut
                const ring = rim * 0.66;

                ctx.beginPath();
                ctx.arc(cx, cy, rim, 0, 2 * Math.PI);
                ctx.fillStyle = chip.body;
                ctx.fill();

                //  Eight spots on 45° centres. Each is the wedge between the rim
                //  and `stop`, which is why they read as cut out of the edge
                //  rather than painted onto it.
                const half = 9 * Math.PI / 180;
                for (let i = 0; i < 8; i++) {
                    const a = i * Math.PI / 4;
                    ctx.beginPath();
                    ctx.arc(cx, cy, rim,  a - half, a + half, false);
                    ctx.arc(cx, cy, stop, a + half, a - half, true);
                    ctx.closePath();
                    ctx.fillStyle = chip.spot;
                    ctx.fill();
                }

                ctx.beginPath();
                ctx.arc(cx, cy, ring, 0, 2 * Math.PI);
                ctx.strokeStyle = chip.spot;
                ctx.lineWidth = Math.max(1, r * 0.055);
                ctx.stroke();

                //  Selection rides the edge instead of adding a second circle
                //  outside it, so picking a chip off the rack does not change
                //  how much room the chip takes up.
                ctx.beginPath();
                ctx.arc(cx, cy, rim, 0, 2 * Math.PI);
                ctx.strokeStyle = chip.selected ? root.theme.fg
                                                : Qt.rgba(0, 0, 0, 0.55);
                ctx.lineWidth = chip.selected ? Math.max(1, edge * 0.6) : edge;
                ctx.stroke();
            }
        }

        //  Canvas repaints itself on resize but not on a colour change, and the
        //  tier moves under a growing stack.
        onTierChanged:     clay.requestPaint()
        onSelectedChanged: clay.requestPaint()

        Text {
            anchors.centerIn: parent
            text: root.chipLabel(chip.amount)
            font.family: root.theme.font
            //  Sized to the face inside the ring, not to the whole chip, so the
            //  number stays within the ring instead of running under the spots.
            font.pixelSize: chip.dim * Math.min(0.42, 1.05 / text.length)
            font.bold: true
            color: root.chipInk[chip.tier]
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  CHIP STACK — a bet, in the chips it is made of
    // ═══════════════════════════════════════════════════════════
    component ChipStack: Row {
        id: stack
        property var  model: []
        property real dim: 26
        property int  maxVisible: 4

        readonly property real lift: Math.max(4, dim * 0.28)
        readonly property real colH: dim + (maxVisible - 1) * lift

        spacing: 2
        //  The count hangs below this height rather than inside it, so a stack
        //  centres on its chips and not on the empty line under them.
        height: colH

        Repeater {
            model: stack.model

            Item {
                id: col
                required property var modelData
                readonly property int shown: Math.min(modelData.count, stack.maxVisible)

                width: stack.dim
                height: stack.height

                Repeater {
                    model: col.shown
                    Chip {
                        required property int index
                        amount: col.modelData.value
                        dim: stack.dim
                        //  Bottom chip first, each one lifted clear of it, so the
                        //  lower discs peek out below the top one.
                        y: stack.colH - stack.dim - index * stack.lift
                        z: index
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: 1
                    text: "×" + col.modelData.count
                    visible: col.modelData.count > stack.maxVisible
                    font.family: root.theme.font
                    font.pixelSize: Math.max(8, stack.dim * 0.34)
                    font.bold: true
                    color: root.theme.fg
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  BUTTON
    // ═══════════════════════════════════════════════════════════
    component Btn: Rectangle {
        id: btn
        property string label: ""
        property string hint: ""
        property bool   accent: false
        property bool   enabled: true
        //  Overrides the label colour when set — the suit buttons are the only
        //  thing in the widget that is red on purpose rather than in warning.
        property color  ink: "transparent"

        signal activated()

        implicitHeight: 42
        radius: 8
        color: !enabled ? root.theme.surface
             : ma.containsMouse ? (accent ? Qt.lighter(root.theme.gold, 1.12)
                                          : root.theme.raised)
             : (accent ? root.theme.gold : root.theme.surface)
        border.width: 1
        border.color: accent ? "transparent" : root.theme.raised

        Behavior on color { ColorAnimation { duration: 90 } }

        Column {
            anchors.centerIn: parent
            spacing: 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: btn.label
                font.family: root.theme.font
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 1.2
                color: !btn.enabled          ? root.theme.inactive
                     : btn.ink.a > 0         ? btn.ink
                     : btn.accent            ? root.theme.bg : root.theme.fg
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: btn.hint
                font.family: root.theme.font
                font.pixelSize: 9
                color: !btn.enabled ? root.theme.inactive
                     : btn.accent   ? Qt.rgba(0, 0, 0, 0.55) : root.theme.muted
                visible: btn.hint !== ""
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.enabled) btn.activated()
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  IPC
    // ═══════════════════════════════════════════════════════════
    function quit(): void {
        if (root.standalone)
            Qt.quit();
        else
            root.open = false;
    }

    IpcHandler {
        target: "ridethebus"

        function toggle(): void { root.open = !root.open; }
        function show():   void { root.open = true; }
        function hide():   void { root.quit(); }

        function ride():  void { root.board(); }
        function call(guess: string): void { root.guess(guess); }
        function cash():  void { root.cash(); }

        function undo():  void { root.undo(); }
        function clear(): void { root.clearBets(); }
        function rebet(): void { root.rebet(); }
        function reset(): void { root.resetBank(); }
        function payback(): void { root.payBack(); }

        //  Stakes `amount` regardless of the selected chip, so a scripted ride
        //  doesn't have to drive the rack first.
        function bet(amount: int): void { root.wager(amount); }
        function chip(n: int): void {
            const i = root.chips.indexOf(n);
            if (i >= 0) root.chipIndex = i;
        }

        function status(): string {
            //  The odds on offer right now, so a script can play the widget
            //  without reimplementing `outs`.
            const opts = [];
            if (root.canGuess()) {
                const s = root.stage + 1;
                const list = root.stageOptions(s);
                for (let i = 0; i < list.length; i++)
                    opts.push({ key: list[i].key,
                                outs: root.outs(s, root.cards, list[i].key),
                                of:   root.unseen(root.cards) });
            }
            return JSON.stringify({
                visible: true,
                credits: root.credits,
                rebuys: root.rebuys,
                wagered: root.wagered,
                stake: root.stake,
                chip: root.chips[root.chipIndex],
                phase: root.phase,
                message: root.message,
                stage: root.stage,
                riding: root.riding,
                profit: root.profit,
                multiplier: root.stage > 0 ? root.ladder[root.stage - 1] : 0,
                nextMultiplier: root.stage < root.stages ? root.ladder[root.stage] : 0,
                outcome: root.outcome,
                lastWin: root.lastWin,
                cards: root.cards.map(root.cardName),
                calls: root.calls,
                options: opts
            });
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  WINDOW
    //
    //  A layer surface in the bottom-right corner, slid up into view —
    //  blackjack's block, because widgets that share a corner should arrive the
    //  same way. Everything below `frame` is untouched by it.
    // ═══════════════════════════════════════════════════════════
    //  Whether it should be on screen. Everything that shows or hides the widget
    //  sets this and nothing else; the window follows.
    property bool open: false

    //  Whether the window exists. Trails `open` by the length of the slide,
    //  because a window destroyed the moment it is hidden has nothing left to
    //  animate. The slide itself sets this back to false when it lands.
    property bool showing: false

    onOpenChanged: if (root.open)
        root.showing = true

    readonly property int tableW: 686
    readonly property int tableH: 398

    //  One quarter of the card row, which is what a rung and a card slot are
    //  each one of. Stated here so the ladder above and the cards below cannot
    //  drift apart.
    readonly property int slotW: 150

    LazyLoader {
        id: loader
        active: root.showing

        PanelWindow {
            id: win
            color: "transparent"
            screen: root.monitor

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "ridethebus"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore

            //  The bottom-right corner, and hard against the bottom edge — the
            //  right-hand margin is a margin, but the bottom one is not. It is
            //  part of the window, empty, sitting under the card: the room the
            //  card slides down through on its way off the screen.
            anchors.right: true
            anchors.bottom: true
            margins.right: root.theme.edgeRight

            implicitWidth: frame.implicitWidth
            implicitHeight: frame.implicitHeight + root.theme.edgeBottom

            //  1 is up, 0 is gone. The card's position is drawn from this rather
            //  than the window being moved, so the layer surface is laid out once
            //  and the compositor isn't resizing it sixty times a second.
            property real reveal: (root.open && win.entered) ? 1 : 0

            //  Off until the window has finished being built, so the first frame
            //  is drawn with the card still below the screen and it slides up
            //  into view. Bind reveal straight to `open` and it would start at 1
            //  — there is no transition from a value a property was created
            //  holding.
            property bool entered: false

            Component.onCompleted: Qt.callLater(() => win.entered = true)

            //  Landed at the bottom, and nothing asked for it back on the way
            //  down: let go of the window. Deferred, since dropping `showing`
            //  destroys this window and we are standing in one of its own
            //  handlers; re-checked on the way out in case the deferral
            //  straddled a re-open.
            onRevealChanged: if (win.reveal <= 0 && !root.open)
                Qt.callLater(() => {
                    if (!root.open)
                        root.showing = false;
                })

            Behavior on reveal {
                NumberAnimation {
                    duration: root.theme.slideMs
                    easing.type: Easing.OutCubic
                }
            }

            //  The window is taller than the card and the difference is
            //  transparent, which is not the same as absent — unmasked it would
            //  swallow clicks meant for whatever is underneath.
            mask: Region {
                y: frame.y
                width: frame.width
                height: frame.height
            }

            Rectangle {
                id: frame
                width: win.width
                y: win.height * (1 - win.reveal)
                radius: 16
                color: root.theme.bg
                border.width: 1
                border.color: root.theme.raised
                focus: true

                implicitWidth: root.tableW + root.theme.pad * 2
                //  pad · header · table · rack · buttons · pad, with the Column's
                //  spacing between each. Stated rather than derived so the window
                //  does not resize itself a frame after it opens.
                implicitHeight: root.theme.pad * 2 + 40 + 14 + root.tableH
                                + 14 + 52 + 14 + 42

                Keys.onPressed: (e) => {
                    //  Digits are the chip rack while betting and the suits on
                    //  the last rung, which never overlap — there is no rack to
                    //  drive once the stake is out of the circle.
                    if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                        const i = e.key - Qt.Key_1;
                        if (root.phase === "betting") {
                            if (i < root.chips.length) root.chipIndex = i;
                        } else if (root.canGuess() && root.stage + 1 === 4 && i < 4) {
                            root.guess(root.suitKey[i]);
                        }
                        e.accepted = true;
                        return;
                    }

                    //  The two-way rungs by position, so the arrows work without
                    //  the player having to remember which letter is which.
                    if (e.key === Qt.Key_Left || e.key === Qt.Key_Right) {
                        if (root.canGuess()) {
                            const opts = root.stageOptions(root.stage + 1);
                            const i = e.key === Qt.Key_Left ? 0 : opts.length - 1;
                            root.guess(opts[i].key);
                        }
                        e.accepted = true;
                        return;
                    }

                    switch (e.key) {
                    case Qt.Key_Space:
                    case Qt.Key_Return:
                    case Qt.Key_Enter: root.board(); break;

                    //  Mnemonics. `r` is red on the first rung and rebet in the
                    //  circle, and the phase is what tells them apart; the rest
                    //  are only ever live on the rung they belong to.
                    case Qt.Key_R: if (root.phase === "betting") root.rebet();
                                   else root.guess("red");
                                   break;
                    case Qt.Key_B: root.guess("black");   break;
                    case Qt.Key_H: root.guess("higher");  break;
                    case Qt.Key_L: root.guess("lower");   break;
                    case Qt.Key_I: root.guess("inside");  break;
                    case Qt.Key_O: root.guess("outside"); break;

                    case Qt.Key_X: root.cash();      break;
                    case Qt.Key_U: root.undo();      break;
                    case Qt.Key_C: root.clearBets(); break;
                    case Qt.Key_Escape: root.quit(); break;
                    default: return;
                    }
                    e.accepted = true;
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: root.theme.pad
                    spacing: 14

                    // ═══ header ═══
                    Item {
                        width: parent.width
                        height: 40

                        Column {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: "RIDE THE BUS"
                                font.family: root.theme.font
                                font.pixelSize: 15
                                font.bold: true
                                font.letterSpacing: 2
                                color: root.theme.fg
                            }
                            Text {
                                text: "1 DECK  ·  TIES LOSE  ·  PAYS "
                                      + root.ladder.join("/") + "×"
                                font.family: root.theme.font
                                font.pixelSize: 9
                                font.letterSpacing: 1
                                color: root.theme.muted
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 18

                            //  Handing 200 back is a deliberate gesture, so it gets a
                            //  button that says so rather than a hover trick on the
                            //  counter. It sits there greyed out when the bank has
                            //  nothing spare or there is nothing to pay off, and a
                            //  click in that state still says why on the felt.
                            Rectangle {
                                id: paybackBtn

                                readonly property bool ready: root.rebuys > 0 && root.credits > 200

                                anchors.verticalCenter: parent.verticalCenter
                                width: paybackLabel.width + 18
                                height: 26
                                radius: root.theme.radius - 2
                                color: paybackTap.containsMouse && paybackBtn.ready
                                       ? root.theme.raised : "transparent"
                                border.width: 1
                                border.color: paybackBtn.ready ? root.theme.gold
                                                               : root.theme.raised

                                Behavior on color { ColorAnimation { duration: 110 } }
                                Behavior on border.color { ColorAnimation { duration: 110 } }

                                Text {
                                    id: paybackLabel
                                    anchors.centerIn: parent
                                    text: "PAY BACK"
                                    font.family: root.theme.font
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1.4
                                    color: paybackBtn.ready ? root.theme.gold
                                                            : root.theme.inactive
                                    Behavior on color { ColorAnimation { duration: 110 } }
                                }

                                MouseArea {
                                    id: paybackTap
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: paybackBtn.ready ? Qt.PointingHandCursor
                                                                  : Qt.ArrowCursor
                                    onClicked: root.payBack()
                                }
                            }

                            //  Times the bank has been emptied. A record, not a control.
                            Column {
                                id: rebuyStat
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0
                                Text {
                                    anchors.right: parent.right
                                    text: "REBUYS"
                                    font.family: root.theme.font
                                    font.pixelSize: 9
                                    font.letterSpacing: 1.4
                                    color: root.theme.inactive
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: root.rebuys
                                    font.family: root.theme.font
                                    font.pixelSize: 19
                                    font.bold: true
                                    color: root.rebuys > 0 ? root.theme.red
                                                           : root.theme.inactive
                                }
                            }

                            Column {
                                spacing: 0
                                Text {
                                    anchors.right: parent.right
                                    text: "RIDING"
                                    font.family: root.theme.font
                                    font.pixelSize: 9
                                    font.letterSpacing: 1.4
                                    color: root.theme.inactive
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: root.riding
                                    font.family: root.theme.font
                                    font.pixelSize: 19
                                    font.bold: true
                                    //  Green only once it is worth more than it
                                    //  cost — the stake riding at ×1 is not a win
                                    //  yet, and colouring it as one would say it
                                    //  was.
                                    color: root.profit > 0 && root.phase !== "betting"
                                           ? root.theme.green : root.theme.fg
                                }
                            }

                            Column {
                                spacing: 0
                                Text {
                                    anchors.right: parent.right
                                    text: "BANK"
                                    font.family: root.theme.font
                                    font.pixelSize: 9
                                    font.letterSpacing: 1.4
                                    color: root.theme.inactive
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: Math.round(root.creditsShown)
                                    font.family: root.theme.font
                                    font.pixelSize: 19
                                    font.bold: true
                                    color: root.theme.gold
                                }
                            }
                        }
                    }

                    // ═══ the table ═══
                    Rectangle {
                        id: table
                        width: parent.width
                        height: root.tableH
                        radius: 14
                        color: root.theme.felt
                        border.width: 1
                        border.color: root.theme.feltLine

                        // ── the four stops, and what each one pays ──
                        //
                        //  The route across the top: cleared rungs behind, the
                        //  one being ridden lit, the rest ahead in felt line.
                        Row {
                            id: route
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 14
                            spacing: root.theme.gap

                            Repeater {
                                model: root.stages

                                Rectangle {
                                    id: rung
                                    required property int index

                                    readonly property int no: index + 1
                                    readonly property bool cleared: root.stage > index
                                    //  The rung being ridden — including the one
                                    //  a card is currently landing on, which is
                                    //  still this rung until `settle` says so.
                                    readonly property bool current:
                                        root.phase !== "betting" && root.stage === index

                                    width: root.slotW
                                    height: 38
                                    radius: 8
                                    color: cleared ? Qt.rgba(0.24, 0.86, 0.52, 0.16)
                                         : current ? Qt.rgba(1, 0.8, 0.3, 0.14)
                                                   : "transparent"
                                    border.width: 1
                                    border.color: cleared ? root.theme.green
                                                : current ? root.theme.gold
                                                          : root.theme.feltLine

                                    Behavior on color       { ColorAnimation { duration: 180 } }
                                    Behavior on border.color { ColorAnimation { duration: 180 } }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 1

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: root.stageName(rung.no)
                                            font.family: root.theme.font
                                            font.pixelSize: 9
                                            font.letterSpacing: 1.6
                                            color: rung.cleared ? root.theme.green
                                                 : rung.current ? root.theme.gold
                                                                : root.theme.feltLine
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "×" + root.ladder[rung.index]
                                            font.family: root.theme.font
                                            font.pixelSize: 14
                                            font.bold: true
                                            color: rung.cleared ? root.theme.green
                                                 : rung.current ? root.theme.gold
                                                                : root.theme.muted
                                        }
                                    }
                                }
                            }
                        }

                        // ── the four cards ──
                        //
                        //  All four slots are drawn from the off, empty ones as
                        //  outlines, so the row does not grow under the player as
                        //  the ride goes on and the ladder above always lines up
                        //  with the card it is about to price.
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 68
                            spacing: root.theme.gap

                            Repeater {
                                model: root.stages

                                Item {
                                    id: seat
                                    required property int index

                                    readonly property var card:
                                        root.cards.length > index ? root.cards[index] : null

                                    //  The newest card is still pending through
                                    //  the reveal beat, which is what gives the
                                    //  mark its moment to land. Every earlier
                                    //  slot is settled by definition: `stage` is
                                    //  the count of rungs cleared, so a slot is
                                    //  a win exactly when it sits below it.
                                    readonly property bool pending:
                                        root.phase === "reveal"
                                        && index === root.cards.length - 1
                                    readonly property bool won:
                                        card !== null && !pending && index < root.stage

                                    width: root.slotW
                                    height: 128

                                    //  The empty seat.
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 0
                                        width: root.theme.cardW
                                        height: root.theme.cardH
                                        radius: root.theme.radius
                                        color: "transparent"
                                        border.width: 1
                                        border.color: root.theme.feltLine
                                        visible: seat.card === null

                                        Text {
                                            anchors.centerIn: parent
                                            text: seat.index + 1
                                            font.family: root.theme.font
                                            font.pixelSize: 22
                                            font.bold: true
                                            color: root.theme.feltLine
                                        }
                                    }

                                    PlayingCard {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 0
                                        visible: seat.card !== null
                                        model: seat.card
                                    }

                                    //  What was called here. The suits are drawn
                                    //  as bare glyphs on the buttons and read
                                    //  badly alone under a card, so they get
                                    //  their name back.
                                    readonly property string callLabel: {
                                        if (index >= root.calls.length) return "";
                                        const key = root.calls[index];
                                        if (index + 1 === 4) return key.toUpperCase();
                                        const opts = root.stageOptions(index + 1);
                                        for (let i = 0; i < opts.length; i++)
                                            if (opts[i].key === key) return opts[i].label;
                                        return "";
                                    }

                                    //  What was called, and how it went. One line
                                    //  under each card, which is the whole record
                                    //  of the ride once it is over.
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: root.theme.cardH + 10
                                        text: seat.callLabel
                                        visible: text !== ""
                                        font.family: root.theme.font
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.letterSpacing: 1.2
                                        color: seat.pending ? root.theme.fg
                                             : seat.won   ? root.theme.green
                                                            : root.theme.red
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: root.theme.cardH + 24
                                        text: seat.won ? "✓" : "✗"
                                        visible: seat.card !== null && !seat.pending
                                        font.family: root.theme.font
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: seat.won ? root.theme.green : root.theme.red
                                    }
                                }
                            }
                        }

                        // ── what the table is saying ──
                        Text {
                            id: banner
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 214
                            text: root.message
                            font.family: root.theme.font
                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 2
                            visible: root.message !== ""
                            color: root.outcome === "bust" ? root.theme.red
                                 : root.lastWin > root.stake ? root.theme.green
                                                             : root.theme.fg

                            SequentialAnimation on opacity {
                                running: root.phase === "payout"
                                loops: 4
                                NumberAnimation { to: 0.5; duration: 240 }
                                NumberAnimation { to: 1.0; duration: 240 }
                            }
                        }

                        //  The offer, while there is one on the table: what is
                        //  riding, and what the next rung would make of it.
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 214
                            spacing: 14
                            visible: root.phase === "riding" && root.stage > 0

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "TAKE " + root.riding
                                font.family: root.theme.font
                                font.pixelSize: 14
                                font.bold: true
                                font.letterSpacing: 1.6
                                color: root.theme.green
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "OR RIDE FOR "
                                      + root.value(root.stake, root.stage + 1)
                                font.family: root.theme.font
                                font.pixelSize: 14
                                font.bold: true
                                font.letterSpacing: 1.6
                                color: root.theme.gold
                            }
                        }

                        // ── the circle ──
                        //
                        //  The stake, before and during. It stops being a pile of
                        //  placed chips the moment the bus pulls away — from then
                        //  on it is a figure with a multiplier on it, so the
                        //  stack is what the multiplier makes of it.
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 248
                            width: 138
                            height: 138

                            Rectangle {
                                anchors.centerIn: parent
                                width: 118
                                height: 118
                                radius: 59
                                color: "transparent"
                                border.width: 2
                                border.color: circleArea.containsMouse
                                              && root.phase === "betting"
                                              ? root.theme.gold : root.theme.feltLine

                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "BET"
                                    font.family: root.theme.font
                                    font.pixelSize: 10
                                    font.letterSpacing: 2
                                    color: root.theme.feltLine
                                    visible: root.riding === 0
                                }
                            }

                            //  Outside the circle rather than inside it, so a tall
                            //  bet spills over the edge the way chips do instead
                            //  of being boxed in by it.
                            ChipStack {
                                anchors.centerIn: parent
                                model: root.phase === "betting" ? root.betStacks()
                                                                : root.chipStacks(root.riding)
                                dim: 28
                                maxVisible: 4
                            }

                            MouseArea {
                                id: circleArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: root.phase === "betting"
                                             ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: (m) => {
                                    if (m.button === Qt.RightButton) root.undo();
                                    else root.placeBet();
                                }
                            }
                        }
                    }

                    // ═══ chip rack ═══
                    Row {
                        width: parent.width
                        height: 52
                        spacing: root.theme.gap
                        //  Dead once the stake is out of the circle — there is
                        //  nothing to put down mid-ride — but kept in place
                        //  rather than hidden, so the felt above it does not
                        //  jump 52 pixels every time a ride starts.
                        opacity: root.phase === "betting" ? 1 : 0.3

                        Behavior on opacity { NumberAnimation { duration: 160 } }

                        Repeater {
                            model: root.chips
                            Item {
                                id: slot
                                required property var modelData
                                required property int index
                                readonly property bool sel: root.chipIndex === index

                                width: 52
                                height: 52

                                Chip {
                                    anchors.centerIn: parent
                                    dim: 52
                                    amount: slot.modelData
                                    selected: slot.sel
                                    scale: slot.sel ? 1.0 : 0.88
                                    Behavior on scale { NumberAnimation { duration: 110 } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: root.phase === "betting"
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.chipIndex = slot.index
                                }
                            }
                        }
                    }

                    // ═══ controls ═══
                    //
                    //  Two rows in one place, swapped by phase. The riding half is
                    //  built out of `stageOptions` rather than written out, so
                    //  the last rung's four suit buttons and the first rung's two
                    //  colours are the same row with a different length — and a
                    //  fifth rung would need no work here at all.
                    Item {
                        width: parent.width
                        height: 42

                        // ── betting ──
                        Row {
                            width: parent.width
                            spacing: root.theme.gap
                            visible: root.phase === "betting"

                            readonly property real btnW:
                                (width - root.theme.gap * 3) / 4

                            Btn {
                                width: parent.btnW
                                label: "CLEAR"
                                hint: "c"
                                enabled: root.wagered > 0
                                onActivated: root.clearBets()
                            }
                            Btn {
                                width: parent.btnW
                                label: "UNDO"
                                hint: "u"
                                enabled: root.betOrder.length > 0
                                onActivated: root.undo()
                            }
                            Btn {
                                width: parent.btnW
                                label: "REBET"
                                hint: "r"
                                enabled: root.lastOrder.length > 0
                                onActivated: root.rebet()
                            }
                            Btn {
                                width: parent.btnW
                                label: "RIDE"
                                hint: "space"
                                accent: true
                                enabled: root.wagered > 0
                                onActivated: root.board()
                            }
                        }

                        // ── riding ──
                        Row {
                            id: callRow
                            width: parent.width
                            spacing: root.theme.gap
                            visible: root.phase !== "betting"

                            //  The rung on offer. Frozen through the reveal beat
                            //  and the payout at whatever was last live, so the
                            //  row does not empty itself out from under the
                            //  player's cursor the moment they click.
                            readonly property int stageNo:
                                Math.min(root.stage + 1, root.stages)
                            readonly property var options: root.stageOptions(stageNo)

                            //  The calls, plus the cash-out — which is only a
                            //  button once there is something to cash, and stops
                            //  being one the moment the ride is settled. Offering
                            //  to cash a stake that has already been paid out or
                            //  lost is the button lying about what it does.
                            readonly property bool cashable:
                                root.stage > 0 && root.phase !== "payout"
                            readonly property int slots:
                                options.length + (cashable ? 1 : 0)
                            readonly property real btnW:
                                (width - root.theme.gap * (slots - 1)) / slots

                            //  The single-letter hint for a call. Positional for
                            //  the suits, which are digits, and the first letter
                            //  everywhere else — which is the mnemonic the key
                            //  handler above implements.
                            function hintFor(key, i) {
                                return callRow.stageNo === 4 ? String(i + 1)
                                                             : key.charAt(0);
                            }

                            Repeater {
                                model: callRow.options

                                Btn {
                                    id: callBtn
                                    required property var modelData
                                    required property int index

                                    //  How many cards still in the deck settle
                                    //  this call — the true count, so the felt
                                    //  says out loud what a flat ladder does not:
                                    //  which of these two is the better bet.
                                    readonly property int outs:
                                        root.canGuess()
                                        ? root.outs(callRow.stageNo, root.cards, modelData.key)
                                        : 0

                                    width: callRow.btnW
                                    label: modelData.label
                                    hint: root.canGuess()
                                          ? outs + "/" + root.unseen(root.cards)
                                          : callRow.hintFor(modelData.key, index)
                                    enabled: root.canGuess()
                                    //  Red suits and the RED call in red. The
                                    //  black ones stay default rather than going
                                    //  actually black, which against this
                                    //  background would be a hole in the button.
                                    ink: (modelData.key === "red"
                                          || modelData.key === "hearts"
                                          || modelData.key === "diamonds")
                                         ? root.theme.cardRed : "transparent"
                                    onActivated: root.guess(modelData.key)
                                }
                            }

                            Btn {
                                width: callRow.btnW
                                visible: callRow.cashable
                                label: "CASH " + root.riding
                                hint: "x"
                                accent: true
                                enabled: root.canCash()
                                onActivated: root.cash()
                            }
                        }
                    }
                }
            }
        }
    }
}
