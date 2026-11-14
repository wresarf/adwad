# Screenshot audit (v7)

The owner supplied 11 screenshots from other pet-throwing games as visual references. They
are explicitly allowed as references. The earlier excluded video was not opened, and nothing
here relies on notes about it.

Four of the frames (8–11 below) are captures from a video player, and one (5) has an
automated-browser banner. I only looked at those still frames.

**About the evidence**
- Still images can't show motion, timing, frame rate or sound, so anything about those is
  labelled *Inferred*.
- This build is **not runtime-tested** in Roblox Studio. The checks were the Rojo build, the
  strict luau-lsp type check, the offline Lune test suite, and approximate headless renders
  from `tests/gui.luau` and `tests/render3d.luau`. Those renders are not Roblox screenshots.
- We copy patterns only. No branding, art, names or assets were taken from these images.

Each section has six parts:
- **Observed:** what is visible in the frame.
- **Inferred:** what I'm guessing from it.
- **Transfer:** what we take from it.
- **Avoid:** what we don't take.
- **Implemented:** what changed in this repo.
- **Acceptance:** the test or render that checks it.

## 1. Food shop modal

- **Observed:**
  - A wide modal with a strong magenta title bar and a red ✕ close button.
  - Three cards, each with a large 3D food model, its name, rarity and tier, and one state button: price or EQUIPPED.
  - The equipped card has a green outline.
  - The side cards are clipped at the modal edges.
- **Inferred:** the cards scroll sideways. The clipping looks like a layout bug, not a design choice.
- **Transfer:**
  - The product model comes first.
  - Each card has one state button.
  - The equipped state is marked by an outline plus text, not by colour alone.
  - A distinct header and close button.
- **Avoid:**
  - Clipped cards.
  - Neon magenta.
  - Huge price suffixes.
- **Implemented:**
  - Every panel now has a tinted header band with a red `danger` close button (`Panels.luau`, `shell`).
  - The Snack Shop is a card grid. Each card shows a `FoodModelBuilder` 3D preview, a craving tag, power and luck, the description, and a state button: `Equipped ✓`, `Equip`, `Buy · price`, or `🔒 price` with a progress bar for the next snack. The equipped card gets a green edge and an "Equipped" tag.
  - `Panels.snackGrid` sizes the cells from the panel width so only whole cards show, with a compact card height on short screens.
- **Acceptance:** tests "snack shop: product cards…" (four viewports: no card crosses the panel edge, every card has a ViewportFrame, all four states) and "panels: tinted header band…". Render: `v7-shop`.

## 2. Scarecrow reveal (dark harvest corridor)

- **Observed:**
  - A dark blue corridor framed by repeated bare angular trees.
  - A bright, outlined creature in the centre.
  - At the bottom: the name, an angled NEW badge, income, and "tap to continue".
  - Almost no other HUD.
- **Inferred:** the camera is placed on purpose to frame the creature. How long it holds can't be told from a still.
- **Transfer:**
  - Specimen first: the world camera frames the pet.
  - The text sits under the pet, in a fixed order.
  - New catches wait for a tap.
- **Avoid:**
  - Thick black outlines.
  - A dark-on-dark palette.
  - Tiny "tap to continue" text.
- **Implemented:**
  - After a followed throw, `Effects.specimenShot` moves the camera to a low 3/4 view sized to the pet. It runs inside the existing sequence, so Skip, finishing or a respawn always gives the camera back.
  - Caught pets were built rotated by π and faced away from the camera. They now face back up the lane.
  - The reveal card is at the bottom centre: material, then species, then size / rarity / distance tags, then income, then status, with an angled NEW badge.
  - New-species and Epic+ catches wait for a tap or Space / Enter, up to 6 s. Other catches dismiss themselves.
  - The reveal now waits for the landing, so it no longer spoils the catch mid-flight.
