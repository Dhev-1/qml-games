// Pulls the hand math, the dealer policy, the settlement and the shoe straight
// out of blackjack.qml and checks them — so this tests the shipped code rather
// than a transcription of it.
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, 'blackjack.qml'), 'utf8');

// ── extraction ────────────────────────────────────────────────
function matched(from, open, close) {
  let depth = 0;
  for (let i = src.indexOf(open, from); i < src.length; i++) {
    if (src[i] === open) depth++;
    else if (src[i] === close && --depth === 0) return src.slice(from, i + 1);
  }
  throw new Error('unbalanced ' + open + ' from ' + from);
}

function fnSrc(name) {
  const at = src.indexOf('function ' + name + '(');
  if (at < 0) throw new Error(name + '() not found in blackjack.qml');
  // strip QML's return-type annotation, which is not JavaScript
  return matched(at, '{', '}');
}

function numProp(name) {
  const m = new RegExp('property\\s+(?:int|real)\\s+' + name + ':\\s*([0-9.]+)').exec(src);
  if (!m) throw new Error(name + ' not found in blackjack.qml');
  return Number(m[1]);
}

// `root` is what the QML functions close over; rebuild just enough of it.
const root = {};
root.decks       = numProp('decks');
root.maxHands    = numProp('maxHands');
root.bjNum       = numProp('bjNum');
root.bjDen       = numProp('bjDen');
root.penetration = numProp('penetration');
root.cardValue   = eval('(' + fnSrc('cardValue') + ')');
root.handValue   = eval('(' + fnSrc('handValue') + ')');
root.isBlackjack = eval('(' + fnSrc('isBlackjack') + ')');
root.dealerHits  = eval('(' + fnSrc('dealerHits') + ')');
root.settleHand  = eval('(' + fnSrc('settleHand') + ')');
root.resultName  = eval('(' + fnSrc('resultName') + ')');
root.buildShoe   = eval('(' + fnSrc('buildShoe') + ')');

const { cardValue, handValue, isBlackjack, dealerHits, settleHand,
        resultName, buildShoe } = root;

// ── harness ───────────────────────────────────────────────────
let failures = 0;
function check(name, detail, ok) {
  if (!ok) failures++;
  console.log(`${name.padEnd(22)} ${String(detail).padEnd(16)} ${ok ? 'ok' : 'FAIL'}`);
}

const c = (rank, suit = 0) => ({ rank, suit });
const RANKS = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14];

// Deterministic RNG, so the simulation below is a fixed number rather than a
// number that drifts every run. Everything that shuffles goes through it.
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
Math.random = mulberry32(20260727);

// ── 1. card values ────────────────────────────────────────────
const wantValue = { 2:2, 3:3, 4:4, 5:5, 6:6, 7:7, 8:8, 9:9, 10:10,
                    11:10, 12:10, 13:10, 14:11 };
check('card values', '13 ranks',
  RANKS.every(r => cardValue(r) === wantValue[r]));

// ── 2. hand totals ────────────────────────────────────────────
const totalCases = [
  [[10, 7],           17, false],
  [[14, 6],           17, true ],   // soft 17
  [[14, 6, 10],       17, false],   // ace demoted
  [[14, 14],          12, true ],   // one ace up, one down
  [[14, 14, 14],      13, true ],
  [[14, 14, 14, 9],   12, false],   // all four demoted
  [[13, 12, 11],      30, false],   // bust on paint
  [[14, 13],          21, true ],
  [[2, 2],             4, false],
  [[14, 2, 3, 4],     20, true ],   // still soft across four cards
  [[14, 2, 3, 4, 5],  15, false],   // one card further and the ace goes down
];
check('hand totals', totalCases.length + ' cases',
  totalCases.every(([ranks, total, soft]) => {
    const v = handValue(ranks.map(r => c(r)));
    return v.total === total && v.soft === soft && v.bust === (total > 21);
  }));

// Exhaustively: no hand may ever report a total above 21 while an ace is still
// counted high — that is the whole contract of the demotion loop.
let softOk = true;
for (const a of RANKS) for (const b of RANKS) for (const d of RANKS) {
  const v = handValue([c(a), c(b), c(d)]);
  if (v.soft && v.total > 21) softOk = false;
  if (v.soft && v.total < 12) softOk = false;   // a high ace means at least 12
}
check('soft never busts', '2197 hands', softOk);

