//  poker.qml — Jacks or Better video poker, the whole widget in one file.
//
//  run:     qs -p ~/cloon/pokr/poker.qml
//  toggle:  qs -p ~/cloon/pokr/poker.qml ipc call poker toggle
//
//  keys:    1-5 hold/unhold · space or enter deal/draw
//           b bet one · m max bet · esc hide
//
//  Edit the `theme` block below to restyle everything.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

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

        readonly property color cardFace:  "#f2f2f6"
        readonly property color cardInk:   "#16161e"
        readonly property color cardRed:   "#d3283a"
        readonly property color cardBack:  "#2b3a63"

        readonly property int    cardW:    92
        readonly property int    cardH:    132
        readonly property int    gap:      10
        readonly property int    pad:      20
        readonly property int    radius:   10
        readonly property string font:     "JetBrainsMono Nerd Font"
    }

    // ═══════════════════════════════════════════════════════════
    //  RULES — 9/6 Jacks or Better. Row order is the ranking.
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

    readonly property var suitGlyph: ["♠", "♥", "♦", "♣"]
    readonly property var rankName: ["", "", "2", "3", "4", "5", "6", "7", "8",
                                     "9", "10", "J", "Q", "K", "A"]

    // ═══════════════════════════════════════════════════════════
    //  GAME STATE
    // ═══════════════════════════════════════════════════════════
    property int  credits:    200
    property int  bet:        5
    property int  lastWin:    0
    property int  winRow:     -1        // index into payTable, -1 = no win
    property string phase:    "deal"    // "deal" = press deal · "draw" = pick holds
    property string message:  "PRESS DEAL TO START"

    property var deck:     []
    property int deckPos:  0
    property var hand:     [null, null, null, null, null]
    property var holds:    [false, false, false, false, false]
    property int revealStep: 5          // cards with index < this are face up

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

    // ── actions ────────────────────────────────────────────────
    function betOne() {
        if (phase !== "deal") return;
        bet = bet >= 5 ? 1 : bet + 1;
    }

    function maxBet() {
        if (phase !== "deal") return;
        bet = 5;
        deal();
    }

    function toggleHold(i) {
        if (phase !== "draw") return;
        let h = holds.slice();
        h[i] = !h[i];
        holds = h;
    }

    function deal() {
        if (credits < bet) {
            message = "NOT ENOUGH CREDITS";
            return;
        }
        credits -= bet;
        lastWin = 0;
        winRow = -1;
        holds = [false, false, false, false, false];
        deck = freshDeck();
        deckPos = 0;

        let h = [];
        for (let i = 0; i < 5; i++) h.push(deck[deckPos++]);
        hand = h;

        phase = "draw";
        message = "HOLD YOUR CARDS";
        revealStep = 0;
        dealTimer.restart();
    }

    function draw() {
        let h = hand.slice();
        for (let i = 0; i < 5; i++)
            if (!holds[i]) h[i] = deck[deckPos++];
        hand = h;

        const row = evaluate(h);
        winRow = row;
        lastWin = row >= 0 ? payTable[row].pay[bet - 1] : 0;
        credits += lastWin;

        phase = "deal";
        message = row >= 0 ? payTable[row].name.toUpperCase() + "  —  WIN "
                             + lastWin
                           : "NO WIN  —  DEAL AGAIN";
        revealStep = 0;
        dealTimer.restart();
    }

    function primary() {
        if (phase === "deal") deal(); else draw();
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
            border.color: root.theme.raised

            Text {
                anchors.centerIn: parent
                text: "HELD"
                font.family: root.theme.font
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.5
                color: card.held ? root.theme.bg : root.theme.raised
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

        implicitHeight: 40
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
                     : btn.accent   ? root.theme.bg
                                    : root.theme.fg
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: btn.hint
                font.family: root.theme.font
                font.pixelSize: 9
                color: !btn.enabled ? root.theme.inactive
                     : btn.accent   ? Qt.rgba(0, 0, 0, 0.55)
                                    : root.theme.muted
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
    //  WINDOW
    // ═══════════════════════════════════════════════════════════
    IpcHandler {
        target: "poker"

        function toggle(): void { loader.active = !loader.active; }
        function show():   void { loader.active = true; }
        function hide():   void { loader.active = false; }

        // play the widget without touching it — bind these in hyprland.conf
        function play(): void   { root.primary(); }   // deal, or draw
        function betOne(): void { root.betOne(); }
        function maxBet(): void { root.maxBet(); }
        function hold(n: int): void { root.toggleHold(n - 1); }

        // machine-readable state — handy for a waybar/eww credits readout
        function status(): string {
            return JSON.stringify({
                visible: loader.active,
                credits: root.credits,
                bet: root.bet,
                phase: root.phase,
                lastWin: root.lastWin,
                holds: root.holds,
                hand: root.hand.map(c => c === null ? null
                    : root.rankName[c.rank] + root.suitGlyph[c.suit])
            });
        }
    }

    LazyLoader {
        id: loader
        active: true

        PanelWindow {
            id: win
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "poker"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore

            implicitWidth: frame.implicitWidth
            implicitHeight: frame.implicitHeight

            Rectangle {
                id: frame
                anchors.fill: parent
                radius: 16
                color: root.theme.bg
                border.width: 1
                border.color: root.theme.raised

                implicitWidth: root.theme.cardW * 5 + root.theme.gap * 4
                               + root.theme.pad * 2
                implicitHeight: layout.implicitHeight + root.theme.pad * 2

                // keyboard driver
                Item {
                    anchors.fill: parent
                    focus: true
                    Keys.onPressed: (e) => {
                        switch (e.key) {
                        case Qt.Key_1: case Qt.Key_2: case Qt.Key_3:
                        case Qt.Key_4: case Qt.Key_5:
                            root.toggleHold(e.key - Qt.Key_1); break;
                        case Qt.Key_Space:
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.primary(); break;
                        case Qt.Key_B: root.betOne(); break;
                        case Qt.Key_M: root.maxBet(); break;
                        case Qt.Key_Escape: loader.active = false; break;
                        default: return;
                        }
                        e.accepted = true;
                    }
                }

                Column {
                    id: layout
                    anchors.fill: parent
                    anchors.margins: root.theme.pad
                    spacing: 12

                    // ── title ──
                    Item {
                        width: parent.width
                        height: 22

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "VIDEO POKER"
                            font.family: root.theme.font
                            font.pixelSize: 15
                            font.bold: true
                            font.letterSpacing: 2
                            color: root.theme.fg
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "JACKS OR BETTER  ·  9/6"
                            font.family: root.theme.font
                            font.pixelSize: 11
                            font.letterSpacing: 1
                            color: root.theme.muted
                        }
                    }

                    // ── pay table ──
                    Rectangle {
                        width: parent.width
                        implicitHeight: payCol.implicitHeight + 12
                        radius: 8
                        color: root.theme.surface
                        border.width: 1
                        border.color: root.theme.raised

                        Column {
                            id: payCol
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 0

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
                                            model: 5

                                            Rectangle {
                                                required property int index
                                                readonly property bool active:
                                                    root.bet === index + 1

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

                    // ── the hand ──
                    Row {
                        spacing: root.theme.gap
                        anchors.horizontalCenter: parent.horizontalCenter

                        Repeater {
                            model: 5
                            Card {}
                        }
                    }

                    // ── message line ──
                    Rectangle {
                        width: parent.width
                        height: 30
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
                                 : root.phase === "draw" ? root.theme.blue
                                                         : root.theme.muted
                        }
                    }

                    // ── meters ──
                    Row {
                        width: parent.width
                        spacing: root.theme.gap

                        Repeater {
                            model: [
                                { label: "CREDITS", value: root.credits,
                                  tint: root.theme.green },
                                { label: "BET",     value: root.bet,
                                  tint: root.theme.blue },
                                { label: "WIN",     value: root.lastWin,
                                  tint: root.theme.gold }
                            ]

                            Rectangle {
                                required property var modelData

                                width: (layout.width - root.theme.gap * 2) / 3
                                height: 44
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
                                        font.family: root.theme.font
                                        font.pixelSize: 18
                                        font.bold: true
                                        color: modelData.tint
                                    }
                                }
                            }
                        }
                    }

                    // ── controls ──
                    Row {
                        width: parent.width
                        spacing: root.theme.gap

                        Btn {
                            width: (layout.width - root.theme.gap * 2) / 3
                            label: "BET ONE"
                            hint: "b"
                            enabled: root.phase === "deal"
                            onActivated: root.betOne()
                        }
                        Btn {
                            width: (layout.width - root.theme.gap * 2) / 3
                            label: "MAX BET"
                            hint: "m"
                            enabled: root.phase === "deal"
                            onActivated: root.maxBet()
                        }
                        Btn {
                            width: (layout.width - root.theme.gap * 2) / 3
                            label: root.phase === "deal" ? "DEAL" : "DRAW"
                            hint: "space"
                            accent: true
                            onActivated: root.primary()
                        }
                    }
                }
            }
        }
    }
}
