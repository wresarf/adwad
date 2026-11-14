# Narration for "The Last Noob": synthesizes every line of voice/script.json with the local Piper TTS
# (en_US-joe-medium, CC0 dataset), trims silence, lays the lines on one timeline and writes
#   voice/voice.wav   48 kHz mono, the whole narration
#   voice/lines.json  per-line start/end + estimated word timings (drives captions, shots and the mix)
# Usage: python audio/voice.py [--model /path/en_US-joe-medium.onnx] [--length-scale 0.92]
# Dialogue lines ("speaker": "pro") are pitched up a little so the pros read as a second voice.
import argparse
import json
import os
import re
import subprocess
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SR = 48000
LEAD_IN = 0.12  # voice starts at frame ~4, like the reference format


def read_wav48(path, pitch=1.0):
    af = "aresample=48000"
    if pitch != 1.0:
        af = f"asetrate=22050*{pitch},atempo={1 / pitch:.5f},aresample=48000"
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-af", af, "-ac", "1", "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def trim(x, thr=0.012, pad=0.03):
    env = np.convolve(np.abs(x), np.ones(240) / 240, "same")
    idx = np.where(env > thr)[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] - int(pad * SR))
    b = min(len(x), idx[-1] + int(pad * SR))
    return x[a:b]


def syllables(word):
    w = re.sub(r"[^a-z]", "", word.lower())
    n = len(re.findall(r"[aeiouy]+", w)) - (1 if w.endswith("e") and len(w) > 3 else 0)
    return max(1, n)


def word_times(x, t0, text):
    """Spread the words over the voiced parts of the line, weighted by syllables, snapping pauses to silences."""
    words = text.split()
    hop = int(0.01 * SR)
    env = np.array([np.sqrt(np.mean(x[i:i + hop] ** 2)) for i in range(0, len(x) - hop, hop)])
    voiced = env > max(0.01, env.max() * 0.06)
    dur = len(x) / SR
    # pauses >= 120 ms inside the line (commas, full stops)
    pauses, run = [], None
    for i, v in enumerate(voiced):
        if not v and run is None:
            run = i
        elif v and run is not None:
            if i - run >= 12 and run > 5:
                pauses.append((run * 0.01, i * 0.01))
            run = None
    # split the words into chunks at punctuation, match chunks to the voiced segments between pauses
    chunks, cur = [], []
    for w in words:
        cur.append(w)
        if re.search(r"[,.!?]$", w):
            chunks.append(cur)
            cur = []
    if cur:
        chunks.append(cur)
    segs, s = [], 0.0
    for a, b in pauses:
        segs.append((s, a))
        s = b
    segs.append((s, dur))
    if len(segs) != len(chunks):  # fall back to one segment, weights by syllables
        segs, chunks = [(0.0, dur)], [words]
    out = []
    for (a, b), ch in zip(segs, chunks):
        wts = np.array([syllables(w) + 0.35 for w in ch], float)
        edges = a + (b - a) * np.concatenate([[0], np.cumsum(wts) / wts.sum()])
        for k, w in enumerate(ch):
            out.append({"w": w, "s": round(t0 + edges[k], 3), "e": round(t0 + edges[k + 1], 3)})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=os.environ.get("PIPER_MODEL", "/tmp/voices/en_US-joe-medium.onnx"))
    ap.add_argument("--piper", default=os.environ.get("PIPER_BIN", "piper"))
    ap.add_argument("--length-scale", type=float, default=0.96)
    args = ap.parse_args()
    spec = json.load(open(os.path.join(ROOT, "voice", "script.json"), encoding="utf-8"))
    pieces, lines, t = [], [], LEAD_IN
    with tempfile.TemporaryDirectory() as tmp:
        for ln in spec["lines"]:
            p = os.path.join(tmp, ln["id"] + ".wav")
            pro = ln.get("speaker") == "pro"
            subprocess.run([args.piper, "-m", args.model, "-f", p, "--length-scale", str(args.length_scale * (0.95 if pro else 1.0)),
                            "--sentence-silence", "0.18"], input=ln["text"].encode(), check=True, capture_output=True)
            x = trim(read_wav48(p, pitch=1.12 if pro else 1.0))
            d = len(x) / SR
            lines.append({"id": ln["id"], "text": ln["text"], "speaker": ln.get("speaker", "narrator"),
                          "s": round(t, 3), "e": round(t + d, 3), "words": word_times(x, t, ln["text"])})
            pieces.append((t, x))
            t += d + ln.get("gap", 0.25)
    total = t + 0.6
    buf = np.zeros(int(total * SR))
    for t0, x in pieces:
        i = int(t0 * SR)
        buf[i:i + len(x)] += x
    buf *= 0.89 / max(1e-6, np.abs(buf).max())
    os.makedirs(os.path.join(ROOT, "voice"), exist_ok=True)
    pcm = (np.clip(buf, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    os.path.join(ROOT, "voice", "voice.wav")], input=pcm, check=True)
    json.dump({"duration": round(total, 3), "lines": lines}, open(os.path.join(ROOT, "voice", "lines.json"), "w"), indent=1)
    print(f"voice {total:.2f} s, {len(lines)} lines")
    for ln in lines:
        print(f"  {ln['id']:>8} {ln['s']:6.2f}-{ln['e']:6.2f}  {ln['text'][:60]}")


if __name__ == "__main__":
    main()
