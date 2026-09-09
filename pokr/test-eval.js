// Extracts evaluate() straight out of poker.qml and enumerates all C(52,5)
// hands, comparing category counts against the known exact distribution.
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, 'Poker.qml'), 'utf8');

const start = src.indexOf('function evaluate(h) {');
if (start < 0) throw new Error('evaluate() not found in poker.qml');
let depth = 0, end = -1;
for (let i = src.indexOf('{', start); i < src.length; i++) {
  if (src[i] === '{') depth++;
  else if (src[i] === '}' && --depth === 0) { end = i + 1; break; }
}
const evaluate = eval('(' + src.slice(start, end) + ')');

// exact 5-card poker distribution, mapped onto the pay table rows
const expected = {
  '0': 4,        // royal flush
  '1': 36,       // straight flush
  '2': 624,      // four of a kind
  '3': 3744,     // full house
  '4': 5108,     // flush
  '5': 10200,    // straight
  '6': 54912,    // three of a kind
  '7': 123552,   // two pair
  '8': 337920,   // pair of jacks or better
  '-1': 2062860, // everything else
};
const NAMES = ['Royal Flush', 'Straight Flush', 'Four of a Kind', 'Full House',
  'Flush', 'Straight', 'Three of a Kind', 'Two Pair', 'Jacks or Better'];

const deck = [];
for (let s = 0; s < 4; s++)
  for (let r = 2; r <= 14; r++) deck.push({ rank: r, suit: s });

const got = {};
let total = 0;
for (let a = 0; a < 48; a++)
for (let b = a + 1; b < 49; b++)
for (let c = b + 1; c < 50; c++)
for (let d = c + 1; d < 51; d++)
for (let e = d + 1; e < 52; e++) {
  const row = evaluate([deck[a], deck[b], deck[c], deck[d], deck[e]]);
  got[row] = (got[row] || 0) + 1;
  total++;
}

let ok = true;
console.log('hand                 expected        got');
console.log('-------------------------------------------');
for (const k of ['0','1','2','3','4','5','6','7','8','-1']) {
  const name = k === '-1' ? '(no win)' : NAMES[k];
  const exp = expected[k], act = got[k] || 0;
  const pass = exp === act;
  if (!pass) ok = false;
  console.log(
    `${name.padEnd(20)} ${String(exp).padStart(8)} ${String(act).padStart(10)}  ${pass ? 'ok' : 'MISMATCH'}`);
}
console.log('-------------------------------------------');
console.log(`total hands enumerated: ${total} (expect 2598960)`);
console.log(ok && total === 2598960 ? '\nPASS' : '\nFAIL');
process.exit(ok && total === 2598960 ? 0 : 1);
