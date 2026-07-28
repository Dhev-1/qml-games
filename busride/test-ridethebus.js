// Pulls the calls, the odds counter, the payout ladder and the deck straight
// out of RideTheBus.qml and checks them — so this tests the shipped code rather
// than a transcription of it.
//
//   node test-ridethebus.js
//
// The last section enumerates every ordered first-three-cards and closes rung
// four in one step, which makes the return figures it prints exact rather than
// simulated. They are the numbers quoted in README.md; if you move the ladder,
// this is what tells you where it landed.
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, 'RideTheBus.qml'), 'utf8');

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
  if (at < 0) throw new Error(name + '() not found in RideTheBus.qml');
  return matched(at, '{', '}');
}

function numProp(name) {
  const m = new RegExp('property\\s+(?:int|real)\\s+' + name + ':\\s*([0-9.]+)').exec(src);
  if (!m) throw new Error(name + ' not found in RideTheBus.qml');
  return Number(m[1]);
}

function arrProp(name) {
  const at = src.indexOf('property var ' + name + ':');
  if (at < 0) throw new Error(name + ' not found in RideTheBus.qml');
  return JSON.parse(matched(src.indexOf('[', at), '[', ']').replace(/'/g, '"'));
}

// `root` is what the QML functions close over; rebuild just enough of it.
const root = {};
root.stages       = numProp('stages');
root.lowRank      = numProp('lowRank');
root.highRank     = numProp('highRank');
root.ladder       = arrProp('ladder');
root.suitKey      = arrProp('suitKey');
root.isRed        = eval('(' + fnSrc('isRed') + ')');
root.stageOptions = eval('(' + fnSrc('stageOptions') + ')');
root.winsGuess    = eval('(' + fnSrc('winsGuess') + ')');
root.outs         = eval('(' + fnSrc('outs') + ')');
root.unseen       = eval('(' + fnSrc('unseen') + ')');
root.value        = eval('(' + fnSrc('value') + ')');
root.buildDeck    = eval('(' + fnSrc('buildDeck') + ')');

const { isRed, stageOptions, winsGuess, outs, unseen, value, buildDeck } = root;
const LADDER = root.ladder;

// ── harness ───────────────────────────────────────────────────
let failures = 0;
function check(name, detail, ok) {
  if (!ok) failures++;
  console.log(`${name.padEnd(26)} ${String(detail).padEnd(22)} ${ok ? 'ok' : 'FAIL'}`);
}

const c = (rank, suit = 0) => ({ rank, suit });
const RANKS = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14];
const DECK = [];
for (let s = 0; s < 4; s++) for (const r of RANKS) DECK.push({ rank: r, suit: s });

console.log('ladder ' + LADDER.join('/') + '×   ' + root.stages + ' rungs\n');

// ── 1. the deck ───────────────────────────────────────────────
{
  const d = buildDeck();
  const keys = new Set(d.map(x => x.rank * 10 + x.suit));
  check('deck size', d.length, d.length === 52);
  check('deck distinct', keys.size, keys.size === 52);
  const ranks = d.every(x => x.rank >= 2 && x.rank <= 14);
  const suits = d.every(x => x.suit >= 0 && x.suit <= 3);
  check('deck in range', 'ranks 2-14, suits 0-3', ranks && suits);
}

// ── 2. colour ─────────────────────────────────────────────────
check('red suits', 'hearts, diamonds',
  !isRed(c(5, 0)) && isRed(c(5, 1)) && isRed(c(5, 2)) && !isRed(c(5, 3)));
check('rung 1 splits the deck', outs(1, [], 'red') + '/' + outs(1, [], 'black'),
  outs(1, [], 'red') === 26 && outs(1, [], 'black') === 26);

// ── 3. every call is win, lose, or tie — never both ───────────
//
// The complement check that makes the whole thing honest: for any position and
// any card, the two calls on a two-way rung can never both be right and can
// never both be wrong except on a genuine tie.
{
  let both = 0, tiesHiLo = 0, tiesInOut = 0;
  for (const a of DECK) {
    for (const b of DECK) {
      if (a === b) continue;
      const hi = winsGuess(2, [a], b, 'higher'), lo = winsGuess(2, [a], b, 'lower');
      if (hi && lo) both++;
      if (!hi && !lo) { tiesHiLo++; if (a.rank !== b.rank) both++; }

      for (const d of DECK) {
        if (d === a || d === b) continue;
        const i = winsGuess(3, [a, b], d, 'inside');
        const o = winsGuess(3, [a, b], d, 'outside');
        if (i && o) both++;
        if (!i && !o) {
          tiesInOut++;
          const lo2 = Math.min(a.rank, b.rank), hi2 = Math.max(a.rank, b.rank);
          if (d.rank !== lo2 && d.rank !== hi2) both++;
        }
      }
    }
  }
  check('calls never overlap', both + ' contradictions', both === 0);
  // Three other cards of the first card's rank, over 52×51 ordered pairs.
  check('high/low ties', tiesHiLo + ' of ' + 52 * 51, tiesHiLo === 52 * 3);
  check('in/out ties', tiesInOut + ' pairs', tiesInOut > 0);
}

// ── 4. the dead calls ─────────────────────────────────────────
check('higher than an ace', outs(2, [c(14)], 'higher'), outs(2, [c(14)], 'higher') === 0);
check('lower than a two',   outs(2, [c(2)],  'lower'),  outs(2, [c(2)],  'lower') === 0);
check('inside a pair', outs(3, [c(9, 0), c(9, 1)], 'inside'),
  outs(3, [c(9, 0), c(9, 1)], 'inside') === 0);
check('inside touching ranks', outs(3, [c(9, 0), c(10, 1)], 'inside'),
  outs(3, [c(9, 0), c(10, 1)], 'inside') === 0);

// ── 5. outs, counted independently ────────────────────────────
//
// Recount every position by hand rather than through winsGuess, so a wrong tie
// rule in the shipped code cannot agree with itself into a pass.
{
  const struck = (prior, card) =>
    prior.some(p => p.rank === card.rank && p.suit === card.suit);

  let bad = 0, checked = 0;
  for (const a of DECK) {
    // rung 2
    let hi = 0, lo = 0;
    for (const x of DECK) {
      if (struck([a], x)) continue;
      if (x.rank > a.rank) hi++; else if (x.rank < a.rank) lo++;
    }
    if (outs(2, [a], 'higher') !== hi || outs(2, [a], 'lower') !== lo) bad++;
    if (hi + lo + 3 !== unseen([a])) bad++;   // the three ties make up the 51
    checked++;

    for (const b of DECK) {
      if (b === a) continue;
      const prior = [a, b];
      const bot = Math.min(a.rank, b.rank), top = Math.max(a.rank, b.rank);
      let inn = 0, out = 0, tie = 0;
      for (const x of DECK) {
        if (struck(prior, x)) continue;
        if (x.rank === bot || x.rank === top) tie++;
        else if (x.rank > bot && x.rank < top) inn++;
        else out++;
      }
      if (outs(3, prior, 'inside') !== inn || outs(3, prior, 'outside') !== out) bad++;
      if (inn + out + tie !== unseen(prior)) bad++;
      checked++;

      // rung 4 — one suit in four, less whatever is already face up
      for (const d of DECK) {
        if (d === a || d === b) continue;
        const p3 = [a, b, d];
        for (let s = 0; s < 4; s++) {
          const want = 13 - p3.filter(x => x.suit === s).length;
          if (outs(4, p3, root.suitKey[s]) !== want) bad++;
        }
        checked++;
        break;   // one third card per pair is enough to pin the suit count
      }
    }
  }
  check('outs match a recount', bad + ' bad of ' + checked, bad === 0);
}

// ── 6. the ladder ─────────────────────────────────────────────
check('busted pays nothing', value(100, 0), value(100, 0) === 0);
check('ladder', LADDER.map((m, i) => value(10, i + 1)).join('/'),
  LADDER.every((m, i) => value(10, i + 1) === 10 * m));
check('ladder rises', LADDER.join(' < '),
  LADDER.every((m, i) => i === 0 || m > LADDER[i - 1]));
check('stage clamps', value(10, 99), value(10, 99) === 10 * LADDER[LADDER.length - 1]);

// ── 7. what it actually returns ───────────────────────────────
//
// Exact, not sampled. Every ordered first three cards is walked with the greedy
// caller — the one that always takes the side with more outs — and rung four is
// closed in a single step from the suits left in the deck. The four figures are
// the return on staking 1 and getting off at that stop.
{
  const key2 = a => a.rank;
  const key3 = (a, b) => Math.min(a.rank, b.rank) * 100 + Math.max(a.rank, b.rank);
  const best = {}, best3 = {};

  const greedy = (stage, prior) => {
    const opts = stageOptions(stage);
    let pick = opts[0].key, n = -1;
    for (const o of opts) {
      const k = outs(stage, prior, o.key);
      if (k > n) { n = k; pick = o.key; }
    }
    return pick;
  };

  // Ordered draws, so the denominators are 52, 52×51 and 52×51×50 and every
  // surviving path counts once. A path that dies is simply not counted — which
  // is what makes n2/N2 the chance of clearing *two* rungs rather than the
  // chance of clearing the second given the first.
  const N1 = 52, N2 = 52 * 51, N3 = 52 * 51 * 50;
  let n1 = 0, n2 = 0, n3 = 0, p4 = 0;

  for (const a of DECK) {
    // Rung one is 26 against 26 whichever way it is called, so the call is
    // arbitrary and "red" stands in for it.
    if (!isRed(a)) continue;
    n1 += 51 * 50;

    const g2 = best[key2(a)] || (best[key2(a)] = greedy(2, [a]));

    for (const b of DECK) {
      if (b === a || !winsGuess(2, [a], b, g2)) continue;
      n2 += 50;

      const k3 = key3(a, b);
      const g3 = best3[k3] || (best3[k3] = greedy(3, [a, b]));

      for (const d of DECK) {
        if (d === a || d === b || !winsGuess(3, [a, b], d, g3)) continue;
        n3++;

        // Survived all three. Rung four is the best suit left in the deck, and
        // it closes analytically — there is no fourth card to enumerate.
        let top = 0;
        for (let s = 0; s < 4; s++)
          top = Math.max(top, outs(4, [a, b, d], root.suitKey[s]));
        p4 += top / 49;
      }
    }
  }

  const p = [n1 / N3, n2 / N3, n3 / N3, p4 / N3];
  const rtp = p.map((q, i) => q * LADDER[i]);

  console.log('\nstop at   chance      pays     returns   house edge');
  console.log('---------------------------------------------------');
  const NAMES = ['colour', 'high/low', 'in/out', 'the suit'];
  for (let i = 0; i < 4; i++)
    console.log(
      `${NAMES[i].padEnd(9)} ${(p[i] * 100).toFixed(2).padStart(6)}%  ` +
      `${('×' + LADDER[i]).padStart(6)}  ${(rtp[i] * 100).toFixed(2).padStart(9)}%  ` +
      `${((1 - rtp[i]) * 100).toFixed(2).padStart(9)}%`);
  console.log('---------------------------------------------------\n');

  check('rung 1 is a coin flip', p[0].toFixed(4), Math.abs(p[0] - 0.5) < 1e-12);
  check('chances fall', p.map(x => x.toFixed(3)).join(' > '),
    p.every((q, i) => i === 0 || q < p[i - 1]));

  // Rung four is always exactly 13/49, however the first three cards fell: only
  // three cards are gone, so at most three suits are short of thirteen and the
  // fullest suit is a full thirteen every time. The last rung is the one place
  // in the game where the cards on the felt tell you nothing — which is worth a
  // check, because it is the sort of thing that reads like a coincidence.
  check('rung 4 is always 13/49', (p[3] / p[2]).toFixed(6),
    Math.abs(p[3] / p[2] - 13 / 49) < 1e-12);

  // Whether a stop is a good bet is a property of the ladder, which is a
  // choice — so it is reported rather than asserted. A stop over 100% is a
  // stop the player should sit on forever, which is worth saying out loud.
  const rich = [];
  for (let i = 0; i < 4; i++) if (rtp[i] > 1) rich.push(NAMES[i]);
  if (rich.length)
    console.log('ADVISORY  the player is ahead getting off at: ' + rich.join(', ')
                + '\n          ride-to-' + NAMES[rtp.indexOf(Math.max(...rtp))]
                + '-and-cash returns ' + (Math.max(...rtp) * 100).toFixed(1)
                + '% of every stake.\n          a ladder near '
                + p.map(q => (1 / q * 0.97).toFixed(2)).join(' / ')
                + ' would put the house 3% ahead at every stop.\n');
}

console.log(failures === 0 ? '\nPASS' : `\nFAIL — ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
