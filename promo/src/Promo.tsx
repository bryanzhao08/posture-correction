import React from "react";
import { AbsoluteFill, Audio, OffthreadVideo, Sequence, interpolate, staticFile, useCurrentFrame } from "remotion";
import {
  BEAT, BODY, Backdrop, Burst, C, Callout, Counter, DISPLAY, Flash, Label, Phone, Slam, Sweep, useIn, usePunch,
} from "./kit";

const S = (s: number) => Math.round(s * 30);

// ---------- 0-8 s: hook ----------
const Hook: React.FC = () => {
  const f = useCurrentFrame();
  const out = interpolate(f, [S(3.6), S(4)], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: out, transform: `scale(${usePunch(0)})` }}>
        <div style={{ display: "flex", gap: 40 }}>
          <Slam text="Every" at={0} size={210} />
          <Slam text="rep." at={BEAT} size={210} />
        </div>
        <div style={{ display: "flex", gap: 40, marginTop: 10 }}>
          <Slam text="Counted." at={BEAT * 2} size={210} color={C.cyan} split />
          <Slam text="Coached." at={BEAT * 4} size={210} color={C.red} split />
        </div>
      </AbsoluteFill>
      <Sequence from={S(4)}>
        <Problem />
      </Sequence>
    </AbsoluteFill>
  );
};

const Problem: React.FC = () => {
  const f = useCurrentFrame();
  const shake = f < 6 ? (f % 2 ? 6 : -6) : 0;
  return (
    <AbsoluteFill style={{ alignItems: "flex-start", justifyContent: "center", paddingLeft: 180, transform: `translateX(${shake}px)` }}>
      <Label color={C.red}>The problem</Label>
      <div style={{ height: 30 }} />
      <Slam text="Practising alone?" at={0} size={150} />
      <div style={{ height: 16 }} />
      <Slam text="You can't see your own form." at={S(1.4)} size={96} color={C.dim} />
      <div style={{ height: 16 }} />
      <Slam text="And your coach isn't always there." at={S(2.6)} size={96} color={C.dim} />
    </AbsoluteFill>
  );
};

// ---------- 8-12 s: logo reveal ----------
const Logo: React.FC = () => {
  const p = useIn(0, 11, 0.7);
  const tag = useIn(S(1.3), 16, 0.6);
  return (
    <AbsoluteFill>
      <Backdrop accent={C.red} accent2={C.cyan} />
      <Burst at={0} color={C.red} count={48} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 46, transform: `scale(${interpolate(p, [0, 1], [0.6, 1]) * usePunch(0, 0.015)})`, opacity: p }}>
          <div style={{
            width: 210, height: 210, borderRadius: 50, background: C.red, display: "flex", alignItems: "center", justifyContent: "center",
            boxShadow: `0 0 80px ${C.red}AA`, fontFamily: BODY, fontWeight: 800, fontSize: 118, color: "#fff", letterSpacing: -6,
          }}>FC</div>
          <Sweep at={8}>
            <div style={{ fontFamily: DISPLAY, fontSize: 230, color: C.white, letterSpacing: 4 }}>FORMCOACH</div>
          </Sweep>
        </div>
        <div style={{ marginTop: 40, opacity: tag, transform: `translateY(${interpolate(tag, [0, 1], [30, 0])}px)`, fontFamily: BODY, fontWeight: 600, fontSize: 52, color: C.dim }}>
          Your coach on a tripod.
        </div>
      </AbsoluteFill>
      <Flash at={0} />
    </AbsoluteFill>
  );
};

// ---------- 12-22 s: live session ----------
const Live: React.FC = () => {
  const f = useCurrentFrame();
  const enter = useIn(0, 14, 0.8);
  const tilt = interpolate(f, [0, S(10)], [-22, 12]);
  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill style={{ flexDirection: "row", alignItems: "center", paddingLeft: 170 }}>
        <div style={{ transform: `translateY(${interpolate(enter, [0, 1], [900, 0])}px)` }}>
          <Phone src={{ video: "clips/golf_session.mp4", startFrom: 3.5, rate: 2.1 }} height={900} tiltY={tilt} tiltX={4} />
        </div>
        <div style={{ marginLeft: 130, display: "flex", flexDirection: "column", gap: 34 }}>
          <Label>Live session</Label>
          <Slam text="Prop it up." at={S(0.4)} size={130} />
          <Slam text="Press start." at={S(1.2)} size={130} color={C.cyan} />
          <div style={{ height: 10 }} />
          <Callout at={S(3)} text="Tracks 13 joints, live, on-device" />
          <Callout at={S(4.6)} text="Counts only real swings — not waggles" color={C.red} />
          <Callout at={S(6.2)} text="A coaching cue after every rep" color={C.gold} />
        </div>
      </AbsoluteFill>
      <Flash at={0} />
    </AbsoluteFill>
  );
};

