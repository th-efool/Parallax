# PARALLAX — Curated 3D RPG Resources, Asset Catalog & Shaders

> Researched high-quality **CC0 / Free Commercial-Use** 3D assets, animation packs, PBR textures, SFX/music sources, Godot 4 plugins, and production-ready `.gdshader` templates tailored specifically to **PARALLAX**.
> **Rule**: Whenever an asset is downloaded into `assets/`, record its exact file path, source URL, and license in Section 6 (Project Asset Register) below.

---

## 1. Architecture, Ruins & Environment Kits (Dark Colosseum / Stone Ruins)

| Resource | License | Format | Best Use in PARALLAX | Where to Source |
| :--- | :--- | :--- | :--- | :--- |
| **Quaternius — Modular Ruins Pack** | **CC0** (Public Domain) | `.gltf` / `.glb` | Ruined stone pillars, broken arches, cracked floor tiles, rubble piles for Entry Vestibule, Hall of Echoes & Collapsed Gallery | `quaternius.com` or `poly.pizza` (search *"Modular Ruins"*) |
| **KayKit — Dungeon Pack (Remastered)** | **CC0** | `.gltf` / `.fbx` | Crisp modular stone walls, pillars, stairs, pressure plates, barred iron gates, braziers/torches | `kaylousberg.com` / Itch.io (*KayKit Dungeon Remastered*) |
| **Avramania — Dungeon & Ruins Low Poly Pack** | **CC0** | `.glb` / `.gltf` | Grid-snapped (`2m`) crypt corridors, archways, wall torches with flame animations, barred gates | Itch.io (*Avramania Dungeon & Ruins*) |
| **Kenney — Modular Dungeon / Fantasy Kit** | **CC0 1.0** | `.glb` | Clean blockout/props fallback (gates, plinths, banners) — darken materials in Godot via `StandardMaterial3D` | `kenney.nl/assets` |
| **ambientCG** *(Stone / Cobble / Metal)* | **CC0** | 2K PNG (`Color`, `NormalGL`, `Roughness`, `AO`, `Displacement`) | High-detail weathered limestone, chiseled colosseum floor tiles, rusted iron gates (`_NormalGL` fits Godot natively!) | `ambientcg.com` (search `StoneWall`, `Tiles`, `Rock`, `Metal`) |
| **Poly Haven** *(HDRIs & Textures)* | **CC0** | `.exr` / `.hdr` & PBR Maps | Moody overcast/dusk outdoor sky HDRI for `PanoramaSkyMaterial` + cracked mossy stone textures | `polyhaven.com` |
| **Sketchfab** *(Colosseum Arches / Altar / Swords)* | **CC0 / CC-BY** *(verify per item)* | `.glb` / `.gltf` | Hero props: Shattered Mirror frame, Shielded Knight shield/sword, Warden greatsword | `sketchfab.com` (filter: *Downloadable + CC0*) |

### Godot 4 PBR & Lighting Recipe for Moody Dark Fantasy
- Pair modular low-poly/stylized meshes with **2K ambientCG `_NormalGL` + `_Roughness` + `_AO`** maps on shared `StandardMaterial3D` resources so stone surfaces catch dramatic light shafts cleanly without blowing polycounts.
- Use `WorldEnvironment`: Enable **SSAO** (darkens pillar bases & masonry crevices), **ACES/Filmic Tonemap**, subtle **Bloom/Glow** (exclusively on amber torch embers, cracked pillar fracture fault, Warden Phase 2 runes, and Mirror cobalt edges), plus a subtle `FogVolume` or distance fog.

---

## 2. Rigged 3D Characters & Combat Animations

