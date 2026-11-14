#!/usr/bin/env bash
# CPU-only preview: composition LastNoob15 (the 30 fps timeline sampled at 15 fps), MSAA on (it costs almost nothing on
# SwiftShader; per-frame draw overhead dominates), rendered in two halves so a partial result survives, then muxed with
# public/audio/mix.wav. Defaults: 540x960 (SCALE=0.5). Output: out/the_last_noob_preview.mp4
set -uo pipefail
cd "$(dirname "$0")/.."
SCALE="${SCALE:-0.5}"
HALF=448
P='{"audio":false,"aa":true}'
mkdir -p out
npx remotion render src/index.ts LastNoob15 out/part1.mp4 --codec h264 --crf 18 --gl=swangle --concurrency=1 --scale "$SCALE" --frames=0-$((HALF-1)) --props="$P" || exit 1
npx remotion render src/index.ts LastNoob15 out/part2.mp4 --codec h264 --crf 18 --gl=swangle --concurrency=1 --scale "$SCALE" --frames=$HALF-894 --props="$P" || exit 1
printf "file 'part1.mp4'\nfile 'part2.mp4'\n" > out/parts.txt
ffmpeg -v error -y -f concat -safe 0 -i out/parts.txt -i public/audio/mix.wav -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart out/the_last_noob_preview.mp4
echo RENDER_DONE
