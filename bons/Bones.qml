//  Bones.qml — 5×5 minesweeper-for-money, the whole widget in one component.
//
//  The game itself. bns.qml wraps this in a ShellRoot to run it on its own;
//  edge instantiates it directly, so the shell and the standalone widget are
//  the same code rather than two copies of it.
//
//  run:     qs -p ~/cloon/widgames/bons/bns.qml
//
//  keys:    1-9 chip · -/+ or [/] bones · space play · arrows aim
//           enter pick · g lucky pick · x cash · u undo · c clear
//           r rebet · esc close
//
//  Edit the `theme` block below to restyle everything.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // The screen to open on. Null takes the compositor's default, which is what
    // the standalone wrapper wants; edge binds it to the focused monitor.
    property var monitor: null

    // True only under bns.qml, where this is the whole process: there, closing
    // is quitting. Inside edge the shell outlives the game, so closing only
    // hides it — and the window is destroyed either way, so the felt and the
    // field stop costing anything the moment it goes.
    property bool standalone: false

    // ═══════════════════════════════════════════════════════════
    //  THEME — the only block you normally touch
    //
    //  Blackjack's palette to the letter, including the two edge offsets:
    //  widgets that share a corner should arrive in the same colours as well as
    //  the same place.
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

        //  The tiles. Face down they sit a step above the felt; turned they
        //  drop back into it, so the unturned ones stay the thing to look at.
        readonly property color tileBack:  "#1f4436"
        readonly property color tileFace:  "#132b22"

        readonly property color cardRed:   "#d3283a"

        readonly property int    tile:     56
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
    //  Twenty-five boxes. Between 1 and 24 of them hold bones; every other box
    //  holds a prize. The code calls the killers bones throughout — that is
    //  the game's name and its IPC surface — but the felt shows a custom
    //  poker chip for the prizes and a stick of dynamite for the bones. See
    //  THE PLATE, which is where a reskin happens.
    //
    //  The stake goes down, the field is dealt, and the
    //  player turns boxes one at a time: a chip multiplies the stake up and
    //  the money can be taken at any point; a bone ends it and the stake is
    //  gone. Turning every chip on the field pays out where it stands, because
    //  there is nothing left to turn but bones.
    //
    //  The price of each chip is not a table, it is one line: fair odds against
    //  surviving the picks made so far, times `rtp`. More bones make each pick
    //  more likely to die and therefore worth more — the whole 24×24 grid of
    //  multipliers falls out of `multiplier` below, which is why there is no
    //  24×24 grid of multipliers in this file.
    // ═══════════════════════════════════════════════════════════
    readonly property int  cells:    25
    readonly property int  minBones: 1
    readonly property int  maxBones: 24

    //  The house's cut, taken as a factor on fair odds. 0.99 is the 1% game.
    readonly property real rtp: 0.99

    // ═══════════════════════════════════════════════════════════
    //  THE PRICE
    //
    //  Pure functions over the two numbers that matter, with no reference to
    //  the widget's state. The round below is built entirely out of these, and
    //  so are the tests — which is the point of keeping them free of it.
    // ═══════════════════════════════════════════════════════════
    //  What the stake is multiplied by after `picks` chips against `bones`
    //  bones. Each pick survives with (safe − i) chances in (cells − i), so
    //  fair odds are the product of the reciprocals — built up term by term
    //  rather than through factorials, which would overflow long before the
    //  9,193× that 13 picks against 13 bones is honestly worth.
    function multiplier(bones, picks) {
        if (picks <= 0) return 0;
        let m = root.rtp;
        for (let i = 0; i < picks; i++)
            m *= (root.cells - i) / (root.cells - bones - i);
        return m;
    }

    //  The credit figure a stake comes back as. Rounded to the nearest whole
    //  credit rather than floored: the smallest chip is 1, and flooring would
    //  pay ×1.96 as ×1 on a stake of 1, which reads as a broken payout rather
    //  than as rounding.
    function payout(stake, bones, picks) {
        return Math.round(stake * root.multiplier(bones, picks));
    }

    //  How a multiplier is printed. Two decimals while they mean anything;
    //  past ×100 they are noise on a number that is about to stop fitting.
    function multText(m) {
        return "×" + (m >= 100 ? Math.round(m) : m.toFixed(2));
    }

    // ═══════════════════════════════════════════════════════════
    //  THE FIELD
    // ═══════════════════════════════════════════════════════════
    //  Fisher-Yates over the 25 indices, bones on the first `bones` of them —
    //  so every layout is equally likely, which is what the distribution test
    //  checks. One flat array of booleans: true is a bone.
    function buildField(bones) {
        const idx = [];
        for (let i = 0; i < root.cells; i++) idx.push(i);
        for (let i = idx.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const t = idx[i]; idx[i] = idx[j]; idx[j] = t;
        }
        const f = [];
        for (let i = 0; i < root.cells; i++) f.push(false);
        for (let i = 0; i < bones; i++) f[idx[i]] = true;
        return f;
    }

    // ═══════════════════════════════════════════════════════════
    //  GAME STATE
    // ═══════════════════════════════════════════════════════════
    //  The house progression — white, red, green, black — which is what these
    //  denominations are on a real floor. `chipSpot` is the colour of the edge
    //  spots and the inner ring: white against every body except the white one,
    //  which takes navy, because white spots on a white chip are no spots.
    readonly property var chipColor: ["#e8e8ee", "#d3283a", "#2f9e5a", "#22222c"]
    readonly property var chipSpot:  ["#2b3a63", "#ffffff", "#ffffff", "#ffffff"]
    readonly property var chipInk:   ["#16161e", "#ffffff", "#ffffff", "#ffffff"]

    readonly property var chipLadder: [1, 5, 25, 100, 1000, 5000, 25000, 100000]

    //  What the round has to play with. The stake sits in the circle during
    //  betting and out on the field after that, so no single figure is the
    //  bankroll — but the pair that is live in each phase always sums to what
    //  the round opened on.
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

    //  betting · picking · payout
    property string phase:   "betting"
    property string message: "PLACE YOUR BET"

    //  How many bones go into the field. Set while betting, frozen the moment
    //  the field is dealt, and remembered on disk beside the bank — a player
    //  who likes the 5-bone game should not have to say so every launch.
    property int bones: 3

    readonly property int safe: root.cells - root.bones

    //  The field itself and what has been turned. Both are flat arrays of 25
    //  booleans, both reassigned whole on every change — QML only notices
    //  whole reassignments. Empty between rounds, which is how the tiles know
    //  there is nothing under them yet.
    property var field:    []
    property var revealed: []

    //  Chips found this round. The multiplier is a function of this and
    //  `bones` and nothing else.
    property int found: 0

    //  Where the fatal bone was, for the one tile that gets the red treatment.
    property int bustAt: -1

    //  The stake, once it is out of the circle and on the field.
    property int stake: 0

    //  How the round ended, for the message and the field's colours:
    //  "" · "cash" · "bust" · "sweep" (every chip on the field found).
    property string outcome: ""

    property int lastWin: 0

    //  Where the keyboard is aimed. The centre box to start, because that is
    //  where the eye starts.
    property int cursor: 12

    //  Chips in the circle, in the order they went down — so undo is a pop and
    //  the total is a sum.
    property var betOrder:  []
    property var lastOrder: []

    readonly property int wagered: {
        let t = 0;
        for (let i = 0; i < root.betOrder.length; i++) t += root.betOrder[i];
        return t;
    }

    //  What taking the money now would come to, and what one more chip would
    //  make of it. Zero picks is worth nothing — walking at the door returns
    //  the stake only in the sense that it never left, and the round does not
    //  allow it — so `cashValue` doubles as `canCash`.
    readonly property int cashValue: root.found > 0
                                     ? root.payout(root.stake, root.bones, root.found)
                                     : 0
    readonly property int nextValue: root.found < root.safe
                                     ? root.payout(root.stake, root.bones, root.found + 1)
                                     : 0

    //  What is on the felt, for the header. Once the round is over this is
    //  what came back rather than what was on offer — a busted round reads 0,
    //  not the pile it died one pick after being worth.
    readonly property int riding: root.phase === "betting" ? root.wagered
                                : root.phase === "payout"  ? root.lastWin
                                : root.found > 0           ? root.cashValue
                                                           : root.stake

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
    //  `~/.local/state/quickshell/by-shell/<id>/`, holding the only things
    //  worth carrying between sittings.
    // ═══════════════════════════════════════════════════════════
    FileView {
        id: bankFile

        path: Quickshell.statePath("bank.json")

        //  Read before the first frame — a bank that arrives a frame late shows
        //  200 and then flickers to the real figure.
        blockLoading: true

        //  And written synchronously. The file is forty bytes, so the cost is
        //  nothing, and the last write is on disk before `Qt.quit()` returns.
        blockWrites: true
        atomicWrites: true

        //  A missing file is the first run, not a fault: say nothing, write the
        //  defaults, carry on. Anything else is a real error and should be loud.
        printErrors: false
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) bankFile.writeAdapter();
            else console.warn("bons: could not read bank:", error);
        }

        JsonAdapter {
            id: bank
            property int credits: 200
            property int rebuys:  0
            property int bones:   3
        }
    }

    //  Explicit copy rather than `credits: bank.credits`, which would be a
    //  binding that silently dies at the first wager. The file is the source at
    //  startup and a mirror from then on.
    Component.onCompleted: {
        //  This `text()` looks pointless and is not — do not delete it.
        //  `blockLoading` blocks a read, but nothing has *asked* for one yet at
        //  this point: FileView's own load lands on `onLoaded`, which fires
        //  after this handler. Read `bank.credits` here without forcing the
        //  load and it is still the default 200, which then gets written
        //  straight back over the real figure.
        bankFile.text();
        root.credits = bank.credits;
        //  Read before topUp(), which is the thing that increments it — a
        //  launch onto an empty bank is a wipeout like any other, and it has to
        //  count from the figure on disk rather than from zero.
        root.rebuys = bank.rebuys;
        //  Clamped on the way in, so a hand-edited file cannot deal a field of
        //  25 bones and no chips.
        root.bones = Math.max(root.minBones, Math.min(root.maxBones, bank.bones));
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
    onBonesChanged: {
        bank.bones = root.bones;
        bankFile.writeAdapter();
    }

    //  The smallest chip is 1, so an empty bank is not a low score — it is a
    //  widget that cannot be played and has no way back. Only called where the
    //  circle is already clear, so it can never top up mid-round and pay out on
    //  a stake the player didn't have.
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

    //  Clamped rather than refused, and only while betting — a field mid-round
    //  holds the bones it was dealt with.
    function setBones(n): void {
        if (root.phase !== "betting") return;
        root.bones = Math.max(root.minBones, Math.min(root.maxBones, n));
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
    //  the total printed on it — a stack per denomination, largest first.
    //  Returns [{ value, count }, …], which is what `ChipStack` draws.
    function betStacks() {
        const counts = {};
        for (let i = 0; i < root.betOrder.length; i++)
            counts[root.betOrder[i]] = (counts[root.betOrder[i]] || 0) + 1;
        const out = [];
        //  Over the whole ladder rather than the current rack: a chip already
        //  in the circle must keep being drawn even if the bankroll it bought
        //  has since dropped below its denomination.
        for (let i = root.chipLadder.length - 1; i >= 0; i--) {
            const d = root.chipLadder[i];
            if (counts[d]) out.push({ value: d, count: counts[d] });
        }
        return out;
    }

    // ═══════════════════════════════════════════════════════════
    //  THE ROUND
    // ═══════════════════════════════════════════════════════════
    function start(): void {
        if (root.phase !== "betting") return;
        if (root.wagered === 0) { root.message = "PLACE A BET FIRST"; return; }

        //  Revealed before field: the boxes' bindings fire the moment each
        //  array lands, and a dealt field against last round's empty
        //  `revealed` reads undefined 25 times over.
        root.revealed = root.buildField(0);      // 25 falses, same shape
        root.field    = root.buildField(root.bones);
        root.found    = 0;
        root.bustAt   = -1;
        root.outcome  = "";
        root.lastWin  = 0;
        root.stake    = root.wagered;
        root.phase    = "picking";
        root.message  = "";
    }

    function canPick(i): bool {
        return root.phase === "picking"
            && i >= 0 && i < root.cells && !root.revealed[i];
    }

    //  The whole of the game, in one function: turn a box and settle it. A
    //  bone settles the round on the spot; a chip re-prices the stake; the
    //  last chip on the field pays out unasked, because the only boxes left
    //  are the ones that lose.
    function pick(i): void {
        if (!root.canPick(i)) return;

        root.cursor = i;
        const r = root.revealed.slice();
        r[i] = true;
        root.revealed = r;

        if (root.field[i]) {
            root.bustAt  = i;
            root.outcome = "bust";
            root.finish(0);
            return;
        }

        root.found += 1;
        if (root.found >= root.safe) {
            root.outcome = "sweep";
            root.finish(root.payout(root.stake, root.bones, root.found));
            return;
        }
        root.message = "";
    }

    //  One box, chosen for you, from the boxes that are still down — the
    //  house's random is no kinder or crueller than your own.
    function luckyPick(): void {
        if (root.phase !== "picking") return;
        const down = [];
        for (let i = 0; i < root.cells; i++)
            if (!root.revealed[i]) down.push(i);
        if (down.length === 0) return;
        root.pick(down[Math.floor(Math.random() * down.length)]);
    }

    function canCash(): bool {
        return root.phase === "picking" && root.found > 0;
    }

    function cash(): void {
        if (!root.canCash()) return;
        root.outcome = "cash";
        root.finish(root.cashValue);
    }

    //  Every ending goes through here: the bank moves once, the message is
    //  written once, and the clear-down is one timer rather than three.
    function finish(ret): void {
        root.credits += ret;
        root.lastWin  = ret;
        root.phase    = "payout";

        const net = ret - root.stake;
        root.message = root.outcome === "bust"
                       ? "KABOOM  −" + root.stake
                     : root.outcome === "sweep" ? "CLEARED THE FIELD  +" + net
                     : net > 0                  ? "CASHED OUT  +" + net
                                                : "CASHED OUT";
        payoutTimer.restart();
    }

    Timer {
        id: payoutTimer
        interval: 2600
        onTriggered: {
            root.lastOrder = root.betOrder.slice();
            root.betOrder  = [];
            root.field     = [];
            root.revealed  = [];
            root.found     = 0;
            root.bustAt    = -1;
            root.stake     = 0;
            root.outcome   = "";
            root.phase     = "betting";
            //  topUp() writes its own message when it fires, so don't stomp it.
            if (!root.topUp()) root.message = "PLACE YOUR BET";
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  CHIP
    //
    //  A real clay chip: a coloured body, eight edge spots cut into the rim,
    //  the ring those spots stop at, a dark edge, and the denomination in the
    //  middle. Every measurement is a fraction of the radius, so the same
    //  component is the chip in the circle and the 52px one in the rack.
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
                //  how much room the chip takes up.
                ctx.beginPath();
                ctx.arc(cx, cy, rim, 0, 2 * Math.PI);
                ctx.strokeStyle = chip.selected ? root.theme.fg
                                                : Qt.rgba(0, 0, 0, 0.55);
                ctx.lineWidth = chip.selected ? Math.max(1, edge * 0.6) : edge;
                ctx.stroke();
            }
        }

        //  Canvas repaints itself on resize but not on a colour change, and
        //  the tier moves under a growing stack.
        onTierChanged:     clay.requestPaint()
        onSelectedChanged: clay.requestPaint()

        Text {
            anchors.centerIn: parent
            text: root.chipLabel(chip.amount)
            font.family: root.theme.font
            //  Sized to the face inside the ring, not to the whole chip, so
            //  the number stays within the ring instead of running under the
            //  spots.
            font.pixelSize: chip.dim * Math.min(0.42, 1.05 / text.length)
            font.bold: true
            color: root.chipInk[chip.tier]
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  THE PLATE — what is under the boxes
    //
    //  The prize is a poker chip supplied as an image — pokchip.png next
    //  door, cropped to its own alpha so it fills the box rather than
    //  floating in its source file's padding. Swap the file to reskin it.
    //
    //  The killer is a stick of dynamite, drawn as literal pixel art — a
    //  12×12 map of cells, each painted as a hard-edged square — so it sits
    //  in the same style as the chip, which is pixel art itself.
    // ═══════════════════════════════════════════════════════════
    component Prize: Image {
        property real dim: 38

        width: dim
        height: dim
        source: "pokchip.png"
        fillMode: Image.PreserveAspectFit
        //  The source is 33px on its long side; the box wants ~42. Mipmap +
        //  smooth is what keeps that upscale from pixelating.
        smooth: true
        mipmap: true
    }

    component Dynamite: Item {
        id: tnt
        property real dim: 40
        //  The one that got you: the fuse is lit. The rest of the field's
        //  sticks show cold, which is the difference between the thing that
        //  went off and the things that merely were there.
        property bool hot: false

        width: dim
        height: dim

        //  One character per pixel. R stick · H highlight · D band ·
        //  F fuse · S spark · W spark core. The spark rows only land when
        //  the fuse is lit; cold sticks get a bare fuse and empty sky.
        readonly property var art: [
            "....WS......",
            "...SWWS.....",
            "....SS......",
            "......F.....",
            "......FF....",
            "...RRRRRR...",
            "...HRRRRR...",
            "...DDDDDD...",
            "...HRRRRR...",
            "...HRRRRR...",
            "...DDDDDD...",
            "...RRRRRR..."
        ]

        Canvas {
            id: stick
            anchors.fill: parent
            //  Pixel art: the whole point is the hard edge.
            smooth: false

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();

                const ink = {
                    R: "#d3283a", H: "#ef6a58", D: "#7d1622",
                    F: "#c9a86a",
                    S: root.theme.gold, W: "#ffffff"
                };

                const rows = tnt.art.length, cols = tnt.art[0].length;
                const px = Math.floor(Math.min(width / cols, height / rows));
                const ox = (width - px * cols) / 2;
                const oy = (height - px * rows) / 2;

                for (let r = 0; r < rows; r++)
                    for (let c = 0; c < cols; c++) {
                        const ch = tnt.art[r].charAt(c);
                        if (ch === ".") continue;
                        if (!tnt.hot && (ch === "S" || ch === "W")) continue;
                        ctx.fillStyle = ink[ch];
                        ctx.fillRect(ox + c * px, oy + r * px, px, px);
                    }
            }

            //  A stick that lights up after being painted cold has to say so.
            Connections {
                target: tnt
                function onHotChanged() { stick.requestPaint(); }
            }
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
        target: "bones"

        function toggle(): void { root.open = !root.open; }
        function show():   void { root.open = true; }
        function hide():   void { root.quit(); }

        function play():  void { root.start(); }
        function pick(i: int): void { root.pick(i); }
        function lucky(): void { root.luckyPick(); }
        function cash():  void { root.cash(); }

        function bones(n: int): void { root.setBones(n); }

        function undo():  void { root.undo(); }
        function clear(): void { root.clearBets(); }
        function rebet(): void { root.rebet(); }
        function reset(): void { root.resetBank(); }

        //  Stakes `amount` regardless of the selected chip, so a scripted
        //  round doesn't have to drive the rack first.
        function bet(amount: int): void { root.wager(amount); }
        function chip(n: int): void {
            const i = root.chips.indexOf(n);
            if (i >= 0) root.chipIndex = i;
        }

        function status(): string {
            return JSON.stringify({
                visible: true,
                credits: root.credits,
                rebuys: root.rebuys,
                wagered: root.wagered,
                stake: root.stake,
                chip: root.chips[root.chipIndex],
                phase: root.phase,
                message: root.message,
                bones: root.bones,
                safe: root.safe,
                found: root.found,
                multiplier: root.found > 0
                            ? root.multiplier(root.bones, root.found) : 0,
                cashValue: root.cashValue,
                nextMultiplier: root.found < root.safe
                                ? root.multiplier(root.bones, root.found + 1) : 0,
                nextValue: root.nextValue,
                outcome: root.outcome,
                lastWin: root.lastWin,
                //  The board as the player sees it: what is turned, and what
                //  was under it. The bones stay unlisted while the round is
                //  live — a script asking the widget where they are is a
                //  script asking to cheat.
                revealed: root.revealed,
                bonesAt: root.phase === "picking" ? null : root.field
            });
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  WINDOW
    //
    //  A layer surface in the bottom-right corner, slid up into view —
    //  blackjack's block, because widgets that share a corner should arrive
    //  the same way. Everything below `frame` is untouched by it.
    // ═══════════════════════════════════════════════════════════
    //  Whether it should be on screen. Everything that shows or hides the
    //  widget sets this and nothing else; the window follows.
    property bool open: false

    //  Whether the window exists. Trails `open` by the length of the slide,
    //  because a window destroyed the moment it is hidden has nothing left to
    //  animate. The slide itself sets this back to false when it lands.
    property bool showing: false

    onOpenChanged: if (root.open)
        root.showing = true

    readonly property int tableW: 686
    readonly property int tableH: 372

    //  The field: five tiles and four gaps, stated once so the grid and the
    //  panel beside it cannot drift apart.
    readonly property int gridSize: root.theme.tile * 5 + root.theme.gap * 4
    readonly property int panelX:   root.theme.pad + root.gridSize + 24
    readonly property int panelW:   root.tableW - root.panelX - root.theme.pad

    LazyLoader {
        id: loader
        active: root.showing

        PanelWindow {
            id: win
            color: "transparent"
            screen: root.monitor

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "bones"
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
            //  slides up into view. Bind reveal straight to `open` and it
            //  would start at 1 — there is no transition from a value a
            //  property was created holding.
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

                implicitWidth: root.tableW + root.theme.pad * 2
                //  pad · header · table · rack · buttons · pad, with the
                //  Column's spacing between each. Stated rather than derived
                //  so the window does not resize itself a frame after it
                //  opens.
                implicitHeight: root.theme.pad * 2 + 40 + 14 + root.tableH
                                + 14 + 52 + 14 + 42

                Keys.onPressed: (e) => {
                    //  Digits are the chip rack, which only exists to drive
                    //  while betting.
                    if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                        const i = e.key - Qt.Key_1;
                        if (root.phase === "betting" && i < root.chips.length)
                            root.chipIndex = i;
                        e.accepted = true;
                        return;
                    }

                    //  The bones stepper, on both pairs of keys that mean
                    //  up-and-down without a shift held.
                    if (e.key === Qt.Key_Minus || e.key === Qt.Key_BracketLeft) {
                        root.setBones(root.bones - 1);
                        e.accepted = true;
                        return;
                    }
                    if (e.key === Qt.Key_Equal || e.key === Qt.Key_Plus
                        || e.key === Qt.Key_BracketRight) {
                        root.setBones(root.bones + 1);
                        e.accepted = true;
                        return;
                    }

                    //  The aim. Clamped at the edges rather than wrapped — a
                    //  cursor that teleports across the field is a cursor you
                    //  have to find again.
                    if (e.key === Qt.Key_Left || e.key === Qt.Key_Right
                        || e.key === Qt.Key_Up || e.key === Qt.Key_Down) {
                        const row = Math.floor(root.cursor / 5);
                        const col = root.cursor % 5;
                        if (e.key === Qt.Key_Left  && col > 0) root.cursor -= 1;
                        if (e.key === Qt.Key_Right && col < 4) root.cursor += 1;
                        if (e.key === Qt.Key_Up    && row > 0) root.cursor -= 5;
                        if (e.key === Qt.Key_Down  && row < 4) root.cursor += 5;
                        e.accepted = true;
                        return;
                    }

                    switch (e.key) {
                    //  Space starts the round; enter starts it too while
                    //  betting and turns the aimed box once it is live — so
                    //  the whole game plays from the arrows and one thumb.
                    case Qt.Key_Space:
                        if (root.phase === "betting") root.start();
                        else root.pick(root.cursor);
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        if (root.phase === "betting") root.start();
                        else root.pick(root.cursor);
                        break;

                    case Qt.Key_G: root.luckyPick(); break;
                    case Qt.Key_X: root.cash();      break;
                    case Qt.Key_U: root.undo();      break;
                    case Qt.Key_C: root.clearBets(); break;
                    case Qt.Key_R: root.rebet();     break;
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
                                text: "BONES"
                                font.family: root.theme.font
                                font.pixelSize: 15
                                font.bold: true
                                font.letterSpacing: 2
                                color: root.theme.fg
                            }
                            Text {
                                text: "5×5  ·  " + root.bones + " TNT  ·  "
                                      + root.safe + " CHIPS  ·  "
                                      + Math.round(root.rtp * 100) + "% RTP"
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
                                    text: "ON THE FIELD"
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

                    // ═══ the felt ═══
                    Rectangle {
                        width: parent.width
                        height: root.tableH
                        radius: 14
                        color: root.theme.felt
                        border.width: 1
                        border.color: root.theme.feltLine

                        // ── the field ──
                        Grid {
                            x: root.theme.pad
                            y: (root.tableH - root.gridSize) / 2
                            columns: 5
                            spacing: root.theme.gap

                            Repeater {
                                model: root.cells

                                Rectangle {
                                    id: box
                                    required property int index

                                    //  What is under it, once there is a field
                                    //  at all — between rounds both arrays are
                                    //  empty and every box is just a box.
                                    readonly property bool live:
                                        root.field.length === root.cells
                                    //  `=== true` so a lookup past either
                                    //  array's end is false rather than
                                    //  undefined-assigned-to-bool.
                                    readonly property bool bone:
                                        live && root.field[index] === true
                                    //  Turned by the player, or turned by the
                                    //  round ending — the payout flips the
                                    //  whole field so the player sees what
                                    //  they were standing on.
                                    readonly property bool picked:
                                        live && root.revealed[index] === true
                                    readonly property bool shown:
                                        picked || (live && root.phase === "payout")
                                    readonly property bool fatal:
                                        root.bustAt === index
                                    readonly property bool aimed:
                                        root.phase === "picking"
                                        && root.cursor === index

                                    width: root.theme.tile
                                    height: root.theme.tile
                                    radius: root.theme.radius

                                    //  Face down a step above the felt; turned,
                                    //  dropped back into it — except the fatal
                                    //  box, which gets the red it earned.
                                    color: fatal ? Qt.rgba(0.83, 0.16, 0.23, 0.30)
                                         : shown ? root.theme.tileFace
                                         : boxArea.containsMouse
                                           && root.phase === "picking"
                                                 ? Qt.lighter(root.theme.tileBack, 1.25)
                                                 : root.theme.tileBack
                                    border.width: 1
                                    border.color: aimed ? root.theme.gold
                                                : fatal ? root.theme.red
                                                : shown ? root.theme.feltLine
                                                        : Qt.lighter(root.theme.tileBack, 1.4)

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    //  Boxes the player turned themselves keep
                                    //  full strength; the ones the payout
                                    //  turned for them fade back, so the round
                                    //  the player actually played stays
                                    //  legible on the flipped field.
                                    Item {
                                        anchors.fill: parent
                                        opacity: !box.shown ? 0
                                               : box.picked || box.fatal ? 1 : 0.35
                                        scale: box.shown ? 1 : 0.6

                                        Behavior on opacity { NumberAnimation { duration: 160 } }
                                        Behavior on scale {
                                            NumberAnimation {
                                                duration: 180
                                                easing.type: Easing.OutBack
                                            }
                                        }

                                        Prize {
                                            anchors.centerIn: parent
                                            dim: root.theme.tile - 16
                                            visible: box.shown && !box.bone
                                        }

                                        Dynamite {
                                            anchors.centerIn: parent
                                            dim: root.theme.tile - 14
                                            hot: box.fatal
                                            visible: box.shown && box.bone
                                        }
                                    }

                                    MouseArea {
                                        id: boxArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: root.canPick(box.index)
                                                     ? Qt.PointingHandCursor
                                                     : Qt.ArrowCursor
                                        onClicked: root.pick(box.index)
                                    }
                                }
                            }
                        }

                        // ── the panel ──
                        //
                        //  Everything beside the field: the bones stepper and
                        //  the circle while betting, the running price once
                        //  the round is live, and the table's one line of
                        //  commentary at the bottom throughout.
                        Item {
                            x: root.panelX
                            y: (root.tableH - root.gridSize) / 2
                            width: root.panelW
                            height: root.gridSize

                            // ── bones stepper ──
                            Column {
                                id: stepper
                                width: parent.width
                                spacing: 6

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "TNT IN THE FIELD"
                                    font.family: root.theme.font
                                    font.pixelSize: 9
                                    font.letterSpacing: 1.6
                                    color: root.theme.feltLine
                                }

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 14

                                    Btn {
                                        width: 38
                                        implicitHeight: 38
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: "−"
                                        enabled: root.phase === "betting"
                                                 && root.bones > root.minBones
                                        onActivated: root.setBones(root.bones - 1)
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.bones
                                        width: 52
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: root.theme.font
                                        font.pixelSize: 30
                                        font.bold: true
                                        color: root.phase === "betting"
                                               ? root.theme.fg : root.theme.muted
                                    }

                                    Btn {
                                        width: 38
                                        implicitHeight: 38
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: "+"
                                        enabled: root.phase === "betting"
                                                 && root.bones < root.maxBones
                                        onActivated: root.setBones(root.bones + 1)
                                    }
                                }

                                //  What the choice costs and pays, before it
                                //  is committed to: the first box's price is
                                //  the whole risk curve in one number.
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "FIRST CHIP PAYS "
                                          + root.multText(root.multiplier(root.bones, 1))
                                    font.family: root.theme.font
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.2
                                    color: root.theme.muted
                                    visible: root.phase === "betting"
                                }
                            }

                            // ── the circle ──
                            //
                            //  The stake while it is still the player's to
                            //  shape. It leaves with the deal — from then on
                            //  the panel below prices it instead.
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 116
                                width: 138
                                height: 138
                                visible: root.phase === "betting"

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 118
                                    height: 118
                                    radius: 59
                                    color: "transparent"
                                    border.width: 2
                                    border.color: circleArea.containsMouse
                                                  ? root.theme.gold
                                                  : root.theme.feltLine

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
                                }

                                //  Outside the circle rather than inside it,
                                //  so a tall bet spills over the edge the way
                                //  chips do instead of being boxed in by it.
                                ChipStack {
                                    anchors.centerIn: parent
                                    model: root.betStacks()
                                    dim: 28
                                    maxVisible: 4
                                }

                                MouseArea {
                                    id: circleArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (m) => {
                                        if (m.button === Qt.RightButton) root.undo();
                                        else root.placeBet();
                                    }
                                }
                            }

                            // ── the price ──
                            //
                            //  The running total and the next rung of it: what
                            //  taking the money now returns, and what the next
                            //  chip would make of it — the pair that makes
                            //  every pick a decision rather than a reflex.
                            Column {
                                width: parent.width
                                y: 124
                                spacing: 14
                                visible: root.phase !== "betting"

                                Column {
                                    width: parent.width
                                    spacing: 1

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "CHIPS FOUND"
                                        font.family: root.theme.font
                                        font.pixelSize: 9
                                        font.letterSpacing: 1.6
                                        color: root.theme.feltLine
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.found + " / " + root.safe
                                        font.family: root.theme.font
                                        font.pixelSize: 19
                                        font.bold: true
                                        color: root.theme.fg
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: 1
                                    visible: root.found > 0
                                             && root.phase === "picking"

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "TAKE"
                                        font.family: root.theme.font
                                        font.pixelSize: 9
                                        font.letterSpacing: 1.6
                                        color: root.theme.feltLine
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.cashValue + "  "
                                              + root.multText(root.multiplier(root.bones, root.found))
                                        font.family: root.theme.font
                                        font.pixelSize: 17
                                        font.bold: true
                                        color: root.theme.green
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: 1
                                    visible: root.phase === "picking"
                                             && root.found < root.safe

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "NEXT CHIP"
                                        font.family: root.theme.font
                                        font.pixelSize: 9
                                        font.letterSpacing: 1.6
                                        color: root.theme.feltLine
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.nextValue + "  "
                                              + root.multText(root.multiplier(root.bones, root.found + 1))
                                        font.family: root.theme.font
                                        font.pixelSize: 17
                                        font.bold: true
                                        color: root.theme.gold
                                    }
                                }
                            }

                            // ── what the table is saying ──
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: root.message
                                font.family: root.theme.font
                                font.pixelSize: 13
                                font.bold: true
                                font.letterSpacing: 1.6
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
                        }
                    }

                    // ═══ chip rack ═══
                    Row {
                        width: parent.width
                        height: 52
                        spacing: root.theme.gap
                        //  Dead once the stake is out of the circle — there is
                        //  nothing to put down mid-round — but kept in place
                        //  rather than hidden, so the felt above it does not
                        //  jump 52 pixels every time a round starts.
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
                    //  Two rows in one place, swapped by phase: the circle's
                    //  four while betting, the two ways out once the field is
                    //  live.
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
                                label: "PLAY"
                                hint: "space"
                                accent: true
                                enabled: root.wagered > 0
                                onActivated: root.start()
                            }
                        }

                        // ── picking ──
                        Row {
                            width: parent.width
                            spacing: root.theme.gap
                            visible: root.phase !== "betting"

                            readonly property real btnW:
                                (width - root.theme.gap) / 2

                            Btn {
                                width: parent.btnW
                                label: "LUCKY BOX"
                                hint: "g"
                                enabled: root.phase === "picking"
                                onActivated: root.luckyPick()
                            }
                            //  The label carries the figure, so cashing out is
                            //  never a click on a number you had to look up
                            //  somewhere else first.
                            Btn {
                                width: parent.btnW
                                label: root.canCash()
                                       ? "CASH " + root.cashValue : "CASH"
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
