// A live practice session: frames from the camera (or a sample recording) -> engine -> HUD callbacks.
import { Engine, type EngineEvent, type Joint, type Profiles, type Recording } from "../engine/engine.ts";
import { detect, loadPose } from "./pose.ts";

export interface SessionOptions {
  sport: string;
  handedness: string;
  view: string;
  focus: string | null;
}

export interface SessionHooks {
  onFrame(joints: Joint[] | null, aspect: number): void;
  onEvent(ev: EngineEvent): void;
  onState(state: string): void;
  onEnd?(): void;
}

const BONES: [number, number][] = [
  [1, 2], [1, 3], [3, 5], [2, 4], [4, 6], [1, 7], [2, 8], [7, 8], [7, 9], [9, 11], [8, 10], [10, 12],
];

/** Draws the tracked skeleton; joints are unmirrored image coordinates (0..1). */
export function drawSkeleton(ctx: CanvasRenderingContext2D, joints: Joint[] | null, w: number, h: number,
                             dom: string, minConf = 0.3) {
  ctx.clearRect(0, 0, w, h);
  if (!joints) return;
  const ok = (j: Joint): j is [number, number, number] => j !== null && j[2] >= minConf;
  const domIdx = dom === "r" ? [2, 4, 6] : [1, 3, 5];
  ctx.lineCap = "round";
  ctx.lineWidth = Math.max(3, w / 160);
  for (const [a, b] of BONES) {
    const p = joints[a], q = joints[b];
    if (!ok(p) || !ok(q)) continue;
    ctx.strokeStyle = domIdx.includes(a) && domIdx.includes(b) ? "#ff5a5f" : "rgba(255,255,255,0.9)";
    ctx.beginPath();
    ctx.moveTo(p[0] * w, p[1] * h);
    ctx.lineTo(q[0] * w, q[1] * h);
    ctx.stroke();
  }
  joints.forEach((j, i) => {
    if (!ok(j)) return;
    ctx.fillStyle = domIdx.includes(i) ? "#ff5a5f" : "#ffffff";
    ctx.beginPath();
    ctx.arc(j[0] * w, j[1] * h, Math.max(4, w / 110), 0, Math.PI * 2);
    ctx.fill();
  });
}

abstract class BaseSession {
  engine: Engine;
  running = false;
  protected t0 = 0;
  protected lastState = "";
  constructor(profiles: Profiles, public opts: SessionOptions, protected hooks: SessionHooks) {
    this.engine = new Engine(profiles, opts.sport, opts.handedness, opts.view, opts.focus);
  }
  protected feed(t: number, joints: Joint[] | null, aspect: number) {
    const evs = this.engine.push(t, joints ?? new Array(13).fill(null), aspect);
    for (const ev of evs) this.hooks.onEvent(ev);
    if (this.engine.state !== this.lastState) {
      this.lastState = this.engine.state;
      this.hooks.onState(this.lastState);
    }
  }
  get elapsed() { return this.running ? (performance.now() - this.t0) / 1000 : 0; }
  abstract stop(): void;
}

/** Camera session. Counting starts when `beginCounting()` is called (after the setup check). */
export class CameraSession extends BaseSession {
  stream: MediaStream | null = null;
  private counting = false;
  private raf = 0;
  private lastVideoT = -1;

  async start(video: HTMLVideoElement, facingMode: "user" | "environment") {
    const pose = loadPose();
    this.stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode, width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } },
      audio: false,
    });
    video.srcObject = this.stream;
    video.muted = true;
    video.playsInline = true;
    await video.play();
    const pl = await pose;
    this.running = true;
    this.t0 = performance.now();
    const loop = () => {
      if (!this.running) return;
      this.raf = requestAnimationFrame(loop);
      if (video.readyState < 2 || video.currentTime === this.lastVideoT) return;
      this.lastVideoT = video.currentTime;
      const now = performance.now();
      let joints: Joint[] | null = null;
      try {
        joints = detect(pl, video, now);
      } catch {
        return;
      }
      const aspect = video.videoWidth / Math.max(1, video.videoHeight);
      this.hooks.onFrame(joints, aspect);
      if (this.counting) this.feed((now - this.t0) / 1000, joints, aspect);
    };
    loop();
  }

  beginCounting() {
    this.t0 = performance.now();
    this.counting = true;
  }

  get isCounting() { return this.counting; }

  stop() {
    this.running = false;
    cancelAnimationFrame(this.raf);
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
  }
}

/** Plays a recorded pose sequence in real time, so the demo works without a camera. */
export class SampleSession extends BaseSession {
  private raf = 0;
  private i = 0;
  constructor(profiles: Profiles, opts: SessionOptions, hooks: SessionHooks, private rec: Recording) {
    super(profiles, opts, hooks);
  }
  start() {
    this.running = true;
    this.t0 = performance.now();
    const aspect = this.rec.aspect ?? 1;
    const tStart = this.rec.frames[0]?.t ?? 0;
    const loop = () => {
      if (!this.running) return;
      const t = tStart + (performance.now() - this.t0) / 1000;
      let last: Joint[] | null = null;
      while (this.i < this.rec.frames.length && this.rec.frames[this.i].t <= t) {
        const fr = this.rec.frames[this.i++];
        this.feed(fr.t, fr.j, aspect);
        last = fr.j;
      }
      if (last) this.hooks.onFrame(last, aspect);
      if (this.i >= this.rec.frames.length) {
        this.running = false;
        this.hooks.onEnd?.();
        return;
      }
      this.raf = requestAnimationFrame(loop);
    };
    loop();
  }
  get duration() {
    const f = this.rec.frames;
    return f.length ? f[f.length - 1].t - f[0].t : 0;
  }
  stop() {
    this.running = false;
    cancelAnimationFrame(this.raf);
  }
}
