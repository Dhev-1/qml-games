// Pulls the wheel, the bet-spot generator and the payout resolver straight out
// of roulette.qml and checks them exhaustively — so this tests the shipped code
// rather than a transcription of it.
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, 'roulette.qml'), 'utf8');

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
  if (at < 0) throw new Error(name + '() not found in roulette.qml');
  return matched(at, '{', '}');
}

function litSrc(prop, open, close) {
  const at = src.indexOf('property var ' + prop + ':');
  if (at < 0) throw new Error(prop + ' not found in roulette.qml');
  return matched(src.indexOf(open, at), open, close);
}

// `root` is what the QML functions close over; rebuild just enough of it.
const root = {};
root.wheelOrder = eval(litSrc('wheelOrder', '[', ']'));
root.reds        = eval(litSrc('reds', '[', ']'));
const geo        = eval('(' + litSrc('geo', '{', '}') + ')');
root.isRed       = eval('(' + fnSrc('isRed') + ')');
root.isBlack     = eval('(' + fnSrc('isBlack') + ')');
root.numberAt    = eval('(' + fnSrc('numberAt') + ')');
root.buildSpots  = eval('(' + fnSrc('buildSpots') + ')');
root.resolve     = eval('(' + fnSrc('resolve') + ')');

const spots = root.buildSpots(geo);

// ── harness ───────────────────────────────────────────────────
let failures = 0;
function check(name, detail, ok) {
  if (!ok) failures++;
  console.log(`${name.padEnd(20)} ${String(detail).padEnd(14)} ${ok ? 'ok' : 'FAIL'}`);
}

// ── 1. wheel ──────────────────────────────────────────────────
const EUROPEAN = [
   0, 32, 15, 19,  4, 21,  2, 25, 17, 34,  6, 27, 13, 36, 11, 30,  8, 23,
  10,  5, 24, 16, 33,  1, 20, 14, 31,  9, 22, 18, 29,  7, 28, 12, 35,  3, 26
];
const wheelSorted = root.wheelOrder.slice().sort((a, b) => a - b);
const isPermutation = root.wheelOrder.length === 37
  && wheelSorted.every((n, i) => n === i);
check('wheel order', `${root.wheelOrder.length} pockets`,
  isPermutation && root.wheelOrder.every((n, i) => n === EUROPEAN[i]));

// ── 2. colors ─────────────────────────────────────────────────
const reds = [], blacks = [];
for (let n = 1; n <= 36; n++) (root.isRed(n) ? reds : blacks).push(n);
check('red/black split', `${reds.length} / ${blacks.length}`,
  reds.length === 18 && blacks.length === 18
  && new Set(root.reds).size === 18
  && root.reds.every(n => n >= 1 && n <= 36)
  && !root.isRed(0) && !root.isBlack(0));

// ── 3. spots ──────────────────────────────────────────────────
const EXPECT = {
  straight: [37, 1], split: [60, 2], street: [12, 3], trio: [2, 3],
  corner: [22, 4], firstfour: [1, 4], sixline: [11, 6],
  column: [3, 12], dozen: [3, 12],
  low: [1, 18], high: [1, 18], even: [1, 18], odd: [1, 18],
  red: [1, 18], black: [1, 18],
};
const byKind = {};
for (const s of spots) byKind[s.kind] = (byKind[s.kind] || 0) + 1;

let countsOk = Object.keys(EXPECT).every(k => byKind[k] === EXPECT[k][0])
  && Object.keys(byKind).length === Object.keys(EXPECT).length;
let shapeOk = spots.every(s =>
  EXPECT[s.kind]
  && s.numbers.length === EXPECT[s.kind][1]
  && new Set(s.numbers).size === s.numbers.length
  && s.numbers.every(n => Number.isInteger(n) && n >= 0 && n <= 36));

check('spot counts', `${spots.length} spots`, countsOk && spots.length === 157);
check('spot shapes', 'numbers valid', shapeOk);
check('spot ids', 'unique', new Set(spots.map(s => s.id)).size === spots.length);

