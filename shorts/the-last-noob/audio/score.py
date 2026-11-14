# Original synthesized score + SFX + final mix for "The Last Noob" (numpy/scipy only, no samples, no services).
# Event times mirror src/story.ts (all keyed to voice/lines.json). Music ducks under the narration (key = word times).
# Writes public/audio/mix.wav (48 kHz stereo, exact video length) and audio/cues.md.
# Usage: python audio/score.py
import json
import os
import subprocess

import numpy as np
from scipy import signal

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SR = 48000
FPS = 30
L = json.load(open(os.path.join(ROOT, "voice", "lines.json")))
TOTAL = int(np.ceil(L["duration"] * FPS))
DUR = TOTAL / FPS
N = int(DUR * SR)
LN = {l["id"]: l for l in L["lines"]}
W = lambda i, k=0: LN[i]["words"][min(k, len(LN[i]["words"]) - 1)]["s"] - 2 / FPS
rng = np.random.default_rng(7)

# ---------------------------------------------------------------- event times (story.ts)
SLAM1 = 0.62
KNOCKS = [W("hook2", 2) + d for d in (0, 0.26, 0.5)]
FLASH = (round(W("night") * FPS) - 3) / FPS
SLAM2 = W("nonoobs", 5) + 0.12
CREAK0, CREAK1 = W("creak", 2), W("creak", 5)
DECOY0, DECOY1 = W("creak", 5) - 0.5, W("wait", 2)
NO_SHADOW = W("wait", 10)
WALL_MOVE = W("wall", 13)
BAIT = W("yousee", 9)
LANTERN = W("lantern", 8)
GLITCH0, GLITCH1 = W("reveal", 8), W("reveal", 10)
KICK = W("door", 1)
RUN = W("door", 6)
DAWN0 = W("escape", 0)
MELT = W("escape", 8)
WELCOME = W("welcome", 0)
TWIST = W("twist", 2)
GHOST = W("twist", 5)
SHADOWS = W("twist", 11)


def t_(d):
    return np.arange(int(d * SR)) / SR


def env(n, a=0.005, r=0.2):
    e = np.ones(n)
    na, nr = min(n // 2, int(a * SR)), min(n // 2, int(r * SR))
    if na: e[:na] = np.linspace(0, 1, na)
    if nr: e[-nr:] *= np.linspace(1, 0, nr)
    return e


def lp(x, f, o=2):
    return signal.sosfilt(signal.butter(o, f, "low", fs=SR, output="sos"), x)


def hp(x, f, o=2):
    return signal.sosfilt(signal.butter(o, f, "high", fs=SR, output="sos"), x)


def bp(x, a, b, o=2):
    return signal.sosfilt(signal.butter(o, [a, b], "band", fs=SR, output="sos"), x)


def place(buf, x, t, g=1.0, pan=0.0):
    i = int(t * SR)
    if i >= N: return
    x = x[: N - i]
    buf[0, i:i + len(x)] += x * g * np.sqrt(0.5 * (1 - pan))
    buf[1, i:i + len(x)] += x * g * np.sqrt(0.5 * (1 + pan))


def m2f(m):
    return 440 * 2 ** ((m - 69) / 12)


# ---------------------------------------------------------------- instruments
def pad(freqs, d, att=1.2, rel=1.5, bright=900, det=0.004):
    t = t_(d)
    x = np.zeros_like(t)
    for f in freqs:
        for dd in (-det, 0, det):
            ph = rng.random() * 6.28
            x += signal.sawtooth(2 * np.pi * f * (1 + dd) * t + ph) * 0.3
    x = lp(x, bright, 2)
    return x * env(len(t), att, rel) / len(freqs)


def drone(f, d, wob=0.15):
    t = t_(d)
    x = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.003 * t) + 0.25 * np.sin(2 * np.pi * f * 3.01 * t)
    x *= 1 + wob * np.sin(2 * np.pi * 0.23 * t)
    return x * env(len(t), 1.5, 1.5) * 0.4


def heartbeat(d, bpm):
    out = np.zeros(int(d * SR))
    k = t_(0.18)
    thump = np.sin(2 * np.pi * (55 - 20 * k / 0.18) * k) * np.exp(-k * 28)
    per = 60 / bpm
    tt = 0.0
    while tt < d - 0.4:
        for off, g in ((0, 1.0), (0.22, 0.7)):
            i = int((tt + off) * SR)
            out[i:i + len(thump)] += thump[: len(out) - i] * g
        tt += per
    return out


