import React from "react";
import {
  AbsoluteFill, Easing, Img, OffthreadVideo, interpolate, random, spring, staticFile, useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { loadFont as loadAnton } from "@remotion/google-fonts/Anton";
import { loadFont as loadInter } from "@remotion/google-fonts/Inter";

export const DISPLAY = loadAnton().fontFamily;
export const BODY = loadInter("normal", { weights: ["400", "600", "800"], subsets: ["latin"] }).fontFamily;

export const C = {
  ink: "#05070A",
  cyan: "#3DF2FF",
  red: "#FF3B4E",
  gold: "#F5C46B",
  white: "#F4F7FA",
  dim: "rgba(244,247,250,0.62)",
};

export const BEAT = 15; // frames per beat at 120 BPM, 30 fps

/** Spring 0 -> 1 starting at `at` frames. */
export const useIn = (at = 0, damping = 14, mass = 0.6) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: f - at, fps, config: { damping, mass, stiffness: 160 } });
};

/** Animated dark backdrop: drifting colour glows, grain and vignette. */
export const Backdrop: React.FC<{ accent?: string; accent2?: string }> = ({ accent = C.cyan, accent2 = C.red }) => {
  const f = useCurrentFrame();
  const x1 = 30 + 12 * Math.sin(f / 70);
  const y1 = 35 + 10 * Math.cos(f / 90);
  const x2 = 72 + 10 * Math.cos(f / 80);
  const y2 = 68 + 12 * Math.sin(f / 65);
  return (
    <AbsoluteFill style={{ background: C.ink }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(circle at ${x1}% ${y1}%, ${accent}33 0%, transparent 42%),
                       radial-gradient(circle at ${x2}% ${y2}%, ${accent2}2A 0%, transparent 40%)`,
        }}
      />
      <AbsoluteFill
        style={{
          backgroundImage:
            "linear-gradient(rgba(255,255,255,0.035) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.035) 1px, transparent 1px)",
          backgroundSize: "80px 80px",
          backgroundPosition: `${(f * 0.6) % 80}px ${(f * 0.3) % 80}px`,
          maskImage: "radial-gradient(circle at 50% 50%, black 0%, transparent 75%)",
        }}
      />
      <Grain />
      <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 50%, transparent 55%, rgba(0,0,0,0.75) 100%)" }} />
    </AbsoluteFill>
  );
};

export const Grain: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ opacity: 0.09, mixBlendMode: "overlay" }}>
      <svg width="100%" height="100%">
        <filter id="g">
          <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves={2} seed={f % 7} />
        </filter>
        <rect width="100%" height="100%" filter="url(#g)" />
      </svg>
    </AbsoluteFill>
  );
};

/** Big display word that slams in (scale + blur + fade) with an optional RGB split. */
export const Slam: React.FC<{
  text: string; at: number; size: number; color?: string; split?: boolean; style?: React.CSSProperties;
}> = ({ text, at, size, color = C.white, split = false, style }) => {
  const f = useCurrentFrame();
  const p = useIn(at, 12, 0.5);
  if (f < at) return null;
  const scale = interpolate(p, [0, 1], [1.6, 1]);
  const blur = interpolate(p, [0, 1], [18, 0]);
  const off = split ? interpolate(f - at, [0, 10], [14, 2], { extrapolateRight: "clamp" }) : 0;
  const base: React.CSSProperties = {
    fontFamily: DISPLAY, fontSize: size, lineHeight: 0.95, letterSpacing: 2, textTransform: "uppercase",
    transform: `scale(${scale})`, filter: `blur(${blur}px)`, opacity: Math.min(1, p * 1.4), whiteSpace: "nowrap",
    ...style,
  };
  return (
    <div style={{ position: "relative", display: "inline-block" }}>
      {split && <div style={{ ...base, color: C.cyan, position: "absolute", left: -off, top: 0, mixBlendMode: "screen", opacity: 0.8 * Math.min(1, p) }}>{text}</div>}
      {split && <div style={{ ...base, color: C.red, position: "absolute", left: off, top: 0, mixBlendMode: "screen", opacity: 0.8 * Math.min(1, p) }}>{text}</div>}
      <div style={{ ...base, color }}>{text}</div>
    </div>
  );
};

/** White flash on a cut. */
export const Flash: React.FC<{ at: number; len?: number; color?: string }> = ({ at, len = 8, color = "#fff" }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [at, at + 1, at + len], [0, 0.85, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return <AbsoluteFill style={{ background: color, opacity: o, pointerEvents: "none" }} />;
};

/** Zoom punch on every beat, for energy. */
export const usePunch = (start: number, strength = 0.025) => {
  const f = useCurrentFrame();
  const t = (f - start) % BEAT;
  return 1 + strength * Math.exp(-t / 3);
};

type ScreenSrc = { video?: string; image?: string; startFrom?: number; rate?: number; scrollTo?: number; scrollFrames?: number };

/** iPhone-style device with a live screen, optional 3D tilt. */
export const Phone: React.FC<{
  src: ScreenSrc; height: number; tiltY?: number; tiltX?: number; glow?: string; style?: React.CSSProperties;
}> = ({ src, height, tiltY = 0, tiltX = 0, glow = C.cyan, style }) => {
  const f = useCurrentFrame();
  const width = height * 0.4602;
  const bezel = height * 0.018;
  const radius = height * 0.085;
  const scroll = src.scrollTo
    ? interpolate(f, [0, src.scrollFrames ?? 90], [0, src.scrollTo], { extrapolateRight: "clamp", easing: Easing.inOut(Easing.cubic) })
    : 0;
  return (
    <div style={{ perspective: 2200, ...style }}>
      <div
        style={{
          width, height, borderRadius: radius, background: "#0B0D10", padding: bezel, boxSizing: "border-box",
          transform: `rotateY(${tiltY}deg) rotateX(${tiltX}deg)`,
          boxShadow: `0 0 0 2px #2A2E35, 0 0 0 ${bezel * 0.35}px #15181D, 0 40px 120px rgba(0,0,0,0.65), 0 0 90px ${glow}40`,
        }}
      >
        <div style={{ width: "100%", height: "100%", borderRadius: radius - bezel, overflow: "hidden", position: "relative", background: "#000" }}>
          {src.video && (
            <OffthreadVideo src={staticFile(src.video)} startFrom={Math.round((src.startFrom ?? 0) * 30)} playbackRate={src.rate ?? 1}
              muted style={{ width: "100%", height: "100%", objectFit: "cover" }} />
          )}
          {src.image && (
            <Img src={staticFile(src.image)} style={{ width: "100%", position: "absolute", top: -scroll * height }} />
          )}
          <div style={{ position: "absolute", inset: 0, background: "linear-gradient(120deg, rgba(255,255,255,0.10) 0%, transparent 35%)" }} />
        </div>
      </div>
    </div>
  );
};

