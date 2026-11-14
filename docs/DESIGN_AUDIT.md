# Design audit: v3 redesign and v4 quality pass

This document is for development only. Players get the single `SnackForce_PetToss.rbxl` file.

## What was wrong (from the Studio screenshot)

| Problem | Fix |
| --- | --- |
| Tiny, crowded `TextScaled` text | Fixed type scale on a 1280×720 canvas (caption 15, body 19, title 26, display 34) that scales to the screen. `TextScaled` is banned by a test. FredokaOne is only used for titles, Builder Sans for everything else. |
| Rainbow button stack on the left | Uniform ivory navigation rail with icon and label: Snacks, Eggs, Pets, Index, Store, Travel, Settings, Help. An amber dot means something is ready. |
| Several prompts stacked at the bottom | One context line: "Hold to charge", "Release to throw", "Release now". Away from the line, the primary button becomes "Go to Throw Line". The world has one ProximityPrompt per stall, range 9, `OneGlobally`, and stalls are at least 68 studs apart. |
| Currency pills floating | One wallet bar at the top centre (coins, income, Gems, Paw Tokens), with weather and boost chips under it. |
| Cravings board tiny | Collapsed chip by default ("Cravings · 2 want Berry"). It expands to rows with a ✓ text marker, so it doesn't rely on colour alone. |
| Neon magenta gym ring, floating dumbbells | Wooden gym deck, fence and rubber mats. Plates sit on bars and bars rest on racks. |
| Huge slanted signs crowding the lane | Small upright cream boards beside the paths. The lane within 72 studs of the centre line has only flat markings and short distance posts. |
| Garish mismatched colours | Toy safari park palette: ivory 246,239,224; charcoal 46,42,38; leaf green 60,142,64; amber 242,169,59; terracotta; muted teal. Neon is only used for lava and a reactor window. |

**Contrast:** contrast ratios are checked by the tests (WCAG formula):

| Text | Minimum ratio |
| --- | --- |
| charcoal on ivory | 7 or more |
| muted on ivory or paper | 4.5 or more |
| white on leaf (large bold) | 3 or more |
| charcoal on amber | 4.5 or more |

**Reduced motion:** honours `GuiService.ReducedMotionEnabled` and a saved *Reduce motion* setting. With either on there is no shake, punch, follow camera, flash or confetti, fewer particles, and instant tweens.

**Pets:** all 14 archetypes share one modeling language: rounded-cube bodies, the same glossy eyes and cheeks, and a distinct silhouette for each. The six new Safari archetypes are Lion, Elephant, Giraffe, Hippo, Toucan and Zebra. Ellipsoids now use a built-in Sphere `SpecialMesh`, because Ball parts can't be stretched.

**VFX order:** wind-up while charging, then the release puff and streak, then a flight arc with a ground shadow, then landing dust and a ring, then the pet hop and a small coin burst. Big celebrations are kept for milestones: Epic or rarer, a new best, a first landing in a zone, Space and the Moon.

## References consulted