def bell(f, d=2.5, v=0.6):
    t = t_(d)
    x = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * dec) for r, a, dec in ((1, 1, 1.6), (2.76, 0.4, 3.5), (5.4, 0.2, 6), (0.5, 0.3, 1.2)))
    return x * v * env(len(t), 0.002, 0.3)


def pluck(f, d=1.2, v=0.6):
    n = int(d * SR)
    p = int(SR / f)
    buf = rng.uniform(-1, 1, p)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = 0.5 * (buf[i % p] + buf[(i + 1) % p]) * 0.996
    return lp(out, 3500) * v


# ---------------------------------------------------------------- sfx
def noise(d):
    return rng.standard_normal(int(d * SR))


def thud(f=70, d=0.45, v=1.0, click=0.3):
    t = t_(d)
    x = np.sin(2 * np.pi * (f + 60 * np.exp(-t * 30)) * t) * np.exp(-t * 9)
    x += lp(noise(d), 1800) * np.exp(-t * 40) * click
    return x * v


def knock(v=1.0):
    t = t_(0.25)
    body = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * dec) for f, dec in ((180, 30), (420, 45), (760, 60)))
    return (body * 0.5 + bp(noise(0.25), 400, 3000) * np.exp(-t * 70) * 0.6) * v


def slam(v=1.0):
    x = thud(60, 0.8, 1.0, 0.8)
    x[: int(0.25 * SR)] += knock(1.0)
    rt = t_(0.8)
    x += bp(noise(0.8), 120, 900) * np.exp(-rt * 6) * 0.3  # rattle of the frame
    return x * v


