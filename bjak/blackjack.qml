//  blackjack.qml — six-deck blackjack, the whole widget in one file.
//
//  run:     qs -p ~/cloon/widgames/bjak/blackjack.qml
//
//  keys:    1-4 chip · space deal · h hit · s stand · d double · p split
//           u undo · c clear · r rebet · esc close
//
//  Edit the `theme` block below to restyle everything.

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // ═══════════════════════════════════════════════════════════
    //  THEME — the only block you normally touch
    // ═══════════════════════════════════════════════════════════
    property QtObject theme: QtObject {
        readonly property color bg:        "#16161e"
        readonly property color surface:   "#1e1e2a"
        readonly property color raised:    "#272733"
        readonly property color fg:        "#ffffff"
        readonly property color muted:     "#8a8a94"
        readonly property color inactive:  "#6a6a7a"
        readonly property color blue:      "#4a9eff"
        readonly property color red:       "#ff4d5e"
        readonly property color green:     "#3ddc84"
        readonly property color gold:      "#ffcc4d"

        readonly property color felt:      "#17342a"
        readonly property color feltLine:  "#2c5646"

        readonly property color cardFace:  "#f2f2f6"
        readonly property color cardInk:   "#16161e"
        readonly property color cardRed:   "#d3283a"
        readonly property color cardBack:  "#2b3a63"

        readonly property int    cardW:    62
        readonly property int    cardH:    88
        readonly property int    pad:      20
        readonly property int    gap:      10
        readonly property int    radius:   8
        readonly property string font:     "JetBrainsMono Nerd Font"
    }

    // ═══════════════════════════════════════════════════════════
    //  RULES
    //
    //  Six decks, dealer stands on all 17s, blackjack pays 3:2, double on any
    //  two cards including after a split, resplit to four hands, split aces get
    //  one card each. No insurance and no surrender — neither is on the felt,
    //  so neither is in here.
    //
    //  That set is the ~0.45% game. Every number below is a knob: `decks`,
    //  `maxHands`, `bjNum`/`bjDen` and `dealerHits` are the whole rule set.
    // ═══════════════════════════════════════════════════════════
    readonly property int  decks:       6
    readonly property int  maxHands:    4
    readonly property int  bjNum:       3     // blackjack pays bjNum : bjDen
    readonly property int  bjDen:       2

    //  How deep the shoe is dealt before it goes back in the shuffler. Measured
    //  at the top of a round, never mid-hand — a shoe that reshuffled between
    //  the player's cards and the dealer's would be a different game.
    readonly property real penetration: 0.75

    readonly property var suitGlyph: ["♠", "♥", "♦", "♣"]
    readonly property var rankName: ["", "", "2", "3", "4", "5", "6", "7", "8",
                                     "9", "10", "J", "Q", "K", "A"]

    // ═══════════════════════════════════════════════════════════
    //  HAND MATH
    //
    //  Pure functions over cards, with no reference to the widget's state. The
    //  round below is built entirely out of these four, and so are the tests —
    //  which is the point of keeping them free of it.
    // ═══════════════════════════════════════════════════════════
    //  Aces are 11 here and demoted by handValue when they have to be, so this
    //  is the *maximum* a card can be worth rather than a fixed value.
    function cardValue(rank) { return rank === 14 ? 11 : Math.min(rank, 10); }

    //  The best total a hand can make, and whether an ace is still standing as
    //  an 11 — which is the only thing "soft" means. Demoting one ace at a time
    //  rather than counting them up front is what makes A-A-A-9 come out at 12
    //  instead of needing a special case: three aces go down, one stays up.
    function handValue(cards) {
        let total = 0, aces = 0;
        for (let i = 0; i < cards.length; i++) {
            total += root.cardValue(cards[i].rank);
            if (cards[i].rank === 14) aces++;
        }
        while (total > 21 && aces > 0) { total -= 10; aces--; }
        return { total: total, soft: aces > 0, bust: total > 21 };
    }

    //  Two cards making 21. A split hand that reaches 21 is *not* this, and the
    //  caller is what knows that — see `handIsBlackjack`.
    function isBlackjack(cards) {
        return cards.length === 2 && root.handValue(cards).total === 21;
    }

    //  The dealer's entire strategy. S17: stands on all seventeens, soft ones
    //  included. For the H17 game this becomes
    //      return total < 17 || (total === 17 && soft);
    //  and nothing else in the file has to change.
    function dealerHits(total, soft) { return total < 17; }

    //  What one settled hand hands back — stake included. The stake left the
    //  bank when the chip went down, so a loss returns nothing, a push returns
    //  the stake, and an even-money win returns twice it.
    //
    //  `hand.bet` is already the doubled figure on a doubled hand, so doubling
    //  needs no arm of its own here.
    function settleHand(hand, dealerCards) {
        const p = root.handValue(hand.cards);
        if (p.bust) return 0;

        const playerBJ = !hand.fromSplit && root.isBlackjack(hand.cards);
        const dealerBJ = root.isBlackjack(dealerCards);

        //  Blackjack against blackjack is a push, and blackjack beats a drawn
        //  21 — so both have to be settled before the totals are compared.
        //
        //  The bonus rounds up: the smallest chip is 1, and 3:2 on an odd stake
        //  is a fraction of a credit. Rounding down would pay 1:1 on a stake of
        //  1, which reads as a broken payout rather than as rounding.
        if (playerBJ)
            return dealerBJ ? hand.bet
                            : hand.bet + Math.ceil(hand.bet * root.bjNum / root.bjDen);
        if (dealerBJ) return 0;

        const d = root.handValue(dealerCards);
        if (d.bust || p.total > d.total) return hand.bet * 2;
        if (p.total === d.total) return hand.bet;
        return 0;
    }

    //  Display only — the money comes from settleHand above. Kept beside it so
    //  the two are read together, and checked against each other by the tests.
    function resultName(hand, dealerCards) {
        const p = root.handValue(hand.cards);
        if (p.bust) return "BUST";
        const playerBJ = !hand.fromSplit && root.isBlackjack(hand.cards);
        const dealerBJ = root.isBlackjack(dealerCards);
        if (playerBJ) return dealerBJ ? "PUSH" : "BLACKJACK";
        if (dealerBJ) return "LOSE";
        const d = root.handValue(dealerCards);
        if (d.bust) return "WIN";
        if (p.total > d.total) return "WIN";
        if (p.total === d.total) return "PUSH";
        return "LOSE";
    }

    // ═══════════════════════════════════════════════════════════
    //  THE SHOE
    // ═══════════════════════════════════════════════════════════
    //  Fisher-Yates over the whole shoe. Six decks are shuffled together as one
    //  block rather than deck by deck, which is what a real shuffle machine
    //  does and what makes the composition tests meaningful.
    function buildShoe(n) {
        const d = [];
        for (let k = 0; k < n; k++)
            for (let s = 0; s < 4; s++)
                for (let r = 2; r <= 14; r++)
                    d.push({ rank: r, suit: s });
        for (let i = d.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const t = d[i]; d[i] = d[j]; d[j] = t;
        }
        return d;
    }

    property var shoe:    []
    property int shoePos: 0

    readonly property int cardsLeft: shoe.length - shoePos

    function newShoe(): void {
        root.shoe = root.buildShoe(root.decks);
        root.shoePos = 0;
    }

    //  The only way a card comes off the shoe. The bounds check is a backstop
    //  for a round that somehow outruns a full shoe rather than the normal path
    //  — `deal()` reshuffles at the cut card, before any card is dealt.
    function draw() {
        if (root.shoePos >= root.shoe.length) root.newShoe();
        const c = root.shoe[root.shoePos];
        root.shoePos += 1;
        return c;
    }

    function cardName(c) {
        return c ? root.rankName[c.rank] + root.suitGlyph[c.suit] : "";
    }

    // ═══════════════════════════════════════════════════════════
    //  GAME STATE
    // ═══════════════════════════════════════════════════════════
    readonly property var chips: [1, 5, 25, 100]
    readonly property var chipColor: ["#e8e8ee", "#d3283a", "#2f9e5a", "#22222c"]
    readonly property var chipInk:   ["#16161e", "#ffffff", "#ffffff", "#ffffff"]

    property int  credits:   200
    property int  chipIndex: 1

    //  betting · dealing · player · dealer · payout
    property string phase:   "betting"
    property string message: "PLACE YOUR BET"

    //  Every hand in front of the player. One to start with, up to `maxHands`
    //  after splits. Each is { cards, bet, fromSplit, doubled, done, ret, result }.
    property var hands:   []
    property int active:  0

    property var  dealer:   []
    property bool holeDown: true       // dealer's second card still face down

    property int lastWin: 0

    //  Chips in the circle, in the order they went down — so undo is a pop and
    //  the total is a sum. Same shape as rolt's felt, one spot instead of 157.
    property var betOrder:  []
    property var lastOrder: []

    readonly property int wagered: {
        let t = 0;
        for (let i = 0; i < root.betOrder.length; i++) t += root.betOrder[i];
        return t;
    }

    //  What is actually at risk once the cards are out — splits and doubles put
    //  more out than the circle ever held.
    readonly property int staked: {
        let t = 0;
        for (let i = 0; i < root.hands.length; i++) t += root.hands[i].bet;
        return t;
    }

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
    //
    //  `statePath` hashes the *canonical* config path, so it resolves to the
    //  same file whichever spelling of the path launched the widget.
    // ═══════════════════════════════════════════════════════════
    FileView {
        id: bankFile

        path: Quickshell.statePath("bank.json")

        //  Read before the first frame — a bank that arrives a frame late shows
        //  200 and then flickers to the real figure.
        blockLoading: true

        //  And written synchronously. The file is thirty bytes, so the cost is
        //  nothing, and the last write is on disk before `Qt.quit()` returns —
        //  which matters when closing *is* quitting.
        blockWrites: true
        atomicWrites: true

        //  A missing file is the first run, not a fault: say nothing, write the
        //  defaults, carry on. Anything else is a real error and should be loud.
        printErrors: false
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) bankFile.writeAdapter();
            else console.warn("bjak: could not read bank:", error);
        }

        JsonAdapter {
            id: bank
            property int credits: 200
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
        //  back over the real figure — the bank silently resets to 200 on every
        //  launch while looking, from the file's contents, like it is working.
        bankFile.text();
        root.credits = bank.credits;
        root.topUp();
        bankFile.writeAdapter();

        root.newShoe();
    }
    onCreditsChanged: {
        bank.credits = root.credits;
        bankFile.writeAdapter();
    }

    //  The smallest chip is 1, so an empty bank is not a low score — it is a
    //  widget that cannot be played and has no way back. Only called where the
    //  circle is already clear, so it can never top up mid-round and pay out on
    //  a stake the player didn't have.
    function topUp(): bool {
        if (root.credits > 0) return false;
        root.credits = 200;
        root.message = "BANK EMPTY — BACK TO 200";
        return true;
    }

    function resetBank(): void {
        root.credits = 200;
        root.message = "BANK RESET";
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

    //  Which chip a stack is drawn as: the largest denomination it covers.
    function chipTier(amount) {
        let k = 0;
        for (let i = 0; i < root.chips.length; i++)
            if (amount >= root.chips[i]) k = i;
        return k;
    }

    // ═══════════════════════════════════════════════════════════
    //  THE ROUND
    //
    //  `hands` is a plain array and QML only notices whole reassignments, so
    //  every mutation below rebuilds the slice it touches. Fiddly, but it means
    //  one property change per card and no manual signal plumbing.
    // ═══════════════════════════════════════════════════════════
    function newHand(cards, bet, fromSplit) {
        return { cards: cards, bet: bet, fromSplit: fromSplit,
                 doubled: false, done: false, ret: 0, result: "" };
    }

    function cloneHand(h) {
        return { cards: h.cards.slice(), bet: h.bet, fromSplit: h.fromSplit,
                 doubled: h.doubled, done: h.done, ret: h.ret, result: h.result };
    }

    function dealTo(i): void {
        const next = root.hands.slice();
        const h = root.cloneHand(next[i]);
        h.cards = h.cards.concat([root.draw()]);
        next[i] = h;
        root.hands = next;
    }

    function markDone(i): void {
        const next = root.hands.slice();
        const h = root.cloneHand(next[i]);
        h.done = true;
        next[i] = h;
        root.hands = next;
    }

    // ── the opening deal ───────────────────────────────────────
    property var dealQueue: []

    function deal(): void {
        if (root.phase !== "betting") return;
        if (root.wagered === 0) { root.message = "PLACE A BET FIRST"; return; }

        //  The cut card, checked here and nowhere else.
        if (root.shoePos > root.shoe.length * root.penetration) root.newShoe();

        root.hands    = [root.newHand([], root.wagered, false)];
        root.dealer   = [];
        root.active   = 0;
        root.holeDown = true;
        root.lastWin  = 0;
        root.phase    = "dealing";
        root.message  = "";

        //  Player, dealer, player, dealer — dealt in that order and one at a
        //  time, because that is the rhythm the game has.
        root.dealQueue = ["p", "d", "p", "d"];
        dealTimer.restart();
    }

    Timer {
        id: dealTimer
        interval: 230
        repeat: true
        onTriggered: {
            if (root.dealQueue.length === 0) { dealTimer.stop(); root.afterDeal(); return; }
            const q = root.dealQueue.slice();
            const which = q.shift();
            root.dealQueue = q;
            if (which === "p") root.dealTo(0);
            else root.dealer = root.dealer.concat([root.draw()]);
        }
    }

    //  The peek. A dealer showing a ten or an ace checks the hole card before
    //  the player acts, so a dealer blackjack ends the round then and there and
    //  can never take a doubled or split stake with it.
    function afterDeal(): void {
        const peeks = root.cardValue(root.dealer[0].rank) >= 10;
        if (peeks && root.isBlackjack(root.dealer)) {
            root.message = "DEALER BLACKJACK";
            root.finish();
            return;
        }
        //  A player blackjack against a non-blackjack dealer is already decided
        //  — there is nothing left to choose, so it pays immediately.
        if (root.isBlackjack(root.hands[0].cards)) { root.finish(); return; }

        root.phase = "player";
        root.message = "";
    }

    // ── player actions ─────────────────────────────────────────
    //  A hand mid-split has one card and is waiting on the timer below; it is
    //  not playable until it has two.
    function ready(i): bool {
        return root.phase === "player" && i === root.active
            && root.hands.length > i && !root.hands[i].done
            && root.hands[i].cards.length >= 2;
    }

    function canHit(i): bool {
        return root.ready(i) && root.handValue(root.hands[i].cards).total < 21;
    }

    function canDouble(i): bool {
        return root.ready(i) && root.hands[i].cards.length === 2
            && root.credits >= root.hands[i].bet;
    }

    //  Any two cards of equal value, which is what makes K-Q splittable. Aces
    //  are not resplit: they took their one card and the hand is over.
    function canSplit(i): bool {
        if (!root.ready(i)) return false;
        const h = root.hands[i];
        if (h.cards.length !== 2) return false;
        if (root.hands.length >= root.maxHands) return false;
        if (root.credits < h.bet) return false;
        return root.cardValue(h.cards[0].rank) === root.cardValue(h.cards[1].rank);
    }

    function hit(): void {
        if (!root.canHit(root.active)) return;
        const i = root.active;
        root.dealTo(i);
        //  21 stands itself — there is no reason to draw to it, and making the
        //  player press stand on a made hand is just a keystroke tax.
        if (root.handValue(root.hands[i].cards).total >= 21) { root.markDone(i); root.advance(); }
    }

    function stand(): void {
        if (!root.ready(root.active)) return;
        root.markDone(root.active);
        root.advance();
    }

    function doubleDown(): void {
        if (!root.canDouble(root.active)) return;
        const i = root.active;
        const next = root.hands.slice();
        const h = root.cloneHand(next[i]);
        root.credits -= h.bet;
        h.bet *= 2;
        h.doubled = true;
        h.cards = h.cards.concat([root.draw()]);
        h.done = true;
        next[i] = h;
        root.hands = next;
        root.advance();
    }

    function split(): void {
        if (!root.canSplit(root.active)) return;
        const i = root.active;
        const h = root.hands[i];
        root.credits -= h.bet;

        const next = root.hands.slice();
        next.splice(i, 1,
            root.newHand([h.cards[0]], h.bet, true),
            root.newHand([h.cards[1]], h.bet, true));
        root.hands = next;

        //  Both halves are one card short. The active one is filled now, the
        //  other when play reaches it — same as a dealer working down the row.
        fillTimer.restart();
    }

    Timer {
        id: fillTimer
        interval: 220
        onTriggered: root.fillActive()
    }

    function fillActive(): void {
        if (root.phase !== "player") return;
        const i = root.active;
        const h = root.hands[i];
        if (!h || h.cards.length !== 1) return;

        const wasAce = h.cards[0].rank === 14;
        root.dealTo(i);

        //  Split aces take one card and that is the hand. So does a drawn 21 —
        //  and note it is a 21, not a blackjack: `fromSplit` is what stops
        //  settleHand paying 3:2 on it.
        if (wasAce || root.handValue(root.hands[i].cards).total >= 21) {
            root.markDone(i);
            root.advance();
        }
    }

    function advance(): void {
        for (let i = root.active + 1; i < root.hands.length; i++) {
            if (!root.hands[i].done) {
                root.active = i;
                if (root.hands[i].cards.length === 1) fillTimer.restart();
                return;
            }
        }
        root.dealerTurn();
    }

    // ── the dealer ─────────────────────────────────────────────
    function anyLive(): bool {
        for (let i = 0; i < root.hands.length; i++)
            if (!root.handValue(root.hands[i].cards).bust) return true;
        return false;
    }

    function dealerTurn(): void {
        root.phase = "dealer";
        root.holeDown = false;

        //  Every hand busted, so the dealer has already won and drawing would
        //  only be theatre — and theatre that changes the shoe.
        if (!root.anyLive()) { finishTimer.restart(); return; }
        dealerTimer.restart();
    }

    Timer {
        id: dealerTimer
        interval: 520
        repeat: true
        onTriggered: {
            const v = root.handValue(root.dealer);
            if (root.dealerHits(v.total, v.soft)) {
                root.dealer = root.dealer.concat([root.draw()]);
                return;
            }
            dealerTimer.stop();
            root.finish();
        }
    }

    //  A beat between the last card and the verdict, for the all-bust path
    //  where the dealer never draws.
    Timer {
        id: finishTimer
        interval: 460
        onTriggered: root.finish()
    }

    function finish(): void {
        dealTimer.stop();
        dealerTimer.stop();
        root.holeDown = false;

        let ret = 0;
        const next = root.hands.slice();
        for (let i = 0; i < next.length; i++) {
            const h = root.cloneHand(next[i]);
            h.ret    = root.settleHand(h, root.dealer);
            h.result = root.resultName(h, root.dealer);
            h.done   = true;
            ret += h.ret;
            next[i] = h;
        }
        root.hands = next;

        root.credits += ret;
        root.lastWin = ret;
        root.phase = "payout";

        const net = ret - root.staked;
        root.message = net > 0 ? "WIN  +" + net
                     : net < 0 ? "LOSE  " + net
                               : "PUSH";
        payoutTimer.restart();
    }

    Timer {
        id: payoutTimer
        interval: 2600
        onTriggered: {
            root.lastOrder = root.betOrder.slice();
            root.betOrder  = [];
            root.hands     = [];
            root.dealer    = [];
            root.active    = 0;
            root.holeDown  = true;
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
        property bool fresh: false        // animate itself in on creation

        readonly property bool isRed: model !== null
                                      && (model.suit === 1 || model.suit === 2)

        implicitWidth: root.theme.cardW
        implicitHeight: root.theme.cardH

        opacity: fresh ? 0 : 1
        Component.onCompleted: if (fresh) entry.start()

        //  The fan positions cards by x alone, so y is always 0 and the slide
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

            //  The hole card turns over without the delegate being rebuilt, so
            //  the face and the back cross-fade rather than flipping.
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
    //  CARD FAN — a hand, overlapped so it fits its slot however long it runs
    // ═══════════════════════════════════════════════════════════
    component CardFan: Item {
        id: fan
        property var  cards: []
        property int  downIndex: -1       // which card is face down, -1 for none
        property real slotW: 158
        property real maxOffset: 30

        implicitWidth: slotW
        implicitHeight: root.theme.cardH

        //  Shrink the overlap rather than the cards, so a seven-card hand still
        //  reads at the same size as a two-card one.
        readonly property real offset:
            cards.length < 2 ? 0
            : Math.min(maxOffset, (slotW - root.theme.cardW) / (cards.length - 1))
        readonly property real spanW:
            root.theme.cardW + Math.max(0, cards.length - 1) * offset

        Repeater {
            model: fan.cards
            PlayingCard {
                required property var modelData
                required property int index

                model: modelData
                faceUp: index !== fan.downIndex
                //  Only the newest card animates in. Reassigning the array
                //  rebuilds every delegate, so without this the whole hand
                //  would re-deal itself on every hit.
                fresh: index === fan.cards.length - 1

                x: (fan.slotW - fan.spanW) / 2 + index * fan.offset
                z: index
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  TOTAL PILL — the number over a hand
    // ═══════════════════════════════════════════════════════════
    component TotalPill: Rectangle {
        id: pill
        property var  cards: []
        property bool hidden: false      // dealer's total while the hole is down
        property bool highlight: false
        property string override: ""

        readonly property var v: root.handValue(cards)

        implicitWidth: Math.max(46, label.implicitWidth + 18)
        implicitHeight: 20
        radius: 10
        visible: cards.length > 0
        color: override !== "" ? "transparent"
             : v.bust          ? root.theme.red
             : highlight       ? root.theme.blue
                               : Qt.rgba(0, 0, 0, 0.35)
        border.width: override !== "" ? 1 : 0
        border.color: root.theme.feltLine

        Behavior on color { ColorAnimation { duration: 160 } }

        Text {
            id: label
            anchors.centerIn: parent
            //  The empty case is reachable even though the pill is hidden for
            //  it — `visible` stops it being drawn, not evaluated.
            text: pill.override !== "" ? pill.override
                : pill.cards.length === 0 ? ""
                : pill.hidden          ? String(root.cardValue(pill.cards[0].rank))
                : pill.v.bust          ? "BUST " + pill.v.total
                : pill.v.soft          ? "SOFT " + pill.v.total
                                       : String(pill.v.total)
            font.family: root.theme.font
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 0.6
            color: root.theme.fg
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  CHIP
    // ═══════════════════════════════════════════════════════════
    component Chip: Rectangle {
        id: chip
        property int amount: 0
        property real dim: 26
        readonly property int tier: root.chipTier(amount)

        width: dim
        height: dim
        radius: dim / 2
        visible: amount > 0
        color: root.chipColor[tier]
        border.width: 2
        border.color: Qt.rgba(0, 0, 0, 0.45)

        Text {
            anchors.centerIn: parent
            text: chip.amount
            font.family: root.theme.font
            font.pixelSize: chip.amount > 99 ? chip.dim * 0.32 : chip.dim * 0.4
            font.bold: true
            color: root.chipInk[chip.tier]
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
                color: !btn.enabled ? root.theme.inactive
                     : btn.accent   ? root.theme.bg : root.theme.fg
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
    //
    //  Closing quits, so a call arriving at all means the widget is up. There
    //  is no state here worth keeping a whole QML engine resident for — the
    //  bank is on disk, and the shoe is 312 shuffled cards that mean nothing
    //  between rounds.
    // ═══════════════════════════════════════════════════════════
    function quit(): void { Qt.quit(); }

    IpcHandler {
        target: "blackjack"

        function toggle(): void { root.quit(); }
        function show():   void {}
        function hide():   void { root.quit(); }

        function deal():   void { root.deal(); }
        function hit():    void { root.hit(); }
        function stand():  void { root.stand(); }
        function double(): void { root.doubleDown(); }
        function split():  void { root.split(); }

        function undo():   void { root.undo(); }
        function clear():  void { root.clearBets(); }
        function rebet():  void { root.rebet(); }
        function reset():  void { root.resetBank(); }

        //  Stakes `amount` regardless of the selected chip, so a scripted round
        //  doesn't have to drive the rack first.
        function bet(amount: int): void { root.wager(amount); }
        function chip(n: int): void {
            const i = root.chips.indexOf(n);
            if (i >= 0) root.chipIndex = i;
        }

        function status(): string {
            const hs = [];
            for (let i = 0; i < root.hands.length; i++) {
                const h = root.hands[i];
                const v = root.handValue(h.cards);
                hs.push({
                    cards: h.cards.map(root.cardName),
                    total: v.total, soft: v.soft, bust: v.bust,
                    bet: h.bet, doubled: h.doubled, fromSplit: h.fromSplit,
                    active: i === root.active && root.phase === "player",
                    result: h.result, ret: h.ret
                });
            }
            //  The hole card is withheld while it is face down — `status` is a
            //  readout of the table, not of the engine.
            const shown = root.holeDown ? root.dealer.slice(0, 1) : root.dealer;
            return JSON.stringify({
                visible: true,
                credits: root.credits,
                wagered: root.wagered,
                staked: root.staked,
                chip: root.chips[root.chipIndex],
                phase: root.phase,
                message: root.message,
                lastWin: root.lastWin,
                cardsLeft: root.cardsLeft,
                dealer: {
                    cards: shown.map(root.cardName),
                    total: shown.length ? root.handValue(shown).total : 0,
                    holeDown: root.holeDown
                },
                hands: hs
            });
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  WINDOW
    //
    //  A plain desktop window for now. Everything below `frame` is
    //  self-contained, so moving this onto a layer shell later means swapping
    //  this block and nothing else.
    // ═══════════════════════════════════════════════════════════
    readonly property int tableW: 686
    readonly property int tableH: 364
    readonly property int slotW:  164

    FloatingWindow {
        id: win
        visible: true
        color: root.theme.bg
        title: "blackjack"

        //  The compositor's close, and anything else that pulls the window
        //  down, takes the process with it.
        onVisibleChanged: if (!visible) root.quit()

        minimumSize: Qt.size(implicitWidth, implicitHeight)
        maximumSize: Qt.size(implicitWidth, implicitHeight)

        implicitWidth: root.tableW + root.theme.pad * 2
        //  pad · header · table · rack · buttons · pad, with the Column's
        //  spacing between each. Stated rather than derived so the window does
        //  not resize itself a frame after it opens.
        implicitHeight: root.theme.pad * 2 + 40 + 14 + root.tableH
                        + 14 + 52 + 14 + 42

        Item {
            id: frame
            anchors.fill: parent
            focus: true

            Keys.onPressed: (e) => {
                switch (e.key) {
                case Qt.Key_1: root.chipIndex = 0; break;
                case Qt.Key_2: root.chipIndex = 1; break;
                case Qt.Key_3: root.chipIndex = 2; break;
                case Qt.Key_4: root.chipIndex = 3; break;
                case Qt.Key_Space:
                case Qt.Key_Return:
                case Qt.Key_Enter: root.deal(); break;
                case Qt.Key_H: root.hit(); break;
                case Qt.Key_S: root.stand(); break;
                case Qt.Key_D: root.doubleDown(); break;
                case Qt.Key_P: root.split(); break;
                case Qt.Key_U: root.undo(); break;
                case Qt.Key_C: root.clearBets(); break;
                case Qt.Key_R: root.rebet(); break;
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
                            text: "BLACKJACK"
                            font.family: root.theme.font
                            font.pixelSize: 15
                            font.bold: true
                            font.letterSpacing: 2
                            color: root.theme.fg
                        }
                        Text {
                            text: root.decks + " DECKS  ·  S17  ·  PAYS "
                                  + root.bjNum + ":" + root.bjDen
                                  + "  ·  " + root.cardsLeft + " LEFT"
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

                        Column {
                            spacing: 0
                            Text {
                                anchors.right: parent.right
                                text: "IN PLAY"
                                font.family: root.theme.font
                                font.pixelSize: 9
                                font.letterSpacing: 1.4
                                color: root.theme.inactive
                            }
                            Text {
                                anchors.right: parent.right
                                text: root.phase === "betting" ? root.wagered
                                                               : root.staked
                                font.family: root.theme.font
                                font.pixelSize: 19
                                font.bold: true
                                color: root.theme.fg
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

                    // ── dealer ──
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 12
                        text: "DEALER"
                        font.family: root.theme.font
                        font.pixelSize: 10
                        font.letterSpacing: 2.4
                        color: root.theme.feltLine
                    }

                    CardFan {
                        id: dealerFan
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 30
                        slotW: 300
                        maxOffset: 30
                        cards: root.dealer
                        //  Face down only while it is genuinely unknown — the
                        //  peek reveals it the instant the dealer has 21.
                        downIndex: root.holeDown ? 1 : -1
                    }

                    TotalPill {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 124
                        cards: root.dealer
                        hidden: root.holeDown
                    }

                    // ── centre: the rules, and whatever the table is saying ──
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 154
                        spacing: 3

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "BLACKJACK PAYS " + root.bjNum + " TO " + root.bjDen
                            font.family: root.theme.font
                            font.pixelSize: 11
                            font.letterSpacing: 2.6
                            color: root.theme.feltLine
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "DEALER MUST STAND ON ALL 17s"
                            font.family: root.theme.font
                            font.pixelSize: 9
                            font.letterSpacing: 1.8
                            color: root.theme.feltLine
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.message
                            font.family: root.theme.font
                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 2
                            color: root.lastWin > root.staked && root.phase === "payout"
                                   ? root.theme.green : root.theme.fg
                            visible: root.message !== ""

                            SequentialAnimation on opacity {
                                running: root.phase === "payout"
                                loops: 4
                                NumberAnimation { to: 0.5; duration: 240 }
                                NumberAnimation { to: 1.0; duration: 240 }
                            }
                        }
                    }

                    // ── player ──
                    Item {
                        id: playerZone
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 210
                        width: parent.width
                        height: 144

                        //  Nothing is out yet: the circle is the whole table.
                        Item {
                            anchors.centerIn: parent
                            width: 96
                            height: 96
                            visible: root.hands.length === 0

                            Rectangle {
                                anchors.centerIn: parent
                                width: 84
                                height: 84
                                radius: 42
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
                                    visible: root.wagered === 0
                                }

                                Chip {
                                    anchors.centerIn: parent
                                    dim: 44
                                    amount: root.wagered
                                }
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

                        //  Cards are out: one column per hand, side by side.
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: root.theme.gap
                            visible: root.hands.length > 0

                            Repeater {
                                model: root.hands

                                Column {
                                    id: handCol
                                    required property var modelData
                                    required property int index

                                    readonly property bool isActive:
                                        index === root.active && root.phase === "player"

                                    width: root.slotW
                                    spacing: 6

                                    opacity: root.phase === "player" && !isActive
                                             && root.hands.length > 1 ? 0.55 : 1
                                    Behavior on opacity { NumberAnimation { duration: 200 } }

                                    TotalPill {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        cards: handCol.modelData.cards
                                        highlight: handCol.isActive
                                    }

                                    CardFan {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        slotW: root.slotW
                                        cards: handCol.modelData.cards
                                    }

                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 8

                                        Chip {
                                            anchors.verticalCenter: parent.verticalCenter
                                            dim: 24
                                            amount: handCol.modelData.bet
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: handCol.modelData.result
                                            font.family: root.theme.font
                                            font.pixelSize: 11
                                            font.bold: true
                                            font.letterSpacing: 1.2
                                            visible: text !== ""
                                            color: {
                                                const r = handCol.modelData.result;
                                                if (r === "BLACKJACK") return root.theme.gold;
                                                if (r === "WIN")       return root.theme.green;
                                                if (r === "PUSH")      return root.theme.muted;
                                                return root.theme.red;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══ chip rack ═══
                Row {
                    width: parent.width
                    height: 52
                    spacing: root.theme.gap

                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            readonly property bool sel: root.chipIndex === index

                            width: 52
                            height: 52
                            radius: 26
                            color: root.chipColor[index]
                            border.width: sel ? 3 : 2
                            border.color: sel ? root.theme.gold : Qt.rgba(0, 0, 0, 0.45)
                            scale: sel ? 1.0 : 0.88

                            Behavior on scale { NumberAnimation { duration: 110 } }
                            Behavior on border.color { ColorAnimation { duration: 110 } }

                            Text {
                                anchors.centerIn: parent
                                text: root.chips[index]
                                font.family: root.theme.font
                                font.pixelSize: 15
                                font.bold: true
                                color: root.chipInk[index]
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.chipIndex = index
                            }
                        }
                    }

                    Item {
                        width: parent.width - 4 * 52 - root.theme.gap * 4
                        height: 52
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.phase === "betting"
                                  ? "1-4 chip  ·  click circle to bet  ·  space deal"
                                  : "h hit  ·  s stand  ·  d double  ·  p split"
                            font.family: root.theme.font
                            font.pixelSize: 10
                            color: root.theme.inactive
                        }
                    }
                }

                // ═══ controls ═══
                //  Two sets in one row, swapped by phase — the betting keys are
                //  dead once the cards are out and the playing keys are dead
                //  before they are, so showing both at once would be four
                //  greyed buttons at all times.
                Row {
                    width: parent.width
                    spacing: root.theme.gap

                    readonly property real btnW:
                        (frame.width - root.theme.pad * 2 - root.theme.gap * 3) / 4

                    Btn {
                        width: parent.btnW
                        visible: root.phase === "betting"
                        label: "CLEAR"
                        hint: "c"
                        enabled: root.wagered > 0
                        onActivated: root.clearBets()
                    }
                    Btn {
                        width: parent.btnW
                        visible: root.phase === "betting"
                        label: "UNDO"
                        hint: "u"
                        enabled: root.betOrder.length > 0
                        onActivated: root.undo()
                    }
                    Btn {
                        width: parent.btnW
                        visible: root.phase === "betting"
                        label: "REBET"
                        hint: "r"
                        enabled: root.lastOrder.length > 0
                        onActivated: root.rebet()
                    }
                    Btn {
                        width: parent.btnW
                        visible: root.phase === "betting"
                        label: "DEAL"
                        hint: "space"
                        accent: true
                        enabled: root.wagered > 0
                        onActivated: root.deal()
                    }

                    Btn {
                        width: parent.btnW
                        visible: root.phase !== "betting"
                        label: "SPLIT"
                        hint: "p"
                        enabled: root.canSplit(root.active)
                        onActivated: root.split()
                    }
                    Btn {
                        width: parent.btnW
                        visible: root.phase !== "betting"
                        label: "DOUBLE"
                        hint: "d"
                        enabled: root.canDouble(root.active)
                        onActivated: root.doubleDown()
                    }
                    Btn {
                        width: parent.btnW
                        visible: root.phase !== "betting"
                        label: "STAND"
                        hint: "s"
                        enabled: root.ready(root.active)
                        onActivated: root.stand()
                    }
                    Btn {
                        width: parent.btnW
                        visible: root.phase !== "betting"
                        label: "HIT"
                        hint: "h"
                        accent: true
                        enabled: root.canHit(root.active)
                        onActivated: root.hit()
                    }
                }
            }
        }
    }
}
