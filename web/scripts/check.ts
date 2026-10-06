// Parity check against the Python engine: node scripts/check.ts <fixtures.json> <sport_profiles.json>
// Fixtures are written by ml/tests/test_parity.py (same format formcore-check reads).
import { readFileSync } from "node:fs";
import { analyzeRecording } from "../src/engine/engine.ts";
import { summarize } from "../src/engine/scoring.ts";
import { correctedPose } from "../src/engine/corrections.ts";

if (process.argv[2] === "--corrections") checkCorrections(process.argv[3]);

// node scripts/check.ts --corrections <file>: each {analyzer, metric, target, pose, ref, torso, dom, expected}
function checkCorrections(path: string): never {
  const cases = JSON.parse(readFileSync(path, "utf8"));
  let bad = 0;
  for (const c of cases) {
    const got = correctedPose(c.analyzer, c.metric, c.target, c.pose, c.ref, c.torso, c.dom);
    const exp = c.expected;
    let ok = (got === null) === (exp === null);
    if (ok && got && exp) {
      for (const k of new Set([...Object.keys(got), ...Object.keys(exp)])) {
        if (!got[k] || !exp[k] || !close(got[k][0], exp[k][0]) || !close(got[k][1], exp[k][1])) ok = false;
      }
    }
    if (!ok) {
      bad++;
      if (bad <= 8) console.log(`FAIL ${c.analyzer}.${c.metric} target ${c.target}: web ${JSON.stringify(got)} vs python ${JSON.stringify(exp)}`);
    }
  }
  console.log(`${cases.length - bad}/${cases.length} corrections match`);
  process.exit(bad ? 1 : 0);
}

const [fxPath, profPath] = process.argv.slice(2);
const fixtures = JSON.parse(readFileSync(fxPath, "utf8"));
const profiles = JSON.parse(readFileSync(profPath, "utf8"));

function close(a: number, b: number) { return Math.abs(a - b) <= 1e-6 * Math.max(1.0, Math.abs(a), Math.abs(b)); }
const sameNum = (a: number | null | undefined, b: number | null | undefined) =>
  a == null || b == null ? a == null && b == null : close(a, b);

function sameMap(a: Record<string, number | null>, b: Record<string, number | null>, what: string, errs: string[]) {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const k of keys) if (!sameNum(a[k], b[k])) errs.push(`${what}.${k}: web ${a[k]} vs python ${b[k]}`);
}

let failed = 0;
for (const fx of fixtures) {
  const { eng } = analyzeRecording(fx.recording, profiles);
  const exp = fx.expected;
  const errs: string[] = [];
  if (eng.reps.length !== exp.reps.length) errs.push(`reps: web ${eng.reps.length} vs python ${exp.reps.length}`);
  eng.reps.forEach((r, i) => {
    const e = exp.reps[i];
    if (!e) return;
    if (r.type !== e.type) errs.push(`rep ${i} type ${r.type} vs ${e.type}`);
    if (!sameNum(r.t_start, e.t_start) || !sameNum(r.t_end, e.t_end)) errs.push(`rep ${i} times`);
    if (!sameNum(r.score, e.score)) errs.push(`rep ${i} score ${r.score} vs ${e.score}`);
    sameMap(r.metrics, e.metrics, `rep ${i} metrics`, errs);
    sameMap(r.scores, e.scores, `rep ${i} scores`, errs);
    sameMap(r.events, e.events, `rep ${i} events`, errs);
    if (JSON.stringify(r.cues) !== JSON.stringify(e.cues)) errs.push(`rep ${i} cues ${r.cues} vs ${e.cues}`);
  });
  sameMap(eng.rejected, exp.rejected, "rejected", errs);
  // the Python fixture summarises with the sport's base metric list
  const summ = summarize(fx.recording.sport, eng.reps, eng.rejected, profiles.sports[fx.recording.sport].metrics,
                         profiles.scoring);
  if (!sameNum(summ.score, exp.score)) errs.push(`session score web ${summ.score} vs python ${exp.score}`);
  if (errs.length) {
    failed++;
    console.log(`FAIL ${fx.name}\n  ${errs.slice(0, 8).join("\n  ")}`);
  }
}
console.log(`${fixtures.length - failed}/${fixtures.length} fixtures match`);
process.exit(failed ? 1 : 0);