- **Acceptance:**
  - Test "catch reveal…": the hierarchy; it stays on screen and clear of the buttons on four viewports; every species name fits without scaled text; only rare or new catches wait; the wait times out; no backward-facing pets.
  - Test "specimen shot…".
  - Renders: `v7-catch`, `v7-catchpreview`.

## 3. Animal inventory

- **Observed:**
  - A narrow right-hand list with a "20/20" capacity pill in the header.
  - Each row has a preview, material, name, size and income, plus separate Pick Up and Sell buttons.
  - A large Equip Best button pinned at the bottom.
  - An equipped hotbar along the bottom of the screen.
  - Big pets behind the list cover the world.
  - Some names are dark grey on a dark background.
- **Inferred:** Equip Best is the action players use most.
- **Transfer:**
  - Capacity always visible in the header.
  - A large Equip Best fixed in one place.
  - Separate actions, with a confirm on Sell.
- **Avoid:**
  - Low-contrast names.
  - Pets covering the UI.
  - A second hotbar that repeats the plot.
- **Implemented:**
  - The header pill reads `🎒 held / cap` and turns amber at 90% and red when full.
  - Equip best is a large button pinned under the selected-pet sheet. It shows ▲ when a backpack pet would earn more on the plot.
  - Existing features kept: the two-tap Sell confirm, Lock, Fuse, the Show filter and Sort. The contrast tests still apply.
- **Acceptance:** test "panels: … capacity and Equip best" (exact pill text, the full-backpack colour, the button under the sheet and inside the panel). Render: `v7-pets`.

## 4. Hub and plot

- **Observed:**
  - A compact Index / Shop rail on the left and Animals on the right.
  - Fenced plots, a striped stall, and a sign with plot capacity and a price.
  - Navigation is clear, but there is a lot of lime green and studs.
  - The camera is very close to the avatar.
- **Inferred:** the plot sign is how players read other players' progress.
- **Transfer:**
  - Fenced plots with a readable gate sign that shows capacity.
  - Striped stalls that show their real goods.
- **Avoid:**
  - Saturated lime.
  - Stud textures everywhere.
  - Stacked signs.
- **Implemented:**
  - Plot gate signs now read `+86 / sec · 6/8 pets` (`PlotService.signText`).
  - The snack stall counter shows all eight real snack models, the same shapes as in the shop and the hand, on a riser.
  - The hub layout (plaza, paths, fenced plots, stalls) was **kept**. The top-down and perspective renders already show clear paths and sightlines, so it wasn't rebuilt this pass.
- **Acceptance:** test "world: … plot capacity signs, real snacks on the stall". Render: `stall`.

## 5. Training post

- **Observed:**
  - The avatar hangs from a pull-up bar with raised arms, with "+1 XP" above.
  - A blue Level / XP bar at the bottom and an obvious red STOP button.
- **Inferred:** training is a toggle you stop explicitly. The animation's motion can't be seen in a still.
- **Transfer:**
  - The character physically trains.
  - An explicit Stop.
  - Visible level progress.
- **Avoid:**
  - Locking the player in place.
  - Fake XP that isn't tied to real numbers.
- **Implemented:**
  - `TrainPose.luau` adds a procedural overhead press on the character's shoulders (plus elbows on R15) through Motor6D `C0`. It blends in and `stop()` restores every joint exactly.
  - Tapping Train starts a session. The button turns into a red **Stop**, and the throw meter is replaced by a training bar showing level, per-rep gain (×2 in the Gym) and progress, all from `GameMath.trainLevel`, which is built on `trainGain`.
  - Holding still works as before (release stops).
  - A session ends on Stop, Q, moving, opening a panel, throwing, a cutscene, death or respawn, and pauses itself after 180 s.
- **Acceptance:** tests "training pose…" (R15 and R6: joints move, then restore exactly; safe to stop twice or with no joints) and "training sessions…". Render: `v7-training`.
- **Unverified:** the pose angles assume the default R15 and R6 joint frames. Whether it reads well alongside the Animate script has not been checked in Studio.

## 6. Biome corridor with luck