def creak(d, f0=180, f1=320, v=0.5):
    t = t_(d)
    f = np.linspace(f0, f1, len(t)) * (1 + 0.08 * np.sin(2 * np.pi * 3.1 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    pulses = (np.sin(ph) > 0.96).astype(float)  # stick-slip
    x = lp(pulses, 4000)
    for fr in (420, 950, 1700):
        x = x + bp(pulses, fr * 0.9, fr * 1.1) * 0.6
    return x * env(len(t), 0.05, 0.3) * v


def wind(d, v=0.3):
    x = lp(noise(d), 600) + bp(noise(d), 700, 1400) * 0.2 * (1 + np.sin(2 * np.pi * 0.17 * t_(d)))
    return x * env(len(x), 1.5, 1.5) * v


def crickets(d, v=0.05):
    t = t_(d)
    gate = (np.sin(2 * np.pi * 14 * t) > 0.3) * (np.sin(2 * np.pi * 0.7 * t) > -0.2)
    return np.sin(2 * np.pi * 4300 * t) * gate * v * env(len(t), 0.5, 0.5)


def whoosh_up(d=0.7, v=0.6):
    t = t_(d)
    x = bp(noise(d), 300, 5000) * (t / d) ** 2
    x += np.sin(2 * np.pi * np.cumsum(np.linspace(300, 1800, len(t))) / SR) * (t / d) ** 3 * 0.3
    return x * v


def shimmer(d=2.0, v=0.4):
    x = sum(bell(m2f(m), d, 0.3) for m in (84, 88, 91, 96))
    return x * v


def glitch(d, v=0.5):
    n = int(d * SR)
    x = np.zeros(n)
    i = 0
    while i < n:
        seg = int(rng.uniform(0.02, 0.08) * SR)
        f = rng.uniform(200, 1600)
        tt = np.arange(min(seg, n - i)) / SR
        x[i:i + len(tt)] = np.sign(np.sin(2 * np.pi * f * tt)) * (rng.random() < 0.7) * 0.5
        i += seg + int(rng.uniform(0, 0.05) * SR)
    return lp(x, 6000) * v


def crash(v=1.0):
    x = thud(55, 1.2, 1.2, 1.0)
    t = t_(1.2)
    x += bp(noise(1.2), 200, 4000) * np.exp(-t * 5) * 0.6
    for k in range(6):  # splinters
        s = bp(noise(0.08), 1500, 6000) * np.exp(-t_(0.08) * 50)
        j = int(rng.uniform(0.02, 0.4) * SR)
        x[j:j + len(s)] += s * 0.4
    return x * v


def step(v=0.4):
    t = t_(0.12)
    return (lp(noise(0.12), 900) * np.exp(-t * 45) + np.sin(2 * np.pi * 90 * t) * np.exp(-t * 35) * 0.5) * v


def melt(d=1.5, v=0.5):
    t = t_(d)
    f = np.linspace(300, 60, len(t))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.1, 0.6)
    return (x + lp(noise(d), 500) * 0.4 * env(len(t), 0.2, 0.8)) * v


def sting(v=0.8):
    t = t_(3.0)
    x = sum(np.sin(2 * np.pi * f * t) for f in (m2f(45), m2f(46), m2f(57), m2f(58.2)))
    x = x * np.exp(-t * 0.9) * 0.3
    x[: int(2.0 * SR)] += thud(45, 2.0, 1.2, 0.2)
    return x * v


# ---------------------------------------------------------------- build stems
music = np.zeros((2, N))
sfx = np.zeros((2, N))
cues = []


def cue(kind, name, t, x, g, pan=0.0):
    place(music if kind == "music" else sfx, x, t, g, pan)
    cues.append((t, kind, name))


night_end = DAWN0
# night bed: A-minor drone + dark pad, rising tension; heartbeat from the decoy reveal to the lantern
cue("music", "drone A1", 0.0, drone(m2f(33), night_end + 1.0), 0.55)
cue("music", "pad Am(add9)", FLASH, pad([m2f(57), m2f(60), m2f(64), m2f(71)], CREAK0 - FLASH + 1.0, bright=700), 0.5)
cue("music", "pad tension Bb/A", CREAK0, pad([m2f(57), m2f(58), m2f(64), m2f(70)], WALL_MOVE - CREAK0 + 0.5, bright=1100), 0.55)
cue("music", "pad dread F#dim", WALL_MOVE - 0.3, pad([m2f(54), m2f(57), m2f(60), m2f(63)], LANTERN - WALL_MOVE + 0.6, bright=1300), 0.6)
cue("music", "heartbeat", DECOY0 + 1.0, heartbeat(LANTERN - DECOY0 - 1.0, 70), 0.5)
cue("music", "heartbeat fast", LANTERN, heartbeat(DAWN0 - LANTERN, 112), 0.55)
# music-box motif (original): Noob's theme, sad at the gate, hopeful at dawn
theme = [69, 72, 76, 74, 72, 71, 72, 69]
for i, m in enumerate(theme):
    cue("music", f"theme gate {i}", W("gate", 1) + i * 0.38, bell(m2f(m + 12), 2.0, 0.35), 0.5, -0.2)
for i, m in enumerate([76, 74, 72, 71]):
    cue("music", f"bait motif {i}", BAIT + i * 0.45, bell(m2f(m), 2.2, 0.35), 0.45, 0.25)
# action pulse: plucked ostinato from the lantern to the escape
k = 0
tt = LANTERN
while tt < DAWN0 + 2.0:
    cue("music", "ostinato", tt, pluck(m2f([45, 52, 57, 52][k % 4]), 0.5, 0.6), 0.55, (-0.3, 0.3)[k % 2])
    tt += 0.214
    k += 1
# dawn: warm major swell + the theme resolved
cue("music", "dawn swell C-G-Am-F", DAWN0, pad([m2f(60), m2f(64), m2f(67), m2f(72)], WELCOME - DAWN0 + 0.4, att=1.5, bright=2200), 0.6)
cue("music", "welcome pad F-C", WELCOME, pad([m2f(53), m2f(60), m2f(65), m2f(69)], TWIST - WELCOME + 0.8, att=0.4, rel=0.9, bright=2400), 0.65)
for i, m in enumerate([72, 76, 79, 81, 79, 76]):
    cue("music", f"theme dawn {i}", WELCOME + i * 0.3, bell(m2f(m + 12), 1.8, 0.4), 0.5, 0.15)
# twist: everything drops, low sting + high eerie tone under "two shadows"
cue("music", "eerie tone", GHOST, pad([m2f(81), m2f(82)], DUR - GHOST, att=0.8, rel=0.4, bright=4000), 0.35)
cue("music", "sting", SHADOWS, sting(), 0.9)

# sfx
cue("sfx", "wind bed night", 0.0, wind(night_end + 1.5, 0.35), 1.0)
cue("sfx", "crickets", FLASH, crickets(CREAK0 - FLASH), 1.0, 0.4)
cue("sfx", "door slam", SLAM1, slam(), 0.9, -0.3)
for i, kk in enumerate(KNOCKS):
    cue("sfx", f"knock {i}", kk, knock(1.0 - 0.1 * i), 0.9, -0.2)
cue("sfx", "flash hit", FLASH, whoosh_up(0.35, 0.5)[::-1].copy(), 0.6)
cue("sfx", "door slam 2", SLAM2, slam(0.8), 0.8, -0.2)
for i in range(4):
    cue("sfx", f"tree creak {i}", CREAK0 + i * 0.55, creak(0.9, 150 + 30 * i, 260 + 40 * i, 0.6), 0.6, (-0.6, 0.5, -0.3, 0.7)[i])
tt, i = DECOY0 + 0.6, 0
while tt < DECOY1:
    cue("sfx", "giant step", tt, thud(48, 0.9, 1.0, 0.25), 0.55 + 0.35 * (tt - DECOY0) / (DECOY1 - DECOY0), (-0.15, 0.15)[i % 2])
    tt += 0.91
    i += 1
cue("sfx", "no shadow: silence breath", NO_SHADOW, wind(1.2, 0.2), 0.6)
cue("sfx", "wall shadow creep", WALL_MOVE, creak(1.6, 90, 140, 0.5), 0.7, -0.4)
cue("sfx", "fire crackle", W("fire", 0), bp(noise(2.3), 1500, 7000) * (rng.random(int(2.3 * SR)) > 0.9985) * 6, 0.25, -0.5)
cue("sfx", "lantern whoosh", LANTERN - 0.7, whoosh_up(0.7, 0.7), 0.7)
cue("sfx", "lantern shimmer", LANTERN, shimmer(2.2), 0.8)
cue("sfx", "disguise glitch", GLITCH0, glitch(GLITCH1 - GLITCH0 + 0.4), 0.6)
cue("sfx", "back door kick", KICK, crash(), 0.95)
for i in range(16):
    cue("sfx", "running steps", RUN + i * 0.14, step(0.5), 0.6, rng.uniform(-0.5, 0.5))
for i in range(14):
    cue("sfx", "escape steps", DAWN0 + i * 0.16, step(0.45), 0.5, rng.uniform(-0.4, 0.4))
cue("sfx", "gate creak", DAWN0 + 0.05, creak(0.6, 220, 380, 0.5), 0.5, 0.3)
cue("sfx", "shadow melts", MELT, melt(), 0.6, -0.5)
cue("sfx", "birds at dawn", W("escape", 9), np.sin(2 * np.pi * np.cumsum(3200 + 900 * np.sin(2 * np.pi * 9 * t_(2.5))) / SR) * (np.sin(2 * np.pi * 1.3 * t_(2.5)) > 0.7) * 0.05, 0.6, 0.6)
cue("sfx", "ghost whisper", GHOST, bp(noise(1.6), 2500, 6000) * env(int(1.6 * SR), 0.6, 0.8) * 0.3, 0.5, -0.6)

# ---------------------------------------------------------------- mix
v = np.zeros(N)
vr = np.frombuffer(subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(ROOT, "voice", "voice.wav"), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                                  capture_output=True, check=True).stdout, np.float32).astype(np.float64)
v[: min(N, len(vr))] = vr[:N]

