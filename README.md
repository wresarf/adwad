# Snack Force: Pet Toss

A Roblox game where you throw snacks across six biomes. Wherever a snack lands, a pet comes to catch it, and you can roll rare **material** and **size** mutations. Everything is generated from primitive parts, with no Toolbox or external assets.

**Playable file:** [`SnackForce_PetToss.rbxl`](SnackForce_PetToss.rbxl). Open it in Roblox Studio and press Play. DataStores only persist in a published place that has *Studio Access to API Services* enabled. Without that, the game stays fully playable and shows a "progress won't be saved" notice.

## Build & test

```bash
# toolchain: rokit install   (or: mise use github:rojo-rbx/rojo@7.7.1 github:lune-org/lune@0.11.1)
rojo build default.project.json -o SnackForce_PetToss.rbxl
lune run tests/run.luau SnackForce_PetToss.rbxl   # offline tests against the built place
# or both at once:
./scripts/build.sh
```

The Lune suite loads the **built place file** and runs its ModuleScripts headlessly. It covers:
- remote contracts (server and client source)
- config integrity
- the sweet-spot, combo and weather multipliers
- Monte Carlo mutation odds
- fusion and auto-sell
- save sanitising and rate limiting
- the weather schedule
- world generation, including Roblox part-size limits
- all 1,512 species × material × size pet models
- plot assignment
- a fresh-save progression simulation

## How to play

| Action | Input |
| --- | --- |
| Charge + throw (at the Throw Line) | hold **E** or the **THROW** button, release in the green **SWEET** zone |
| Train strength | **Q** or **TRAIN** |
| Skip camera effect / cutscene | **Space**, **Enter** or **SKIP** |

- **Sweet spot:** releasing in the green zone gives ×1.25 distance and ×1.35 mutation luck.
- **Biomes:** Sunny Meadow → Sizzle Dunes → Frostbite Peaks → Magma Fields → Toxic Swamp → Nuclear Wasteland. Each biome's wind and gravity stretch or shrink the throw. Past 2,500 m the snack reaches **Space**, and past 3,600 m it reaches **the Moon**. Both play skippable cutscenes. Catches below your *auto-skip rarity* setting skip the cutscene automatically.
- **Cravings:** every biome craves Berry, Meat, Spicy or Cosmic, and the cravings re-roll with each weather event. Landing the matching food builds a streak, with combo multipliers 1.5 → 2 → 3 → 4 → 5 → 6.5 → 8 → **10×** mutation odds. A miss resets the streak.
- **Mutations:** materials are Normal / Gold / Diamond / Emerald / Ruby / Rainbow. Sizes are Normal / Huge / Colossal / Monstrous / Titanic / Cosmic / Infinite.
- **Fusion:** three identical pets (same species, material and size) fuse into the next material tier. *Fuse All* cascades.
- **Auto-sell:** sells new catches (and existing pets with *Sell Matching*) at or below a chosen rarity. Mutated pets are protected by default.
- **Weather:** every 90 s, a 45 s event starts. **Titan Storm** gives 3× size luck, **Feast Frenzy** gives 2× craving bonus (the streak grows twice as fast and craving coins double), and **Prism Aurora** gives 4× material luck.
- **Plots:** six plot pads, each with 8 pedestals. Equipped pets stand on them with labels and earn passive income.
- **Auto-Throw:** unlocks once you reach the Toxic Swamp (1,250 m). It throws every 3.5 s at a fixed charge that never hits the sweet spot.

## Layout

```
default.project.json             Rojo tree (Remotes are declared here so they exist before any script runs)
src/ReplicatedStorage/Config     GameConfig, BiomeConfig, PetConfig, MutationConfig, FoodConfig
src/ReplicatedStorage/Shared     GameMath (pure, authoritative math), PetModelBuilder, RemoteContract
src/ServerScriptService          GameServer + Server/ (WorldBuilder, PlotService, Inventory, PlayerData,
                                 DataService, WeatherService, RateLimiter)
src/StarterPlayerScripts         GameClient + Client/ (Hud, Panels, Effects, UI)
tests/                           Lune runtime shim + test-suite
```

## Security model

- The server owns every number. The client only sends intents: `ThrowFood("Begin"|"Release")`, `TrainStrength()`, and the five RemoteFunctions.
- Throw charge comes from the **server's own timestamps** between Begin and Release, so a client cannot claim a perfect charge.
- Each remote has its own token-bucket rate limit. Throws and training also have cooldowns.
- All arguments are type-checked, length-checked and checked against the configs.
- Manual throws require the character to be at the Throw Line.
- Saved data is sanitised on load: values are clamped, UIDs reassigned, and unknown pets and foods dropped. If a load fails, the player still gets a playable session, but the save is never overwritten.