/** Pill callout that slides in. */
export const Callout: React.FC<{ at: number; text: string; color?: string; style?: React.CSSProperties }> = ({ at, text, color = C.cyan, style }) => {
  const f = useCurrentFrame();
  const p = useIn(at, 13, 0.5);
  if (f < at) return null;
  return (
    <div
      style={{
        display: "inline-flex", alignItems: "center", gap: 16, padding: "18px 30px", borderRadius: 999,
        background: "rgba(10,14,20,0.72)", border: `1.5px solid ${color}88`, backdropFilter: "blur(8px)",
        boxShadow: `0 0 40px ${color}33`, transform: `translateX(${interpolate(p, [0, 1], [60, 0])}px)`, opacity: p,
        fontFamily: BODY, fontWeight: 600, fontSize: 34, color: C.white, whiteSpace: "nowrap", ...style,
      }}
    >
      <span style={{ width: 14, height: 14, borderRadius: 7, background: color, boxShadow: `0 0 14px ${color}` }} />
      {text}
    </div>
  );
};

/** Number that counts up. */
export const Counter: React.FC<{ at: number; to: number; dur?: number; suffix?: string; decimals?: number; style?: React.CSSProperties }> = ({
  at, to, dur = 30, suffix = "", decimals = 0, style,
}) => {
  const f = useCurrentFrame();
  const v = interpolate(f, [at, at + dur], [0, to], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
  const s = decimals ? v.toFixed(decimals) : Math.round(v).toLocaleString("en-US");
  return <span style={style}>{s}{suffix}</span>;
};

/** Diagonal light sweep across its children. */
export const Sweep: React.FC<{ at: number; children: React.ReactNode }> = ({ at, children }) => {
  const f = useCurrentFrame();
  const x = interpolate(f, [at, at + 24], [-60, 160], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <div style={{ position: "relative", display: "inline-block" }}>
      {children}
      <div
        style={{
          position: "absolute", inset: 0, pointerEvents: "none", mixBlendMode: "overlay",
          background: `linear-gradient(105deg, transparent ${x - 20}%, rgba(255,255,255,0.95) ${x}%, transparent ${x + 20}%)`,
        }}
      />
    </div>
  );
};

/** Sparks that burst outward from the centre at `at`. */
export const Burst: React.FC<{ at: number; color?: string; count?: number }> = ({ at, color = C.cyan, count = 40 }) => {
  const f = useCurrentFrame();
  const t = f - at;
  if (t < 0 || t > 40) return null;
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", pointerEvents: "none" }}>
      {new Array(count).fill(0).map((_, i) => {
        const a = random(`a${i}${at}`) * Math.PI * 2;
        const sp = 8 + random(`s${i}${at}`) * 22;
        const d = sp * t * (1 - t / 80);
        const o = interpolate(t, [0, 30, 40], [1, 0.6, 0]);
        return (
          <div key={i} style={{
            position: "absolute", width: 4, height: 18 + random(`l${i}`) * 30, borderRadius: 2, background: color, opacity: o,
            boxShadow: `0 0 12px ${color}`, transform: `translate(${Math.cos(a) * d}px, ${Math.sin(a) * d}px) rotate(${a + Math.PI / 2}rad)`,
          }} />
        );
      })}
    </AbsoluteFill>
  );
};

export const Label: React.FC<{ children: React.ReactNode; color?: string; style?: React.CSSProperties }> = ({ children, color = C.cyan, style }) => (
  <div style={{ fontFamily: BODY, fontWeight: 800, fontSize: 26, letterSpacing: 8, color, textTransform: "uppercase", ...style }}>{children}</div>
);