// positions must be far enough apart that nearest-spot picking is unambiguous
let minD = Infinity, minPair = '';
for (let i = 0; i < spots.length; i++)
  for (let j = i + 1; j < spots.length; j++) {
    const d = Math.hypot(spots[i].x - spots[j].x, spots[i].y - spots[j].y);
    if (d < minD) { minD = d; minPair = `${spots[i].id} / ${spots[j].id}`; }
  }
check('spot spacing', `min ${minD.toFixed(1)}px`, minD >= 20);
if (minD < 20) console.log(`   closest: ${minPair}`);

// the numbers each outside bet claims must actually be those numbers
const find = k => spots.find(s => s.kind === k).numbers;
const setEq = (a, b) => a.length === b.length && a.every((n, i) => n === b[i]);
const range = (lo, hi) => Array.from({ length: hi - lo + 1 }, (_, i) => lo + i);
check('outside bets', 'sets correct',
  setEq(find('low'), range(1, 18))
  && setEq(find('high'), range(19, 36))
  && setEq(find('even'), range(1, 36).filter(n => n % 2 === 0))
  && setEq(find('odd'), range(1, 36).filter(n => n % 2 === 1))
  && setEq(find('red'), range(1, 36).filter(n => root.isRed(n)))
  && setEq(find('black'), range(1, 36).filter(n => root.isBlack(n))));

// every number 1-36 is covered by exactly one dozen and one column
const dozens = spots.filter(s => s.kind === 'dozen');
const columns = spots.filter(s => s.kind === 'column');
check('dozens/columns', 'partition 1-36',
  range(1, 36).every(n =>
    dozens.filter(d => d.numbers.includes(n)).length === 1
    && columns.filter(c => c.numbers.includes(n)).length === 1));

// ── 4. payout invariant ───────────────────────────────────────
// In single zero every bet pays so that (pays + 1) * covered == 36.
const badPay = spots.filter(s => (s.pays + 1) * s.numbers.length !== 36);
check('payout invariant', `${spots.length} spots`, badPay.length === 0);
if (badPay.length) badPay.slice(0, 5).forEach(s =>
  console.log(`   ${s.id}: pays ${s.pays} on ${s.numbers.length} numbers`));

// ── 5. exhaustive resolve ─────────────────────────────────────
// Stake 1 on every spot, run all 37 outcomes, and check what resolve() hands
// back — both per spot and across the whole felt.
let staked = 0, returned = 0;
const offenders = [];
for (const s of spots) {
  let got = 0;
  for (let win = 0; win <= 36; win++)
    got += root.resolve([{ numbers: s.numbers, pays: s.pays, amount: 1 }], win);
  if (got !== 36) offenders.push(`${s.id} returned ${got}/37`);
  staked += 37;
  returned += got;
}
check('expected return', `${returned}/${staked}`,
  offenders.length === 0 && returned === spots.length * 36
  && staked === spots.length * 37);
offenders.slice(0, 5).forEach(o => console.log('   ' + o));

// a mixed board resolves to the sum of its parts
const board = spots.filter((_, i) => i % 7 === 0)
  .map(s => ({ numbers: s.numbers, pays: s.pays, amount: 5 }));
let boardTotal = 0;
for (let win = 0; win <= 36; win++) boardTotal += root.resolve(board, win);
check('mixed board', `${board.length} bets`,
  boardTotal === board.length * 5 * 36);

// ── 6. spin landing ───────────────────────────────────────────
// The spin's whole claim is that the ball ends up on the pocket the RNG picked.
// Pull the integrator and the solved settle out of the QML, run them headless at
// 60fps, and check where the ball actually comes to rest.
function numProp(name) {
  const m = src.match(new RegExp('property real ' + name + ':([^\\n]+)'));
  if (!m) throw new Error(name + ' not found in roulette.qml');
  const cut = m[1].indexOf('//');
  return eval(cut < 0 ? m[1] : m[1].slice(0, cut));
}
for (const k of ['pocketArc', 'kWheel', 'kBall', 'tWheel', 'tBall', 'minFree',
                 'maxFree', 'trackR', 'pocketR', 'scatAmp', 'scatFrom', 'scatHops'])
  root[k] = numProp(k);