- **Observed:**
  - A long, readable canyon with sparse trees beyond a clear centre.
  - A white boundary line across the ground.
  - "Forest" and "2.19x LUCK" at the top of the screen.
  - A banana as the focal point.
- **Inferred:** the luck figure updates per zone. We can't tell whether it is real.
- **Transfer:**
  - A zone name when entering a zone.
  - A visible ground boundary.
  - A clear centre line.
  - A luck readout.
- **Avoid:** any multiplier the server doesn't actually use.
- **Implemented:**
  - A zone banner (name, plus "craves X · your snack ✓") appears as the player's own snack crosses into each biome.
  - A painted zone band and an ivory edge line span the lane at every biome boundary.
  - A faint dashed aim line runs down the lane centre.
  - The luck readout (`🍀 Luck xA · xB on a craving`) comes from `GameMath.luckPreview`, which uses exactly the same formula as `computeThrow`. It shows both outcomes because the combo depends on where the snack lands. While charging in the Sweet zone, the caption adds the ×1.35 Sweet luck.
- **Acceptance:** tests "luck HUD uses the server's throw formula" (every snack × streak × weather, for both the match and miss cases) and "world: zone boundary bands, aim line…". Render: `v7-zone`.

## 7. Gold pet discovery (staged catch)

- **Observed:**
  - The food lies on the ground next to a gold, low four-legged animal with claws.
  - The camera is low and close.
  - Ring / vignette framing.
  - The name is partly hidden ("B_DG_R").
- **Inferred:** a mystery reveal before the full name.
- **Transfer:**
  - A low, close specimen camera with the pet's silhouette in the middle of the frame.
  - The food stays in the scene.
- **Avoid:** heavy vignettes. The hidden-name tease isn't used, because our Index already shows ??? silhouettes.
- **Implemented:**
  - The specimen shot from section 2. The landed snack stays visible until the flight cleans up.
  - Distinct snack models (section 9) make the food readable on the ground.
- **Acceptance:** test "specimen shot…" (the camera is on the face side, aims at the body, and widens for bigger pets).

## 8. Food on the ground

- **Observed:**
  - A simple carrot model with clear leaves on the ground.
  - Radial speed lines at the screen edges.
  - Nothing else.
- **Inferred:** an anticipation beat before the pet appears. Its timing can't be seen in a still.
- **Transfer:** the food silhouette has to read on its own.
- **Avoid:** full-screen radial lines (motion sickness; they also fight our Reduce motion setting).
- **Implemented:**
  - `FoodModelBuilder` gives each of the eight snacks its own multi-part silhouette:
    - a berry with seeds and a leaf crown;
    - a bone with knobs;
    - a curved chili with a stem;
    - a five-point cookie;
    - a fluted tart with berries;
    - a T-bone steak with grill marks;
    - a drumstick with a small flame;
    - a nugget with an orbit ring.
  - The same model is used in the hand, in flight, in cutscenes, in the shop and on the stall.
  - The landing keeps the existing restrained dust, ring and marker effects.
- **Acceptance:** test "snack models…" (at least four parts each; safe collision and query flags; size within 3.2 studs; no two snacks share a silhouette; the rig is welded to its core; no asset IDs). Render: `foods`.

## 9. Throw wind-up

- **Observed:** the avatar winds up with a raised arm at the throw line next to the hub; the throw direction is clear.
- **Inferred:** a wind-up animation. Its timing can't be seen in a still, and none is copied.
- **Transfer:** the held snack should read as "loaded".
- **Avoid:** inventing animation timing from one frame.
- **Implemented:**
  - The held snack is now the real model.
  - Its wobble and spin speed up as the charge builds (the spin is off under Reduce motion), with the existing wind-up motes, Sweet outline and dotted arc preview.
  - There's no arm animation on throw: it is not verified and was left out.
- **Acceptance:** source checks in "snack models…". The rest is not runtime-verified.

## 10. Gold badger reveal