// ---------- 22-30 s: four sports ----------
const SPORTS = [
  { name: "Golf", clip: "clips/golf_session.mp4", from: 18.5, color: C.cyan },
  { name: "Basketball", clip: "clips/basketball_session.mp4", from: 6, color: C.red },
  { name: "Tennis", clip: "clips/tennis_session.mp4", from: 5.5, color: C.gold },
  { name: "Pickleball", clip: "clips/pickleball_session.mp4", from: 3.5, color: C.cyan },
];
const Montage: React.FC = () => {
  const f = useCurrentFrame();
  const seg = S(2);
  const i = Math.min(3, Math.floor(f / seg));
  const local = f - i * seg;
  const s = SPORTS[i];
  const slide = interpolate(local, [0, 8], [140, 0], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill>
      <Backdrop accent={s.color} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "row", gap: 120 }}>
        <div style={{ textAlign: "right", width: 820 }}>
          <Label color={s.color}>{`0${i + 1} / 04`}</Label>
          <Sequence from={i * seg} durationInFrames={seg} layout="none">
            <Slam text={s.name} at={0} size={150} color={C.white} split />
          </Sequence>
        </div>
        <div style={{ transform: `translateX(${slide}px) scale(${usePunch(0, 0.02)})` }}>
          <Sequence from={i * seg} durationInFrames={seg} layout="none">
            <Phone src={{ video: s.clip, startFrom: s.from, rate: 1.4 }} height={860} tiltY={-10} glow={s.color} />
          </Sequence>
        </div>
      </AbsoluteFill>
      <Flash at={0} len={6} />
      <Flash at={seg} len={6} />
      <Flash at={seg * 2} len={6} />
      <Flash at={seg * 3} len={6} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "flex-end", paddingBottom: 60 }}>
        <div style={{ fontFamily: BODY, fontWeight: 600, fontSize: 30, color: C.dim, letterSpacing: 4 }}>ONE APP · FOUR SPORTS · ONE TRIPOD</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// ---------- 30-38 s: scored against the pros ----------
const Bar: React.FC<{ at: number; label: string; you: string; value: number; color: string }> = ({ at, label, you, value, color }) => {
  const f = useCurrentFrame();
  const w = interpolate(f, [at, at + 24], [0, value], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const o = interpolate(f, [at - 4, at + 6], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <div style={{ opacity: o, width: 640 }}>
      <div style={{ display: "flex", justifyContent: "space-between", fontFamily: BODY, fontWeight: 600, fontSize: 30, color: C.white }}>
        <span>{label}</span><span style={{ color: C.dim }}>{you}</span>
      </div>
      <div style={{ height: 14, borderRadius: 7, background: "rgba(255,255,255,0.1)", marginTop: 12 }}>
        <div style={{ height: 14, borderRadius: 7, width: `${w}%`, background: color, boxShadow: `0 0 20px ${color}` }} />
      </div>
    </div>
  );
};
const Score: React.FC = () => {
  const f = useCurrentFrame();
  const swap = f > S(4);
  return (
    <AbsoluteFill>
      <Backdrop accent={C.gold} accent2={C.cyan} />
      <AbsoluteFill style={{ flexDirection: "row", alignItems: "center", paddingLeft: 170, gap: 120 }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 30 }}>
          <Label color={C.gold}>Every rep, scored</Label>
          <Slam text="Measured" at={0} size={140} />
          <Slam text="against the pros." at={S(0.5)} size={110} color={C.gold} />
          <div style={{ display: "flex", alignItems: "baseline", gap: 24, marginTop: 10 }}>
            <Counter at={S(1.2)} to={94} dur={36} style={{ fontFamily: DISPLAY, fontSize: 220, color: C.white, lineHeight: 1 }} />
            <span style={{ fontFamily: BODY, fontWeight: 600, fontSize: 34, color: C.dim }}>session score</span>
          </div>
          <Bar at={S(2.4)} label="Tempo" you="2.0 : 1" value={92} color={C.cyan} />
          <Bar at={S(3.0)} label="Lead arm at the top" you="176°" value={100} color={C.cyan} />
          <Bar at={S(3.6)} label="Shoulder turn" you="short" value={38} color={C.red} />
        </div>
        <Phone src={{ image: swap ? "clips/golf_summary2.png" : "clips/golf_summary.png" }} height={900} tiltY={-14} glow={C.gold} />
      </AbsoluteFill>
      <Flash at={0} />
      <Flash at={S(4)} len={5} color={C.gold} />
    </AbsoluteFill>
  );
};