const spinner = { running: false };
root.land        = () => {};
root.norm180     = eval('(' + fnSrc('norm180') + ')');
root.pocketAngle = eval('(' + fnSrc('pocketAngle') + ')');
root.scatter     = eval('(' + fnSrc('scatter') + ')');
root.ballR       = eval('(' + fnSrc('ballR') + ')');
root.stepFree    = eval('(' + fnSrc('stepFree') + ')');
root.stepSettle  = eval('(' + fnSrc('stepSettle') + ')');

// deterministic runs, so a failure is reproducible
let seed = 20260726;
const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;

const DT = 1 / 60;
function simulate(win) {
  Object.assign(root, {
    winNumber: win, wheelAngle: rnd() * 360, ballAngle: rnd() * 360,
    wheelVel: 290 + rnd() * 70, ballVel: -(1180 + rnd() * 160),
    ballRadius: root.trackR, freeT: 0, settleT: 0,
    hasPrev: false, prevErr: 0, stage: 'free',
  });
  spinner.running = true;

  let frames = 0, prevAngle = root.ballAngle, vBefore = 0, vAfter = null;
  while (spinner.running && frames++ < 3000) {
    const wasFree = root.stage === 'free';
    if (wasFree) root.stepFree(DT); else root.stepSettle(DT);
    const v = (root.ballAngle - prevAngle) / DT;
    if (wasFree) vBefore = v;
    else if (vAfter === null) vAfter = v;   // first frame after the handoff
    prevAngle = root.ballAngle;
  }
  return {
    err: Math.abs(root.norm180(
      root.ballAngle - root.wheelAngle - root.pocketAngle(win))),
    seconds: frames * DT,
    radius: root.ballRadius,
    jump: vAfter === null ? 0 : Math.abs(vAfter / vBefore - 1),
    fellThrough: root.freeT > root.maxFree,
  };
}

let maxErr = 0, maxJump = 0, minS = Infinity, maxS = 0, fell = 0, runs = 0;
let radiusOk = true;
for (let rep = 0; rep < 60; rep++)
  for (let win = 0; win <= 36; win++) {
    const r = simulate(win);
    maxErr = Math.max(maxErr, r.err);
    maxJump = Math.max(maxJump, r.jump);
    minS = Math.min(minS, r.seconds);
    maxS = Math.max(maxS, r.seconds);
    if (r.fellThrough) fell++;
    if (Math.abs(r.radius - root.pocketR) > 1e-9) radiusOk = false;
    runs++;
  }

check('spin lands', `${runs} spins`, maxErr < 1e-6);
if (maxErr >= 1e-6) console.log(`   worst miss: ${maxErr.toFixed(4)}°`);
check('ball seats', 'in the pocket', radiusOk);
// the handoff from free integration to the solved curve must not visibly kick
check('handoff smooth', `${(maxJump * 100).toFixed(1)}% max`, maxJump < 0.10);
check('spin length', `${minS.toFixed(1)}-${maxS.toFixed(1)}s`,
  minS > 4 && maxS < 7);
// falling through to maxFree means no zero-crossing was found in time; rare is
// fine (the landing is still exact), routine would mean the window is too tight
check('crossing found', `${runs - fell}/${runs}`, fell / runs < 0.05);

// ── verdict ───────────────────────────────────────────────────
const edge = (1 - returned / staked) * 100;
console.log('-'.repeat(48));
console.log(`house edge: ${edge.toFixed(2)}%  (expect 2.70%)`);
console.log(failures === 0 ? '\nPASS' : `\nFAIL (${failures})`);
process.exit(failures === 0 ? 0 : 1);