| Resource | License | Format | Best Use in PARALLAX | Where to Source |
| :--- | :--- | :--- | :--- | :--- |
| **KayKit — Character Pack: Skeletons** | **CC0** | `.gltf` | **Skeleton Guard**, **Phantom Twin** (apply `mirror_spectral.gdshader`!), and armored Skeleton Knight base for **Shielded Guard** | Itch.io (`KayKit Skeletons`) or Godot Asset Library |
| **KayKit — Adventurers / Knight + Character Animations (160+)** | **CC0** | `.gltf` | Humanoid combat animations (3-hit sword combo, heavy overhead swing, dodge roll, jump/fall, shield bash, hit react, death) | `kaylousberg.com` / Itch.io |
| **Quaternius — Universal Animation Library (Godot Edition)** | **CC0** | 30fps `.glb` | **120+ animations** built explicitly with Godot 4 retargeting & Root Motion support — ideal universal `AnimationLibrary` (`Idle`, `Run`, `Jump`, `Roll`, `Slash`, `Heavy`) | Quaternius Itch.io (*Universal Animation Library*) |
| **Adobe Mixamo** *(Sword & Shield / Great Sword Packs)* | Free Commercial Use *(no redistribution as raw assets)* | `.fbx` -> import `.glb` via Blender/Godot | **Protagonist Warrior** (auto-rigged female fighter + red cloth cape via bone chain or SoftBody/Shader wind) & **The Warden** (massive Great Sword cleaves, lunges, staggers) | `mixamo.com` |

### Godot 4 Animation Retargeting Workflow
1. Select imported animation `.glb` -> **Import** dock -> **Retarget** -> Create `BoneMap` with `SkeletonProfileHumanoid` -> **Reimport**.
2. Export retargeted animations as a shared `.res` (`AnimationLibrary`) so `Player`, `Skeleton`, `Phantom`, `Shielded Guard`, and `Warden` can mix Mixamo + Quaternius + KayKit clips on one `AnimationPlayer` / `AnimationTree`.
3. **CRITICAL Forward Axis Check**: Check imported model local forward (`+Z` vs `-Z`). Rotate child `ModelRoot` `180°` around Y if model faces `+Z` while `CharacterBody3D` uses `-Z` for `look_at()`.

---

## 3. Production Godot 4 Shaders (`assets/shaders/`) — live files are the source of truth

> Inline listings were removed in Claude Pass B (they had drifted). Read the `.gdshader` files directly.

| Shader | Used By | Key Uniforms / Features |
| :--- | :--- | :--- |
| `mirror_spectral.gdshader` | Phantom Twins (`CharacterAnimationBridge`), Mirror stepping stones, spectral bridge, suspended weight (builder `"spectral"` surface) | Fresnel rim (`rim_power`, `rim_strength`), world-space scanlines, **procedural animated spectral alpha noise** (`spectral_noise_strength/scale/speed`, `min_alpha`), dissolve (`dissolve_amount`; `use_noise_texture` to use `dissolve_noise`). |
| `sword_slash_trail.gdshader` | `PlayerController._spawn_slash_arc_vfx()` on `CombatVFX.build_arc_ribbon_mesh()` ribbons | UV.x along swing / UV.y inner->outer. Tween `progress` `0 -> 1 + trail_length`, then `fade` -> 0. `slash_color`, `core_color`, `intensity`; procedural streaks unless `use_noise_tex`. |
| `realm_shift_pulse.gdshader` | `Main/RealmShiftFX/PulseOverlay` (ColorRect, CanvasLayer 0) via `RealmEnvironmentController.pulse_overlay_rect_path` | `shift_progress` 0->1 over `0.20 s`. Chromatic aberration (`max_aberration`) + barrel lens distortion (`max_distortion`) + vignette scale with `sin(pi*t)` -> **peak at t = 0.5**. Samples `hint_screen_texture`; expanding ring tinted `pulse_color`. |
| `realm_stone.gdshader` | All opaque greybox floors/walls/rubble + breakable pillars (builder `"stone"` surface; one cached `ShaderMaterial` per tint) | World-space triplanar running-bond masonry. `mirror_blend` 0 (warm limestone) -> 1 (cobalt slate with **emissive runic mortar seams**), tweened `0.20 s` by `ColosseumGreyboxBuilder` on realm change (`0.5` when merged). |
| `mirror_obsidian.gdshader` | `Stage05_ExecutionArena/CentralMirrorPlane/IntactVisual/MirrorPlaneMesh` | Translucent obsidian glass (`surface_alpha` 0.5 — Warden spawns inside the plane), cobalt Fresnel, liquid ripple, Voronoi fracture lines driven by `crack_amount` (builder maps Warden HP 1000 -> 500 to 0 -> 1). |

