import assert from "node:assert/strict";
import { strokeEstimate, strokeCounts, type StrokePrediction } from "../src/engine/strokes.ts";
import type { Rep } from "../src/engine/engine.ts";
const prediction = (label:string,p:number,spin="slice",spinP=0.6):StrokePrediction => ({
  coarse:{label,probs:{[label]:p}},groundstroke_spin:{label:spin,probs:{[spin]:spinP}},serve_type:{label:"kick",probs:{kick:1}},
});
assert.equal(strokeEstimate(prediction("forehand",0.599999)),null);
assert.equal(strokeEstimate(prediction("forehand",0.6))?.text,"Forehand · slice · estimate");
assert.equal(strokeEstimate(prediction("backhand_one",0.6,"flat_topspin"))?.text,"One-handed backhand · topspin/flat · estimate");
assert.equal(strokeEstimate(prediction("backhand_two",0.6,"slice",0.599999))?.text,"Two-handed backhand · estimate");
assert.equal(strokeEstimate(prediction("serve",0.6))?.text,"Serve · estimate");
for(const weak of ["volley","smash"]){assert.equal(strokeEstimate(prediction(weak,0.749999)),null);assert(strokeEstimate(prediction(weak,0.75)));}
const reps=["forehand","backhand_one","backhand_two","serve"].map(label=>({stroke_estimate:prediction(label,0.8)} as Rep));
assert.equal(strokeCounts(reps),"1 forehand · 2 backhands · 1 serve");
console.log("Stroke display confidence, spin, counts and hidden experimental output checks passed");
