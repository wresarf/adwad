#!/usr/bin/env bash
# Full render: 1790 frames, 1080x1920 @ 30 fps, narration track from public/audio/mix.wav.
# SwiftShader (CPU WebGL) needs no GPU; on a GPU machine use --gl=angle and raise --concurrency.
set -euo pipefail
cd "$(dirname "$0")/.."
SCALE="${SCALE:-1}"
npx remotion render src/index.ts LastNoob out/the_last_noob.mp4 --codec h264 --crf 18 --gl="${GL:-swangle}" --concurrency="${CONCURRENCY:-1}" --scale "$SCALE"
python3 scripts/short_qa.py out/the_last_noob.mp4 out/qa || true
