// A live practice session: frames from the camera (or a sample recording) -> engine -> HUD callbacks.
import { Engine, type EngineEvent, type Joint, type Profiles, type Recording } from "../engine/engine.ts";
import type { Player } from "../engine/personalize.ts";
import { detect, loadPose } from "./pose.ts";
import type { Frame } from "./fixcard.ts";

export interface SessionOptions {
  sport: string;
  handedness: string;
  view: string;
  focus: string | null;
  player: Player | null;
  drill: string | null;
}

export interface SessionHooks {
  onFrame(joints: Joint[] | null, aspect: number): void;
  onEvent(ev: EngineEvent): void;
  onState(state: string): void;
  onEnd?(): void;
  onCameraStatus?(message: string | null): void;
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
  startedAt: string | null = null;
  private stoppedElapsed = 0;
  protected lastState = "";
  constructor(profiles: Profiles, public opts: SessionOptions, protected hooks: SessionHooks) {
    this.engine = new Engine(profiles, opts.sport, opts.handedness, opts.view, opts.focus, opts.player, opts.drill);
  }
  protected feed(t: number, joints: Joint[] | null, aspect: number) {
    const evs = this.engine.push(t, joints ?? new Array(13).fill(null), aspect);
    for (const ev of evs) this.hooks.onEvent(ev);
    if (this.engine.state !== this.lastState) {
      this.lastState = this.engine.state;
      this.hooks.onState(this.lastState);
    }
  }
  protected beginClock() {
    this.t0 = performance.now();
    this.startedAt = new Date().toISOString();
    this.stoppedElapsed = 0;
  }
  protected stopClock() {
    this.stoppedElapsed = this.elapsed;
    this.running = false;
  }
  get elapsed() { return !this.startedAt ? 0 : this.running ? (performance.now() - this.t0) / 1000 : this.stoppedElapsed; }
  abstract stop(): void;
}

/** Camera session. Counting starts when `beginCounting()` is called (after the setup check). */
export class CameraSession extends BaseSession {
  stream: MediaStream | null = null;
  private counting = false;
  private raf = 0;
  private lastVideoT = -1;
  /** The last few seconds of camera frames (small, memory only) for the last-rep card. */
  frames: Frame[] = [];
  private lastCapture = -1;

  private cancelled = false;
  private video: HTMLVideoElement | null = null;
  private removeListeners: (() => void)[] = [];

  async start(video: HTMLVideoElement, facingMode: "user" | "environment") {
    if (this.cancelled) return;
    this.video = video;
    // Observe rejection immediately, even if media permission rejects first.
    const pose = loadPose().then((pl) => ({ pl }), (error: unknown) => ({ error }));
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode, width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } },
      audio: false,
    });
    if (this.cancelled) {
      stream.getTracks().forEach((t) => t.stop());
      return;
    }
    this.stream = stream;
    video.srcObject = stream;
    video.muted = true;
    video.playsInline = true;
    await video.play();
    if (this.cancelled) return;
    const result = await pose;
    if (this.cancelled) return;
    if ("error" in result) throw result.error;
    const pl = result.pl;
    this.running = true;
    const listen = (target: EventTarget, event: string, handler: () => void) => {
      target.addEventListener(event, handler);
      this.removeListeners.push(() => target.removeEventListener(event, handler));
    };
    listen(video, "pause", () => { if (this.running) void this.resume(); });
    listen(video, "playing", () => {
      if (!stream.getVideoTracks().some((t) => t.muted)) this.hooks.onCameraStatus?.(null);
    });
    for (const track of stream.getVideoTracks()) {
      listen(track, "mute", () => {
        this.hooks.onCameraStatus?.("Camera interrupted. Tap Resume camera; if it stays interrupted, turn spoken tips off or end and try again.");
        void this.resume();
      });
      listen(track, "unmute", () => { void this.resume(); });
      listen(track, "ended", () => this.hooks.onCameraStatus?.("Camera disconnected. End the session and start again."));
    }
    const loop = () => {
      if (!this.running) return;
      this.raf = requestAnimationFrame(loop);
      if (video.paused || stream.getVideoTracks().some((t) => t.muted || t.readyState === "ended") ||
          video.readyState < 2 || video.currentTime === this.lastVideoT) return;
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
      if (this.counting) {
        const t = (now - this.t0) / 1000;
        if (t - this.lastCapture >= 0.12) this.capture(video, t);
        this.feed(t, joints, aspect);
      }
    };
    loop();
  }

  /** Can be called directly by the Resume camera tap if autoplay recovery is denied. */
  async resume() {
    if (this.cancelled || !this.video || !this.stream) return;
    try {
      await this.video.play();
      if (this.cancelled) return;
      const interrupted = this.stream?.getVideoTracks().some((t) => t.muted || t.readyState === "ended");
      this.hooks.onCameraStatus?.(interrupted ? "Camera interrupted. Resume camera or end and start again; spoken tips can be turned off." : null);
    } catch {
      if (!this.cancelled) this.hooks.onCameraStatus?.("Camera paused. Tap Resume camera to continue, or turn spoken tips off.");
    }
  }

  private capture(video: HTMLVideoElement, t: number) {
    this.lastCapture = t;
    const h = 240, w = Math.round((h * video.videoWidth) / Math.max(1, video.videoHeight));
    const old = this.frames.length >= 30 && t - this.frames[0].t > 3.5 ? this.frames.shift()! : null;
    const c = (old?.image as HTMLCanvasElement | undefined) ?? document.createElement("canvas");
    c.width = w; c.height = h;
    c.getContext("2d")!.drawImage(video, 0, 0, w, h);
    this.frames.push({ t, image: c, w, h });
    while (this.frames.length && t - this.frames[0].t > 3.5) this.frames.shift();
  }

  beginCounting() {
    if (this.cancelled || !this.running || this.counting) return;
    this.beginClock();
    this.counting = true;
  }

  get isCounting() { return this.counting; }

  stop() {
    this.cancelled = true;
    this.stopClock();
    cancelAnimationFrame(this.raf);
    this.removeListeners.splice(0).forEach((remove) => remove());
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
    if (this.video) this.video.srcObject = null;
    this.video = null;
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
    this.beginClock();
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
        this.stopClock();
        this.hooks.onEnd?.();
        return;
      }
      this.raf = requestAnimationFrame(loop);
    };
    loop();
  }
  get duration() {
    const f = this.rec.frames;
    return this.i > 0 ? f[this.i - 1].t - f[0].t : 0;
  }
  stop() {
    this.stopClock();
    cancelAnimationFrame(this.raf);
  }
}
