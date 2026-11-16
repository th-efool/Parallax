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

## 3. Production-Ready Godot 4 Shaders (`assets/shaders/`)

Agents can save these directly into `assets/shaders/` when implementing visual polish (Day 3+ / Day 6):

### 3.1 `mirror_spectral.gdshader` (Phantom Twins, Spectral Bridge, Mirror Echoes)
Features cobalt Fresnel rim glow, subtle holographic scanlines, and animated dissolve (`dissolve_amount` `0.0 -> 1.0` on death/shift).
```glsl
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 base_tint : source_color = vec4(0.06, 0.14, 0.30, 0.72);
uniform vec4 rim_color : source_color = vec4(0.20, 0.75, 1.00, 1.00);
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float rim_strength : hint_range(0.0, 5.0) = 2.4;
uniform float scanline_density : hint_range(10.0, 150.0) = 55.0;
uniform float scanline_speed = 3.0;
uniform sampler2D dissolve_noise : hint_default_white;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    float n = texture(dissolve_noise, UV * 2.0).r;
    if (n < dissolve_amount) {
        discard;
    }
    float edge = smoothstep(dissolve_amount, dissolve_amount + 0.08, n);
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
    float scan = 0.9 + 0.1 * sin(UV.y * scanline_density + TIME * scanline_speed);

    ALBEDO = base_tint.rgb * scan;
    EMISSION = rim_color.rgb * (fresnel * rim_strength + (1.0 - edge) * 3.0);
    ALPHA = clamp(base_tint.a + fresnel * 0.65, 0.0, 1.0);
}
```

### 3.2 `sword_slash_trail.gdshader` (Amber Reality & Cobalt Mirror Swing Arcs)
```glsl
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 slash_color : source_color = vec4(1.0, 0.65, 0.2, 1.0); // Amber default; tween to Cyan in Mirror
uniform sampler2D noise_tex : hint_default_white;
uniform float progress : hint_range(0.0, 1.0) = 0.5;
uniform float intensity : hint_range(0.5, 5.0) = 2.5;

void fragment() {
    float trail_mask = smoothstep(0.0, 0.25, UV.x) * (1.0 - smoothstep(progress - 0.15, progress + 0.05, UV.x));
    float arc_fade = sin(UV.y * 3.14159);
    float streaks = texture(noise_tex, vec2(UV.x * 2.0 - TIME * 4.0, UV.y * 3.0)).r;
    float alpha = clamp(trail_mask * arc_fade * (0.4 + 0.6 * streaks), 0.0, 1.0);
    ALBEDO = slash_color.rgb * intensity;
    ALPHA = alpha * slash_color.a;
}
```

### 3.3 `realm_shift_pulse.gdshader` (Fullscreen `ColorRect` 0.20s Q-Transition Ripple)
```glsl
shader_type canvas_item;

uniform float shift_progress : hint_range(0.0, 1.0) = 0.0; // Animate 0 -> 1 on shift
uniform vec4 pulse_color : source_color = vec4(0.2, 0.78, 1.0, 1.0);
uniform float thickness = 0.12;

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    float ring = smoothstep(shift_progress - thickness, shift_progress, dist)
               * (1.0 - smoothstep(shift_progress, shift_progress + thickness, dist));
    float fade = 1.0 - shift_progress;
    COLOR = vec4(pulse_color.rgb, ring * fade * 0.55);
}
```

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
- **Optional Camera Upgrade**: *PhantomCamera* (only if `SpringArm3D` proves insufficient, though built-in `SpringArm3D` + `Camera3D` easily covers PARALLAX requirements with zero extra dependencies).

---

## 6. Project Asset Register (Populate as Assets Are Imported)

| Asset Name | Local Path (`res://...`) | Source | License | Attribution Required? |
| :--- | :--- | :--- | :--- | :--- |
| `KayKit Adventurers (Knight, Barbarian + textures)` | `assets/models/characters/Knight.glb`, `Barbarian.glb`, `knight_texture.png`, `barbarian_texture.png`, `assets/textures/` | `KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0` | `CC0 1.0` | `No` |
| `KayKit Skeletons (Skeleton_Warrior, Skeleton_Rogue + texture)` | `assets/models/characters/Skeleton_Warrior.glb`, `Skeleton_Rogue.glb`, `skeleton_texture.png`, `assets/textures/` | `KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0` | `CC0 1.0` | `No` |
| `KayKit Dungeon Remastered (20 .glb architecture/prop pieces + texture)` | `assets/models/dungeon/{floor_tile_*,wall*,pillar*,column,rubble_large,stairs_wide,torch_lit,banner_red,banner_blue,box_large,barrel_large}*.glb`, `dungeon_texture.png`, `assets/textures/dungeon_texture.png` | `KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0` | `CC0 1.0` | `No` |
| `Production Shaders (Spectral, Slash Trail, Shift Pulse)` | `assets/shaders/mirror_spectral.gdshader`, `sword_slash_trail.gdshader`, `realm_shift_pulse.gdshader` | Authored for PARALLAX | `Project-Owned` | `No` |
| `Runtime-synthesized gore/feel SFX (no files)` | Generated in memory by `scripts/core/game_feel.gd` (`slash_flesh`, `bone_crunch`, `splat`, `whoosh_light`, `whoosh_heavy`, `clang`, `thud`, `land_heavy`, `gib_burst`) | Authored for PARALLAX | `Project-Owned` | `No` |
| `Procedural ambient fauna & flora (no files)` | Bodies, wing textures, glow sprites, grass tufts + wind shader generated by `scripts/ambient/fauna_mesh_kit.gd`; creature sounds (`caw`, `squeak`, `chirp`, `chime`, `flutter`, `spore_puff`) synthesized in `game_feel.gd` | Authored for PARALLAX | `Project-Owned` | `No` |
| `Borrowed KayKit prop meshes (no new files)` | Skeleton rigs reuse `Barbarian.glb::1H_Axe`, `Knight.glb::{Round_Shield,1H_Sword,1H_Sword_Offhand}` at runtime via `CharacterLoadout`; splat decal texture is procedurally generated by `GoreFX` | KayKit (see rows above) | `CC0 1.0` | `No` |
| `12 Procedural Combat/Realm SFX + Dark Colosseum Drone Loop` | `assets/audio/sfx/{shift_to_mirror,shift_to_reality,shift_rejected,sword_light,sword_heavy,landing_slam,enemy_hit,shield_deflect,pillar_crack,pillar_collapse,mirror_shatter,gate_open}.wav`, `assets/audio/music/colosseum_drone_loop.wav` | Generated 16-bit PCM `44.1 kHz` WAVs | `Project-Owned` | `No` |