// ---------- 38-45 s: hologram demos ----------
const HoloPanel: React.FC<{ clip: string; label: string; color: string; delay: number; tilt: number }> = ({ clip, label, color, delay, tilt }) => {
  const f = useCurrentFrame();
  const p = useIn(delay, 14, 0.7);
  const W = 520, H = 640;
  const scan = (f * 4) % (H + 120) - 60;
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 22, opacity: p,
      transform: `perspective(1800px) rotateY(${tilt * (1 - 0.4 * p)}deg) translateY(${interpolate(p, [0, 1], [260, 0])}px)` }}>
      <div style={{ width: W, height: H, borderRadius: 36, overflow: "hidden", position: "relative", background: "#030608",
        border: `2px solid ${color}AA`, boxShadow: `0 0 80px ${color}55, inset 0 0 60px ${color}33` }}>
        <div style={{ position: "absolute", left: (W - W * 1.75) / 2, top: -H * 0.62, width: W * 1.75 }}>
          <Phoneless clip={clip} width={W * 1.75} />
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, top: scan, height: 60, background: `linear-gradient(180deg, transparent, ${color}30, transparent)` }} />
        <div style={{ position: "absolute", inset: 0, backgroundImage: `repeating-linear-gradient(0deg, ${color}12 0px, ${color}12 1px, transparent 2px, transparent 5px)` }} />
      </div>
      <div style={{ fontFamily: BODY, fontWeight: 800, fontSize: 44, color, letterSpacing: 3, textShadow: `0 0 24px ${color}` }}>{label}</div>
    </div>
  );
};
const Phoneless: React.FC<{ clip: string; width: number }> = ({ clip, width }) => (
  <OffthreadVideo src={staticFile(clip)} startFrom={30} muted style={{ width, filter: "saturate(1.5) brightness(1.25)" }} />
);
const Holo: React.FC = () => (
  <AbsoluteFill>
    <Backdrop accent={C.cyan} accent2="#FF8A3D" />
    <AbsoluteFill style={{ alignItems: "center", paddingTop: 60 }}>
      <Label>Show me</Label>
      <div style={{ display: "flex", gap: 30, marginTop: 16 }}>
        <Slam text="Don't get it?" at={0} size={110} />
        <Slam text="See it." at={S(0.6)} size={110} color={C.cyan} split />
      </div>
    </AbsoluteFill>
    <AbsoluteFill style={{ flexDirection: "row", alignItems: "flex-end", justifyContent: "center", gap: 120, paddingBottom: 50 }}>
      <HoloPanel clip="clips/golf_holo_wrong.mp4" label="✕  WRONG" color="#FF8A3D" delay={S(0.9)} tilt={18} />
      <HoloPanel clip="clips/golf_holo_correct.mp4" label="✓  RIGHT" color={C.cyan} delay={S(1.3)} tilt={-18} />
    </AbsoluteFill>
    <Flash at={0} />
  </AbsoluteFill>
);

// ---------- 45-51 s: progress + email ----------
const Progress: React.FC = () => {
  const mail = useIn(S(1.6), 13, 0.6);
  const mail2 = useIn(S(3.2), 13, 0.6);
  const Card: React.FC<{ p: number; title: string; body: string; y: number }> = ({ p, title, body, y }) => (
    <div style={{
      width: 720, padding: "28px 34px", borderRadius: 30, background: "rgba(245,247,250,0.94)", color: "#0B0D10",
      boxShadow: "0 30px 80px rgba(0,0,0,0.5)", transform: `translateX(${interpolate(p, [0, 1], [900, 0])}px) translateY(${y}px)`, opacity: p,
      fontFamily: BODY,
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 14, fontSize: 24, color: "#5A6270", fontWeight: 600 }}>
        <span style={{ width: 40, height: 40, borderRadius: 10, background: C.red, color: "#fff", display: "inline-flex", alignItems: "center", justifyContent: "center", fontWeight: 800, fontSize: 18 }}>FC</span>
        FormCoach · now
      </div>
      <div style={{ fontSize: 34, fontWeight: 800, marginTop: 12 }}>{title}</div>
      <div style={{ fontSize: 26, color: "#3A4250", marginTop: 6 }}>{body}</div>
    </div>
  );
  return (
    <AbsoluteFill>
      <Backdrop accent={C.cyan} accent2={C.red} />
      <AbsoluteFill style={{ flexDirection: "row", alignItems: "center", paddingLeft: 170, gap: 110 }}>
        <Phone src={{ image: "clips/golf_history.png" }} height={900} tiltY={18} />
        <div style={{ display: "flex", flexDirection: "column", gap: 26 }}>
          <Label>Progress</Label>
          <Slam text="Watch it" at={0} size={140} />
          <Slam text="add up." at={S(0.4)} size={140} color={C.cyan} split />
          <Card p={mail} y={0} title="Your latest Golf session score: 94" body="Up 6 on your average. Next: rotate your back to the target." />
          <Card p={mail2} y={0} title="Checkpoint 2 reached" body="5 more sessions done. Your block average: 88 → 94." />
        </div>
      </AbsoluteFill>
      <Flash at={0} />
    </AbsoluteFill>
  );
};

