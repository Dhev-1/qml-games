// Pulls the pricing, the payout and the field builder straight out of
// Bones.qml and checks them — so this tests the shipped code rather than a
// transcription of it.
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, 'Bones.qml'), 'utf8');

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
  if (at < 0) throw new Error(name + '() not found in Bones.qml');
  // strip QML's return-type annotation, which is not JavaScript
  return matched(at, '{', '}').replace(/\)\s*:\s*\w+\s*\{/, ') {');
}

function numProp(name) {
  const m = new RegExp('property\\s+(?:int|real)\\s+' + name + ':\\s*([0-9.]+)').exec(src);
  if (!m) throw new Error(name + ' not found in Bones.qml');
  return Number(m[1]);
}

// `root` is what the QML functions close over; rebuild just enough of it.
const root = {};
root.cells      = numProp('cells');
root.minBones   = numProp('minBones');
root.maxBones   = numProp('maxBones');
root.rtp        = numProp('rtp');
root.multiplier = eval('(' + fnSrc('multiplier') + ')');
root.payout     = eval('(' + fnSrc('payout') + ')');
root.buildField = eval('(' + fnSrc('buildField') + ')');

const { multiplier, payout, buildField } = root;

// ── harness ───────────────────────────────────────────────────
let failures = 0;
function check(name, detail, ok) {
  if (!ok) failures++;
  console.log(`${name.padEnd(30)} ${String(detail).padEnd(24)} ${ok ? 'ok' : 'FAIL'}`);
}

console.log(root.cells + ' boxes   bones ' + root.minBones + '-' + root.maxBones
            + '   rtp ' + root.rtp + '\n');

// ── 1. the field ──────────────────────────────────────────────
{
  const f = buildField(5);
  check('field size', f.length, f.length === root.cells);
  check('field bone count', f.filter(Boolean).length,
    f.filter(Boolean).length === 5);
  check('field is boolean', typeof f[0], f.every(x => typeof x === 'boolean'));

  const edges = [buildField(1), buildField(24)];
  check('bone counts at both ends',
    edges[0].filter(Boolean).length + '/' + edges[1].filter(Boolean).length,
    edges[0].filter(Boolean).length === 1
    && edges[1].filter(Boolean).length === 24);
}

// ── 2. the layout is uniform ──────────────────────────────────
//
// Every box should carry a bone in `bones/25` of the fields dealt. 20,000
// deals of the 3-bone field put 2,400 bones on each box in expectation, with
// a standard deviation near 46 — so ±5σ is a wall only a broken shuffle hits.
{
  const N = 20000, BONES = 3;
  const hits = new Array(root.cells).fill(0);
  for (let n = 0; n < N; n++) {
    const f = buildField(BONES);
    for (let i = 0; i < root.cells; i++) if (f[i]) hits[i]++;
  }
  const exp = N * BONES / root.cells;
  const sd = Math.sqrt(N * (BONES / root.cells) * (1 - BONES / root.cells));
  const worst = Math.max(...hits.map(h => Math.abs(h - exp)));
  check('every box equally deadly',
    'worst drift ' + worst.toFixed(0) + ' (5σ=' + (5 * sd).toFixed(0) + ')',
    worst < 5 * sd);
}

// ── 3. the price is fair odds times rtp ───────────────────────
//
// The closed form the loop is standing in for: C(25,p) / C(25-m,p), which is
// the reciprocal of the chance of pulling p chips in a row.
{
  function comb(n, k) {
    let c = 1;
    for (let i = 0; i < k; i++) c = c * (n - i) / (i + 1);
    return c;
  }
  let worst = 0;
  for (let m = root.minBones; m <= root.maxBones; m++)
    for (let p = 1; p <= root.cells - m; p++) {
      const fair = comb(root.cells, p) / comb(root.cells - m, p);
      const rel = Math.abs(multiplier(m, p) - root.rtp * fair) / (root.rtp * fair);
      if (rel > worst) worst = rel;
    }
  check('matches closed form', 'worst rel err ' + worst.toExponential(1),
    worst < 1e-9);
}

