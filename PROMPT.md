# PROMPT.md — Build a 4-Blink *Before Your Eyes* Experience on the PARALLAX Main Map

> **Target Engine**: Godot `4.7.2.stable` (Forward+), `d:\Desktop\Godot\parallax`
> **Mandatory Reading Before Coding**:
> 1. Read `AGENTS.md` and `MEMORY/00_MEMORY_INDEX_AND_RULES.md` (respect all PARALLAX rules, explicit `preload()`, and hard command/test timeouts).
> 2. Read the complete research package in `research/`:
>    - `research/00_README_RESEARCH_INDEX.md`
>    - `research/01_BEFORE_YOUR_EYES_MECHANICS_AND_DESIGN.md`
>    - `research/02_3D_WINDOW_MEMORY_VISUAL_ARCHITECTURE.md`
>    - `research/03_BLINK_DETECTION_TECH_AND_DEV_RECREATIONS.md`
>    - `research/04_IMPLEMENTATION_STRATEGY_AND_GODOT4_BLUEPRINT.md`
>    - `research/05_NEEDS_EVALUATION_RISKS_AND_CLAUDE_HANDOFF.md`

---

## 1. Goal — What You Are Building

Build a **short, atmospheric, museum-grade 4-blink interactive experience** inspired directly by ***Before Your Eyes*** ("looking into fragmented memories through a painterly 3D window/void, where blinking advances time") — staged **directly inside our existing live main map (`scenes/environment/grand_journey.tscn` / `GrandJourneyBuilder`)**!

**Do NOT break or regress the main PARALLAX combat game.** Build this as a clean, self-contained runnable experience:
- Standalone scene: **`res://scenes/prototypes/before_you_blink.tscn`** (runnable directly via Godot or accessible via a clean non-intrusive **"Memory Experience (4 Blinks)"** button on the Title Screen if desired, without altering main combat gameplay).
- All new scripts under **`scripts/memory_window/`**, shaders under **`assets/shaders/memory_window/`**, UI icons/textures under **`assets/textures/memory_window/`** & **`assets/ui/memory_window/`**, and optional webcam tracker under **`tools/blink_tracker/`**.

---

## 2. The Signature Visual Feel (CRITICAL — Must Match Research!)

This must **NOT** look like a cheap 2D black vignette. Reproduce the exact *Before Your Eyes* "weird 3D window into memory" look documented in `research/02_3D_WINDOW_MEMORY_VISUAL_ARCHITECTURE.md`:

1. **World-Space Multi-Island Painterly Void (Depth-Reconstructed Across the Real Main Map!)**:
   - Because we are reusing the real `grand_journey.tscn` (which mixes `realm_pbr.gdshader`, `journey_terrain.gdshader`, `journey_sky.gdshader`, `StandardMaterial3D` props, and `MultiMeshInstance3D` dressing), implement the void as a **camera-attached full-screen spatial quad** (`MemoryVoidQuad`, `render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled;`) that:
     - Reads `hint_depth_texture` + `hint_screen_texture` and reconstructs exact **3D world position `w_pos`** (`INV_PROJECTION_MATRIX` + `INV_VIEW_MATRIX`) and **world normal `w_nrm`** (`normalize(cross(dFdx(w_pos), dFdy(w_pos)))`) for every pixel on screen!
     - Evaluates up to `32` world-space ellipsoid reveal islands packed in a `32×2` `Image.FORMAT_RGBAF` global `sampler2D` (`memory_reveal_data`), combined with smooth-minimum (`smin`) + triplanar ink-splatter distortion + crisp `fwidth()` anti-aliased edges + **detached outer stipple paint droplets** + subtle 8 FPS stepped painterly boil!
     - Masks **sky pixels** (`depth <= 0.00001` in Godot 4.7 Reverse-Z) using a world-space directional sky window cone warped by splatter noise so the real `journey_sky.gdshader` clouds & sunset also dissolve into jagged ink-splattered black void!
     - Keeps **foreground anchor props unmasked** (`view_distance < foreground_exempt_dist` OR dedicated foreground reveal sphere) so a close prop (`~0.9–1.5 m` in front of the camera) floats cleanly **in front of** the `#000000` black void separating two background memory islands!
     - Applies a subtle stylized pastel/flat grading lift inside revealed islands so they pop with graphic clarity against pure `#000000`.
   - **Zero edits to existing `grand_journey.tscn` materials required!**
