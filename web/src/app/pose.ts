// On-device pose tracking with MediaPipe Pose Landmarker. Video frames never leave the browser.
import { FilesetResolver, PoseLandmarker } from "@mediapipe/tasks-vision";
import type { Joint } from "../engine/engine.ts";

// engine joint order (shared/sport_profiles.json "joints") -> MediaPipe landmark index,
// the same mapping ml/extract_pose.py used to build the reference data
const MP_INDEX = [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28];

let landmarker: Promise<PoseLandmarker> | null = null;

export function loadPose(): Promise<PoseLandmarker> {
  landmarker ??= (async () => {
    const base = import.meta.env.BASE_URL + "mediapipe/";
    const fileset = await FilesetResolver.forVisionTasks(base + "wasm");
    const make = (delegate: "GPU" | "CPU") => PoseLandmarker.createFromOptions(fileset, {
      baseOptions: { modelAssetPath: base + "pose_landmarker_lite.task", delegate },
      runningMode: "VIDEO",
      numPoses: 1,
    });
    try {
      return await make("GPU");
    } catch {
      return await make("CPU");
    }
  })();
  landmarker.catch(() => { landmarker = null; });
  return landmarker;
}

/** Engine joints for one video frame (unmirrored image coordinates), or null when nobody is seen. */
export function detect(pl: PoseLandmarker, video: HTMLVideoElement, tMs: number): Joint[] | null {
  const res = pl.detectForVideo(video, tMs);
  const lm = res.landmarks[0];
  if (!lm) return null;
  return MP_INDEX.map((k) => {
    const p = lm[k];
    return p ? [p.x, p.y, p.visibility ?? 1] as Joint : null;
  });
}
