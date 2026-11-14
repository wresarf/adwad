# Snack Force: Pet Toss

A Roblox game where you throw snacks across six biomes. Wherever a snack lands, a pet comes to catch it, and you can roll rare **material** and **size** mutations. Everything is generated from primitive parts, with no Toolbox or external assets.

**Playable file:** [`SnackForce_PetToss.rbxl`](SnackForce_PetToss.rbxl). This one binary contains the whole game: every script, config and remote. The world is generated at runtime from primitive parts. Open it in Roblox Studio and press Play. DataStores only persist in a published place that has *Studio Access to API Services* enabled. Without that, the game stays fully playable and shows a "progress won't be saved" notice.

## Build & test

```bash
# toolchain: rokit install   (or: mise use github:rojo-rbx/rojo@7.7.1 github:lune-org/lune@0.11.1)
rojo build default.project.json -o SnackForce_PetToss.rbxl
lune run tests/run.luau SnackForce_PetToss.rbxl   # offline tests against the built place
./scripts/typecheck.sh                            # strict Luau type-check against the Roblox API (needs luau-lsp)
# or everything at once (type-check runs when luau-lsp is installed):
./scripts/build.sh
# dev tool: top-down SVG map of the generated world
lune run tests/map.luau -300 300 -320 40 2 /tmp/hub.svg
# dev tools: approximate review renders of the built place (not Roblox screenshots)
lune run tests/gui.luau pets /tmp/pets-panel.svg 844 390 touch   # real HUD/panels, any viewport
lune run tests/snapshots.luau pets /tmp/pets.svg                  # every species, 3/4 portrait
```

The Lune suite loads the **built place file** and runs its ModuleScripts headlessly. It covers:
- the full script hierarchy packed into the place, and client modules loading headlessly
- HUD layout at six desktop, phone and tablet viewports (no overlaps, on screen, readable size, touch targets, clear of the thumbstick and jump button, panels fit)
- v4: coin upgrades, pet actions (equip, lock, sell), the SaveGate release ordering, store loading and pending states, v3 to v4 save migration, and a paid-random-items audit
- remote contracts (server and client source)
- config integrity
- the sweet-spot, combo and weather multipliers
- Monte Carlo mutation odds
- fusion and auto-sell
- save sanitising and rate limiting
- the weather schedule
- quests, discovery and zone rewards, offline earnings, the Gym, and v1 to v2 save migration
- world generation, including Roblox part-size limits, stall prompts and keeping scenery out of the throw lane
- all 1,512 species × material × size pet models
- plot assignment
- a fresh-save progression simulation that also completes the quest line

## How to play

| Action | Input |
| --- | --- |
| Charge + throw (at the Throw Line) | hold **E** / **THROW** / **R2**, release in the green **SWEET** zone. The meter previews the distance and biome |
| Train strength | hold **Q** / **TRAIN** / **X** (2× inside the Gym) |
| Skip camera effect / cutscene | **Space**, **Enter** or **SKIP** |
| Food Shop / Pets & Fuse / Pet Index / How to Play | **F** / **G** / **N** / **H**, the left menu, or **R** at the hub stalls |
| Teleport | **T** / Travel: Throw Line, Gym or your plot |
| Safari Eggs | **B**, the Eggs button, or **R** at the Hatchery |

- **Sweet spot:** releasing in the green zone gives ×1.25 distance and ×1.35 mutation luck.
- **Biomes:** Sunny Meadow → Sizzle Dunes → Frostbite Peaks → Magma Fields → Toxic Swamp → Nuclear Wasteland. Each biome's wind and gravity stretch or shrink the throw. Past 2,500 m the snack reaches **Space**, and past 3,600 m it reaches **the Moon**. Both play skippable cutscenes. Catches below your *auto-skip rarity* setting skip the cutscene automatically.
- **Cravings:** every biome craves Berry, Meat, Spicy or Cosmic, and the cravings re-roll with each weather event. Landing the matching food builds a streak, with combo multipliers 1.5 → 2 → 3 → 4 → 5 → 6.5 → 8 → **10×** mutation odds. A miss resets the streak.
- **Mutations:** materials are Normal / Gold / Diamond / Emerald / Ruby / Rainbow. Sizes are Normal / Huge / Colossal / Monstrous / Titanic / Cosmic / Infinite.
- **Fusion:** three identical pets (same species, material and size) fuse into the next material tier. *Fuse All* cascades, and a reveal shows the result.
- **Pets panel:** tap a pet to select it. You can place it on your plot or move it back to your backpack, **lock** it (locked pets are never sold or fused), or sell one copy (tap twice to confirm).
- **Upgrades** (Snack Shop → Upgrades, coins only):
  - Training Coach: +25% training per level.
  - Craving Chef: +50% craving coins per level.
  - Night Shift: +1 h offline earnings per level.