2. **Dynamic Gaze/Cursor Rack-Focus Depth of Field (`CameraAttributesPractical`)**:
   - Smoothly rack focus between the close foreground prop (`~1.0–1.5 m`, background islands softly blurred) and the mid/background memory islands (`~4.0–18.0 m`, foreground prop melts into creamy near-field bokeh) as the player moves the mouse/reticle!
3. **Constrained Diorama Camera Sway + Optional Head-Tracked 3D Window Parallax**:
   - Semi-fixed diorama camera per beat (no WASD walking): moving the mouse smoothly pans (`±16°` yaw, `±10°` pitch) **AND applies subtle lateral/vertical translation (`±0.22 m` X, `±0.12 m` Y)** so foreground props shift with rich 3D parallax across the background islands and black void!
   - When webcam tracking is active, optionally feed smoothed MediaPipe 3D head pose into `Camera3D.set_frustum()` (off-axis projection, toggleable in HUD/options) for a true physical "3D window" peek effect.
4. **Anatomical Curved Eyelid Shutter (`eyelid_blink_overlay.gdshader`)**:
   - Full-screen `CanvasLayer` curved top/bottom eyelid shutters with subtle defocus blur as eyes close, snapping to `#000000` (`closure >= 0.98`) to hide every scene transition **atomically with zero visual pop**, and hiding (`visible = false`) when `closure <= 0.001` for 0 ms idle cost.

---

## 3. The 4-Blink Narrative & Scene Sequence (Using Our Real Main Map)

Instantiate `GrandJourneyBuilder` (`scenes/environment/grand_journey.tscn`, built with `enable_set_dressing = true`, `configure_atmosphere = true`, enemies disabled/frozen or posed cinematically so nothing attacks the camera!). Use `level.get_key_anchors()` and `JourneyLayout` world coordinates to stage **4 unforgettable memories** across **4 Blinks**:

### Pre-Roll (Calibration / Title Card — ~5 s or Instant Skip)
- Minimalist dark void start overlay:
  - Toggle: **Webcam Blink Mode** (connects to MediaPipe UDP sidecar with a fast 3-second open-eyes + 2-blink calibration bar) **OR** **Keyboard/Mouse Mode** (`Space` or `Left Click` — press to close eyes, hold to keep closed, release to open — works immediately with zero webcam!).
  - Pressing `Space` / blinking once opens the eyelids onto **Scene 1**.

### Scene 1 (Leading to Blink 1) — **Gate of Reflections: The Broken Crossing**
- **Map Location**: `entry_gap_center` `(0, 0, 1.0)` & Forecourt (`Z ≈ -6 .. +5`, `Y = 0`), looking North (`+Z`) across the chasm toward the gatehouse arch and twin 10 m sword monuments (`(±4.3, 2.4, 3.6)`).
- **Framing & Islands**:
  - *Foreground anchor (`~1.2 m`)*: Close silhouette of a planted siege sword / stone parapet rail (unmasked, crisp in near-focus).
  - *Background Island A (Left)*: Fallen defender shields & left gatehouse arch pier.
  - *Background Island B (Right)*: Opposite switch plinth & right sword monument, separated from Island A by a pitch-black void river cutting through the chasm!
  - *Sky Window*: Ink-splattered arch opening framing the clouds above the gatehouse.
- **Interactive Beat**:
  - Floating white **Eye Icon** hotspot over the dark chasm. Hovering + blinking on the Eye Icon **does NOT skip the scene** — instead it **blooms a 3rd glowing painterly island** over the chasm revealing the cobalt Mirror stepping stones (tweening `realm_mirror_blend` briefly `0.0 -> 0.85`) with a crystalline chime!
  - Caption whisper: *"Before the fall, the bridge was still whole..."*
  - After `min_protected_sec = 4.5 s`, the **Metronome** icon fades in at bottom-center and ticks softly → **Blink #1** slams eyelids shut and cuts atomically to Scene 2.

