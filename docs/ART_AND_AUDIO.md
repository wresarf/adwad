# Art and audio bible: toy-pet adventure

This is a development reference. Players only get `SnackForce_PetToss.rbxl`.

The images referred to below are approximate review renders made by
`tests/gui.luau`, `tests/render3d.luau` and `tests/snapshots.luau` from the built place. They are not Roblox screenshots.

## Palette

| Role | RGB | Use |
| --- | --- | --- |
| Ivory surface | 246,239,224 | panels, stalls, signs |
| Paper | 252,249,242 | cards, inputs |
| Charcoal text | 46,42,38 | all body text (contrast 7 or more on ivory) |
| Muted text | 104,96,86 | secondary lines (contrast 4.5 or more) |
| Leaf green | 60,142,64 | the one primary action, selected state |
| Amber | 242,169,59 | rewards, coins, "something is ready" dots |
| Terracotta | 196,92,64 | errors, danger, stall awnings |
| Teal | 52,128,130 | info, Tundra tag |

Biome ground and tag colours live in `WorldBuilder` `Styles`, one per biome. Neon is used only for lava and the reactor window.

## Type and spacing

- **Fonts:** Fredoka One for titles, Builder Sans for everything people read.
- **Type scale:** caption 15, small 17, body 19, label 21, title 26, display 34 (logical units on a 1280×720 canvas).
- **Scaling:** on small screens `Hud.scaleFor` keeps the canvas at most 900 × 460, so captions stay at 11–13 px on phones. `TextScaled` is never used.
- **Spacing:** 4 / 8 / 12 / 16 / 24.
- **Corner radius:** 8 / 12 / 18 / pill.
- **Buttons:** a face over a darker 4 px lip that sinks on press (the toy-button reading of the Kenney UI Pack).

## States

Every state pairs a word or symbol with its colour, never colour alone:
- **Selected:** a 3 px leaf edge plus the detail sheet.
- **Equipped:** "On plot".
- **Locked:** 🔒.
- **Included:** "Included ✓".
- **Owned:** "Owned ✓".
- **Loading:** "Checking price…".
- **Pending:** "Finishing…".
- **Empty:** an explanatory sentence.
- **Failure:** a terracotta toast with "!" and an error sound.
- **Insufficient funds:** "Need N more".

## Free perks

The former game passes are built in for every player and are never sold. They are listed in the Store under "Included for everyone":
- **Double Coins:** plot income ×2.
- **Auto-Throw:** available from the start. The old 1,250 m unlock is kept in saves only as history.
- **Big Backpack:** +150 pets.
- **Golden Trail:** cosmetic, switchable in Settings.

There are no pass ids, no prompts and no ownership checks. Gem developer products are unchanged: still id 0 and disabled until real ids exist, granted only by `ProcessReceipt`.

## Models

- **Pet units:** pets face −Z, stand on Y = 0 and are scaled by BaseScale × size.
- **Shared face:** two glossy ink eyes with a white shine, and soft cheeks.
- **Silhouette comes from pose and add-ons, not from new faces:**
  - Pup stands, with floppy ears and a wagging tail.
  - Kitty sits, with its tail curled on the ground and whiskers.
  - Bear is a sitting teddy with paw pads.
  - Dragon has raised bat wings.
  - Lion has a mane ring.
  - Giraffe and Zebra are tall.
  - Frogs and slimes are low and wide.
- **Framing:** previews frame both height and width (`PetModelBuilder.portraitCamera`).
- **Reference:** Kenney Cube Pets (CC0), https://kenney.nl/assets/cube-pets. Its head-and-body block reads at about 1:1, with big wide-set eyes, ears and tails carrying the species, and no outlines. Used as a style reference only; nothing was copied.

## World

- **Lane:** the throw lane (|x| ≤ 72) holds only flat things:
  - lane lines and 100 m marker lines;
  - tonal ground patches;
  - biome blend patches.
- **Edges:** all 3D scenery stays outside the lane.
  - Vegetation is densest 14–46 studs outside the lane edge, which is the band visible while throwing.
  - Mountains sit beyond the side walls.