# duck music + beds under speech (word spans), ~-7 dB, smoothed
key = np.zeros(N)
for ln in L["lines"]:
    a, b = int((ln["s"] - 0.08) * SR), int((ln["e"] + 0.12) * SR)
    key[max(0, a):b] = 1
k = int(0.12 * SR)
key = np.convolve(key, np.ones(k) / k, "same")
duck = 10 ** (-7.0 * key / 20)
music *= duck
rms = lambda x: np.sqrt(np.mean(x ** 2) + 1e-12)
vs = v[key > 0.5]
music *= (rms(vs) * 10 ** (-9 / 20)) / max(1e-9, rms(music.mean(0)[key > 0.5]))  # music bed ~9 dB under voice
sfx *= (rms(vs) * 10 ** (-6 / 20)) / max(1e-9, np.percentile(np.abs(sfx.mean(0)), 99.5) / 3)
mix = music + sfx + v[None, :]
mix = np.tanh(mix * 1.1) / np.tanh(1.1)  # soft clip
mix *= 0.89 / np.abs(mix).max()
fade = int(0.05 * SR)
mix[:, -fade:] *= np.linspace(1, 0, fade)
os.makedirs(os.path.join(ROOT, "public", "audio"), exist_ok=True)
pcm = (np.clip(mix.T, -1, 1) * 32767).astype("<i2").tobytes()
out = os.path.join(ROOT, "public", "audio", "mix.wav")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-", "-af", "loudnorm=I=-15:TP=-1.5:LRA=9", "-ar", str(SR), out], input=pcm, check=True)
with open(os.path.join(HERE, "cues.md"), "w") as f:
    f.write(f"# Cue sheet: The Last Noob ({DUR:.3f} s, 48 kHz stereo, loudnorm -15 LUFS)\n\n| time (s) | stem | cue |\n|---|---|---|\n")
    for t, kind, name in sorted(cues):
        f.write(f"| {t:6.2f} | {kind} | {name} |\n")
print(f"mix {DUR:.3f} s -> {out}; {len(cues)} cues")