---

## 4. Audio & SFX Packs

| Resource | License | Content Fit for PARALLAX | Where to Source |
| :--- | :--- | :--- | :--- |
| **Sonniss GDC Game Audio Bundles** | 100% Free Commercial (No Attribution) | AAA Foley: broadsword slashes, shield clangs, stone collapses, eerie dungeon wind, dark impact stings | `sonniss.com/gameaudio` |
| **OpenGameArt Dark Fantasy / Sword Combat** | **CC0** / CC-BY *(check tag)* | Orchestral dark ambient arena loops + sword/skeleton combat SFX (`Cynicmusic`, `Reitanna`, `SubspaceAudio`) | `opengameart.org` |
| **Freesound.org** *(Filter: CC0)* | **CC0** | Glass harmonic chime + reverse whoosh (layer to create signature `Q` Dimension Shift SFX), deep stone crumble (`Cracked Pillar`), mirror shatter | `freesound.org` |
| **Kenney — Impact / RPG Audio** | **CC0** | Crisp UI clicks, stone steps, wood/metal hits for rapid Day 2–4 prototyping | `kenney.nl/assets` |

---

## 5. Helpful Godot 4 Addons (Optional Helpers — Do Not Overbloat)
- **Installed**: `godot-ai` v4.4.1 (`addons/godot_ai`) — live editor & automated verification MCP bridge.
- **Installed (project-owned)**: `PARALLAX Squad AI` (`addons/parallax_squad_ai`, editor plugin enabled in `project.godot`) — streaming AI chat / STT / TTS for the ally squad; no third-party code. See `05` §2.4.
- **Optional Camera Upgrade**: *PhantomCamera* (only if `SpringArm3D` proves insufficient, though built-in `SpringArm3D` + `Camera3D` easily covers PARALLAX requirements with zero extra dependencies).

---

## 6. Project Asset Register (Populate as Assets Are Imported)

