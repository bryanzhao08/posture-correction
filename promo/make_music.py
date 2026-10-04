"""Synthesize an original 60 s, 120 BPM promo track (no samples, no licensing).

Bars are 2 s (one bar = 60 video frames at 30 fps). Section changes land on the scene cuts in
src/Promo.tsx: impacts at 8 s, 12 s, 22 s, 30 s, 38 s, 45 s, 51 s, 56 s.
"""
import numpy as np
import wave

SR = 44100
BPM = 120
BEAT = 60 / BPM
DUR = 60.0
N = int(SR * DUR)
rng = np.random.default_rng(7)
mix = np.zeros((N, 2))


def add(sig, t, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i >= N:
        return
    sig = sig[: N - i] * gain
    l, r = np.sqrt(0.5 * (1 - pan)), np.sqrt(0.5 * (1 + pan))
    mix[i:i + len(sig), 0] += sig * l
    mix[i:i + len(sig), 1] += sig * r


def env(n, a, d):
    e = np.ones(n)
    na = max(1, int(a * SR))
    e[:na] = np.linspace(0, 1, na)
    e[na:] = np.exp(-np.arange(n - na) / (d * SR))
    return e


def kick(level=1.0):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * env(n, 0.002, 0.16)
    click = rng.standard_normal(n) * env(n, 0.0005, 0.004) * 0.3
    return np.tanh((s + click) * 1.6) * level


def clap():
    n = int(0.3 * SR)
    noise = rng.standard_normal(n)
    e = np.zeros(n)
    for k, off in enumerate((0, 0.011, 0.022)):
        i = int(off * SR)
        e[i:] += np.exp(-np.arange(n - i) / (0.012 * SR if k < 2 else 0.09 * SR))
    s = noise * e
    # crude band-pass: difference of moving averages
    s = np.convolve(s, np.ones(3) / 3, "same") - np.convolve(s, np.ones(40) / 40, "same")
    return s * 0.55


def hat(open_=False):
    n = int((0.18 if open_ else 0.05) * SR)
    s = rng.standard_normal(n)
    s = s - np.convolve(s, np.ones(6) / 6, "same")
    return s * env(n, 0.001, 0.06 if open_ else 0.012) * 0.22


def bass(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    saw = 2 * ((t * freq) % 1) - 1
    sub = np.sin(2 * np.pi * freq / 2 * t)
    s = 0.55 * saw + 0.7 * sub
    s = np.convolve(s, np.ones(18) / 18, "same")      # soften
    return np.tanh(s * 1.4) * env(n, 0.004, dur * 0.7) * 0.42


def pad(freqs, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) + 0.3 * np.sin(2 * np.pi * f * 2.003 * t) for f in freqs)
    a = np.minimum(1, t / 0.4) * np.minimum(1, (dur - t) / 0.4)
    return s * a * 0.05


def riser(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    noise = noise - np.convolve(noise, np.ones(int(30 - 26 * 1)) / 4, "same") * 0
    sweep = np.sin(2 * np.pi * np.cumsum(200 + 1800 * (t / dur) ** 2) / SR)
    return (noise * 0.25 + sweep * 0.15) * (t / dur) ** 2 * 0.6


def impact():
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    boom = np.sin(2 * np.pi * np.cumsum(70 * np.exp(-t * 3) + 30) / SR) * env(n, 0.001, 0.5)
    crash = rng.standard_normal(n) * env(n, 0.001, 0.35) * 0.35
    return np.tanh((boom + crash) * 1.3) * 0.9


def whoosh(dur=0.45):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = rng.standard_normal(n)
    s = np.convolve(s, np.ones(8) / 8, "same")
    return s * np.sin(np.pi * t / dur) ** 2 * 0.35


# A minor: Am - F - C - G (one chord per bar)
ROOTS = [55.0, 43.65, 65.41, 49.0]
CHORDS = [[220, 261.6, 329.6], [174.6, 220, 261.6], [261.6, 329.6, 392], [196, 246.9, 293.7]]
IMPACTS = [8, 12, 22, 30, 38, 45, 51, 56]

for bar in range(30):
    t0 = bar * 2.0
    root = ROOTS[bar % 4]
    intro = t0 < 8          # sparse: kick on 1 only, filtered pad
    breakdown = 51 <= t0 < 56
    outro = t0 >= 56
    add(pad(CHORDS[bar % 4], 2.0), t0, 1.4 if intro or breakdown else 1.0)
    for b in range(4):
        tb = t0 + b * BEAT
        if outro and b > 0:
            continue
        if intro:
            if b == 0:
                add(kick(0.8), tb)
            add(hat(), tb + BEAT / 2, 0.6, 0.3)
            continue
        if breakdown:
            add(hat(), tb + BEAT / 2, 0.7, -0.3)
            continue
        add(kick(), tb)
        if b in (1, 3):
            add(clap(), tb, 1.0, 0.1)
        add(hat(), tb + BEAT / 2, 1.0, 0.35)
        add(hat(), tb + BEAT / 4, 0.45, -0.35)
        if b == 3 and bar % 2 == 1:
            add(hat(True), tb + BEAT * 0.75, 0.8, 0.2)
        for k in range(2):  # 8th-note bass
            add(bass(root * (2 if k == 1 and b == 2 else 1), BEAT / 2), tb + k * BEAT / 2)

for t in IMPACTS:
    add(riser(1.5), t - 1.5, 1.0)
    add(impact(), t, 1.0)
for t in (2, 4, 6, 14, 16, 18, 20, 24, 26, 28, 32, 34, 40, 42, 47, 49):
    add(whoosh(), t - 0.2, 0.8, rng.uniform(-0.6, 0.6))

# fades, gentle master compression, normalise
fade = np.ones(N)
fade[: int(0.05 * SR)] = np.linspace(0, 1, int(0.05 * SR))
fade[-int(2.5 * SR):] = np.linspace(1, 0, int(2.5 * SR)) ** 1.5
mix *= fade[:, None]
mix = np.tanh(mix * 1.1)
mix /= np.max(np.abs(mix)) * 1.12
pcm = (mix * 32767).astype(np.int16)
with wave.open("public/music.wav", "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("wrote public/music.wav", round(N / SR, 2), "s")