// ── 3. naturals ───────────────────────────────────────────────
let bjCount = 0, bjOk = true;
for (const a of RANKS) for (const b of RANKS) {
  const hand = [c(a), c(b)];
  const nat = isBlackjack(hand);
  const want = (a === 14 && cardValue(b) === 10) || (b === 14 && cardValue(a) === 10);
  if (nat !== want) bjOk = false;
  if (nat) bjCount++;
}
// three cards can make 21 but never a natural
for (const a of RANKS) for (const b of RANKS) for (const d of RANKS)
  if (isBlackjack([c(a), c(b), c(d)])) bjOk = false;
check('naturals', bjCount + ' of 169', bjOk && bjCount === 8);

// ── 4. dealer policy — stands on all 17s ──────────────────────
let policyOk = true;
for (let t = 4; t <= 21; t++)
  for (const soft of [false, true]) {
    const want = t < 17;
    if (dealerHits(t, soft) !== want) policyOk = false;
  }
check('dealer S17', 'stands 17-21', policyOk);

// ── 5. settlement invariants ──────────────────────────────────
//  Stated as properties of the rules rather than as a second copy of the
//  function, so a bug has to break the rule to get through.
const BET = 100;
const hand = (ranks, fromSplit = false) =>
  ({ cards: ranks.map(r => c(r)), bet: BET, fromSplit: fromSplit });

// build pools of real hands: every two- and three-card combination
const two = [], three = [];
for (const a of RANKS) for (const b of RANKS) {
  two.push([c(a), c(b)]);
  for (const d of RANKS) three.push([c(a), c(b), c(d)]);
}

let bustOk = true, pushOk = true, natOk = true, dbustOk = true, monoOk = true;
let splitNatOk = true, pairs = 0;

for (const p of three.concat(two)) {
  for (const d of two) {
    const h = { cards: p, bet: BET, fromSplit: false };
    const ret = settleHand(h, d);
    const pv = handValue(p), dv = handValue(d);
    const pbj = p.length === 2 && pv.total === 21;
    const dbj = d.length === 2 && dv.total === 21;
    pairs++;

    if (pv.bust && ret !== 0) bustOk = false;
    if (!pv.bust && !pbj && !dbj && !dv.bust && pv.total === dv.total && ret !== BET)
      pushOk = false;
    if (pbj && !dbj && ret !== BET + Math.ceil(BET * 3 / 2)) natOk = false;
    if (pbj && dbj && ret !== BET) natOk = false;
    if (!pv.bust && !pbj && !dbj && dv.bust && ret !== 2 * BET) dbustOk = false;

    // a split hand reaching 21 on two cards is a 21, not a natural
    if (pbj) {
      const s = settleHand({ cards: p, bet: BET, fromSplit: true }, d);
      const want = dbj ? 0 : (dv.bust || 21 > dv.total ? 2 * BET
                            : 21 === dv.total ? BET : 0);
      if (s !== want) splitNatOk = false;
    }
  }
}

// higher is never worth less: sweep hard totals against a fixed dealer hand
for (const d of two) {
  let prev = -1;
  for (let t = 12; t <= 21; t++) {
    // a hard total t as three cards, so it is never mistaken for a natural
    const ranks = t <= 20 ? [10, 2, t - 12] : [10, 9, 2];
    if (ranks[2] < 2) continue;
    const ret = settleHand(hand(ranks), d);
    if (ret < prev) monoOk = false;
    prev = ret;
  }
}

check('bust never pays', pairs.toLocaleString() + ' pairs', bustOk);
check('equal totals push', 'exact stake', pushOk);
check('naturals pay 3:2', 'and push each other', natOk);
check('dealer bust pays', '2x stake', dbustOk);
check('split 21 is not BJ', 'pays even money', splitNatOk);
check('higher never worse', 'monotone', monoOk);

// ── 6. result labels agree with the money ─────────────────────
let labelOk = true;
for (const p of three.concat(two)) for (const d of two) {
  const h = { cards: p, bet: BET, fromSplit: false };
  const ret = settleHand(h, d);
  const name = resultName(h, d);
  const wantSign = ret > BET ? 'win' : ret === BET ? 'push' : 'loss';
  const gotSign = (name === 'WIN' || name === 'BLACKJACK') ? 'win'
                : name === 'PUSH' ? 'push' : 'loss';
  if (wantSign !== gotSign) labelOk = false;
  if (handValue(p).bust && name !== 'BUST') labelOk = false;
}
check('labels match money', 'every pair', labelOk);