| Asset Name | Local Path (`res://...`) | Source | License | Attribution Required? |
| :--- | :--- | :--- | :--- | :--- |
| `KayKit Adventurers (Knight, Barbarian + textures)` | `assets/models/characters/Knight.glb`, `Barbarian.glb`, `knight_texture.png`, `barbarian_texture.png`, `assets/textures/` | `KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0` | `CC0 1.0` | `No` |
| `KayKit Skeletons (Skeleton_Warrior, Skeleton_Rogue + texture)` | `assets/models/characters/Skeleton_Warrior.glb`, `Skeleton_Rogue.glb`, `skeleton_texture.png`, `assets/textures/` | `KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0` | `CC0 1.0` | `No` |
| `KayKit Skeletons (Skeleton_Mage, Skeleton_Minion, Skeleton_Staff prop)` — added 2026-11-21 | `assets/models/characters/Skeleton_Mage.glb` (Hexcaster), `Skeleton_Minion.glb` (Warden colossus + Warden thralls), `assets/models/characters/props/Skeleton_Staff.gltf` + `.bin` + `skeleton_texture.png` (Hexcaster staff) | `KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0` (GitHub raw) | `CC0 1.0` | `No` |
| `KayKit Dungeon Remastered (20 .glb architecture/prop pieces + texture)` | `assets/models/dungeon/{floor_tile_*,wall*,pillar*,column,rubble_large,stairs_wide,torch_lit,banner_red,banner_blue,box_large,barrel_large}*.glb`, `dungeon_texture.png`, `assets/textures/dungeon_texture.png` | `KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0` | `CC0 1.0` | `No` |
| `Poly Haven PBR texture sets (2k JPG: diff / nor_gl / arm)` — Large Sandstone Blocks, Stone Tiles 02, Cobblestone Floor 08, Rock Face, Coast Sand Rocks 02, Marble 01, Castle Brick 07 | `assets/textures/pbr/<id>/<id>_{diff,nor_gl,arm}_2k.jpg` (imported VRAM-compressed + mipmaps; normals flagged) | `polyhaven.com` (downloaded 2026-11-16) | `CC0 1.0` | `No` |
| `Poly Haven HDRI — Kloppenheim 06 (Pure Sky), 4k` | `assets/sky/kloppenheim_06_puresky_4k.hdr` (BC6H). Baked sun at panorama `u = 0.6069`, elevation `8.26°` | `polyhaven.com` (downloaded 2026-11-16) | `CC0 1.0` | `No` |
| `Landscape shaders` | `assets/shaders/journey_terrain.gdshader` (slope/height layered terrain reusing Poly Haven `rock_face` + `coast_sand_rocks_02`), `journey_water.gdshader` (ripple normals, fresnel sky reflection) | Authored for PARALLAX | `Project-Owned` | `No` |
| `Grand Journey shaders` | `assets/shaders/realm_pbr.gdshader` (world triplanar PBR + Mirror rune cavities via global `realm_mirror_blend`), `journey_sky.gdshader` (HDRI <-> moonlit night), `cloud_sea.gdshader`, `banner_cloth.gdshader` | Authored for PARALLAX | `Project-Owned` | `No` |
| `Production Shaders (Spectral, Slash Trail, Shift Pulse, Realm Stone, Mirror Obsidian)` | `assets/shaders/mirror_spectral.gdshader`, `sword_slash_trail.gdshader`, `realm_shift_pulse.gdshader`, `realm_stone.gdshader`, `mirror_obsidian.gdshader` | Authored for PARALLAX (Pass 4 + Claude Passes A/B) | `Project-Owned` | `No` |
| `Runtime-synthesized gore/feel SFX (no files)` | Generated in memory by `scripts/core/game_feel.gd` (`slash_flesh`, `bone_crunch`, `splat`, `whoosh_light`, `whoosh_heavy`, `clang`, `thud`, `land_heavy`, `gib_burst`) | Authored for PARALLAX | `Project-Owned` | `No` |
| `Quaternius animated animals (Fox, Deer, Stag, Alpaca, Raccoon, Rat)` | `assets/models/fauna/quaternius/*.glb` (+ `LICENSE.txt`) | `quaternius.com` via `poly.pizza` (downloaded 2026-11-17) | `CC0 1.0` | `No` |
| `Quaternius Stylized Nature MegaKit subset (21 models: common trees, pines, bushes, fern, clover, big plant, mushroom, flower & grass clumps, wispy grass short/tall, 2 medium rocks)` | `assets/models/flora/megakit/*.glb` (+ `LICENSE.txt`) | `quaternius.com` via `poly.pizza` (downloaded 2026-11-17) | `CC0 1.0` | `No` |
| `Procedural ambient fauna & flora (no files)` | Bodies, wing textures, glow sprites, grass tufts + wind shader generated by `scripts/ambient/fauna_mesh_kit.gd`; creature sounds (`caw`, `squeak`, `chirp`, `chime`, `flutter`, `spore_puff`) synthesized in `game_feel.gd` | Authored for PARALLAX | `Project-Owned` | `No` |
| `Borrowed KayKit prop meshes (no new files)` | Skeleton rigs reuse `Barbarian.glb::1H_Axe`, `Knight.glb::{Round_Shield,1H_Sword,1H_Sword_Offhand}` at runtime via `CharacterLoadout`; splat decal texture is procedurally generated by `GoreFX` | KayKit (see rows above) | `CC0 1.0` | `No` |
| `12 Procedural Combat/Realm SFX + Dark Colosseum Drone Loop` | `assets/audio/sfx/{shift_to_mirror,shift_to_reality,shift_rejected,sword_light,sword_heavy,landing_slam,enemy_hit,shield_deflect,pillar_crack,pillar_collapse,mirror_shatter,gate_open}.wav`, `assets/audio/music/colosseum_drone_loop.wav` | Generated 16-bit PCM `44.1 kHz` WAVs | `Project-Owned` | `No` |
| `Music (5 tracks)` | `assets/audio/music/journey_explore.mp3` ("The Ancient Legend"), `interior_explore.ogg` ("Dungeon002"), `combat_war.ogg` ("War Theme v2"), `boss_epic_loop.wav` (Juhani Junkala "Epic Boss Battle", seamless loop), `ending_fallen_dawn.wav` ("A Fallen Dawn") | opengameart.org (downloaded 2026-11-17) | `CC0 1.0` | `No` |
| `Ambience loops` | `assets/audio/ambience/{rain_light_loop.wav, rain_heavy_loop.ogg, wind_cliff_loop.ogg, wind_gust_loop.ogg, thunder_1.ogg, fire_loop.wav, interior_room_tone.ogg}`. **WeatherDirector loads `rain_light_loop`, `rain_heavy_loop`, `wind_cliff_loop`, `thunder_1..6` by name** (add `thunder_2..6` to get more variety) | opengameart.org: rain_on_window_loop, Dark Rainy Night, Wind pack, wind woosh loop, rain-thunder, fire, dark_cavern_ambient_001 | `CC0 1.0` | `No` |
| `SFX banks (216 clips, 43 banks)` | `assets/audio/sfx/<group>/<bank>/<bank>_NN.(ogg/wav)` with groups `player` (footstep_stone/sand/wet, armor_foley, sword_light/heavy, dodge, hurt, attack_shout, death), `combat` (hit_flesh/bone/metal, shield_block, body_fall, landing_slam), `world` (stone_crack/collapse, glass_shatter, gate_iron, switch, mirror_whisper), `enemy` (skeleton/phantom/guard/warden × idle/attack/hurt/death, skeleton_step, warden_roar), `ui` (click/confirm/back). **Drop a new clip into a bank folder and it is picked up automatically** | opengameart.org packs: Fantozzi footsteps, Kenney RPG + Interface sounds, RPG Sound Pack, swishes, StarNinjas sword + sword clash, 100 CC0 wood/metal, breaking & falling, 100 CC0 SFX v2, footsteps (metal/leather), yelling sounds, exewin death sounds, zombies, bones rattle, Ghost & Lich voice pack, qubodup Ghost Moans, scary high-pitched ghost, 80 CC0 creature SFX 1 & 2, monster roar, troll roars | `CC0 1.0` | `No` |

