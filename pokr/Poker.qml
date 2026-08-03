//  Poker.qml — Jacks or Better video poker, the whole widget in one component.
//
//  The game itself. poker.qml wraps this in a ShellRoot to run it on its own;
//  edge instantiates it directly, so the shell and the standalone widget are
//  the same code rather than two copies of it.
//
//  run:     qs -p ~/cloon/widgames/pokr/poker.qml
//
//  keys:    1-9 chip · q w e r t hold · b bet a coin · m max bet
//           space deal/draw · esc quit
//
//           1-5 are the chip rack before the cards are out and the five holds
//           once they are, because neither set of keys means anything in the
//           other phase. q-w-e-r-t sits above them and holds in either.
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

    //  Standalone, closing quits: there is nothing worth keeping a whole QML
    //  engine resident for once the window is down — the bank is on disk and
    //  the deck is 52 cards that mean nothing between hands. Inside edge the
    //  process is the shell's and outlives any one game, so closing only lowers
    //  `open`.
    property bool standalone: false

    // The screen to open on. Null takes the compositor's default, which is
    // what the standalone wrapper wants; edge binds it to the focused monitor.
    property var monitor: null

    // ═══════════════════════════════════════════════════════════
    //  THEME — the table if one is set, these values if not
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

        readonly property int    cardW:    92
        readonly property int    cardH:    132
        readonly property int    gap:      10
        readonly property int    pad:      20
        readonly property int    radius:   10
        readonly property string font:     "JetBrainsMono Nerd Font"

        //  Where the card sits: clear of the bar on the right, riding the
        //  bottom edge, and how long the slide up and down takes.
        readonly property int    edgeRight:  44 + 14
        readonly property int    edgeBottom: 10 + 14
        readonly property int    slideMs:    260
    }

    // ═══════════════════════════════════════════════════════════
    //  RULES — 9/6 Jacks or Better. Row order is the ranking.
    //
    //  The figures are in *coins*, which is what a pay table is denominated in
    //  on a real machine: what a hand actually returns is the coin figure times
    //  the chip on the rack. The royal's jump from 1000 to 4000 in the fifth
    //  column is the whole reason the coin count exists — it is the only line
    //  that does not scale, and playing short of five coins gives up ~1.4% for
    //  nothing.
    // ═══════════════════════════════════════════════════════════
    readonly property var payTable: [
        { name: "Royal Flush",     pay: [250, 500, 750, 1000, 4000] },
        { name: "Straight Flush",  pay: [ 50, 100, 150,  200,  250] },
        { name: "Four of a Kind",  pay: [ 25,  50,  75,  100,  125] },
        { name: "Full House",      pay: [  9,  18,  27,   36,   45] },
        { name: "Flush",           pay: [  6,  12,  18,   24,   30] },
        { name: "Straight",        pay: [  4,   8,  12,   16,   20] },
        { name: "Three of a Kind", pay: [  3,   6,   9,   12,   15] },
        { name: "Two Pair",        pay: [  2,   4,   6,    8,   10] },
        { name: "Jacks or Better", pay: [  1,   2,   3,    4,    5] }
    ]

    readonly property int maxCoins: 5

    readonly property var suitGlyph: ["♠", "♥", "♦", "♣"]
    readonly property var rankName: ["", "", "2", "3", "4", "5", "6", "7", "8",
                                     "9", "10", "J", "Q", "K", "A"]

    // ═══════════════════════════════════════════════════════════
    //  CHIPS
    //
    //  The house progression — white, red, green, black — which is what these
    //  denominations are on a real floor. `chipSpot` is the colour of the edge
    //  spots and the inner ring: white against every body except the white one,
    //  which takes navy, because white spots on a white chip are no spots.
    // ═══════════════════════════════════════════════════════════
    readonly property var chipColor: ["#e8e8ee", "#c13a4e", "#2f9e5a", "#22222c"]
    readonly property var chipSpot:  ["#55432a", "#e8ddc4", "#e8ddc4", "#e8ddc4"]
    readonly property var chipInk:   ["#0e0b0d", "#e8ddc4", "#e8ddc4", "#e8ddc4"]

    //  Every denomination that exists, in order. The first four are the rack a
    //  machine starts with; the rest are the high end, and repeat the same
    //  1/5/25/100 shape a thousand times up.
    readonly property var chipLadder: [1, 5, 25, 100, 1000, 5000, 25000, 100000]

    //  What the hand has to play with. The wager leaves `credits` when the
    //  cards come out and only comes back at the payout, so during the draw the
    //  bankroll is the pair — which is what stops the rack losing a chip
    //  underneath the player between the deal and the draw.
    readonly property int bankroll: root.credits
                                    + (root.phase === "draw" ? root.wager : 0)

    //  The rack. The base four are always out; above them a denomination
    //  appears once the bankroll covers it, so the thousand arrives the moment
    //  you are worth one.
    readonly property var chips: {
        const out = [];
        for (let i = 0; i < root.chipLadder.length; i++)
            if (i < 4 || root.chipLadder[i] <= root.bankroll)
                out.push(root.chipLadder[i]);
        return out;
    }

    //  Losing the top chip out from under the selection would otherwise leave
    //  it pointing past the end of the rack.
    onChipsChanged: if (root.chipIndex >= root.chips.length)
                        root.chipIndex = root.chips.length - 1;

    //  Which of the four palettes a chip wears. Everything from the hundred up
    //  wears the hundred's — a black chip carrying a bigger number — because a
    //  fifth and sixth invented colour would say less than the number already
    //  on the face does.
    function chipTier(amount) {
        if (amount >= 100) return 3;
        if (amount >= 25)  return 2;
        if (amount >= 5)   return 1;
        return 0;
    }

    //  What is printed on it. Four digits do not fit inside the ring, and
    //  nobody calls it a one-thousand chip anyway.
    function chipLabel(amount) {
        if (amount >= 1000000) return (amount / 1000000) + "M";
        if (amount >= 1000)    return (amount / 1000) + "k";
        return String(amount);
    }

    //  The wager, in the chips it is made of — which for video poker is always
    //  one column, since the coin count and the denomination are exactly what
    //  the player chose. Same [{ value, count }] shape `ChipStack` draws
    //  everywhere else.
    function betStacks() {
        return root.coins > 0 ? [{ value: root.denom, count: root.coins }] : [];
    }

    // ═══════════════════════════════════════════════════════════
    //  GAME STATE
    // ═══════════════════════════════════════════════════════════
    property int  credits:   200
    property int  chipIndex: 1          // index into `chips`, not a denomination
    property int  coins:     5          // 1-5, and the pay table's column

    //  How many times the bank has been emptied and put back. Kept beside the
    //  credits on disk, because a tally that reset every launch would only ever
    //  read 0 or 1.
    property int  rebuys:    0

    readonly property int denom: root.chips[root.chipIndex]

    //  What a deal costs, and what the payout is measured against.
    readonly property int wager: root.denom * root.coins

    property int  lastWin:    0
    property int  winRow:     -1        // index into payTable, -1 = no win
    property string phase:    "deal"    // "deal" = press deal · "draw" = pick holds
    property string message:  "PRESS DEAL TO START"

    property var deck:     []
    property int deckPos:  0
    property var hand:     [null, null, null, null, null]
    property var holds:    [false, false, false, false, false]
    property int revealStep: 5          // cards with index < this are face up

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
    //  same file whichever spelling of the path launched the widget — and to a
    //  different one from bjak's and rolt's, which is why the three games keep
    //  separate banks without arranging it.
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
            else console.warn("pokr: could not read bank:", error);
        }

        JsonAdapter {
            id: bank
            property int credits: 200
            property int rebuys:  0
        }
    }

    //  Explicit copy rather than `credits: bank.credits`, which would be a
    //  binding that silently dies at the first deal. The file is the source at
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
        //  Read before topUp(), which is the thing that increments it — a
        //  launch onto an empty bank is a wipeout like any other, and it has to
        //  count from the figure on disk rather than from zero.
        root.rebuys = bank.rebuys;
        root.topUp();
        bankFile.writeAdapter();
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
    //  widget that cannot be played and has no way back. Only called between
    //  hands, so it can never top up mid-round and pay out on a stake the
    //  player didn't have.
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

    // ── deck helpers ───────────────────────────────────────────
    function freshDeck() {
        let d = [];
        for (let s = 0; s < 4; s++)
            for (let r = 2; r <= 14; r++)
                d.push({ rank: r, suit: s });
        for (let i = d.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const t = d[i]; d[i] = d[j]; d[j] = t;
        }
        return d;
    }

    function cardName(c) {
        return c ? root.rankName[c.rank] + root.suitGlyph[c.suit] : "";
    }

    // ── hand evaluation ────────────────────────────────────────
    //  Returns a payTable row index, or -1 for a losing hand.
    function evaluate(h) {
        const ranks = h.map(c => c.rank).sort((a, b) => a - b);
        const suits = h.map(c => c.suit);

        const flush = suits.every(s => s === suits[0]);

        let straight = true;
        for (let i = 1; i < 5; i++)
            if (ranks[i] !== ranks[i - 1] + 1) { straight = false; break; }

        // the wheel: A2345, ace plays low
        const wheel = ranks[0] === 2 && ranks[1] === 3 && ranks[2] === 4
                   && ranks[3] === 5 && ranks[4] === 14;
        if (wheel) straight = true;

        const royal = straight && !wheel && ranks[0] === 10;

        let counts = {};
        for (const r of ranks) counts[r] = (counts[r] || 0) + 1;
        const groups = Object.keys(counts)
            .map(k => ({ rank: parseInt(k), n: counts[k] }))
            .sort((a, b) => b.n - a.n);

        if (flush && royal)                       return 0;
        if (flush && straight)                    return 1;
        if (groups[0].n === 4)                    return 2;
        if (groups[0].n === 3 && groups[1].n === 2) return 3;
        if (flush)                                return 4;
        if (straight)                             return 5;
        if (groups[0].n === 3)                    return 6;
        if (groups[0].n === 2 && groups[1].n === 2) return 7;
        if (groups[0].n === 2 && groups[0].rank >= 11) return 8;
        return -1;
    }

    // ═══════════════════════════════════════════════════════════
    //  BETTING
    //
    //  Two numbers make the stake: the chip off the rack and how many of them.
    //  Neither can move once the cards are out, because the pay table column
    //  the hand will be settled against is the coin count — a machine that let
    //  you raise after the deal would be a different game.
    // ═══════════════════════════════════════════════════════════
    function betOne(): void {
        if (root.phase !== "deal") return;
        root.coins = root.coins >= root.maxCoins ? 1 : root.coins + 1;
    }

    function unbetOne(): void {
        if (root.phase !== "deal") return;
        root.coins = root.coins <= 1 ? root.maxCoins : root.coins - 1;
    }

    function setCoins(n): void {
        if (root.phase !== "deal") return;
        if (n >= 1 && n <= root.maxCoins) root.coins = n;
    }

    function selectChip(i): void {
        if (root.phase !== "deal") return;
        if (i >= 0 && i < root.chips.length) root.chipIndex = i;
    }

    function maxBet(): void {
        if (root.phase !== "deal") return;
        root.coins = root.maxCoins;
        root.deal();
    }

    // ── actions ────────────────────────────────────────────────
    function toggleHold(i): void {
        if (root.phase !== "draw") return;
        if (i < 0 || i > 4) return;
        let h = holds.slice();
        h[i] = !h[i];
        holds = h;
    }

    function deal(): void {
        if (root.phase !== "deal") return;
        if (root.credits < root.wager) {
            root.message = "NOT ENOUGH CREDITS";
            return;
        }
        root.credits -= root.wager;
        root.lastWin = 0;
        root.winRow = -1;
        root.holds = [false, false, false, false, false];
        root.deck = root.freshDeck();
        root.deckPos = 0;

        let h = [];
        for (let i = 0; i < 5; i++) h.push(root.deck[root.deckPos++]);
        root.hand = h;

        root.phase = "draw";
        root.message = "HOLD YOUR CARDS";
        root.revealStep = 0;
        dealTimer.restart();
    }

    function draw(): void {
        if (root.phase !== "draw") return;

        let h = root.hand.slice();
        for (let i = 0; i < 5; i++)
            if (!root.holds[i]) h[i] = root.deck[root.deckPos++];
        root.hand = h;

        const row = root.evaluate(h);
        root.winRow = row;
        //  The pay table is in coins; the chip is what a coin is worth.
        root.lastWin = row >= 0 ? root.payTable[row].pay[root.coins - 1] * root.denom
                                : 0;
        root.credits += root.lastWin;

        root.phase = "deal";
        root.message = row >= 0
            ? root.payTable[row].name.toUpperCase() + "  —  WIN " + root.lastWin
            : "NO WIN  —  DEAL AGAIN";
        root.revealStep = 0;
        dealTimer.restart();

        //  The hand is settled and nothing is out, so this is the one moment a
        //  refill cannot land on top of a live stake.
        root.topUp();
    }

    function primary(): void {
        if (root.phase === "deal") root.deal(); else root.draw();
    }

    Timer {
        id: dealTimer
        interval: 65
        repeat: true
        running: false
        onTriggered: {
            root.revealStep++;
            if (root.revealStep >= 5) running = false;
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  CHIP — drawn rather than drawn on
    //
    //  A coloured body, eight spots cut into the rim, the ring they stop at and
    //  the denomination in the middle. Every measurement is a fraction of the
    //  radius, so the same component is the 26px chip in the circle and the
    //  52px one in the rack, and neither is a scaled bitmap.
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

                //  Eight spots on 45° centres. Each is the wedge between the
                //  rim and `stop`, which is why they read as cut out of the
                //  edge rather than painted onto it.
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
                //  how much room the chip takes up. It goes on thinner than
                //  the dark edge it replaces — a fine white line reads as
                //  picked out, where a heavy one reads as a different chip.
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
            id: face
            anchors.centerIn: parent
            text: root.chipLabel(chip.amount)
            font.family: root.theme.font
            //  Sized to the face inside the ring, not to the whole chip, so
            //  the number stays within the ring instead of running under the
            //  spots. The face is 0.66 of the chip and this font runs about
            //  0.6em to the character, so n characters need 0.6n em and the
            //  ratio that fits them is 0.66 / 0.6n.
            font.pixelSize: chip.dim * Math.min(0.42, 1.05 / text.length)
            font.bold: true
            color: root.chipInk[chip.tier]
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  CHIP STACK — a bet, in the chips it is made of
    //
    //  One column per denomination, each drawn as discs leaning up out of the
    //  one below so the stack has a height you can read at a glance. Past
    //  `maxVisible` the column stops growing and states its count instead.
    // ═══════════════════════════════════════════════════════════
    component ChipStack: Row {
        id: stack
        property var  model: []
        property real dim: 26
        property int  maxVisible: 5

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
                        //  Bottom chip first, each one lifted clear of it, so
                        //  the lower discs peek out below the top one.
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
    //  CARD — one playing card, face down until revealed
    // ═══════════════════════════════════════════════════════════
    component Card: Item {
        id: card

        required property int index
        readonly property var  model:  root.hand[index]
        readonly property bool held:   root.holds[index]
        // held cards never flip back down on a draw
        readonly property bool faceUp: model !== null
                                       && (held || index < root.revealStep)
        readonly property bool isRed:  model !== null
                                       && (model.suit === 1 || model.suit === 2)

        implicitWidth: root.theme.cardW
        implicitHeight: root.theme.cardH + 22

        // ── hold flag ──
        Rectangle {
            id: flag
            width: parent.width
            height: 18
            radius: 4
            color: card.held ? root.theme.gold : "transparent"
            border.width: card.held ? 0 : 1
            border.color: root.theme.feltLine

            Text {
                anchors.centerIn: parent
                text: "HELD"
                font.family: root.theme.font
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.5
                color: card.held ? root.theme.bg : root.theme.feltLine
            }

            Behavior on color { ColorAnimation { duration: 120 } }
        }

        // ── the card itself ──
        Item {
            id: body
            anchors.top: flag.bottom
            anchors.topMargin: 4
            width: parent.width
            height: root.theme.cardH

            scale: card.faceUp ? 1 : 0.94
            Behavior on scale {
                NumberAnimation { duration: 140; easing.type: Easing.OutBack }
            }

            Rectangle {
                anchors.fill: parent
                radius: root.theme.radius
                color: card.faceUp ? root.theme.cardFace : root.theme.cardBack
                border.width: 2
                border.color: card.held ? root.theme.gold : "transparent"

                Behavior on color { ColorAnimation { duration: 110 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                // face-down lattice
                Item {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: !card.faceUp
                    clip: true
                    Repeater {
                        model: 14
                        Rectangle {
                            required property int index
                            width: 1
                            height: parent.height * 2
                            x: index * 10 - 20
                            y: -parent.height / 2
                            rotation: 30
                            color: Qt.lighter(root.theme.cardBack, 1.5)
                            opacity: 0.6
                        }
                    }
                }

                // corner rank + pip
                Column {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: 7
                    anchors.leftMargin: 9
                    spacing: -2
                    visible: card.faceUp

                    Text {
                        text: card.model ? root.rankName[card.model.rank] : ""
                        font.family: root.theme.font
                        font.pixelSize: 19
                        font.bold: true
                        color: card.isRed ? root.theme.cardRed : root.theme.cardInk
                    }
                    Text {
                        text: card.model ? root.suitGlyph[card.model.suit] : ""
                        font.family: root.theme.font
                        font.pixelSize: 15
                        color: card.isRed ? root.theme.cardRed : root.theme.cardInk
                    }
                }

                // big centre pip
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 10
                    text: card.model ? root.suitGlyph[card.model.suit] : ""
                    font.pixelSize: 46
                    color: card.isRed ? root.theme.cardRed : root.theme.cardInk
                    opacity: 0.92
                    visible: card.faceUp
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: root.phase === "draw" ? Qt.PointingHandCursor
                                                   : Qt.ArrowCursor
                onClicked: root.toggleHold(card.index)
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
    // ═══════════════════════════════════════════════════════════
    function quit(): void {
        if (root.standalone)
            Qt.quit();
        else
            root.open = false;
    }

    IpcHandler {
        target: "poker"

        function toggle(): void { root.open ? root.quit() : root.open = true; }
        function show():   void { root.open = true; }
        function hide():   void { root.quit(); }

        //  Play the widget without touching it — bind these in hyprland.conf.
        function play(): void   { root.primary(); }   // deal, or draw
        function deal(): void   { root.deal(); }
        function draw(): void   { root.draw(); }
        function betOne(): void { root.betOne(); }
        function maxBet(): void { root.maxBet(); }
        function hold(n: int): void { root.toggleHold(n - 1); }

        //  Stakes by denomination rather than by rack position, so a script
        //  does not have to know what the rack looks like today.
        function chip(n: int): void {
            root.selectChip(root.chips.indexOf(n));
        }
        function coins(n: int): void { root.setCoins(n); }
        function reset(): void { root.resetBank(); }
        function payback(): void { root.payBack(); }

        //  Machine-readable state — handy for a waybar/eww credits readout.
        function status(): string {
            return JSON.stringify({
                //  `open`, not whether the window happens to be mapped.
                visible: root.open,
                credits: root.credits,
                rebuys: root.rebuys,
                chip: root.denom,
                coins: root.coins,
                wager: root.wager,
                phase: root.phase,
                message: root.message,
                lastWin: root.lastWin,
                winRow: root.winRow,
                winName: root.winRow >= 0 ? root.payTable[root.winRow].name : "",
                holds: root.holds,
                hand: root.hand.map(root.cardName)
            });
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  WINDOW
    //
    //  A plain desktop window, the same one roulette opens in — everything
    //  below `frame` is self-contained, so putting this on a layer shell later
    //  means swapping this block and nothing else.
    // ═══════════════════════════════════════════════════════════
    //  Whether it should be on screen. Everything that shows or hides the
    //  widget sets this and nothing else; the window follows.
    property bool open: false

    //  pad · header · pay table · felt · rack · buttons · pad, with the
    //  Column's spacing between each. Stated rather than derived so the window
    //  does not resize itself a frame after it opens.
    readonly property int headerH: 40
    readonly property int payH:    12 + 20 * (1 + payTable.length)
    readonly property int feltH:   324
    readonly property int rackH:   52
    readonly property int btnH:    42

    //  The surface follows `open`; `showing` keeps it alive through the
    //  slide-out, then lets the LazyLoader drop the window - engine, felt and
    //  all - so a closed game costs nothing.
    property bool showing: false

    onOpenChanged: if (root.open)
        root.showing = true

    LazyLoader {
        id: loader
        active: root.showing

        PanelWindow {
            id: win
            color: "transparent"
            screen: root.monitor

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "poker"
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

            //  1 is up, 0 is gone. The card's position is drawn from this
            //  rather than the window being moved, so the layer surface is
            //  laid out once and the compositor isn't resizing it sixty times
            //  a second.
            property real reveal: (root.open && win.entered) ? 1 : 0

            //  Off until the window has finished being built, so the first
            //  frame is drawn with the card still below the screen and it
            //  slides up into view.
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
            //  transparent, which is not the same as absent — unmasked it
            //  would swallow clicks meant for whatever is underneath.
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

                implicitWidth: root.theme.cardW * 5 + root.theme.gap * 4
                               + root.theme.pad * 2
                implicitHeight: root.theme.pad * 2 + root.headerH + 14 + root.payH
                                + 14 + root.feltH + 14 + root.rackH + 14 + root.btnH

            Keys.onPressed: (e) => {
                //  1-5 are two different keys depending on what is on the felt,
                //  which is the same swap the button row below makes: the rack
                //  is dead once the cards are out and the holds are dead before
                //  they are. q-w-e-r-t holds in either phase for anyone who
                //  would rather not think about it.
                if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                    const i = e.key - Qt.Key_1;
                    if (root.phase === "draw") root.toggleHold(i);
                    else                       root.selectChip(i);
                    e.accepted = true;
                    return;
                }
                switch (e.key) {
                case Qt.Key_Q: root.toggleHold(0); break;
                case Qt.Key_W: root.toggleHold(1); break;
                case Qt.Key_E: root.toggleHold(2); break;
                case Qt.Key_R: root.toggleHold(3); break;
                case Qt.Key_T: root.toggleHold(4); break;
                case Qt.Key_Space:
                case Qt.Key_Return:
                case Qt.Key_Enter: root.primary(); break;
                case Qt.Key_B: root.betOne(); break;
                case Qt.Key_M: root.maxBet(); break;
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
                    height: root.headerH

                    Column {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: "VIDEO POKER"
                            font.family: root.theme.font
                            font.pixelSize: 15
                            font.bold: true
                            font.letterSpacing: 2
                            color: root.theme.fg
                        }
                        Text {
                            text: "JACKS OR BETTER  ·  9/6  ·  "
                                  + root.denom + " PER COIN"
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
                                text: "IN PLAY"
                                font.family: root.theme.font
                                font.pixelSize: 9
                                font.letterSpacing: 1.4
                                color: root.theme.inactive
                            }
                            Text {
                                anchors.right: parent.right
                                text: root.wager
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

                // ═══ pay table ═══
                //
                //  The five columns are the coin counts, so the header row is
                //  the coin selector rather than a second control that says the
                //  same thing somewhere else: the column you are playing is the
                //  column you are paid out of, and clicking one picks it.
                Rectangle {
                    width: parent.width
                    height: root.payH
                    radius: 8
                    color: root.theme.surface
                    border.width: 1
                    border.color: root.theme.raised

                    Column {
                        id: payCol
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 0

                        // ── coin selector, doubling as the column heads ──
                        Item {
                            width: payCol.width
                            height: 20

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "COINS"
                                font.family: root.theme.font
                                font.pixelSize: 9
                                font.letterSpacing: 1.6
                                color: root.theme.inactive
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                Repeater {
                                    model: root.maxCoins

                                    Rectangle {
                                        id: head
                                        required property int index
                                        readonly property bool active:
                                            root.coins === index + 1

                                        width: 54
                                        height: 18
                                        radius: 3
                                        color: head.active ? root.theme.raised
                                                           : "transparent"

                                        Behavior on color {
                                            ColorAnimation { duration: 110 }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: head.index + 1
                                            font.family: root.theme.font
                                            font.pixelSize: 11
                                            font.bold: head.active
                                            color: head.active ? root.theme.gold
                                                               : root.theme.inactive
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: root.phase === "deal"
                                                ? Qt.PointingHandCursor
                                                : Qt.ArrowCursor
                                            onClicked: root.setCoins(head.index + 1)
                                        }
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: root.payTable

                            Rectangle {
                                required property int index
                                required property var modelData

                                // named aliases: the inner Repeater below
                                // shadows `index`, and `modelData` there
                                // would be ambiguous to a reader
                                readonly property int rowIndex: index
                                readonly property var row: modelData
                                readonly property bool winner:
                                    root.winRow === rowIndex

                                width: payCol.width
                                height: 20
                                radius: 4
                                color: winner ? root.theme.gold
                                              : "transparent"

                                Behavior on color {
                                    ColorAnimation { duration: 160 }
                                }

                                // flash the winning row
                                SequentialAnimation on opacity {
                                    running: winner
                                    loops: 6
                                    NumberAnimation {
                                        to: 0.45; duration: 200
                                    }
                                    NumberAnimation {
                                        to: 1.0; duration: 200
                                    }
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.name
                                    font.family: root.theme.font
                                    font.pixelSize: 12
                                    font.bold: winner
                                    color: winner ? root.theme.bg
                                                  : root.theme.fg
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0

                                    Repeater {
                                        model: root.maxCoins

                                        Rectangle {
                                            required property int index
                                            readonly property bool active:
                                                root.coins === index + 1

                                            width: 54
                                            height: 18
                                            radius: 3
                                            color: active && root.winRow < 0
                                                   ? root.theme.raised
                                                   : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: row.pay[index]
                                                font.family: root.theme.font
                                                font.pixelSize: 12
                                                font.bold: parent.active
                                                horizontalAlignment: Text.AlignRight
                                                color: winner
                                                       ? root.theme.bg
                                                       : parent.active
                                                         ? root.theme.gold
                                                         : root.theme.inactive
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══ the table ═══
                Rectangle {
                    id: table
                    width: parent.width
                    height: root.feltH
                    radius: 14
                    color: root.theme.felt
                    border.width: 1
                    border.color: root.theme.feltLine

                    // ── the hand ──
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 14
                        spacing: root.theme.gap

                        Repeater {
                            model: 5
                            Card {}
                        }
                    }

                    // ── whatever the table is saying ──
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 176
                        text: root.message
                        font.family: root.theme.font
                        font.pixelSize: 13
                        font.bold: true
                        font.letterSpacing: 2
                        color: root.lastWin > 0   ? root.theme.green
                             : root.phase === "draw" ? root.theme.fg
                                                     : root.theme.feltLine

                        SequentialAnimation on opacity {
                            running: root.lastWin > 0 && root.phase === "deal"
                            loops: 4
                            NumberAnimation { to: 0.5; duration: 240 }
                            NumberAnimation { to: 1.0; duration: 240 }
                        }
                    }

                    // ── the bet ──
                    //
                    //  The circle holds the coins as the chips they are, so the
                    //  stake is a thing on the felt rather than a number in a
                    //  box. Clicking it is the coin selector again — up on the
                    //  left button, down on the right — because a bet you can
                    //  see is a bet you should be able to touch.
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 206
                        width: 104
                        height: 104

                        Rectangle {
                            anchors.centerIn: parent
                            width: 96
                            height: 96
                            radius: 48
                            color: "transparent"
                            border.width: 2
                            border.color: circleArea.containsMouse
                                          && root.phase === "deal"
                                          ? root.theme.gold : root.theme.feltLine

                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }

                        //  Outside the circle rather than inside it, so a tall
                        //  bet spills over the edge the way chips do instead of
                        //  being boxed in by it.
                        ChipStack {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -6
                            model: root.betStacks()
                            dim: 28
                            maxVisible: root.maxCoins
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: root.coins + " × " + root.denom
                            font.family: root.theme.font
                            font.pixelSize: 10
                            font.letterSpacing: 1.4
                            color: root.theme.feltLine
                        }

                        MouseArea {
                            id: circleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: root.phase === "deal"
                                         ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: (m) => {
                                if (m.button === Qt.RightButton) root.unbetOne();
                                else root.betOne();
                            }
                        }
                    }
                }

                // ═══ chip rack ═══
                Row {
                    width: parent.width
                    height: root.rackH
                    spacing: root.theme.gap

                    Repeater {
                        model: root.chips
                        Item {
                            id: slot
                            required property var modelData
                            required property int index
                            readonly property bool sel: root.chipIndex === index

                            width: root.rackH
                            height: root.rackH

                            Chip {
                                anchors.centerIn: parent
                                dim: root.rackH
                                amount: slot.modelData
                                selected: slot.sel
                                scale: slot.sel ? 1.0 : 0.88
                                opacity: root.phase === "deal" ? 1 : 0.5
                                Behavior on scale { NumberAnimation { duration: 110 } }
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: root.phase === "deal"
                                             ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.selectChip(slot.index)
                            }
                        }
                    }
                }

                // ═══ controls ═══
                //  Two sets in one row, swapped by phase — the betting buttons
                //  are dead once the cards are out and the draw is dead before
                //  they are, so showing both at once would be greyed buttons at
                //  all times.
                Row {
                    width: parent.width
                    height: root.btnH
                    spacing: root.theme.gap

                    readonly property real btnW:
                        (frame.width - root.theme.pad * 2 - root.theme.gap * 2) / 3

                    Btn {
                        width: parent.btnW
                        visible: root.phase === "deal"
                        label: "BET ONE"
                        hint: "b"
                        onActivated: root.betOne()
                    }
                    Btn {
                        width: parent.btnW
                        visible: root.phase === "deal"
                        label: "MAX BET"
                        hint: "m"
                        enabled: root.credits >= root.denom * root.maxCoins
                        onActivated: root.maxBet()
                    }
                    Btn {
                        width: parent.btnW
                        visible: root.phase === "deal"
                        label: "DEAL"
                        hint: "space"
                        accent: true
                        enabled: root.credits >= root.wager
                        onActivated: root.deal()
                    }

                    Btn {
                        width: parent.btnW * 2 + root.theme.gap
                        visible: root.phase === "draw"
                        label: "HOLD"
                        hint: "click a card · q w e r t"
                        enabled: false
                    }
                    Btn {
                        width: parent.btnW
                        visible: root.phase === "draw"
                        label: "DRAW"
                        hint: "space"
                        accent: true
                        onActivated: root.draw()
                    }
                }
            }
        }
    }
    }
}