- **Roblox accessibility guide:** [accessibility](https://create.roblox.com/docs/production/publishing/accessibility). I used its guidance on not relying on colour alone, `ReducedMotionEnabled` and avoiding `TextScaled`.
- **Roblox adaptive design guide:** [adaptive design](https://create.roblox.com/docs/production/publishing/adaptive-design). Used for `ScreenInsets = CoreUISafeInsets`, collapsing secondary UI on small screens and touch minimums.
- **Roblox art style guide:** [choose an art style](https://create.roblox.com/docs/tutorials/curriculums/user-interface-design/choose-an-art-style). Used for a limited palette, icons paired with labels, and a primary/secondary/tertiary hierarchy.
- **Kenney CC0 packs (style references only, nothing copied):**
  - [Cube Pets](https://kenney.nl/assets/cube-pets): chunky rounded toy pets with big glossy eyes.
  - [UI Pack Adventure](https://kenney.nl/assets/ui-pack-adventure) and [UI Pack](https://kenney.nl/assets/ui-pack): cream panels and buttons with a darker bottom lip.
- **Competitor:** [Throw Food For Animals](https://www.roblox.com/games/120219252362013/Throw-Food-For-Animals). I read its public description and thumbnail only. Its loop is: throw food, attract animals, earn, buy better food, train.

## Monetization design

**Primary docs:**
- [Passes](https://create.roblox.com/docs/production/monetization/passes)
- [Developer products](https://create.roblox.com/docs/production/monetization/developer-products)
- [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService)
- [Player data purchasing](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing)
- [Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items)

**Currencies:**
- **Coins:** earned only, never sold.
- **Paw Tokens:** earned only. You get them from quests (+1), a first landing in a zone (+2), a new species (+1) and every 50 catches (+1). They are the only egg currency.
- **Gems:** the only currency you can buy with Robux. Gems only buy fixed, fully described items: Gold Lion Cub, Huge Baby Elephant and Coin Rush (2× plot coins for 30 minutes). Gems never buy eggs, tokens, coins, foods or luck, so no Robux path leads to a random outcome or an odds modifier.

**Exclusive eggs:** the Safari Egg and the Royal Savanna Egg contain seven species you can't catch by throwing. Each egg shows its full odds table, summing to exactly 100%, before you hatch. Luck, weather and combos never change egg odds. Because eggs cost earn-only tokens, they are not paid random items.

**Policy gate:** the server still gates any egg priced in a purchasable currency through `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted`, and treats errors or missing fields as restricted. So if a future config adds a Gem egg, it is gated automatically.

**Game passes:** Double Coins, Auto-Throw Pass, Big Backpack (+150 pets) and Golden Trail (cosmetic).
- **Ownership checks:** `UserOwnsGamePassAsync` runs on the server when you join, and again after `PromptGamePassPurchaseFinished`.
- **Not stored:** pass ownership is never saved and never trusted from the client.
- **Saved pets:** saves keep up to 300 pets, so a failed pass check never deletes pets.

**Developer products** (Gem packs of 100, 550 and 1,200):
- **One handler:** a single `ProcessReceipt` callback, `Server/Receipts.luau`, grants all of them.
- **Grant and save:** it waits for your save to load, skips any PurchaseId already in the save, adds the Gems and records the PurchaseId, then saves. It only returns `PurchaseGranted` after the save succeeds.
- **Failed saves:** if the save fails, both changes are rolled back and it returns `NotProcessedYet`.
- **Gem spending:** blocked while a receipt is saving.
- **Purchase history:** the save keeps the newest 500 PurchaseIds.
- **No grants from the prompt event:** nothing is granted from `PromptProductPurchaseFinished`.

**Session lock:** saves now hold a session lock (`DataService`), so only one server can write your save at a time. A lock that hasn't been refreshed for 5 minutes is taken over. A server that can't get the lock plays without saving and never grants purchases.

**IDs and prices:** every pass and product ID is `0` in `Config/MonetizationConfig.luau`. While an ID is 0, the Store shows "Not available yet", no purchase prompt opens, and no price lookup is made. Once real IDs are set, the Robux prices come from `GetProductInfoAsync`, falling back to `GetProductInfo`. No Robux prices are hard-coded.

## v4 quality pass (2026-11-14)

This pass checked the v3 claims instead of repeating them. Two new dev tools render the **built place** headlessly so layout and models could actually be looked at:

- `tests/gui.luau` runs the real `Client/Hud` and `Client/Panels` modules with fake engine services and draws the GUI tree as SVG. It approximates Roblox layout (Size, Position, AnchorPoint, UIPadding, UIListLayout, UIGridLayout, AutomaticSize with estimated text widths, ScrollingFrame clipping, Sibling ZIndex). Fonts are substitutes and text widths are estimates.
- `tests/render3d.luau` is a small software renderer (perspective camera, painter's algorithm, flat shading) used for pet portraits, viewport previews and world views.

Neither is a Roblox screenshot. Nothing in this pass was run in Roblox Studio.

### What the renders found, and the fixes

| Found | Fix |
| --- | --- |
| The quest card's full-size tap button shared a parent with its `UIListLayout`. Roblox lays out every sibling GuiObject, so the button pushed the quest text below the card. | The list moved into an inner `Body` frame; the tap target is a sibling of it. |
| On an 844×390 phone the 1280×720 canvas scaled to 0.65, so captions rendered at about 10 px and nav labels were tiny. | A scale floor (`Hud.scaleFor`): the canvas is never wider than 900 or taller than 460 logical units on small screens. Captions now render at 12.7 px on 844×390 and 11 px on a 667×375 phone. |
| The left nav column reached into the bottom-left thumbstick corner on touch devices. | The compact layout puts the nav in a 4×2 block under the quest card, with 60-unit cells (44 px or more on every tested phone). |
| The bottom buttons sat over the thumbstick corner on phones and tablets. | On touch screens the cluster is placed between the thumbstick corner and Roblox's small-screen jump button (about W−95…W−25, H−90…H−20, from the PlayerModule TouchJump defaults). |
| Panels were 540 tall on a 462-unit phone canvas. | `Panels:fit` sizes panels to the canvas. The pet sheet scrolls. |
| The quest card, Throw bar and cravings stayed visible around open panels. | `Hud:onPanel` hides them while a panel is open; the wallet and nav stay. |
| Pet previews were framed by height only, so frogs, slimes, the hippo and the toucan were cropped. | `PetModelBuilder.build` now also returns the footprint width, and `PetModelBuilder.portraitCamera` fits both height and width. |
| Pup, Kitty, Bear, Dragon and Lion shared one standing four-leg block. | Kitty now sits upright with haunches, whiskers and a tail curled on the ground. Bear is a sitting teddy with its feet forward and paw pads. The Dragon has raised wings with a wing bone. |

`tests/run.luau` turns the layout checks into a test at 1280×720, 1920×1080, 800×600, 844×390 touch, 667×375 touch and 1024×768 touch. It checks:
- no HUD regions overlap;
- everything is on screen;
- caption size;
- touch targets of 44 px or more;
- the thumbstick corner and jump button are kept clear;
- every panel fits;
- the play HUD hides behind panels.

### State audit (every screen)

| Screen | States covered after this pass |
| --- | --- |
| Snack Shop | Equipped ✓, Equip (owned), Buy (affordable), locked price with a progress bar toward the next snack. A new **Upgrades** tab shows Buy, "Need N more" and Maxed ✓, with level pips. |
| Pets | Empty, grouped, on plot / partly on plot, 🔒 locked, and **selected** (thick leaf edge plus a detail sheet). The sheet offers Place on plot or Back to backpack, Fuse 3 (disabled with a count, or "Unlock to fuse"), Lock or Unlock, and Sell 1 with a second tap to confirm. |
| Eggs | Hatch (affordable) or "Need N 🐾". Each egg has a 3D preview of every possible pet with its odds, rarity, income and Owned ✓. View or hide odds. |
| Hatch / fusion / offer reveal | The header names the source ("Safari Egg hatched", "Fusion complete", "Fused 3 times · best result", "Added to your pets"). The first tap skips the wobble. **Again · 3 🐾** shows only when you can afford another hatch. |
| Store | Owned ✓, priced, **Checking price…** (configured, not fetched yet), **Finishing…** (a Gem receipt is saving), "Try again later" (fetch error), Not on sale, and Not available yet (unset id). Gem offers show "Need N more 💎" instead of a dead button. |
| Settings, Index, Help | Unchanged, but checked by the panel-fit test. |
| Input | Gamepad ButtonB closes the open panel. |

### Gameplay gaps fixed

- **Pet management.** You could not choose which pets stand on your plot, and nothing could set the saved `locked` flag. The new `ManagePet` remote acts on one group of identical pets. Equip and Unequip move one copy and explain when the plot is full. Lock and Unlock cover the whole group, and locked pets are never auto-sold, sold through Sell matching or fused. Sell 1 prefers a copy that isn't on the plot.
- **Earned upgrades (coins only).** The new `BuyUpgrade` remote and `Config/UpgradeConfig` add three upgrades. Each level has a fixed price and effect, and none touch mutation luck, the sweet spot, combos or weather.
  - Training Coach: +25% strength per training, 4 levels.
  - Craving Chef: +50% craving-match coins, 3 levels.
  - Night Shift: +1 h offline cap, 3 levels.
- **Fusion celebration.** FusePets now fires a reveal for a single fuse, and for Fuse all it shows the best surviving result.
- **Save v4.** Adds `upgrades`. v1–v3 saves migrate with no upgrades and keep `locked`, receipts, Gems and tokens.

### Purchase and persistence fixes

- **Session lock after leaving.** The lock could be re-taken after a player left. An autosave or receipt queued behind the releasing save in `PlayerRemoving` would write again with a fresh lock, so the player's next server waited up to 18 s and then loaded an unsaved session for up to 5 minutes. `Server/SaveGate` now makes the releasing save the session's final write. Leaving sessions stop taking receipts, which return `NotProcessedYet` so Roblox retries them on the next join.
- **Shutdown.** `BindToClose` saved *without* releasing the lock and forced a concurrent write by setting `saving = false`. It now does a releasing save for every player, waiting for any in-flight save first.
- **Prices.** Configured offers report `loading` until fetched. Errored fetches are retried every 30 s, and successful ones refresh every 10 minutes. With every id at 0, no requests are made.
- **Paid random items audit (test).** Paw Tokens only change through gameplay `giveTokens` and egg spending. Gem offers never give tokens or luck, no pass is a luck, token or egg pass, and the PolicyService gate is still consulted for any egg priced in a purchasable currency.

### Sources checked in this pass

These were fetched in this session. Quotes went through a summariser, so check exact wording on the live pages before reusing them.

- **[Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items).** "Paying Robux to buy gems or spin tickets that are spent at a prize wheel" counts as paid random. So any Gem → token, Gem → luck or Robux → egg path would make the Safari Eggs paid random items. None exists, and a test guards it. Odds stay shown for earn-only eggs anyway.
- **[Developer products](https://create.roblox.com/docs/production/monetization/developer-products) and [player data purchasing](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing).** The docs give this order: check the PurchaseId, grant, record, save, then return PurchaseGranted, or NotProcessedYet if the save fails. They also call for a single callback and no grants from `Prompt*PurchaseFinished`. The implementation matches. The docs also mention a newer `BindReceiptHandler`; ProcessReceipt is not deprecated, so it stays.
- **[MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService).** `GetProductInfo` is deprecated in favour of `GetProductInfoAsync`, which is already used first.
- **[Monetization overview](https://create.roblox.com/docs/production/monetization).** It bans fake "always on sale" discounts, false scarcity, countdowns that restart on their own, and pushy copy. The Store has none: Coin Rush is a real fixed duration, and the copy is "Buy · 💎 250" or "Need N more 💎".
- **[Accessibility](https://create.roblox.com/docs/production/publishing/accessibility) and [adaptive design](https://create.roblox.com/docs/production/publishing/adaptive-design).** They cover `GuiService.ReducedMotionEnabled`, `PreferredTextSize`, using symbols alongside colour, and keeping buttons out of the bottom corners where the default touch controls sit. No official minimum text size or touch-target size was found; 44 px is a common platform convention, not a Roblox rule.
- **Not found or blocked.** The performance-optimization pages gave no numeric part, particle or ViewportFrame budgets. `/docs/ui/mobile-input` returned 404, and the Community Standards help page returned 403.
- **[Kenney Cube Pets](https://kenney.nl/assets/cube-pets) (CC0 preview images viewed; style reference only).** The head and body read as one bevelled block of about 1:1 on stubby legs, with big glossy wide-set eyes. Species are told apart by ears, tails and patches, with soft shading and no outlines. That supports keeping one shared face and using pose and add-ons for silhouette.
- **[Kenney UI Pack](https://kenney.nl/assets/ui-pack) and [UI Pack Adventure](https://kenney.nl/assets/ui-pack-adventure).** A lighter button face over a darker 4–5 px lip, small corner radii, and parchment or wood panels. That matches the existing toy button.
- **Competitors.** For [Throw Food For Animals](https://www.roblox.com/games/120219252362013/Throw-Food-For-Animals) only the page text and thumbnail were available: a thick throw arc to a glowing landing ring, colour-coded ground zones, and a big creature labelled with its income.

### Still not done / not verified

- **Not run on Roblox.** No Roblox Studio playtest and no engine screenshots. The renders are approximations.
- **No audio.** Built-in `rbxasset://sounds` paths couldn't be verified offline, and nothing uses unverified ids.
- **World unchanged.** World composition was not reworked in this pass beyond what v3 built.
- **Purchases untested live.** Purchases still haven't been tested against live Roblox services, because all ids are 0.

## v6 audit pass (2026-11-14)

The fresh references and their takeaways are in [REFERENCES.md](REFERENCES.md). The earlier competitor video is no longer used. Every problem below was found in the source or in the offline renders.

| Problem (evidence) | Player impact | Fix | Acceptance test |
| --- | --- | --- | --- |
| No `CharacterAdded` handler in GameClient. | Dying mid-charge left the meter charging and Train held. A respawn during a cutscene could leave the camera on the old Humanoid. | `onCharacter`: skip the cutscene, cancel the charge, release Train, then set `CameraType = Custom` and `CameraSubject` to the new Humanoid. | "quality, respawn recovery and sound variation" |
| Help said "Auto-throw unlocks at 1250 m", the Swamp quest said "unlock Auto-Throw", and Settings could show "🔒 1250 m". | Wrong copy, because Auto-Throw is a free perk. | Copy fixed, and the lock branch removed. | "every former game pass is a free perk…" |
| The Pets panel could only sort. You couldn't tell whether a pet beat your plot pets. | Extra clicks and guesswork. | Show filter (All, On plot, Backpack, Mutated, Locked), a Newest sort, a compare line in the sheet, and an amber dot on Pets when a backpack pet would earn more. | "pet list: group, filter, sort, compare and the upgrade dot" |
| No effects quality option. | Older phones get every emitter, light and small-prop shadow. | Effects quality: Low, applied locally and reversible. | "quality, respawn…" |
| After the last quest the card said "All quests complete". | No goal on screen. | Free-play goal: the next zone, Space, then the Moon. | Rendered HUD |
| Every repeat of a cue had identical pitch. | Repetition fatigue (held Train, charge ticks). | ±3% pitch variation on every play. | "quality, respawn…" |
| A catch showed only a label. | Weak reaction moment. | An emote bubble: ♥, ! (new species) or ★ (rare). | Source check |

**Still open:**
- **Not run in Roblox:** no Studio runtime and nothing heard.
- **No music or ambience:** that needs an owned or permitted audio upload; see REFERENCES.md.
- **World:** the hub and world structure were not rebuilt in this pass.

## Not verified (v3)

- The game hasn't been playtested in Roblox Studio and there are no in-game screenshots. Checks are limited to the strict type-check, the Rojo build and 57 headless Lune tests against the built place file.
- Purchases haven't been tested against real Roblox services, because nothing is published and the IDs are 0.
