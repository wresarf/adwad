# The Last Noob: They Left the Noob Outside

An original vertical survival-mystery short, about 60 s long (1790 frames, 1080x1920, 30 fps). It's built with the uploaded
`claude-animated-shorts` package workflow: three.js inside Remotion, timed to the narration's word timings.

**Story.** Experienced players lock a beginner outside their cabin. A huge creature walks out of the fog, and the
players press against the window to watch it. Noob notices it casts no moonlight shadow, while a shadow on the cabin
wall moves on its own. The creature is a flat cut-out decoy, and the impostor is sitting by the fire. Noob flashes his
lantern through the glass, the disguise flickers away, and he kicks open the back door. Everyone escapes at sunrise.
After they welcome him, a second shadow appears behind him on the grass.

Hook: *"They locked him outside. Then something knocked from inside."*

## Layout
| Path | What it is |
|---|---|
| `voice/script.json` | Narration script (17 lines, 185 words, English) |
| `voice/voice.wav`, `voice/lines.json` | Synthesized narration and per-line/per-word timings (everything is timed to these) |
| `audio/voice.py` | Offline TTS: Piper `en_US-joe-medium` (CC0 dataset). Pro dialogue lines are pitched up |
| `audio/score.py`, `audio/cues.md` | Synthesized score and SFX (numpy/scipy), ducked under the voice, normalized to -15 LUFS, written to `public/audio/mix.wav` |
| `src/story.ts` | Shot plan: `SHOTS`, `FLASH_AT`, `KICKS`, per-shot camera keys with smootherstep glides and creep push-ins, poses, events, caption chunks |
| `src/World.tsx` | Forest of block pines, fenced yard and gate, log cabin with interior (fireplace, back wall), sky, moon, stars, cardboard decoy |
| `src/Blocky.tsx` | Original block characters: Noob, Red (helmet), Green (ponytail), Blue (cap), Purple (hood, the impostor) and its void form |
| `src/Block.tsx` | Toon box with ink hull, plus a planar projected-shadow material (it lets the decoy cast *no* shadow) |
| `src/look.ts` | Toon ramp, ink colour, painted Canvas2D textures, night and dawn light presets |
| `src/LastNoob.tsx` | Composition: scene, vignette grade, flashes, title card, word-highlighted captions, audio |
| `scripts/stills.mjs` | Look-check stills (`node scripts/stills.mjs out/x_ 22,137,874 0.5`) |
| `scripts/render.sh`, `scripts/short_qa.py` | Full 30 fps render, then the package's frame-by-frame QA |
| `scripts/render_preview.sh` | CPU-only preview: composition `LastNoob15` (the same timeline sampled at 15 fps), 432x768, no MSAA, muxed with the mix |

## Run
```bash
npm install
npx remotion browser ensure
npm run studio                       # preview with scrubbing
node scripts/stills.mjs out/s_ 22,137,874,1054 0.5
python audio/score.py                # rebuild music + SFX + mix (needs numpy, scipy, ffmpeg)
./scripts/render_preview.sh          # fast 15 fps 432x768 preview -> out/the_last_noob_preview.mp4
./scripts/render.sh                  # 1080x1920 master -> out/the_last_noob.mp4 (SCALE=0.5 for a fast 540x960 pass)
# regenerate the narration (optional): pip install piper-tts, download en_US-joe-medium.onnx(.json) from rhasspy/piper-voices
PIPER_MODEL=/path/en_US-joe-medium.onnx python audio/voice.py
```

## Credits and licences
- Workflow, `short_qa.py` and the pipeline structure come from the uploaded *claude-animated-shorts* package (MIT, see `third_party/`).
  None of the package's study-only reference frames are copied or used.
- The story, characters, sets, script and narration are original. There are no third-party models or images; everything is boxes and Canvas2D paint.
- Font: Lilita One (SIL OFL, `public/fonts/OFL.txt`). Voice: Piper `en_US-joe-medium`, CC0 dataset.