// ── 4. spot checks against the published table ────────────────
//
// A handful of corners of the 24-row table the game was specced from. The
// table's own typos (1 mine/1 pick printed as 1.01, 12 picks/1 mine as 1.99)
// are corrected here to what the formula — and every other cell of that same
// table — says they should be. Two cells land on exact halves and the table
// truncates them where this widget rounds: 1.125 and 12.375 print here as
// 1.13 and 12.38, there as 1.12 and 12.37 — same price, different last pixel.
{
  const T = [
    [1, 1, 1.03],      // table says 1.01; 0.99·25/24 = 1.03125
    [2, 1, 1.08], [3, 1, 1.13], [24, 1, 24.75],
    [23, 1, 12.38], [23, 2, 297],
    [1, 12, 1.90],     // table says 1.99
    [1, 24, 24.75],
    [3, 3, 1.48], [5, 5, 3.39],
    [10, 10, 1077], [13, 12, 5148297],
    [24, 1, 24.75],
  ];
  let bad = 0;
  for (const [m, p, want] of T) {
    const got = multiplier(m, p);
    const shown = got >= 100 ? Math.round(got) : Number(got.toFixed(2));
    if (Math.abs(shown - want) / want > 0.005) {
      bad++;
      console.log('  table mismatch  m=' + m + ' p=' + p
                  + '  want ' + want + '  got ' + shown);
    }
  }
  check('table spot checks', T.length + ' cells', bad === 0);
}

// ── 5. the shape of the curve ─────────────────────────────────
{
  let rises = true, deepens = true;
  for (let m = root.minBones; m <= root.maxBones; m++)
    for (let p = 2; p <= root.cells - m; p++)
      if (multiplier(m, p) <= multiplier(m, p - 1)) rises = false;
  for (let p = 1; p <= root.cells - root.maxBones; p++)
    for (let m = root.minBones + 1; m <= root.maxBones; m++)
      if (root.cells - m >= p && multiplier(m, p) <= multiplier(m - 1, p)) deepens = false;
  check('each chip raises the price', 'all m, p', rises);
  check('each bone raises the price', 'all m, p', deepens);

  // Zero picks pay nothing, on every setting — the round has no walk-in-and-
  // leave, and the header leans on this being 0 rather than 0.99.
  let zeroOk = true;
  for (let m = root.minBones; m <= root.maxBones; m++)
    if (multiplier(m, 0) !== 0 || payout(100, m, 0) !== 0) zeroOk = false;
  check('zero picks pay zero', 'all m', zeroOk);
}

// ── 6. the house edge is what the subtitle claims ─────────────
//
// Expected return of pick-p-then-cash: P(survive p picks) · multiplier — which
// telescopes back to exactly `rtp` for every strategy, because that is the
// whole design. Checked over every (m, p) rather than derived once, since a
// stray Math.round in `multiplier` would break some cells and not others.
{
  let worst = 0;
  for (let m = root.minBones; m <= root.maxBones; m++)
    for (let p = 1; p <= root.cells - m; p++) {
      let surv = 1;
      for (let i = 0; i < p; i++)
        surv *= (root.cells - m - i) / (root.cells - i);
      const ret = surv * multiplier(m, p);
      if (Math.abs(ret - root.rtp) > worst) worst = Math.abs(ret - root.rtp);
    }
  check('every strategy returns rtp', 'worst drift ' + worst.toExponential(1),
    worst < 1e-9);
}

// ── 7. payouts in whole credits ───────────────────────────────
{
  check('payout rounds', '1 @ m3 p2 → ' + payout(1, 3, 2),
    payout(1, 3, 2) === Math.round(multiplier(3, 2)));
  check('payout scales', '100 @ m24 p1 → ' + payout(100, 24, 1),
    payout(100, 24, 1) === 2475);
  const big = payout(100, 13, 12);
  check('payout survives the deep end', big,
    Number.isFinite(big) && big > 5e8);
}

console.log(failures === 0 ? '\nPASS' : `\nFAIL — ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