- **Auto-sell:** sells new catches (and existing pets with *Sell Matching*) at or below a chosen rarity. Mutated pets are protected by default.
- **Weather:** every 90 s, a 45 s event starts. **Titan Storm** gives 3× size luck, **Feast Frenzy** gives 2× craving bonus (the streak grows twice as fast and craving coins double), and **Prism Aurora** gives 4× material luck.
- **Plots:** six plot pads, each with 8 pedestals. Equipped pets stand on them with labels and earn passive income.
- **Auto-Throw:** unlocks once you reach the Toxic Swamp (1,250 m). It throws every 3.5 s at a fixed charge that never hits the sweet spot.
- **Quests (onboarding):** a 23-step quest line, from *Warm Up* to *Moonshot*, teaches each mechanic in order and pays coins. A guide beam points to where the current quest happens; you can turn it off in Settings.
- **Rewards:** your first landing in each zone pays a bonus, and so does the first catch of each species. You'll find both in the **Pet Index**. Your plot earns 25% of its income while you're offline, for up to 2 hours. The hub leaderboard shows the best throws on the server.
- **Hub:** Strength Gym (2× training), Food Shop stall, Fusion Altar, Pet Index book, leaderboard, signposts, bunting and balloons. Each biome has its own landmarks: windmills and a rainbow arch, a pyramid and an oasis, an igloo and snowmen, a volcano with a lava river, giant glowing mushrooms, and cooling towers. Mountains line the lane, and the atmosphere changes colour with the biome and the weather.
- **HUD:** scales to any screen size. Touch devices get a larger minimum size, and on small screens the cravings board collapses. You also get coin popups, reward banners, catch cards with a 3D pet preview, a landing beacon, a best-distance flag, and a welcome screen on your first session.

## Store, eggs and purchases

- **Snacks:** bought with earned coins.
- **Safari Eggs** (Hatchery stall or **B**): opened with **Paw Tokens**. You earn tokens from quests, first landings in a zone, new species and every 50 catches, and you can't buy them. Each egg shows its complete odds before you hatch.
- **Store:** game passes (Double Coins, Auto-Throw Pass, Big Backpack, Golden Trail), Gem packs (developer products) and fixed-content Gem offers. All Robux IDs are `0` (unset) in `Config/MonetizationConfig.luau`, so those offers show "Not available yet" and never open a prompt. Once real IDs are set, the server reads prices from MarketplaceService.
- **Security:** grants only happen in one server-side `ProcessReceipt`. It records each PurchaseId in the session-locked save and returns PurchaseGranted only after the save succeeds. See [`docs/DESIGN_AUDIT.md`](docs/DESIGN_AUDIT.md) for the full design and the paid-random-items reasoning.

## Layout

```
default.project.json             Rojo tree (Remotes are declared here so they exist before any script runs)
src/ReplicatedStorage/Config     GameConfig, BiomeConfig, PetConfig, MutationConfig, FoodConfig, QuestConfig,
                                 EggConfig, MonetizationConfig
src/ReplicatedStorage/Shared     GameMath (pure, authoritative math), Progression (quests/rewards), PetModelBuilder, RemoteContract
src/ServerScriptService          GameServer + Server/ (WorldBuilder, PlotService, Inventory, PlayerData,
                                 DataService (session lock), WeatherService, RateLimiter, MarketService, Receipts)
src/StarterPlayerScripts         GameClient + Client/ (Hud, Panels, Effects, UI)
tests/                           Lune runtime shim + test-suite
```

## Security model

- The server owns every number. The client only sends intents: `ThrowFood("Begin"|"Release")`, `TrainStrength()`, and the five RemoteFunctions.
- Throw charge comes from the **server's own timestamps** between Begin and Release, so a client cannot claim a perfect charge.
- Each remote has its own token-bucket rate limit. Throws and training also have cooldowns.
- All arguments are type-checked, length-checked and checked against the configs.
- Manual throws require the character to be at the Throw Line. The Gym bonus is checked against the server-side character position.
- Quest, discovery, zone and offline rewards are all computed and paid by the server. Four remotes were added after the original ten: `StorePurchase` (it only asks the server to show a prompt, or to spend Gems on a fixed offer), `HatchEgg`, `ManagePet` (equip, unequip, lock, unlock or sell one group) and `BuyUpgrade` (coins only).
- Saves are session-locked. The save made when a player leaves or the server closes is the final write and releases the lock (`Server/SaveGate`).
- Saved data is sanitised on load: values are clamped, UIDs reassigned, and unknown pets and foods dropped. If a load fails, the player still gets a playable session, but the save is never overwritten.