- **Observed:** "GOLD" in small caps above a large "BADGER", then "$18/s", an angled NEW! badge, and "tap to continue".
- **Inferred:** material → species → income is the deliberate reading order.
- **Transfer:** exactly that order, with the NEW badge angled beside the name.
- **Avoid:** huge outlined type, and covering the pet.
- **Implemented:**
  - The catch reveal (section 2) and the hatch / fusion card both use: material line (tinted with the material colour), species (stepped font size so it always fits, no `TextScaled`), rarity and size tags, then income.
  - The NEW badge is rotated −10°.
- **Acceptance:** test "catch reveal…". Renders: `v7-catch`, `v7-hatch`.

## 11. Power meter

- **Observed:**
  - A tall, segmented vertical meter in the centre (green → yellow → red) with a white moving marker and "+6".
  - "TAP TO THROW!" written over the avatar.
- **Inferred:** a timing-tap mechanic.
- **Transfer:**
  - Segments and a marker that read without colour.
  - A short caption saying where the throw will land.
- **Avoid:**
  - Covering the avatar.
  - Replacing our server-checked hold-and-release Sweet zone with a tap mechanic.
- **Implemented:**
  - The horizontal meter stays in the bottom cluster.
  - It now has ten tick segments, a white marker that follows the charge, and an amber gradient fill.
  - The labelled Sweet zone is unchanged.
  - The caption gives the landing distance and zone, plus the Sweet luck when you're in the zone.
  - The server still checks every release.
- **Acceptance:** the "HUD layout" test (no overlaps, on screen, clear of the touch controls on six viewports). Render: `v7-charging`.

## Engine docs relied on

- [ViewportFrame](https://create.roblox.com/docs/reference/engine/classes/ViewportFrame) and [Camera](https://create.roblox.com/docs/reference/engine/classes/Camera): used for the shop previews and the specimen camera.
- [Assemblies](https://create.roblox.com/docs/physics/assemblies): "An Anchored part will always be assigned as the root part". This is the basis for welding the snack details to an anchored core.
- [WeldConstraint](https://create.roblox.com/docs/reference/engine/classes/WeldConstraint): keeps parts "in the same relative position and orientation".
- [Motor6D](https://create.roblox.com/docs/reference/engine/classes/Motor6D): the pose layers `C0` and leaves `Transform` to animations.

The docs I fetched don't spell out two behaviours, so these remain assumptions until a Studio check:
- that moving the anchored core by CFrame carries the welded details with it;
- that the Animator only writes `Transform`.

## v8: hub composition (follow-up to section 4)

The random hub tree scatter is replaced by a designed layout (`WorldBuilder.buildHubLandscape`):

- **Throw Line gateway:** an arch across the avenue at z = −70 that frames the straight
  view from the spawn to the lane.
- **Pet Plots gateways:** one arch on each side, where the cross path meets the plot
  promenades.
- **Stall forecourts:** paved areas in front of the snack shop and the hatchery.
- **Cross boulevard:** 16 trees in pits along the cross path.
- **Hedges:** along the hub side of both promenades, with a gap at every crossing.
- **Groves:** four groves, each with a bench, filling the empty quadrants.

These stay as they were: plot positions and spacing, the gym (`GymCenter`), the stalls,
the lane, and every progression distance.

**Evidence:** top-down maps and a spawn-view render from the built place file. They are
approximate renders, not Roblox screenshots.

**Tests:**
- "hub: landscaping and gateways never block a path";
- "hub: spawn on open ground facing the Throw Line, every stall reachable by path";
- "world budgets" (3,106 parts, 31 lights, 22 emitters).

**Audio:** none of the verified built-in client sounds is an ambience loop, so ambience
and music stay off until the owner sets an uploaded asset id they have permission to use.

## What is still open

- Nothing in this pass has been played or heard in Roblox Studio. Studio can't run in this
  environment.
- Music and ambience still need audio the owner uploads and has permission to use.
- Gem pack IDs are still unset.
- The biomes' terrain silhouettes were not reworked beyond the v5 and v7 boundary
  markers.