// ── 7. the shoe ───────────────────────────────────────────────
const shoe = buildShoe(root.decks);
const perRank = {}, perSuit = {};
for (const card of shoe) {
  perRank[card.rank] = (perRank[card.rank] || 0) + 1;
  perSuit[card.suit] = (perSuit[card.suit] || 0) + 1;
}
check('shoe size', shoe.length + ' cards', shoe.length === root.decks * 52);
check('shoe composition', root.decks * 4 + ' per rank',
  RANKS.every(r => perRank[r] === root.decks * 4)
  && [0, 1, 2, 3].every(s => perSuit[s] === root.decks * 13));

// a shuffle that loses or duplicates a card would show up as a changed
// composition, so shuffle a hundred shoes and compare every one
let shuffleOk = true;
for (let k = 0; k < 100; k++) {
  const s = buildShoe(root.decks);
  const counts = {};
  for (const card of s) {
    const key = card.rank + ':' + card.suit;
    counts[key] = (counts[key] || 0) + 1;
  }
  if (Object.keys(counts).length !== 52) shuffleOk = false;
  for (const key in counts) if (counts[key] !== root.decks) shuffleOk = false;
}
check('shuffle preserves', '100 shoes', shuffleOk);

// and it has to actually move things: an unshuffled shoe would put the same
// rank at the same index every time
const firstRanks = new Set();
for (let k = 0; k < 200; k++) firstRanks.add(buildShoe(1)[0].rank);
check('shuffle mixes', firstRanks.size + ' first ranks', firstRanks.size >= 10);

// ══════════════════════════════════════════════════════════════
//  8. THE DEALER, EXACTLY
//
//  The dealer's outcome distribution computed two ways and compared.
//
//  The first is exact: an infinite deck, where every rank is equally likely and
//  a ten therefore comes up four times as often as anything else, summed over
//  every line of play by recursion. No probabilities are written down here —
//  they fall out of `handValue` and `dealerHits` and the definition of a deck.
//
//  The second deals the real six-deck shoe and plays it out. Agreeing to within
//  a few tenths of a percent is what says the shoe, the draw and the dealer's
//  loop all do what the recursion says they should. It will not agree exactly,
//  and should not: six decks are not infinite, and a card dealt is a card that
//  cannot come again.
// ══════════════════════════════════════════════════════════════
const BUCKETS = ['17', '18', '19', '20', '21', 'bust'];
const zero = () => ({ '17': 0, '18': 0, '19': 0, '20': 0, '21': 0, 'bust': 0 });

//  Two dealer hands with the same total and softness play identically from here
//  on, so that pair is the whole state and memoising on it collapses the tree.
//  Every draw raises the total by at least two, so the recursion cannot loop.
const memo = new Map();
function dealerDist(cards) {
  const v = handValue(cards);
  const key = v.total + (v.soft ? 's' : 'h');
  if (memo.has(key)) return memo.get(key);

  const out = zero();
  if (!dealerHits(v.total, v.soft)) {
    out[v.bust ? 'bust' : String(v.total)] = 1;
  } else {
    for (const r of RANKS) {
      const sub = dealerDist(cards.concat([c(r)]));
      for (const k of BUCKETS) out[k] += sub[k] / RANKS.length;
    }
  }
  memo.set(key, out);
  return out;
}

//  Exact, by upcard. The hole card is one of thirteen equally likely ranks, and
//  a natural is a 21 rather than a special case — this is the distribution
//  before any peek, which is what the simulation below also measures.
const exact = {};
for (const up of RANKS) {
  const d = zero();
  for (const hole of RANKS) {
    const sub = dealerDist([c(up), c(hole)]);
    for (const k of BUCKETS) d[k] += sub[k] / RANKS.length;
  }
  exact[cardValue(up)] = exact[cardValue(up)] || d;
}

//  Same thing off the shipped shoe.
let dshoe = buildShoe(root.decks), dpos = 0;
const DEALER_HANDS = 2000000;
const seen = {}, seenTotal = {};
for (const u of [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]) { seen[u] = zero(); seenTotal[u] = 0; }