### Scene 2 (Leading to Blink 2) — **Hall of Echoes: Feast & Ruin**
- **Map Location**: `JourneyLayout.HALL_CENTER` `(0, 4, 86)` (inside the vaulted Hall of Echoes, looking toward the cracked central pillar `(0, 4, 86)` and the side arcade feast/ruin dressing at `|x| >= 8.2`).
- **Framing & Islands**:
  - *Foreground anchor (`~1.1 m`)*: Low close-up over an overturned bench / spilled goblet / column base.
  - *Background Island A (Center)*: The fractured central stone pillar with its glowing amber seam.
  - *Background Island B (Upper Arcade)*: The crashed chandelier & tattered banners (separated by pitch-black void across the stone floor).
- **Interactive Beat**:
  - White **Eye Icon** on the pillar/chandelier: blinking while focused on it **flashes the memory into the Mirror Realm** (`realm_mirror_blend -> 1.0`, toggling `MirrorDressing` on so the lit ghost chandelier and standing feast tables glow through expanding ink islands!).
  - Caption whisper: *"We swore the stone would outlast our names."*
  - Metronome arms (`min_protected_sec = 4.5 s`) → **Blink #2** cuts atomically to Scene 3.

### Scene 3 (Leading to Blink 3) — **Clock-Tower Chamber: Hold the Dark**
- **Map Location**: `JourneyLayout.CHAMBER_CENTER` `(0, 6, 210)` (18 m clockwork walls, spinning bronze gears, raised dais `(-3, 7.35, 209)`, suspended Mirror weight above the plate, high oculus overhead).
- **Framing & Islands**:
  - *Foreground anchor (`~1.0 m`)*: Rusted loose gears on the workbench/dais edge.
  - *Background Island A*: The giant turning bronze gears on the chamber wall.
  - *Background Island B*: The glowing suspended Mirror weight floating beneath the oculus sky opening.
- **Interactive Beat (Sustained Eyes-Closed Mechanic!)**:
  - Prompt whispers: *"Close your eyes and listen..."*
  - Keeping eyes closed (`>= 0.7 s`) triggers the **Sustained Eyes-Closed** state: screen holds pure black while a rich resonant clockwork/glass-harmonic memory layer plays in the dark; when the player opens their eyes, the painterly islands **bloom wide open** revealing the turning spectral gears overhead!
  - Metronome arms (`min_protected_sec = 4.5 s`) → **Blink #3** cuts atomically to Scene 4.

### Scene 4 (Leading to Blink 4 — Finale) — **Sunset Summit: The Vigil**
- **Map Location**: Knight's Grave at Sunset Summit (`Vector3(-5.6, 10.0, 197.8 + JourneyLayout.OFF_S5)` = `(-5.6, 10.0, 357.8)`, facing west/northwest along `GrandJourneyBuilder.SUN_HEADING` toward the setting sun & mountain horizon!).
- **Framing & Islands**:
  - *Foreground anchor (`~1.1 m`)*: The knight's planted sword, weathered helm, and fresh wreath/wildflowers right in front of the lens (razor-sharp when looking down; dreamy blurred frame when looking out at the sunset!).
  - *Background Island A*: The spectral knight silhouette / glowing sigil keeping vigil beside the grave (`MirrorDressing` blended gently in!).
  - *Sky Window*: Wide, poetic ink-splattered opening revealing the golden sunset clouds in `journey_sky.gdshader` surrounded by infinite black void.
- **Interactive Beat (Emotional Staring-Contest Finale)**:
  - Caption fades in slowly: *"They built a mirror to preserve champions. It learned to preserve their deaths."*
  - The Metronome arms gently (`min_protected_sec = 4.0 s`) while the golden light softly brightens and the islands breathe — inviting the player to resist blinking just a few seconds longer to stay with the sunset.
  - **Blink #4** slowly closes the eyelids to pure `#000000` with a warm fading chord → clean minimalist End Card showing total time spent across the 4 memories + **`Experience Again`** / **`Quit`** buttons.

---