| `Archetype enemies & squad allies (no new files)` | Reuse KayKit rigs: Hexcaster = `Skeleton_Mage.glb` + borrowed `props/Skeleton_Staff.gltf` (orb on the staff head, light violet tint); non-archetype hostiles keep their texture with a mild tint from `CharacterAnimationBridge._apply_hostile_appearance` (`HOSTILE_TINT`, blackened `HOSTILE_KNIGHT_TINT` for Knight-rig Shielded Guards; never a flat `material_override` — that produced the solid-red Hall skeletons); Grave Brute = `Barbarian.glb` ×1.18 (`2H_Axe`, pale-green tint); Shade Stalker = `Skeleton_Rogue.glb` (borrowed Knight blades, blue tint); Brannoc = `Barbarian.glb` (`1H_Axe` + `Barbarian_Round_Shield`); Sera = `Skeleton_Rogue.glb` (borrowed blades, cyan tint); Ivo = `Knight.glb` (`1H_Sword`, violet tint). Tints are runtime material duplicates; VFX (bolts, rings, sigils) are procedural | KayKit (see rows above) / Authored for PARALLAX | `CC0 1.0` / `Project-Owned` | `No` |
| `External AI services (runtime, optional, no files)` | Google Gemini API (`generativelanguage.googleapis.com`: chat via OpenAI-compatible endpoint, STT + TTS via native endpoints) and/or OpenAI API — only when the user supplies their own key (env / gitignored `.env` / `user://squad_ai.cfg`). Generated speech is streamed, not stored | Google / OpenAI terms of service (user's own account) | Service ToS | `No` (no bundled content) |

- **UI fonts (OFL, Google Fonts repo)**: assets/fonts/Cinzel-Regular.ttf (variable, used at wght 700), CormorantGaramond-Italic.ttf (variable), Rajdhani-Medium.ttf, Rajdhani-SemiBold.ttf - loaded by UITheme.