- **Biome borders:** each border has a pylon pair just outside the lane, with a flag in the biome's colour, small entry signs, and a 50-stud blend of the two ground colours.
- **Biome palette:**

  | Biome | Ground | Props |
  | --- | --- | --- |
  | Meadow | green | trees, flowers |
  | Dunes | sand | cacti, dunes |
  | Tundra | snow | pines, ice |
  | Magma | slate | lava pools, vents |
  | Swamp | moss | pools, reeds, mushrooms |
  | Nuclear | khaki | barrels, dead trees |

## Motion

- **Throw sequence:** anticipation (wind-up and rising charge ticks), then release (punch, streak, whoosh), then flight (arc and shadow), then impact (dust, ring, thud), then reward (pet hop, chime, coin popup).
- **Plot pets:**
  - they idle with a bob and a sway;
  - they blink every 2–5.5 s;
  - within 18 studs they turn to face the player and hop every 2.5–4.5 s.
- **Big celebrations:** only milestones get them.
- **Reduced motion** (setting or `GuiService.ReducedMotionEnabled`):
  - no shake, flashes, confetti or hops;
  - a calmer bob;
  - instant tweens.

## Audio

**Source:** every effect uses sounds that ship inside the Roblox client (`rbxasset://sounds/...`). They need no upload, no asset permissions and no Toolbox.
- **Verified list:** the files were checked against the client file manifest, `rbxManifest.txt` in https://github.com/MaximumADHD/Roblox-Client-Tracker (branch `roblox`). It lists 11 sounds in `content/sounds`:
  - action_falling, action_footsteps_plastic, action_get_up, action_jump, action_jump_land, action_swim;
  - impact_explosion_03, impact_water;
  - oof, ouch, volume_slider.

  The configured cue table only uses files from that list, and a test enforces it.

**Cues** (`Config/SoundConfig`). Pitch and layering turn the few files into a set of cues:

| Cue | Sound |
| --- | --- |
| Charge | slider tick rising with the meter |
| Sweet spot | a two-note chime |
| Throw | jump whoosh, two layers |
| Land | spatial landing thud; a water splash in the Swamp |
| Catch | major arpeggio |
| Reward / milestone | arpeggio plus a soft distant pop |
| Buy | two notes |
| Error | falling minor two notes |
| Train | soft high thud |
| Fuse / hatch | soft pop plus chime |
| Egg wobble | low ticks |
| Weather | descending chime |
| Panel | click |

**Mixing:**
- two SoundGroups, Effects and Music, following the Sound effects and Music settings;
- per-cue cooldowns and concurrency limits, and at most 12 voices;
- every Sound destroys itself, with a 4 s safety net;
- spatial roll-off out to 220 studs.

**Music and ambience (blocker):** the client ships no music, and no licensed track was supplied. `SoundConfig.MusicId` is 0, so nothing plays. To add music, upload or license a track your account may use in this experience, then set the id. The Music setting already controls it.

**Not verified:** none of this has been heard in a running Roblox client. Volumes and pitches are first-pass values from the offline build.

## References

- **Roblox docs:**
  - [Accessibility](https://create.roblox.com/docs/production/publishing/accessibility)
  - [Adaptive design](https://create.roblox.com/docs/production/publishing/adaptive-design)
  - [Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items)
  - [Developer products](https://create.roblox.com/docs/production/monetization/developer-products)
  - [Player data purchasing](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing)
  - [Monetization overview](https://create.roblox.com/docs/production/monetization)
- **Kenney packs (CC0, style reference only):**
  - [Cube Pets](https://kenney.nl/assets/cube-pets)
  - [UI Pack](https://kenney.nl/assets/ui-pack)
  - [UI Pack Adventure](https://kenney.nl/assets/ui-pack-adventure)
- **Competitor:** [Throw Food For Animals](https://www.roblox.com/games/120219252362013/Throw-Food-For-Animals). I had only its page text and thumbnail: a throw arc to a glowing landing ring and colour-coded zones.
- **Competitor video:** [YouTube r157nlkQwz4](https://youtu.be/r157nlkQwz4). I had only the title and thumbnail; the footage was not watched. No claim of superiority is made.