## 4. Blink Detection & Input Requirements

Follow `research/03_BLINK_DETECTION_TECH_AND_DEV_RECREATIONS.md` and `research/04_IMPLEMENTATION_STRATEGY_AND_GODOT4_BLUEPRINT.md`:
1. **`BlinkService` + `BlinkStateMachine`**:
   - Unified signals: `blink_closure_changed(val: float)`, `eyes_closed()`, `eyes_held_closed(duration: float)`, `eyes_opened(duration: float)`, `blink_committed()`, `face_tracking_changed(detected: bool)`.
   - Schmitt-trigger hysteresis (`T_close` / `T_open`), `45 ms` min closure debounce, `300 ms` refractory cooldown, `650 ms` held-closed threshold, `face == false` / `250 ms` UDP staleness safety freeze.
   - **Three input providers**:
     - `ManualInputSource` (`Space` or `LMB` hold-to-close / release-to-open — **always works out of the box**).
     - `MediaPipeUdpSource` (non-blocking `PacketPeerUDP` on `127.0.0.1:4242` parsing the JSON packet schema in `research/04`).
     - `SyntheticTestSource` (for automated headless/windowed verification tests).
2. **Python MediaPipe Sidecar (`tools/blink_tracker/`)**:
   - Create `tools/blink_tracker/requirements.txt`, `tools/blink_tracker/tracker.py` (`MediaPipe FaceLandmarker`, `RunningMode.VIDEO`, `320×240`, `eyeBlinkLeft/Right` + `eyeSquint` penalty + EAR + `head_xyz/rpy`, `--parent-pid` auto-exit watchdog), and `tools/blink_tracker/mock_udp_sender.py` (deterministic test injector).
   - Provide a clean HUD status pill (`WEBCAM LIVE` / `FACE PAUSED` / `SPACE TO BLINK`) and one-key Recalibrate (`R`) + mode toggle (`C` or UI button).

---

## 5. Strict Quality & Verification Gates (Do Not Skip!)

Use bounded PowerShell timeouts per `AGENTS.md` (30 s `--check-only`, 90 s headless tests, 180 s windowed screenshot tests) and include a `120 s` SceneTree watchdog in every test script:

1. **Parse Gate**: `--headless --check-only -s` passes with 0 errors on every new script under `scripts/memory_window/`.
2. **Headless Logic Test (`tests/test_before_you_blink.gd`)**:
   - Verifies protected blinks do NOT skip before metronome.
   - Verifies hovering an Eye Icon hotspot + blinking triggers the hotspot (blooming new reveal island / shifting realm) and does NOT skip the scene.
   - Verifies metronome-armed blinks advance Scene 1 → 2 → 3 → 4 → End Card (exact 4 blinks!).
   - Verifies sustained eyes-closed (`>= 0.7 s`) in Scene 3 triggers `eyes_held_closed` audio/bloom state.
   - Verifies `face == false` freezes blink evaluation (0 false skips).
   - Verifies `MemoryRevealManager` packs `32×2` `FORMAT_RGBAF` texture cleanly and updates `memory_reveal_data`.
3. **Visual Screenshot Verification (`tests/test_before_you_blink_visuals.gd`)**:
   - Capture windowed screenshots of all 4 scenes (including foreground vs background rack-focus comparison in Scene 1 & Scene 4, Eye-Icon bloom state, and mid-blink curved eyelid closure) and visually inspect them with `read_file`!
   - Confirm:
     - Void outside painterly islands is literal `#000000` (not grey/fogged).
     - Ink contours have organic painterly teeth + detached stipple droplets locked in 3D world space.
     - Foreground anchor props stand cleanly unmasked in front of the black void and blur smoothly when focus shifts to background islands.
     - Sky in Scene 1 & Scene 4 is masked cleanly into an ink-splattered opening.
4. **Main Game Non-Regression Check**:
   - Verify `scenes/main/main.tscn` still boots cleanly and `memory_mask_enabled` / `MemoryVoidQuad` has **zero effect** on normal PARALLAX gameplay.
5. **Memory Update**:
   - Append a concise dated summary line to `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` once implementation is complete.
