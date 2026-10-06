// Puts the MediaPipe runtime and pose model into public/ so the site serves them itself
// (no third-party requests at run time). Runs before `dev` and `build`; both outputs are gitignored.
import { cpSync, existsSync, mkdirSync, writeFileSync } from "node:fs";

const out = new URL("../public/mediapipe/", import.meta.url);
mkdirSync(out, { recursive: true });
cpSync(new URL("../node_modules/@mediapipe/tasks-vision/wasm/", import.meta.url), new URL("wasm/", out), { recursive: true });

const model = new URL("pose_landmarker_lite.task", out);
if (!existsSync(model)) {
  const url = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task";
  const res = await fetch(url);
  if (!res.ok) throw new Error(`model download failed: ${res.status}`);
  writeFileSync(model, Buffer.from(await res.arrayBuffer()));
}
console.log("MediaPipe assets ready in public/mediapipe/");
