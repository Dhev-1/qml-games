//  roulette.qml — European single-zero roulette, the whole widget in one file.
//
//  run:     qs -p ~/cloon/widgames/rolt/roulette.qml
//
//  keys:    1-4 chip · space spin · u undo · c clear · r rebet · esc close
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
        readonly property color green:     "#3ddc84"
        readonly property color gold:      "#ffcc4d"

        readonly property color felt:      "#17342a"
        readonly property color feltLine:  "#2c5646"
        readonly property color numRed:    "#b3202f"
        readonly property color numBlack:  "#1b1b22"
        readonly property color numGreen:  "#12684a"

        readonly property color wheelRim:  "#3a2a1c"
        readonly property color wheelHub:  "#241a12"
        readonly property color fret:      "#6b5b46"

        readonly property int    pad:      20
        readonly property int    gap:      10
        readonly property int    radius:   10

        //  Two faces, split by job. `display` is for figures only — the winning
        //  number, the bank, the chips, the felt, the wheel. It is the heaviest
        //  sans on the box, which is what these need: the same face has to hold
        //  up at 10px in a wheel pocket and at 46px in the result badge, and it
        //  keeps 1 and 7 apart, which a geometric face does not. `font` is for
        //  every word in the widget.
        readonly property string font:     "Open Sans"
        readonly property string display:  "DejaVu Sans"
    }

    // ═══════════════════════════════════════════════════════════
    //  WHEEL — the real European pocket sequence, clockwise from 0
    // ═══════════════════════════════════════════════════════════
    readonly property var wheelOrder: [
         0, 32, 15, 19,  4, 21,  2, 25, 17, 34,  6, 27, 13, 36, 11, 30,  8, 23,
        10,  5, 24, 16, 33,  1, 20, 14, 31,  9, 22, 18, 29,  7, 28, 12, 35,  3, 26
    ]

    readonly property var reds: [
        1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36
    ]

    readonly property real pocketArc: 360 / 37

    function isRed(n)   { return root.reds.indexOf(n) >= 0; }
    function isBlack(n) { return n !== 0 && root.reds.indexOf(n) < 0; }

    //  Where pocket `n` sits, in degrees clockwise from the 12 o'clock marker,
    //  measured in the wheel's own frame. The ball is over that pocket when its
    //  screen angle equals wheelAngle + pocketAngle(n).
    function pocketAngle(n) { return root.wheelOrder.indexOf(n) * root.pocketArc; }

    // ═══════════════════════════════════════════════════════════
    //  FELT GEOMETRY
    //
    //  Origin (0,0) is the top-left of the zero cell. The number grid starts at
    //  x = zeroW. Cell (r, c) holds 3c + (3 - r), so the top row runs 3, 6, 9 …
    //  and the bottom row 1, 4, 7 … exactly as it does on a real felt.
    // ═══════════════════════════════════════════════════════════
    //  The dozen row is deliberately deep. Street and six-line chips go on the
    //  grid's bottom line, which is also the dozen boxes' top edge, so a shallow
    //  dozen row would hand half its own height to those line bets. 46 keeps
    //  every dozen's centre a clear 23px clear of the line.
    readonly property var geo: ({
        zeroW: 44, cellW: 48, cellH: 44, colW: 48, dozenH: 46, outsideH: 40
    })

    readonly property real feltW: geo.zeroW + 12 * geo.cellW + geo.colW
    readonly property real feltH: 3 * geo.cellH + geo.dozenH + geo.outsideH

    function numberAt(r, c) { return 3 * c + (3 - r); }

    // ═══════════════════════════════════════════════════════════
    //  BET SPOTS
    //
    //  Every bet on the felt, generated as data from the geometry above. The
    //  same records do hit-testing, chip rendering and payout, so those three
    //  cannot drift apart. 157 of them.
    // ═══════════════════════════════════════════════════════════
    function buildSpots(g) {
        const s = [];
        const gx = g.zeroW, gy = 0;
        const W = g.cellW, H = g.cellH;

        function add(kind, nums, pays, x, y) {
            const sorted = nums.slice().sort(function (a, b) { return a - b; });
            s.push({
                id: kind + ":" + sorted.join("-"),
                kind: kind, numbers: sorted, pays: pays, x: x, y: y
            });
        }

        // ── straights ──
        add("straight", [0], 35, gx / 2, 1.5 * H);
        for (let c = 0; c < 12; c++)
            for (let r = 0; r < 3; r++)
                add("straight", [root.numberAt(r, c)], 35,
                    gx + (c + 0.5) * W, gy + (r + 0.5) * H);

        // ── splits: vertical (within a column), horizontal (across columns) ──
        for (let c = 0; c < 12; c++)
            for (let r = 0; r < 2; r++)
                add("split", [root.numberAt(r, c), root.numberAt(r + 1, c)], 17,
                    gx + (c + 0.5) * W, gy + (r + 1) * H);
        for (let r = 0; r < 3; r++)
            for (let c = 0; c < 11; c++)
                add("split", [root.numberAt(r, c), root.numberAt(r, c + 1)], 17,
                    gx + (c + 1) * W, gy + (r + 0.5) * H);
        // ── splits against zero: 0-3, 0-2, 0-1 down the zero cell's edge ──
        for (let r = 0; r < 3; r++)
            add("split", [0, root.numberAt(r, 0)], 17, gx, gy + (r + 0.5) * H);

        // ── streets: the outer line below each column of three ──
        for (let c = 0; c < 12; c++)
            add("street", [3 * c + 1, 3 * c + 2, 3 * c + 3], 11,
                gx + (c + 0.5) * W, gy + 3 * H);

        // ── trios and the first four, on the zero cell's corners ──
        add("trio", [0, 2, 3], 11, gx, gy + H);
        add("trio", [0, 1, 2], 11, gx, gy + 2 * H);
        add("firstfour", [0, 1, 2, 3], 8, gx, gy);

        // ── corners ──
        for (let r = 0; r < 2; r++)
            for (let c = 0; c < 11; c++)
                add("corner", [root.numberAt(r, c),     root.numberAt(r, c + 1),
                               root.numberAt(r + 1, c), root.numberAt(r + 1, c + 1)],
                    8, gx + (c + 1) * W, gy + (r + 1) * H);

        // ── six-lines ──
        for (let c = 0; c < 11; c++) {
            const six = [];
            for (let k = 1; k <= 6; k++) six.push(3 * c + k);
            add("sixline", six, 5, gx + (c + 1) * W, gy + 3 * H);
        }

        // ── columns: the three 2:1 boxes off the right end ──
        for (let r = 0; r < 3; r++) {
            const col = [];
            for (let c = 0; c < 12; c++) col.push(root.numberAt(r, c));
            add("column", col, 2,
                gx + 12 * W + g.colW / 2, gy + (r + 0.5) * H);
        }

        // ── dozens ──
        for (let d = 0; d < 3; d++) {
            const dz = [];
            for (let k = 1; k <= 12; k++) dz.push(12 * d + k);
            add("dozen", dz, 2, gx + (4 * d + 2) * W, 3 * H + g.dozenH / 2);
        }

        // ── outside even-money ──
        const low = [], high = [], even = [], odd = [], red = [], black = [];
        for (let n = 1; n <= 36; n++) {
            (n <= 18 ? low : high).push(n);
            (n % 2 === 0 ? even : odd).push(n);
            (root.isRed(n) ? red : black).push(n);
        }
        const outY = 3 * H + g.dozenH + g.outsideH / 2;
        const outs = [
            { kind: "low",   nums: low },   { kind: "even",  nums: even },
            { kind: "red",   nums: red },   { kind: "black", nums: black },
            { kind: "odd",   nums: odd },   { kind: "high",  nums: high }
        ];
        for (let k = 0; k < 6; k++)
            add(outs[k].kind, outs[k].nums, 1, gx + (2 * k + 1) * W, outY);

        return s;
    }

    //  Total returned for a set of bets against a winning number. A winning bet
    //  hands back stake plus winnings; a losing one hands back nothing, its
    //  stake having already left the bank when the chip went down.
    function resolve(bets, win) {
        let ret = 0;
        for (let i = 0; i < bets.length; i++)
            if (bets[i].numbers.indexOf(win) >= 0)
                ret += bets[i].amount * (bets[i].pays + 1);
        return ret;
    }

    readonly property var spots: buildSpots(geo)

    function spotById(id) {
        for (let i = 0; i < root.spots.length; i++)
            if (root.spots[i].id === id) return root.spots[i];
        return null;
    }

    //  Nearest spot to a point on the felt, or null past the snap radius. One
    //  distance sweep over 157 records — cheaper than edge hit-testing, and it
    //  removes the whole "which line did I actually click" class of bug.
    readonly property real snapRadius: 30
    function spotAt(x, y) {
        let best = null, bestD = root.snapRadius * root.snapRadius;
        for (let i = 0; i < root.spots.length; i++) {
            const s = root.spots[i];
            const dx = s.x - x, dy = s.y - y;
            const d = dx * dx + dy * dy;
            if (d < bestD) { bestD = d; best = s; }
        }
        return best;
    }

    // ═══════════════════════════════════════════════════════════
    //  FELT CELLS — what you actually see. Purely visual; the spots above are
    //  the logical bets, and both come off the same geometry.
    // ═══════════════════════════════════════════════════════════
    function buildCells(g) {
        const cells = [];
        const gx = g.zeroW, W = g.cellW, H = g.cellH;

        cells.push({ n: 0, label: "0", id: "straight:0",
                     x: 0, y: 0, w: g.zeroW, h: 3 * H, tone: "green" });

        for (let c = 0; c < 12; c++)
            for (let r = 0; r < 3; r++) {
                const n = root.numberAt(r, c);
                cells.push({ n: n, label: String(n), id: "straight:" + n,
                             x: gx + c * W, y: r * H, w: W, h: H,
                             tone: root.isRed(n) ? "red" : "black" });
            }

        for (let r = 0; r < 3; r++)
            cells.push({ n: -1, label: "2:1", id: root.spots ? "" : "",
                         x: gx + 12 * W, y: r * H, w: g.colW, h: H,
                         tone: "plain", col: r });

        const dozLabel = ["1st 12", "2nd 12", "3rd 12"];
        for (let d = 0; d < 3; d++)
            cells.push({ n: -1, label: dozLabel[d], x: gx + 4 * d * W,
                         y: 3 * H, w: 4 * W, h: g.dozenH, tone: "plain",
                         doz: d });

        const outLabel = ["1-18", "EVEN", "RED", "BLACK", "ODD", "19-36"];
        const outKind  = ["low", "even", "red", "black", "odd", "high"];
        for (let k = 0; k < 6; k++)
            cells.push({ n: -1, label: outLabel[k], x: gx + 2 * k * W,
                         y: 3 * H + g.dozenH, w: 2 * W, h: g.outsideH,
                         tone: outKind[k] === "red" ? "red"
                             : outKind[k] === "black" ? "black" : "plain",
                         out: outKind[k] });
        return cells;
    }

    readonly property var cells: buildCells(geo)

    //  The bet id a non-number cell stands for, so clicking its label and
    //  hovering its spot light up the same thing.
    function cellBetId(cell) {
        if (cell.n >= 0) return "straight:" + cell.n;
        if (cell.col !== undefined) {
            const col = [];
            for (let c = 0; c < 12; c++) col.push(root.numberAt(cell.col, c));
            return "column:" + col.sort(function (a, b) { return a - b; }).join("-");
        }
        if (cell.doz !== undefined) {
            const dz = [];
            for (let k = 1; k <= 12; k++) dz.push(12 * cell.doz + k);
            return "dozen:" + dz.join("-");
        }
        if (cell.out !== undefined) {
            for (let i = 0; i < root.spots.length; i++)
                if (root.spots[i].kind === cell.out) return root.spots[i].id;
        }
        return "";
    }

    // ═══════════════════════════════════════════════════════════
    //  GAME STATE
    // ═══════════════════════════════════════════════════════════
    //  Same three palettes as bjak, in the same order, so a 25 is the same green
    //  clay in both games. `chipSpot` is the colour of the edge spots and the
    //  ring — white on everything except the white chip, which takes navy,
    //  because white spots on a white chip are no spots.
    readonly property var chips: [1, 5, 25, 100]
    readonly property var chipColor: ["#e8e8ee", "#d3283a", "#2f9e5a", "#22222c"]
    readonly property var chipSpot:  ["#2b3a63", "#ffffff", "#ffffff", "#ffffff"]
    readonly property var chipInk:   ["#16161e", "#ffffff", "#ffffff", "#ffffff"]

    //  Which chip a disc is drawn as: the largest denomination it covers, so a
    //  stack of 30 wears the 25's green.
    function chipTier(amount) {
        let k = 0;
        for (let i = 0; i < root.chips.length; i++)
            if (amount >= root.chips[i]) k = i;
        return k;
    }

    property int  credits:   200
    property int  chipIndex: 1

    //  How many times the bank has been emptied and refilled. A lifetime tally,
    //  not a per-session one — it rides in the state file next to the bank,
    //  which is the whole point of it.
    property int  losses:    0

    //  ── the bank on disk ───────────────────────────────────────
    //  Closing quits the process, so without this the bank would reset to 200
    //  every time the window went away. One small JSON file under
    //  `~/.local/state/quickshell/by-shell/<id>/`, holding the only thing worth
    //  carrying between sittings.
    //
    //  `statePath` hashes the *canonical* config path, so it resolves to the
    //  same file whether this is launched as `rolt/roulette.qml` or as
    //  `edge/../widgames/rolt/roulette.qml` the way the poker tab launches
    //  poker. Verified, because a bank that silently forked per launch spelling
    //  would look exactly like a bank that doesn't persist at all.
    FileView {
        id: bankFile

        path: Quickshell.statePath("bank.json")

        //  Read before the first frame — a bank that arrives a frame late shows
        //  200 and then flickers to the real figure.
        blockLoading: true

        //  And written synchronously. The file is thirty bytes, so the cost is
        //  nothing, and it buys two things: chips placed in quick succession
        //  cannot leave writes racing each other, and the last write is on disk
        //  before `Qt.quit()` returns — which matters when closing *is* quitting.
        blockWrites: true
        atomicWrites: true

        //  A missing file is the first run, not a fault: say nothing, write the
        //  defaults, carry on. Anything else is a real error and should be loud.
        printErrors: false
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) bankFile.writeAdapter();
            else console.warn("rolt: could not read bank:", error);
        }

        JsonAdapter {
            id: bank
            property int credits: 200
            property int losses:  0
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
        //  Touching `text()` performs the blocking read, so the line below sees
        //  the file. Caught by relaunching after a loss, not by the tests.
        bankFile.text();
        root.credits = bank.credits;
        root.losses  = bank.losses;
        root.topUp();

        //  Normalise on the way in. An unreadable file falls back to 200 above
        //  but stays unreadable on disk until something happens to move the
        //  bank; writing here means the file is valid JSON from launch onward.
        bankFile.writeAdapter();
    }
    onCreditsChanged: {
        bank.credits = root.credits;
        bankFile.writeAdapter();
    }
    onLossesChanged: {
        bank.losses = root.losses;
        bankFile.writeAdapter();
    }

    //  The smallest chip is 1, so an empty bank is not a low score — it is a
    //  widget that cannot be played and has no way back. That was survivable
    //  while the bank died with the process; now that it persists, busting would
    //  be permanent. So a bank with nothing in it refills.
    //
    //  Only called where the felt is already clear — startup and the end of a
    //  round — so it can never top up mid-round and pay out on a stake the
    //  player didn't have.
    function topUp(): bool {
        if (root.credits > 0) return false;
        root.credits = 200;
        root.losses += 1;
        root.message = "BANK EMPTY — BACK TO 200";
        return true;
    }

    //  Deliberate reset, for when the bank has drifted somewhere uninteresting.
    function resetBank(): void {
        root.credits = 200;
        root.message = "BANK RESET";
    }

    //  The meter reads this rather than `credits` directly, so a payout counts
    //  up instead of snapping to the new total.
    property real creditsShown: credits
    Behavior on creditsShown {
        NumberAnimation { duration: 520; easing.type: Easing.OutCubic }
    }
    property int  lastWin:   0
    property int  winNumber: -1

    //  What the badge reads. Separate from `winNumber` because that is drawn
    //  before the wheel starts moving — bind the badge to it and the answer sits
    //  on screen for the whole spin.
    property int  shownNumber: -1
    property string phase:   "betting"    // betting · spinning · payout
    property string message: "PLACE YOUR BETS"
    property var history:    []

    //  Every chip on the felt, in the order it was placed. The single source of
    //  truth for what is down: the map below is derived, undo is a pop, and
    //  right-clicking a spot lifts the most recent chip on it.
    property var betOrder:  []
    property var lastOrder: []

    readonly property var betMap: {
        const m = {};
        for (let i = 0; i < root.betOrder.length; i++) {
            const b = root.betOrder[i];
            m[b.id] = (m[b.id] || 0) + b.amount;
        }
        return m;
    }

    readonly property int wagered: {
        let t = 0;
        for (let i = 0; i < root.betOrder.length; i++) t += root.betOrder[i].amount;
        return t;
    }

    // ── betting actions ────────────────────────────────────────
    //  Everything that puts money on the felt goes through here, so the bank and
    //  the chip list can never disagree about what is down.
    function wager(spot, amount) {
        if (root.phase !== "betting" || !spot || amount <= 0) return false;
        if (root.credits < amount) { root.message = "NOT ENOUGH CREDITS"; return false; }
        root.credits -= amount;
        root.betOrder = root.betOrder.concat([{ id: spot.id, amount: amount }]);
        return true;
    }

    function placeBet(spot) {
        if (root.wager(spot, root.chips[root.chipIndex]))
            root.message = "PLACE YOUR BETS";
    }

    function liftBet(spot) {
        if (root.phase !== "betting" || !spot) return;
        for (let i = root.betOrder.length - 1; i >= 0; i--)
            if (root.betOrder[i].id === spot.id) {
                root.credits += root.betOrder[i].amount;
                const next = root.betOrder.slice();
                next.splice(i, 1);
                root.betOrder = next;
                return;
            }
    }

    function undo() {
        if (root.phase !== "betting" || root.betOrder.length === 0) return;
        const next = root.betOrder.slice();
        root.credits += next.pop().amount;
        root.betOrder = next;
    }

    function clearBets() {
        if (root.phase !== "betting") return;
        root.credits += root.wagered;
        root.betOrder = [];
    }

    function rebet() {
        if (root.phase !== "betting" || root.lastOrder.length === 0) return;
        let need = 0;
        for (let i = 0; i < root.lastOrder.length; i++) need += root.lastOrder[i].amount;
        if (root.credits < need) { root.message = "NOT ENOUGH CREDITS"; return; }
        root.credits += root.wagered;
        root.credits -= need;
        root.betOrder = root.lastOrder.slice();
    }

    function cycleChip() { root.chipIndex = (root.chipIndex + 1) % root.chips.length; }

    //  The bets as resolve() wants them: stake joined to the spot it sits on.
    function activeBets() {
        const out = [];
        for (const id in root.betMap) {
            const s = root.spotById(id);
            if (s) out.push({ numbers: s.numbers, pays: s.pays, amount: root.betMap[id] });
        }
        return out;
    }

    // ═══════════════════════════════════════════════════════════
    //  SPIN
    //
    //  The winning number is drawn up front and the motion solved to arrive
    //  there — the only way the ball is guaranteed to land on the pocket the
    //  RNG actually chose. A scripted spin with physical feel, not a sim.
    // ═══════════════════════════════════════════════════════════
    readonly property real kWheel:  0.22     // friction, per second
    readonly property real kBall:   0.26
    readonly property real tWheel:      3.0      // wheel settle, seconds
    readonly property real tBall:      2.35     // ball settle — seats first, then
                                              // rides the wheel's last coast
    readonly property real minFree: 2.0
    readonly property real maxFree: 2.7

    //  Both are absolute pixels in a 288px wheel, so they track the pocket band
    //  in the Wheel component: the ball flies just inside the rim and seats at
    //  the middle of a pocket. Move one without the other and the ball rides
    //  over the hub or off the edge.
    readonly property real trackR:  134      // ball on the outer track
    readonly property real pocketR: 112      // ball seated in a pocket

    readonly property real scatAmp:  16      // scatter, degrees
    readonly property real scatFrom: 0.62    // when it starts, as a fraction
    readonly property real scatHops: 2.5

    property real wheelAngle: 0
    property real ballAngle:  0
    property real ballRadius: 118
    property real wheelVel:   0
    property real ballVel:    0

    property string stage:   "rest"           // rest · free · settle
    property real   freeT:   0
    property real   settleT: 0
    property real   w0:      0
    property real   b0:      0
    property real   rangeW:  0
    property real   rangeB:  0
    property real   prevErr: 0
    property bool   hasPrev: false

    function norm180(d) { return ((d + 180) % 360 + 360) % 360 - 180; }

    function spin() {
        if (root.phase !== "betting") return;
        if (root.wagered === 0) { root.message = "PLACE A BET FIRST"; return; }

        root.winNumber = Math.floor(Math.random() * 37);
        root.phase = "spinning";
        //  Nothing on the message line while the wheel is turning — the wheel
        //  is already saying it, and a caption repeating the obvious is the
        //  first thing you stop reading.
        root.message = "";
        root.lastWin = 0;
        root.shownNumber = -1;

        root.wheelAngle = ((root.wheelAngle % 360) + 360) % 360;
        root.ballAngle  = ((root.ballAngle  % 360) + 360) % 360;
        root.wheelVel   = 290 + Math.random() * 70;
        root.ballVel    = -(1180 + Math.random() * 160);
        root.ballRadius = root.trackR;

        root.freeT = 0;
        root.hasPrev = false;
        root.stage = "free";
        spinner.running = true;
    }

    //  Free spin: both bodies under exponential friction, nothing committed.
    //  Each frame past minFree we ask what a velocity-matched settle would do
    //  and how far it would miss by; when that error crosses zero, the settle
    //  we are about to start is already the right one and the residual snap is
    //  under a frame's worth of travel.
    function stepFree(dt) {
        root.wheelVel *= Math.exp(-root.kWheel * dt);
        root.ballVel  *= Math.exp(-root.kBall * dt);
        root.wheelAngle += root.wheelVel * dt;
        root.ballAngle  += root.ballVel * dt;
        root.freeT += dt;
        if (root.freeT < root.minFree) return;

        //  OutCubic is 1-(1-t)³, whose slope at t=0 is 3 — so a curve of range R
        //  over T leaves at 3R/T. Taking range = v·T/3 hands the settle exactly
        //  the speed the body already has, and the handoff has no kink in it.
        const rw = root.wheelVel * root.tWheel / 3;
        const tb = root.tBall / root.tWheel;
        const wAtTb = root.wheelAngle + rw * (1 - Math.pow(1 - tb, 3));
        const target = wAtTb + root.pocketAngle(root.winNumber);
        const rb = root.ballVel * root.tBall / 3;
        const err = root.norm180(root.ballAngle + rb - target);

        const crossed = root.hasPrev
            && Math.abs(err) + Math.abs(root.prevErr) < 180
            && ((err <= 0 && root.prevErr > 0) || (err >= 0 && root.prevErr < 0));

        if (crossed || root.freeT > root.maxFree) {
            root.w0 = root.wheelAngle;
            root.b0 = root.ballAngle;
            root.rangeW = rw;
            root.rangeB = rb - err;      // lands on target exactly
            root.settleT = 0;
            root.stage = "settle";
            return;
        }
        root.prevErr = err;
        root.hasPrev = true;
    }

    //  Additive on top of the solved curve, and zero at both ends — which is
    //  what lets the ball look chaotic without ever threatening the landing.
    function scatter(t) {
        if (t < root.scatFrom) return 0;
        const u = (t - root.scatFrom) / (1 - root.scatFrom);
        return root.scatAmp * Math.pow(1 - u, 2)
             * Math.sin(u * Math.PI * 2 * root.scatHops);
    }

    function ballR(t) {
        if (t < 0.5) return root.trackR;
        const u = (t - 0.5) / 0.5;
        return root.trackR + (root.pocketR - root.trackR)
             * (1 - Math.pow(1 - u, 2));
    }

    function stepSettle(dt) {
        root.settleT += dt;
        const tw = Math.min(root.settleT / root.tWheel, 1);
        root.wheelAngle = root.w0 + root.rangeW * (1 - Math.pow(1 - tw, 3));

        if (root.settleT < root.tBall) {
            const t = root.settleT / root.tBall;
            root.ballAngle = root.b0 + root.rangeB * (1 - Math.pow(1 - t, 3))
                           + root.scatter(t);
            root.ballRadius = root.ballR(t);
        } else {
            // seated: rides the wheel through its last coast, and cannot drift
            root.ballAngle = root.wheelAngle + root.pocketAngle(root.winNumber);
            root.ballRadius = root.pocketR;
        }

        if (tw >= 1) {
            spinner.running = false;
            root.stage = "rest";
            root.wheelAngle = root.w0 + root.rangeW;
            root.ballAngle = root.wheelAngle + root.pocketAngle(root.winNumber);
            root.land();
        }
    }

    function land() {
        const ret = root.resolve(root.activeBets(), root.winNumber);
        root.shownNumber = root.winNumber;
        root.lastWin = ret;
        root.credits += ret;
        root.history = [root.winNumber].concat(root.history).slice(0, 12);
        root.phase = "payout";
        root.message = ret > 0 ? "WIN  " + ret : "NO WIN";
        payoutTimer.restart();
    }

    FrameAnimation {
        id: spinner
        running: false
        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            if (root.stage === "free") root.stepFree(dt);
            else if (root.stage === "settle") root.stepSettle(dt);
        }
    }

    Timer {
        id: payoutTimer
        interval: 2400
        onTriggered: {
            root.lastOrder = root.betOrder.slice();
            root.betOrder = [];
            root.phase = "betting";
            //  topUp() writes its own message when it fires, so don't stomp it.
            if (!root.topUp()) root.message = "PLACE YOUR BETS";
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  WHEEL COMPONENT
    // ═══════════════════════════════════════════════════════════
    component Wheel: Item {
        id: wh
        property real dim: 288
        implicitWidth: dim
        implicitHeight: dim

        //  Proportioned off a real wheel diagram: a thin outer edge, a wide
        //  band of pockets, and a hollow centre a bit over half the outer
        //  radius. What this replaces spent 30 of its 144px on rim and ball
        //  track, leaving the colour band a 36px strip; it is 67px now.
        readonly property real rOuter: dim / 2
        readonly property real rPocketOut: dim / 2 - 4
        readonly property real rPocketIn:  rPocketOut * 0.60
        //  Centred in the band, so the clearance to the inner and outer frets
        //  is equal.
        readonly property real rLabel:     (rPocketOut + rPocketIn) / 2

        // ── rim ──
        //  A hairline. No rim disc and no separate ball track any more — the
        //  ball rides the outer end of the pockets, which is where it ends up
        //  on a real wheel once it has dropped off the track anyway.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: root.theme.raised
        }
        // ── the wheel proper: painted once, spun by the scene graph ──
        Item {
            id: turning
            anchors.fill: parent
            rotation: root.wheelAngle

            Canvas {
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const cx = width / 2, cy = height / 2;
                    const step = 2 * Math.PI / 37;

                    for (let i = 0; i < 37; i++) {
                        const n = root.wheelOrder[i];
                        const a0 = i * step - step / 2 - Math.PI / 2;
                        const a1 = a0 + step;
                        ctx.beginPath();
                        ctx.arc(cx, cy, wh.rPocketOut, a0, a1, false);
                        ctx.arc(cx, cy, wh.rPocketIn, a1, a0, true);
                        ctx.closePath();
                        ctx.fillStyle = n === 0 ? root.theme.numGreen
                                      : root.isRed(n) ? root.theme.numRed
                                                      : root.theme.numBlack;
                        ctx.fill();
                        ctx.strokeStyle = root.theme.fret;
                        ctx.lineWidth = 1;
                        ctx.stroke();
                    }

                    // hub
                    ctx.beginPath();
                    ctx.arc(cx, cy, wh.rPocketIn, 0, Math.PI * 2);
                    //  Hollow, like the reference — the panel showing through
                    //  rather than a disc of woodgrain. Only the fret ring
                    //  marks where the pockets stop. The turret that used to
                    //  sit in the middle is gone with it.
                    ctx.fillStyle = root.theme.bg;
                    ctx.fill();
                    ctx.strokeStyle = root.theme.fret;
                    ctx.lineWidth = 2;
                    ctx.stroke();
                }
                Component.onCompleted: requestPaint()
            }

            Repeater {
                model: 37
                Text {
                    required property int index
                    readonly property real a:
                        (index * root.pocketArc - 90) * Math.PI / 180

                    x: turning.width / 2 + Math.cos(a) * wh.rLabel - width / 2
                    y: turning.height / 2 + Math.sin(a) * wh.rLabel - height / 2
                    rotation: index * root.pocketArc
                    text: root.wheelOrder[index]
                    font.family: root.theme.display
                    font.pixelSize: 10
                    font.bold: true
                    color: root.theme.fg
                }
            }
        }

        // ── result, in the hollow centre ──
        //  Outside `turning`, so it stays upright while the wheel spins. The
        //  disc is comfortably inside rPocketIn, so it never touches a pocket
        //  or the ball, which flies well outside it.
        Rectangle {
            anchors.centerIn: parent
            width: wh.rPocketIn * 1.5
            height: width
            radius: width / 2

            color: root.shownNumber < 0 ? "transparent"
                 : root.shownNumber === 0 ? root.theme.numGreen
                 : root.isRed(root.shownNumber) ? root.theme.numRed
                                                : root.theme.numBlack
            border.width: root.shownNumber < 0 ? 0 : 2
            border.color: root.theme.raised

            Behavior on color { ColorAnimation { duration: 200 } }

            Text {
                anchors.centerIn: parent
                text: root.shownNumber < 0 ? "—" : root.shownNumber
                font.family: root.theme.display
                font.pixelSize: 52
                font.bold: true
                color: root.shownNumber < 0 ? root.theme.inactive
                                            : root.theme.fg
            }

            SequentialAnimation on opacity {
                running: root.phase === "payout"
                loops: 4
                NumberAnimation { to: 0.55; duration: 220 }
                NumberAnimation { to: 1.0;  duration: 220 }
            }
        }

        // ── ball ──
        Rectangle {
            width: 11
            height: 11
            radius: 5.5
            color: "#f4f4f8"
            border.width: 1
            border.color: "#b8b8c4"
            x: wh.width / 2
                + Math.cos((root.ballAngle - 90) * Math.PI / 180) * root.ballRadius
                - width / 2
            y: wh.height / 2
                + Math.sin((root.ballAngle - 90) * Math.PI / 180) * root.ballRadius
                - height / 2
        }

        // ── marker ──
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -3
            width: 3
            height: 14
            radius: 1.5
            color: root.theme.gold
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  CHIP
    //
    //  Ported from bjak/blackjack.qml so both games hand you the same object: a
    //  coloured clay body, eight spots cut into the rim, the ring those spots
    //  stop at, a dark edge, and the denomination in the middle. Drawn rather
    //  than drawn-on — every measurement is a fraction of the radius, so the
    //  26px disc on the felt and the 52px one in the rack are one drawing at
    //  two sizes, not a scaled bitmap.
    // ═══════════════════════════════════════════════════════════
    component Chip: Item {
        id: chip
        property int   amount: 0
        property real  dim: 26
        //  Set to pick a chip out. It replaces the dark edge instead of adding
        //  a ring outside it, so a highlighted chip occupies exactly the room an
        //  ordinary one does and nothing shifts when the selection moves.
        property color highlight: "transparent"

        readonly property int   tier: root.chipTier(amount)
        readonly property color body: root.chipColor[tier]
        readonly property color spot: root.chipSpot[tier]
        readonly property bool  lit:  chip.highlight.a > 0

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

                //  A fine line reads as picked out; a heavy one reads as a
                //  different chip, so the highlight goes on thinner than the
                //  dark edge it replaces.
                ctx.beginPath();
                ctx.arc(cx, cy, rim, 0, 2 * Math.PI);
                ctx.strokeStyle = chip.lit ? chip.highlight
                                           : Qt.rgba(0, 0, 0, 0.55);
                ctx.lineWidth = chip.lit ? Math.max(1, edge * 0.6) : edge;
                ctx.stroke();
            }
        }

        //  Canvas repaints on resize but not on a colour change, and the tier
        //  moves under a growing stack.
        onTierChanged:      clay.requestPaint()
        onHighlightChanged: clay.requestPaint()

        Text {
            anchors.centerIn: parent
            text: chip.amount
            font.family: root.theme.display
            //  Sized to the face inside the ring, not to the whole chip, so
            //  "100" stays within the ring instead of running under the spots.
            font.pixelSize: chip.amount > 99 ? chip.dim * 0.33 : chip.dim * 0.42
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
    //  Closing quits the process rather than hiding the window. A hidden
    //  instance is a whole QML engine and a painted wheel resident in memory
    //  doing nothing, and there is no state here worth keeping alive for it —
    //  the bank lives in memory and starts at 200 either way. So the widget
    //  exists for exactly as long as it is on screen, and whatever opens it
    //  starts it fresh. The other ways out are in the WINDOW block.
    // ═══════════════════════════════════════════════════════════
    function quit(): void { Qt.quit(); }

    IpcHandler {
        target: "roulette"

        //  If a call reaches us at all then the widget is running, and running
        //  now means on screen — so toggle and hide are the same door out, and
        //  show is already true by the time anything could ask for it.
        function toggle(): void { root.quit(); }
        function show():   void {}
        function hide():   void { root.quit(); }

        function spin():   void { root.spin(); }
        function clear():  void { root.clearBets(); }
        function rebet():  void { root.rebet(); }
        function undo():   void { root.undo(); }
        function reset():  void { root.resetBank(); }

        //  Spot ids are the ones `status` reports: "straight:17", "corner:8-9-11-12",
        //  "red:1-3-5-…". Places the stake regardless of the selected chip.
        function bet(spot: string, amount: int): void {
            root.wager(root.spotById(spot), amount);
        }
        function chip(n: int): void {
            const i = root.chips.indexOf(n);
            if (i >= 0) root.chipIndex = i;
        }

        function status(): string {
            const bets = [];
            for (const id in root.betMap)
                bets.push({ spot: id, amount: root.betMap[id] });
            return JSON.stringify({
                //  Constant, but kept in the payload: a caller reads it to
                //  decide whether to start the widget or close it, and gets the
                //  right answer either way — this reply means running, and no
                //  reply at all means not.
                visible: true,
                credits: root.credits,
                losses: root.losses,
                wagered: root.wagered,
                chip: root.chips[root.chipIndex],
                phase: root.phase,
                lastNumber: root.winNumber,
                lastWin: root.lastWin,
                history: root.history,
                bets: bets
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
    FloatingWindow {
        id: win
        visible: true
        color: root.theme.bg
        title: "roulette"

        //  The compositor's close, and anything else that pulls the window
        //  down, takes the process with it. Qt's default is to leave `visible`
        //  false with the engine still resident, which is the thing being
        //  avoided.
        onVisibleChanged: if (!visible) root.quit()

        //  Fixed layout — the felt is a fixed pixel size, so letting the window
        //  stretch only adds dead space beside it.
        minimumSize: Qt.size(implicitWidth, implicitHeight)
        maximumSize: Qt.size(implicitWidth, implicitHeight)

        implicitWidth: root.feltW + root.theme.pad * 2
        //  pad · wheel · felt · rack · buttons · pad, with the Column's spacing
        //  between each. Stated rather than derived so the window does not
        //  resize itself a frame after it opens.
        implicitHeight: root.theme.pad * 2 + 288 + 14 + root.feltH
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
                case Qt.Key_Enter: root.spin(); break;
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

                // ═══ top: wheel + readouts ═══
                Row {
                    width: parent.width
                    spacing: 16

                    Wheel { dim: 288 }

                    //  Centred against the wheel rather than top-aligned. With
                    //  the result badge gone this column is a good deal shorter
                    //  than the 288px wheel beside it, and hanging it from the
                    //  top just puts all the slack in one lump at the bottom.
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 288 - 16
                        spacing: 14

                        Item {
                            width: parent.width
                            height: 26
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "ROULETTE"
                                font.family: root.theme.font
                                font.pixelSize: 15
                                font.bold: true
                                font.letterSpacing: 2
                                color: root.theme.fg
                            }

                            //  Times the bank has been emptied. Sits in the
                            //  header rather than beside WAGERED and WIN
                            //  because those two reset every round and this
                            //  one never does — and it is the one number here
                            //  that outlives the window.
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "REBUYS"
                                    font.family: root.theme.font
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.5
                                    color: root.theme.muted
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.losses
                                    font.family: root.theme.display
                                    font.pixelSize: 15
                                    font.bold: true
                                    color: root.losses > 0 ? root.theme.numRed
                                                           : root.theme.inactive
                                }
                            }
                        }

                        // ── bank ──
                        //  Above the number rather than down in the meters: it
                        //  is the figure you actually watch, and the one that
                        //  decides whether the next bet is even possible.
                        Rectangle {
                            width: parent.width
                            height: 48
                            radius: 8
                            color: root.theme.surface
                            border.width: 1
                            border.color: root.theme.raised

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: "CREDITS"
                                font.family: root.theme.font
                                font.pixelSize: 10
                                font.letterSpacing: 1.5
                                color: root.theme.muted
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(root.creditsShown)
                                font.family: root.theme.display
                                font.pixelSize: 22
                                font.bold: true
                                color: root.theme.green
                            }
                        }

                        //  The result used to be a badge here. It lives in the
                        //  wheel's hollow centre now — see the Wheel component.

                        // ── message ──
                        Rectangle {
                            width: parent.width
                            height: 34
                            radius: 6
                            color: root.theme.surface
                            Text {
                                anchors.centerIn: parent
                                text: root.message
                                font.family: root.theme.font
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 1.2
                                color: root.lastWin > 0 ? root.theme.gold
                                     : root.phase === "spinning" ? root.theme.blue
                                                                 : root.theme.muted
                            }
                        }

                        // ── meters ──
                        Row {
                            width: parent.width
                            spacing: root.theme.gap
                            Repeater {
                                //  CREDITS lives in its own bar above the
                                //  number now, so this is the pair that only
                                //  matter while a round is in play.
                                //  One tint across both. Green stays the bank's
                                //  alone and gold stays the win message's, so
                                //  colour in this widget means something rather
                                //  than just decorating each tile differently.
                                model: [
                                    { label: "WAGERED", value: root.wagered,
                                      tint: root.theme.blue },
                                    { label: "WIN",     value: root.lastWin,
                                      tint: root.theme.blue }
                                ]
                                Rectangle {
                                    required property var modelData
                                    width: (frame.width - root.theme.pad * 2
                                            - 288 - 16 - root.theme.gap) / 2
                                    height: 50
                                    radius: 8
                                    color: root.theme.surface
                                    border.width: 1
                                    border.color: root.theme.raised
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 0
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.label
                                            font.family: root.theme.font
                                            font.pixelSize: 9
                                            font.letterSpacing: 1.5
                                            color: root.theme.muted
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.value
                                            font.family: root.theme.display
                                            font.pixelSize: 18
                                            font.bold: true
                                            color: modelData.tint
                                        }
                                    }
                                }
                            }
                        }

                        // ── history ──
                        Row {
                            spacing: 5
                            Repeater {
                                model: root.history
                                Rectangle {
                                    required property var modelData
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: modelData === 0 ? root.theme.numGreen
                                         : root.isRed(modelData) ? root.theme.numRed
                                                                 : root.theme.numBlack
                                    border.width: 1
                                    border.color: root.theme.raised
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: root.theme.display
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: root.theme.fg
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══ felt ═══
                Rectangle {
                    id: felt
                    width: root.feltW
                    height: root.feltH
                    radius: 8
                    color: root.theme.felt
                    border.width: 1
                    border.color: root.theme.feltLine
                    clip: false

                    property var hover: null

                    // ── cells ──
                    Repeater {
                        model: root.cells
                        Rectangle {
                            required property var modelData
                            readonly property string betId: root.cellBetId(modelData)
                            readonly property bool lit:
                                felt.hover !== null
                                && (modelData.n >= 0
                                    ? felt.hover.numbers.indexOf(modelData.n) >= 0
                                    : felt.hover.id === betId)
                            readonly property bool won:
                                root.phase === "payout" && modelData.n >= 0
                                && modelData.n === root.winNumber

                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: 5
                            color: modelData.tone === "red"   ? root.theme.numRed
                                 : modelData.tone === "black" ? root.theme.numBlack
                                 : modelData.tone === "green" ? root.theme.numGreen
                                                              : "transparent"
                            border.width: 1
                            border.color: root.theme.feltLine

                            //  n >= 0 is a numbered cell, n < 0 an outside bet
                            //  whose label is a word ("EVEN", "1st 12") — so the
                            //  same test picks both the size and the face.
                            //
                            //  The zero used to be turned on its side to fit a
                            //  tall thin cell. It reads as a mistake rather than
                            //  as a design, and "0" is narrow enough to sit
                            //  upright in 44px regardless.
                            //  A chip on an outside bet lands on a word, and a
                            //  chip over "1st 12" or "BLACK" reads as neither.
                            //  The chip already says what is staked and where,
                            //  so the label steps aside while it is there and
                            //  comes back when the felt clears. Numbered cells
                            //  keep theirs: a chip on a number covers a digit or
                            //  two, which is legible, and losing the number
                            //  would cost you the grid.
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                visible: modelData.n >= 0
                                         || !(root.betMap[root.cellBetId(modelData)] > 0)
                                font.family: modelData.n >= 0 ? root.theme.display
                                                              : root.theme.font
                                font.pixelSize: modelData.n >= 0 ? 13 : 11
                                font.bold: true
                                color: root.theme.fg
                            }

                            // hover wash
                            Rectangle {
                                anchors.fill: parent
                                color: root.theme.fg
                                opacity: parent.lit ? 0.22 : 0
                                Behavior on opacity { NumberAnimation { duration: 90 } }
                            }

                            // winning cell
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.width: 2
                                border.color: root.theme.gold
                                visible: parent.won
                                SequentialAnimation on opacity {
                                    running: parent.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.25; duration: 260 }
                                    NumberAnimation { to: 1.0;  duration: 260 }
                                }
                            }
                        }
                    }

                    // ── chips ──
                    Repeater {
                        model: root.spots
                        Item {
                            id: chip
                            required property var modelData

                            readonly property int amount: root.betMap[modelData.id] || 0
                            readonly property bool winner:
                                root.phase === "payout"
                                && modelData.numbers.indexOf(root.winNumber) >= 0
                            //  A chip is only a loser once the ball has landed —
                            //  during the spin every chip is still live.
                            readonly property bool loser:
                                root.phase === "payout" && !winner
                            visible: amount > 0
                            x: modelData.x - 13
                            y: modelData.y - 13
                            width: 26
                            height: 26

                            opacity: loser ? 0.22 : 1
                            Behavior on opacity { NumberAnimation { duration: 420 } }

                            Chip {
                                dim: 26
                                amount: chip.amount
                                highlight: chip.winner ? root.theme.gold
                                                       : "transparent"
                            }

                            SequentialAnimation on scale {
                                running: chip.winner
                                loops: 5
                                NumberAnimation { to: 1.18; duration: 200 }
                                NumberAnimation { to: 1.0;  duration: 200 }
                            }
                        }
                    }

                    // ── one hit area for the whole felt ──
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: felt.hover !== null && root.phase === "betting"
                                     ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPositionChanged: (m) => felt.hover = root.spotAt(m.x, m.y)
                        onExited: felt.hover = null
                        onClicked: (m) => {
                            const s = root.spotAt(m.x, m.y);
                            if (m.button === Qt.RightButton) root.liftBet(s);
                            else root.placeBet(s);
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
                        Item {
                            id: slot
                            required property int index
                            readonly property bool sel: root.chipIndex === index

                            width: 52
                            height: 52
                            scale: sel ? 1.0 : 0.88
                            Behavior on scale { NumberAnimation { duration: 110 } }

                            Chip {
                                dim: 52
                                amount: root.chips[slot.index]
                                //  White, as in bjak. Gold is the winning
                                //  chip's on the felt, and one colour should
                                //  not mean both "selected" and "paid".
                                highlight: slot.sel ? root.theme.fg
                                                    : "transparent"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.chipIndex = slot.index
                            }
                        }
                    }

                }

                // ═══ controls ═══
                Row {
                    width: parent.width
                    spacing: root.theme.gap

                    Btn {
                        width: (frame.width - root.theme.pad * 2 - root.theme.gap * 3) / 4
                        label: "CLEAR"
                        hint: "c"
                        enabled: root.phase === "betting" && root.wagered > 0
                        onActivated: root.clearBets()
                    }
                    Btn {
                        width: (frame.width - root.theme.pad * 2 - root.theme.gap * 3) / 4
                        label: "UNDO"
                        hint: "u"
                        enabled: root.phase === "betting" && root.betOrder.length > 0
                        onActivated: root.undo()
                    }
                    Btn {
                        width: (frame.width - root.theme.pad * 2 - root.theme.gap * 3) / 4
                        label: "REBET"
                        hint: "r"
                        enabled: root.phase === "betting" && root.lastOrder.length > 0
                        onActivated: root.rebet()
                    }
                    Btn {
                        width: (frame.width - root.theme.pad * 2 - root.theme.gap * 3) / 4
                        label: "SPIN"
                        hint: "space"
                        accent: true
                        enabled: root.phase === "betting"
                        onActivated: root.spin()
                    }
                }
            }
        }
    }
}