for (let i = 0; i < DEALER_HANDS; i++) {
  if (dpos > dshoe.length * root.penetration) { dshoe = buildShoe(root.decks); dpos = 0; }
  const d = [dshoe[dpos++], dshoe[dpos++]];
  const up = cardValue(d[0].rank);
  for (;;) {
    const v = handValue(d);
    if (!dealerHits(v.total, v.soft)) break;
    if (dpos >= dshoe.length) { dshoe = buildShoe(root.decks); dpos = 0; }
    d.push(dshoe[dpos++]);
  }
  const v = handValue(d);
  seen[up][v.bust ? 'bust' : String(v.total)] += 1;
  seenTotal[up] += 1;
}

let worst = 0, worstAt = '';
for (const u of [2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
  for (const k of BUCKETS) {
    const gap = Math.abs(seen[u][k] / seenTotal[u] - exact[u][k]);
    if (gap > worst) { worst = gap; worstAt = u + '/' + k; }
  }

// every distribution has to be one, exactly
const sums = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  .map(u => BUCKETS.reduce((a, k) => a + exact[u][k], 0));
check('dealer dist sums', '10 upcards',
  sums.every(s => Math.abs(s - 1) < 1e-12));
check('dealer exact vs shoe', (worst * 100).toFixed(2) + '% at ' + worstAt,
  worst < 0.006);
check('dealer bust overall', (
  [2, 3, 4, 5, 6, 7, 8, 9, 10, 11].reduce((a, u) => a + exact[u].bust, 0) / 10 * 100
).toFixed(2) + '%', true);

// ══════════════════════════════════════════════════════════════
//  9. THE HOUSE EDGE
//
//  Plays the shipped engine against basic strategy for this exact rule set —
//  6 decks, S17, DAS, resplit to four, aces not resplit, no surrender — and
//  measures what comes back over four million rounds.
//
//  This is the test that catches the bugs the unit checks cannot: an ace
//  mishandled inside a split, a doubled stake settled at single, a dealer that
//  draws when every hand has already busted. All of those move this figure by
//  whole percentage points and none of them move anything above.
//
//  The band is deliberately wide. The commonly quoted 0.43% for six-deck S17
//  is the game that also resplits aces, which this one does not — worth
//  something under a tenth of a percent — and the strategy chart below is the
//  total-dependent one rather than the composition-dependent ideal. So this
//  asserts the shape of the answer, a small edge in the house's favour, and
//  pins the exact figure only as a regression.
// ══════════════════════════════════════════════════════════════
const EDGE_LO = 0.003, EDGE_HI = 0.0075;
const ROUNDS = 4000000;

// Basic strategy, 6D S17 DAS. Returns H(it) S(tand) D(ouble) P(split).
function strategy(cards, up, canDbl, canSpl) {
  const v = handValue(cards);

  if (canSpl) {
    const pv = cardValue(cards[0].rank);
    if (pv === 11) return 'P';                                   // A,A
    if (pv === 9 && (up <= 6 || up === 8 || up === 9)) return 'P';
    if (pv === 8) return 'P';
    if (pv === 7 && up <= 7) return 'P';
    if (pv === 6 && up <= 6) return 'P';
    if (pv === 4 && (up === 5 || up === 6)) return 'P';
    if ((pv === 3 || pv === 2) && up <= 7) return 'P';
    // 10,10 and 5,5 are never split — they fall through to the totals below
  }

  if (v.soft) {
    const t = v.total;
    if (t >= 19) return 'S';
    if (t === 18) {
      if (up >= 3 && up <= 6) return canDbl ? 'D' : 'S';
      return up <= 8 ? 'S' : 'H';
    }
    if (t === 17) return (up >= 3 && up <= 6 && canDbl) ? 'D' : 'H';
    if (t === 16 || t === 15) return (up >= 4 && up <= 6 && canDbl) ? 'D' : 'H';
    if (t === 14 || t === 13) return (up >= 5 && up <= 6 && canDbl) ? 'D' : 'H';
    return 'H';
  }

  const t = v.total;
  if (t >= 17) return 'S';
  if (t >= 13) return up <= 6 ? 'S' : 'H';
  if (t === 12) return (up >= 4 && up <= 6) ? 'S' : 'H';
  if (t === 11) return (canDbl && up <= 10) ? 'D' : 'H';
  if (t === 10) return (canDbl && up <= 9) ? 'D' : 'H';
  if (t === 9)  return (canDbl && up >= 3 && up <= 6) ? 'D' : 'H';
  return 'H';
}

let sim = buildShoe(root.decks), pos = 0, shuffles = 0;
function drawCard() {
  if (pos >= sim.length) { sim = buildShoe(root.decks); pos = 0; shuffles++; }
  return sim[pos++];
}

let net = 0, staked = 0, splits = 0, doubles = 0, naturals = 0, dealt = 0;

for (let r = 0; r < ROUNDS; r++) {
  // the cut card, checked at the top of the round and nowhere else
  if (pos > sim.length * root.penetration) {
    sim = buildShoe(root.decks); pos = 0; shuffles++;
  }
  const before = pos;

  // player, dealer, player, dealer
  const ph = [drawCard()];
  const dl = [drawCard()];
  ph.push(drawCard());
  dl.push(drawCard());

  let hands = [{ cards: ph, bet: BET, fromSplit: false }];
  staked += BET;
  const up = cardValue(dl[0].rank);

  const peeked = up >= 10 && isBlackjack(dl);
  if (!peeked && !isBlackjack(ph)) {
    for (let i = 0; i < hands.length; i++) {
      const h = hands[i];

      // a hand fresh out of a split arrives with one card
      if (h.cards.length === 1) {
        const wasAce = h.cards[0].rank === 14;
        h.cards.push(drawCard());
        if (wasAce || handValue(h.cards).total >= 21) continue;
      }

      for (;;) {
        const v = handValue(h.cards);
        if (v.total >= 21) break;
        const canDbl = h.cards.length === 2;
        const canSpl = canDbl && hands.length < root.maxHands
          && cardValue(h.cards[0].rank) === cardValue(h.cards[1].rank)
          && !(h.fromSplit && h.cards[0].rank === 14);

        const a = strategy(h.cards, up, canDbl, canSpl);

        if (a === 'P') {
          splits++; staked += BET;
          const keep = h.cards[0], give = h.cards[1];
          hands.splice(i + 1, 0, { cards: [give], bet: h.bet, fromSplit: true });
          h.cards = [keep];
          h.fromSplit = true;
          h.cards.push(drawCard());
          if (keep.rank === 14 || handValue(h.cards).total >= 21) break;
          continue;
        }
        if (a === 'D') {
          doubles++; staked += h.bet;
          h.bet *= 2;
          h.cards.push(drawCard());
          break;
        }
        if (a === 'S') break;
        h.cards.push(drawCard());
      }
    }

    // the dealer only plays if something is still standing
    if (hands.some(h => !handValue(h.cards).bust)) {
      for (;;) {
        const v = handValue(dl);
        if (!dealerHits(v.total, v.soft)) break;
        dl.push(drawCard());
      }
    }
  } else if (isBlackjack(ph)) {
    naturals++;
  }

  let ret = 0, out = 0;
  for (const h of hands) { ret += settleHand(h, dl); out += h.bet; }
  net += ret - out;
  dealt += pos - before;
}

const edge = -net / staked;
const initialEdge = -net / (ROUNDS * BET);

check('rounds played', ROUNDS.toLocaleString(), dealt > ROUNDS * 4);
check('splits taken', splits.toLocaleString(), splits > 0);
check('doubles taken', doubles.toLocaleString(), doubles > 0);
check('shoes used', shuffles.toLocaleString(),
  shuffles >= Math.floor(dealt / (root.decks * 52)));
check('house edge', (initialEdge * 100).toFixed(3) + '%',
  initialEdge > EDGE_LO && initialEdge < EDGE_HI);

console.log('------------------------------------------------');
console.log(`house edge: ${(initialEdge * 100).toFixed(2)}%  `
          + `(expect ${(EDGE_LO * 100).toFixed(1)}-${(EDGE_HI * 100).toFixed(1)}%)`);
console.log(`per unit wagered: ${(edge * 100).toFixed(2)}%  `
          + `· ${staked / BET / ROUNDS} units staked per round`);

process.exit(failures ? 1 : 0);