// ---------- 51-56 s: proof ----------
const Proof: React.FC = () => {
  const stats = [
    { to: 1800, suffix: "+", label: "real swings & shots\ntested", color: C.cyan, at: 0 },
    { to: 97, suffix: "%", label: "of pro golf swings\ndetected", color: C.gold, at: 10 },
    { to: 98, suffix: "%", label: "of free throws\ncounted exactly once", color: C.red, at: 20 },
  ];
  return (
    <AbsoluteFill>
      <Backdrop accent={C.gold} accent2={C.cyan} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        <Label color={C.gold}>Validated on real data</Label>
        <div style={{ display: "flex", gap: 120, marginTop: 50 }}>
          {stats.map((s, i) => (
            <div key={i} style={{ textAlign: "center", width: 440 }}>
              <Counter at={s.at} to={s.to} dur={34} suffix={s.suffix} style={{ fontFamily: DISPLAY, fontSize: 190, color: s.color, textShadow: `0 0 40px ${s.color}66` }} />
              <div style={{ fontFamily: BODY, fontWeight: 600, fontSize: 34, color: C.white, whiteSpace: "pre-line", marginTop: 6 }}>{s.label}</div>
            </div>
          ))}
        </div>
      </AbsoluteFill>
      <Flash at={0} len={10} color={C.gold} />
    </AbsoluteFill>
  );
};

// ---------- 56-60 s: end card ----------
const End: React.FC = () => {
  const p = useIn(0, 12, 0.7);
  const sub = useIn(S(0.8), 16, 0.6);
  return (
    <AbsoluteFill>
      <Backdrop accent={C.red} accent2={C.cyan} />
      <Burst at={0} color={C.cyan} count={56} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 40, opacity: p, transform: `scale(${interpolate(p, [0, 1], [1.3, 1])})` }}>
          <div style={{ width: 170, height: 170, borderRadius: 40, background: C.red, display: "flex", alignItems: "center", justifyContent: "center", boxShadow: `0 0 70px ${C.red}AA`, fontFamily: BODY, fontWeight: 800, fontSize: 96, color: "#fff", letterSpacing: -5 }}>FC</div>
          <Sweep at={6}><div style={{ fontFamily: DISPLAY, fontSize: 190, color: C.white, letterSpacing: 4 }}>FORMCOACH</div></Sweep>
        </div>
        <div style={{ opacity: sub, transform: `translateY(${interpolate(sub, [0, 1], [24, 0])}px)`, textAlign: "center", marginTop: 34 }}>
          <div style={{ fontFamily: BODY, fontWeight: 600, fontSize: 48, color: C.white }}>Your coach on a tripod.</div>
          <div style={{ fontFamily: BODY, fontWeight: 600, fontSize: 30, color: C.dim, letterSpacing: 6, marginTop: 22 }}>GOLF · BASKETBALL · TENNIS · PICKLEBALL</div>
          <div style={{ display: "inline-block", marginTop: 40, padding: "18px 44px", borderRadius: 999, border: `2px solid ${C.cyan}`, fontFamily: BODY, fontWeight: 800, fontSize: 32, color: C.cyan, letterSpacing: 3 }}>COMING SOON ON IPHONE</div>
        </div>
      </AbsoluteFill>
      <Flash at={0} len={10} />
    </AbsoluteFill>
  );
};

export const Promo: React.FC = () => (
  <AbsoluteFill style={{ background: C.ink }}>
    <Audio src={staticFile("music.wav")} />
    <Sequence from={0} durationInFrames={S(8)}><Hook /></Sequence>
    <Sequence from={S(8)} durationInFrames={S(4)}><Logo /></Sequence>
    <Sequence from={S(12)} durationInFrames={S(10)}><Live /></Sequence>
    <Sequence from={S(22)} durationInFrames={S(8)}><Montage /></Sequence>
    <Sequence from={S(30)} durationInFrames={S(8)}><Score /></Sequence>
    <Sequence from={S(38)} durationInFrames={S(7)}><Holo /></Sequence>
    <Sequence from={S(45)} durationInFrames={S(6)}><Progress /></Sequence>
    <Sequence from={S(51)} durationInFrames={S(5)}><Proof /></Sequence>
    <Sequence from={S(56)} durationInFrames={S(4)}><End /></Sequence>
  </AbsoluteFill>
);

