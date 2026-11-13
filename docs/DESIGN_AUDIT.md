# Design audit: v3 redesign

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
- **Competitor video:** [YouTube r157nlkQwz4](https://youtu.be/r157nlkQwz4). I could only verify the title ("…INFINITE SIZE MUTATION in THROW FOOD FOR ANIMALS"). I couldn't watch the footage, and nothing here claims it was reviewed or that this game is better.

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

## Not verified

- The game hasn't been playtested in Roblox Studio and there are no in-game screenshots. Checks are limited to the strict type-check, the Rojo build and 57 headless Lune tests against the built place file.
- Purchases haven't been tested against real Roblox services, because nothing is published and the IDs are 0.
