#!/usr/bin/env bash
# Fast CPU preview: 15 fps sampling of the 30 fps timeline, 432x768, no MSAA, rendered in two halves, then muxed with
# the generated mix (public/audio/mix.wav). Output: out/the_last_noob_preview.mp4
set -uo pipefail
cd "$(dirname "$0")/.."
SCALE="${SCALE:-0.4}"
HALF=448
P='{"audio":false,"aa":false}'
npx remotion render src/index.ts LastNoob15 out/part1.mp4 --codec h264 --crf 19 --gl=swangle --concurrency=1 --scale "$SCALE" --frames=0-$((HALF-1)) --props="$P"
npx remotion render src/index.ts LastNoob15 out/part2.mp4 --codec h264 --crf 19 --gl=swangle --concurrency=1 --scale "$SCALE" --frames=$HALF-894 --props="$P"
printf "file 'part1.mp4'\nfile 'part2.mp4'\n" > out/parts.txt
ffmpeg -v error -y -f concat -safe 0 -i out/parts.txt -i public/audio/mix.wav -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest out/the_last_noob_preview.mp4
echo DONE
