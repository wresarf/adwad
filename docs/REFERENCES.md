# Fresh reference board (v6)

This is a development reference only. Players get just `SnackForce_PetToss.rbxl`.

By request, this board does not use the earlier competitor video, or anything previously said about it. Every image below was opened and looked at in this session.
- **Steam images:** store screenshots, which are stills, not footage.
- **Roblox images:** game thumbnails, which are promo art, not gameplay.
- **No video** was watched. Nothing here was copied; these are takeaways only.

| Source | What was inspected | Takeaways |
| --- | --- | --- |
| [Slime Rancher](https://store.steampowered.com/app/433340/) | 3 store screenshots | Squashy creatures with dot eyes, where the mouth shape alone carries emotion. Thin white swirl lines show something being pulled or launched. A tiny panel shows icon + count ("x17"). Rare items glow; common ground stays matte. |
| [Overcooked! 2](https://store.steampowered.com/app/728880/) | 2 store screenshots | Each interactable shows its state as a large icon on a disc. Gold sparkles mark the active actor. Reveal screens use a big outlined title, the characters centred, and bunting plus confetti. |
| [A Short Hike](https://store.steampowered.com/app/1055540/) | Store screenshot | A tight palette carries the cosy feel, not detail. Thin paths and fences lead the eye, and smoke wisps mark the point of interest. No HUD while exploring. |
| [Untitled Goose Game](https://store.steampowered.com/app/837470/) | Store screenshot | Flat pastel shading, with key props set apart by colour. Reactions are small 2D billboard bubbles over the 3D scene. Soft blob contact shadows ground the characters. |
| [Roblox cross-platform guide](https://create.roblox.com/docs/projects/cross-platform) | Doc image + text | The selected slot is enlarged with a bright fill and border. The docs call for input hints (keys or gamepad buttons), adapting to the device, and keeping UI clear of device cutouts and Roblox's own UI. |
| [Pet Simulator 99](https://www.roblox.com/games/8737899170) | 2 game thumbnails + description | The hero pet fills the frame, with an outline and glow for top rarity. Common pets stay plain. |
| [Adopt Me!](https://www.roblox.com/games/920587237) | 2 game thumbnails | Rounded low-poly pets with big glossy eyes. A sleeping-pet emote ("ZZZ") carries the pet-care feeling. |
| [Kenney Interface](https://kenney.nl/assets/interface-sounds), [Impact](https://kenney.nl/assets/impact-sounds) and [Music Jingles](https://kenney.nl/assets/music-jingles) sounds | Asset pages (licence text) | The licence reads "Creative Commons CC0" on every page. [kenney.nl/support](https://kenney.nl/support) says "Attribution is not required." The sound files themselves were not downloaded or heard. |

## What this pass implemented from it

- **Pets panel:**
  - a **Show** filter: All, On plot, Backpack, Mutated, Locked;
  - a **Newest** sort;
  - a compare line in the selected-pet sheet, next to Place on plot ("▲ +12/s vs. weakest on plot");
  - an amber dot on Pets when a backpack pet would earn more on the plot.

  This follows the doc hotbar and the Slime Rancher icon-plus-count panel.
- **Catch emotes:** an emote bubble (♥ caught, ! new species, ★ rare) pops over the caught pet. This follows Goose Game's billboard reactions.
- **Effects quality: Low setting.** It turns off world particle emitters and lights, stops small props casting shadows, and cuts burst particles to 40%. This follows Roblox's [performance guidance](https://create.roblox.com/docs/performance-optimization/improve): use fewer lights, set CastShadow off on small parts, and go easy on particle changes.
- **Respawn recovery.** On `CharacterAdded` the client:
  - skips any cutscene;
  - cancels a charge and releases a held Train;
  - sets `CameraType = Custom` and `CameraSubject` to the new Humanoid.

  This follows the Camera reference: restore CameraSubject to the local Humanoid, and never set it to nil.
- **Sound variation:** each play varies pitch by ±3%, so repeated cues don't sound identical.
- **Post-quest goal.** After the quest line, the quest card shows the next distance target ("Next: the Moon") instead of a dead end.

## Audio licensing and permissions

These come from [Roblox audio assets](https://create.roblox.com/docs/audio/assets) and [asset privacy](https://create.roblox.com/docs/projects/assets/privacy).

- **What you may upload:** only audio "that you're certain you have permission to use". Files can be .mp3, .ogg, .wav or .flac, under 20 MB and 7 minutes.
- **Upload limits:** 100 a month for unverified accounts, 2,000 for ID-verified accounts. Uploads are moderated.
- **Permissions:** uploaded audio is private by default. The experience must be granted permission (Creator Dashboard → Audio → Permissions → the experience's universe ID). Otherwise it is silent at runtime and Output shows an error.
- **Creator Store:** it offers free Roblox and partner sound effects and music for use in experiences. Rights outside Roblox were not confirmed.
- **Recommended route for music and ambience:** an owned or CC0 track, such as Kenney Music Jingles (CC0), uploaded by the game owner, or a Creator Store partner track. Then set `Config/SoundConfig.MusicId` and grant the experience permission. Nothing was uploaded in this pass, so music stays off.
