// On-device port of ml/strokes.py. Counting and scoring are independent of these estimates.
import modelJson from "../../../shared/stroke_model.json" with { type: "json" };
import type { Pt, Rep, Sample } from "./engine.ts";
export type Features = Record<string, number | null>;
export interface StrokeModel {
  n_points: number; features: string[];
  normalization: { impute: number[]; mean: number[]; std: number[] };
  tasks: Record<string, { classes: string[]; weights: number[][]; bias: number[]; applies_to_coarse?: string[] | null }>;
}
export interface TaskPrediction { label: string; probs: Record<string, number> }
export type StrokePrediction = Record<string, TaskPrediction>;
export const strokeModel = modelJson as StrokeModel;
const events = ["backswing", "contact", "finish"];
const metrics = ["stance_height", "contact_arm", "contact_height", "swing_through", "shoulder_turn", "swing_tempo",
  "backswing_size", "ready_height", "head_stability", "finish_height", "elbow_finish", "off_hand_reach", "spacing", "extension_through"];
function angle(a?: Pt, b?: Pt, c?: Pt): number | null {
  if (!a || !b || !c) return null;
  const x = [a[0] - b[0], a[1] - b[1]], y = [c[0] - b[0], c[1] - b[1]];
  const n = Math.hypot(...x) * Math.hypot(...y);
  return n < 1e-9 ? null : Math.acos(Math.max(-1, Math.min(1, (x[0] * y[0] + x[1] * y[1]) / n))) * 180 / Math.PI;
}
function filled(values: (Pt | null)[]): (Pt | null)[] {
  const out = [...values]; let last: Pt | null = null;
  for (let i = 0; i < out.length; i++) { if (out[i] === null) out[i] = last; else last = out[i]; }
  last = null;
  for (let i = out.length - 1; i >= 0; i--) { if (out[i] === null) out[i] = last; else last = out[i]; }
  return out;
}
function resample(ts: number[], vals: number[], t0: number, t1: number, n: number) {
  let j = 0; const out: number[] = [];
  for (let i = 0; i < n; i++) {
    const t = t0 + (t1 - t0) * i / (n - 1);
    while (j < ts.length - 2 && ts[j + 1] < t) j++;
    if (ts.length === 1 || t <= ts[0]) out.push(vals[0]);
    else if (t >= ts[ts.length - 1]) out.push(vals[vals.length - 1]);
    else { const w = ts[j + 1] > ts[j] ? (t - ts[j]) / (ts[j + 1] - ts[j]) : 0; out.push(vals[j] + w * (vals[j + 1] - vals[j])); }
  }
  return out;
}
export function repFeatures(samples: Sample[], rep: Pick<Rep, "t_start" | "t_end" | "type" | "events" | "metrics">, dom = "r"): Features {
  const off = dom === "r" ? "l" : "r";
  const seg = samples.filter(s => rep.t_start - 1e-6 <= s.t && s.t <= rep.t_end + 1e-6);
  if (seg.length < 2) throw new Error("rep has fewer than 2 samples");
  const side = seg.reduce((n,s) => n + (s.pts[dom + "_shoulder"][0] - s.pts[off + "_shoulder"][0]) / s.torso, 0) >= 0 ? 1 : -1;
  const rel = (s: Sample, name: string): Pt | null => { const p = s.pts[name]; return p ? [(p[0]-s.hip[0])/s.torso*side, (p[1]-s.hip[1])/s.torso] : null; };
  const ts = seg.map(s => s.t), t0 = ts[0], t1 = ts[ts.length-1], duration = Math.max(t1-t0,1e-6);
  const dw = filled(seg.map(s => rel(s,dom+"_wrist")));
  if (!dw[0]) throw new Error("dominant wrist never seen");
  let ow = filled(seg.map(s => rel(s,off+"_wrist"))); if (!ow[0]) ow = dw;
  const d = dw as Pt[], o = ow as Pt[], f: Features = {};
  for (const [name,traj] of [["dom",d],["off",o]] as const) for (const [axis,k] of [["x",0],["y",1]] as const) {
    resample(ts,traj.map(p => p[k]),t0,t1,16).forEach((v,i) => { f[`${name}_${axis}_${i}`] = v; });
  }
  const at = (t:number) => { let best = 0; seg.forEach((s,i) => { if (Math.abs(s.t-t) < Math.abs(seg[best].t-t)) best=i; }); return best; };
  const idx: Record<string,number|null> = {};
  for (const e of events) idx[e] = rep.events[e] != null ? at(rep.events[e]) : null;
  if (idx.contact === null) { idx.contact = 0; seg.forEach((s,i) => { if (s.speed > seg[idx.contact!].speed) idx.contact=i; }); }
  for (const e of events) {
    const i=idx[e], s=i===null ? null : seg[i];
    f[`dom_elbow_${e}`]=s?angle(s.pts[dom+"_shoulder"],s.pts[dom+"_elbow"],s.pts[dom+"_wrist"]):null;
    f[`off_elbow_${e}`]=s?angle(s.pts[off+"_shoulder"],s.pts[off+"_elbow"],s.pts[off+"_wrist"]):null;
    f[`dom_wrist_y_${e}`]=i===null?null:d[i][1]; f[`dom_wrist_x_${e}`]=i===null?null:d[i][0];
  }
  const c=idx.contact!; let lo=idx.backswing??0,hi=idx.finish??seg.length-1; if(hi<lo)[lo,hi]=[hi,lo];
  const gap=(i:number)=>Math.hypot(d[i][0]-o[i][0],d[i][1]-o[i][1]);
  const gaps=seg.slice(lo,hi+1).map((_,i)=>gap(lo+i));
  f.hands_gap_min=Math.min(...gaps); f.hands_gap_mean=gaps.reduce((a,b)=>a+b,0)/gaps.length;
  f.hands_gap_contact=gap(c); f.hands_close_frac=gaps.filter(g=>g<0.5).length/gaps.length;
  f.duration=duration; f.peak_speed=Math.max(...seg.map(s=>s.speed)); f.contact_frac=(seg[c].t-t0)/duration; f.backswing_frac=(seg[lo].t-t0)/duration;
  const apex=(a:Pt[])=>{let k=0;a.forEach((p,i)=>{if(p[1]<a[k][1])k=i});return k;};const da=apex(d),oa=apex(o);
  f.dom_apex_y=d[da][1];f.off_apex_y=o[oa][1];f.toss_lead=(seg[da].t-seg[oa].t)/duration;f.off_apex_x=o[oa][0];
  const nose=rel(seg[c],"nose"),la=seg[c].pts.l_ankle,ra=seg[c].pts.r_ankle;
  f.nose_x_contact=nose?.[0]??null;f.nose_y_contact=nose?.[1]??null;f.ankle_gap_contact=la&&ra?Math.abs(la[0]-ra[0])/seg[c].torso:null;
  const end=seg[seg.length-1]; f.hip_dx=(end.hip[0]-seg[0].hip[0])/end.torso*side;f.hip_dy=(end.hip[1]-seg[0].hip[1])/end.torso;
  const width=(s:Sample)=>Math.hypot(s.pts.l_shoulder[0]-s.pts.r_shoulder[0],s.pts.l_shoulder[1]-s.pts.r_shoulder[1]);
  f.shoulder_width_min=Math.min(...seg.map(width))/Math.max(width(seg[0]),1e-6);
  f.dom_path_len=d.slice(1).reduce((n,p,i)=>n+Math.hypot(p[0]-d[i][0],p[1]-d[i][1]),0);
  const a=Math.max(c-1,0),b=Math.min(c+1,seg.length-1),dt=Math.max(seg[b].t-seg[a].t,1e-6);
  f.dom_vx_contact=(d[b][0]-d[a][0])/dt;f.dom_vy_contact=(d[b][1]-d[a][1])/dt;
  for(const type of ["forehand","backhand","serve"])f[`type_${type}`]=rep.type===type?1:0;
  for(const key of metrics)f[`m_${key}`]=rep.metrics[key]??null;
  return f;
}
export function predict(features: Features | (number|null)[], model: StrokeModel = strokeModel, tasks?: string[]): StrokePrediction {
  if(Array.isArray(features)&&features.length!==model.features.length)throw new Error(`expected ${model.features.length} features, got ${features.length}`);
  const z=model.features.map((name,i)=>{const v=Array.isArray(features)?features[i]:features[name];return ((v!=null&&Number.isFinite(v)?v:model.normalization.impute[i])-model.normalization.mean[i])/model.normalization.std[i]});
  const out: StrokePrediction={};
  for(const [name,task] of Object.entries(model.tasks)) {
    if(tasks&&!tasks.includes(name))continue;
    const logits=task.weights.map((row,i)=>row.reduce((n,w,k)=>n+w*z[k],0)+task.bias[i]);
    const max=Math.max(...logits),exps=logits.map(x=>Math.exp(x-max)),sum=exps.reduce((a,b)=>a+b,0);
    const probs=exps.map(x=>x/sum);let best=0;probs.forEach((p,i)=>{if(p>probs[best])best=i});
    out[name]={label:task.classes[best],probs:Object.fromEntries(task.classes.map((c,i)=>[c,probs[i]]))};
  }
  return out;
}
const families: Record<string,string>={forehand:"Forehand",backhand_one:"One-handed backhand",backhand_two:"Two-handed backhand",serve:"Serve",volley:"Volley",smash:"Smash"};
export function strokeEstimate(prediction?: StrokePrediction): {family:string;key:string;text:string}|null {
  const c=prediction?.coarse;if(!c||!families[c.label]||(c.probs[c.label]??0)<(["volley","smash"].includes(c.label)?0.75:0.6))return null;
  const spin=prediction?.groundstroke_spin;
  const variant=["forehand","backhand_one","backhand_two"].includes(c.label)&&spin&&(spin.probs[spin.label]??0)>=0.6
    ?spin.label==="slice"?"slice":spin.label==="flat_topspin"?"topspin/flat":null:null;
  return{key:c.label,family:families[c.label],text:[families[c.label],variant,"estimate"].filter(Boolean).join(" · ")};
}
export function strokeCounts(reps: Rep[]): string {
  const counts: Record<string,number>={};for(const rep of reps){const e=strokeEstimate(rep.stroke_estimate);const key=e?.key.startsWith("backhand_")?"backhand":e?.key??"uncertain";counts[key]=(counts[key]??0)+1;}
  return ["forehand","backhand","serve","volley","smash","uncertain"].filter(k=>counts[k]).map(k=>`${counts[k]} ${k==="uncertain"?"uncertain":k+(counts[k]===1?"":"s")}`).join(" · ");
}
