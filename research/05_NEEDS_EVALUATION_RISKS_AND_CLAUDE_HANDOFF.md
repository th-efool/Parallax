# 05 — Needs Evaluation, Risk Register, Performance Budget & Claude Handoff Plan

> Practical evaluation of everything required to build, test, and ship the Blink + 3D Memory Window system in Godot 4.7.2 (Forward+), plus an ordered Phase 0–5 roadmap ready for Claude to execute.

---

## 1. Comprehensive Needs Evaluation

### 1.1 Software, Engine & ML Dependencies
| Category | Requirement | Status in Current Workspace | Action Needed |
| :--- | :--- | :--- | :--- |
| **Game Engine** | Godot `4.7.2.stable` (Forward+) | **Installed** (`C:/Users/agrim/.local/bin/godot.cmd`) | None — supports `CameraAttributesPractical` DoF, `Image.FORMAT_RGBAF`, `RenderingServer.global_shader_parameter_set`, and native `stencil_mode`! |
| **CV Runtime (Dev)** | Python `3.10–3.12` + `mediapipe` + `opencv-python` + `numpy` | Needs check / local `.venv` inside `tools/blink_tracker/` (gitignored!) | Create isolated venv; pin versions in `tools/blink_tracker/requirements.txt`. |
| **ML Model Asset** | `face_landmarker.task` (~3.7 MB, Apache 2.0 from Google MediaPipe) | Not yet downloaded | Download once into `tools/blink_tracker/models/face_landmarker.task` (register source/license if committed, or auto-fetch script). |
| **Shipping Packager (Later)** | `PyInstaller --onedir --noconsole` OR C++/ONNX Runtime sidecar | Deferred until export phase | Keep sidecar decoupled behind UDP protocol so packaging never blocks development. |
| **Hardware (Testing)** | Any 720p/480p USB or laptop webcam (optional for automated dev!) | Optional during Claude dev | Build `ManualInputSource` (`Space`/`LMB`) + `SyntheticUdpBlinkInjector` so **100% of Godot features & tests work with or without a webcam**. |

### 1.2 Art, Shader & Audio Asset Needs
| Asset Type | Exact Spec | How to Acquire / Generate |
| :--- | :--- | :--- |
| **Seamless Ink-Splatter Noise (`ink_splatter_512.png`)** | `512×512` grayscale tileable organic brush/ink blot texture (high contrast, painterly ragged edges) | Procedural generation script (Python/Pillow or Godot `FastNoiseLite` domain-warped Cellular+Perlin baked to PNG) or CC0 brush texture. |
| **Stipple Droplet Noise (`stipple_dots_512.png`)** | `512×512` grayscale tileable scattered micro-droplets (Voronoi dots with varied radii) | Procedural baking script (deterministic seed) — zero external license issues! |
| **Stencil Window Blob Mask (`window_blob_512.png`)** | `512×512` radial brush-stroke aperture mask for Approach B stencil 3D windows | Procedural or hand-painted PNG. |
| **Stylized Diorama Demo Props** | Low-poly, flat-shaded / hand-painted toy-like vignette (e.g., Foreground Desk/Window Sill Prop + 2 Background Memory Islands + Masked Sky Dome) | Can reuse clean stylized meshes or procedural `ProcMeshKit` + flat pastel palettes for the Phase 1 prototype! |
| **Diegetic UI Icons** | Crisp vector/SDF white **Eye Icon** (open / hover-tightening / blink frames), **Ink Reticle Arcs**, and **Metronome Icon** (pendulum swing) | Author cleanly via SVG (`256×256` crisp white on transparent) imported into Godot. |
| **Audio Cues** | Soft **Metronome Tick** (wooden/clockwork, subtle), **Blink Whoosh/Shutter** (soft low-pass thump on close, airy swell on open), **Hotspot Focus Chime**, **Closed-Eyes Room Tone / Whisper layer** | Procedural `.wav` synthesis (matching `PARALLAX`'s existing audio pipeline) or CC0 Freesound assets. |

---

## 2. Performance Budget (60 FPS @ 1920×1080 Target)

Consistent with `PARALLAX`'s strict 60 FPS target (including integrated GPU fallback):

| Component | Target Frame Cost | Optimization Guardrails |
| :--- | :--- | :--- |
| **World-Space Reveal Shader (`memory_void_reveal.gdshader`)** | `<= 0.6 ms` GPU | Cap `memory_reveal_count` to active islands only (typically `3–8` per diorama, hard max `32`). Skip inactive slots (`radius <= 0.0001`). Use `filter_nearest` `texelFetch`. Only evaluate outer stipple branch inside `warped_sdf > 0.0 && warped_sdf < droplet_band`! |
| **Stencil 3D Window (`stencil_mode`)** | `<= 0.2 ms` GPU | Zero `SubViewport` cameras; single stencil pass. |
| **Dynamic Rack-Focus DoF (`CameraAttributesPractical`)** | `0.8 – 1.6 ms` GPU | Set `dof_blur_quality` to `MEDIUM` by default (`LOW` on integrated GPUs via `LeaderboardStore.is_low_end_gpu()`). |
| **Eyelid Overlay (`CanvasLayer`)** | `<= 0.25 ms` GPU | Hide (`visible = false`) whenever `blink_closure <= 0.001` so full-screen `hint_screen_texture` copy costs **0.0 ms** between blinks! |
| **MediaPipe Sidecar (`tracker.py`)** | `~3–6%` of 1 CPU core (0.0 ms on Godot main thread!) | Capture at `320×240` (or `640×480` max) @ `30 FPS`; `RunningMode.VIDEO`; zero OpenCV preview drawing in production. |

---

## 3. Integration Strategy Evaluation (How This Fits Into Your Game)

Before Claude touches any production `PARALLAX` scenes, decide which integration path you want (Phase 1 builds the isolated prototype first so you can experience it before committing!):

1. **Path 1 — Standalone Sandbox Prototype First *(Strongly Recommended Step 1)***:
   - Build everything cleanly inside `scenes/prototypes/memory_window_demo.tscn` + `scripts/memory_window/` + `assets/shaders/memory_window/`.
   - Contains a playable 3-beat mini-sequence showcasing:
     - **Beat 1 (Living Room Diorama)**: Foreground unmasked prop + 2 separate wall/floor memory islands separated by pure black void + dynamic DoF rack-focus + white Eye Icon hotspot that blooms a 3rd island when blinked at!
     - **Beat 2 (Backyard / Outdoor Void)**: Masked 3D sky dome + ground/house ink splatter + Metronome-armed time-skip + sustained eyes-closed hidden audio!
     - **Beat 3 (Stencil 3D Window Portal)**: Floating painterly tear in the dark void that you physically peer *through* (with mouse parallax or head-tracking off-axis frustum!) into a full 3D memory diorama!
2. **Path 2 — Integration Into `PARALLAX` (If Adding to the Mirror-Realm Game)**:
   - Remember `AGENTS.md`: `PARALLAX` locks its main combat gameplay to third-person over-right-shoulder camera.
   - **Where this fits naturally WITHOUT breaking `PARALLAX`'s combat**:
     - **Opening / Lore Memory Vignettes**: Interactive "Memory Echo" altars or stage-transition flashbacks rendered in the painterly black void (blink or press `Space` to advance memories of the Warden / condemned warrior!).
     - **Mirror Rift 3D Windows (Approach B Stencil)**: Floating jagged painterly rifts inside the colosseum where you literally peer through a 3D window into the Mirror Realm *before* pressing `Q` to shift!
     - **Optional Blink-to-Shift Experimental Mode**: Toggleable Accessibility/Experimental option letting webcam blinks trigger `RealmManager.request_shift()`!
3. **Path 3 — Foundation for a Dedicated Narrative / Memory Game**:
   - Because all scripts live cleanly inside `scripts/memory_window/` and `assets/shaders/memory_window/`, the entire module can be lifted straight into a new Godot 4.7 project with zero `PARALLAX` coupling!

---

## 4. Risk Register & Technical Mitigations

| # | Risk | Severity | Concrete Mitigation |
| :--- | :--- | :--- | :--- |
| **1** | **False-positive blinks (dim lighting, glasses glare, smiling/squinting, looking down)** | High | Use MediaPipe `eyeBlinkLeft/Right` + `eyeSquint` penalty + 5-second adaptive per-user calibration + Schmitt hysteresis + `45 ms` minimum closure + `300 ms` refractory cooldown. |
| **2** | **Tracking loss mistaken for a blink** | High | Explicit `face: bool` flag + `250 ms` UDP staleness watchdog; when face is lost, **freeze** blink state machine and show unobtrusive HUD prompt. |
| **3** | **Black void turns dark grey under lights, fog, SSAO, or IBL reflections** | High | Use `unshaded` + custom directional wrap (or custom `light()` multiplying diffuse/specular by `mask`), `fog_disabled`, `BG_COLOR = #000000`, and disable SSAO/Glow bleed on `#000000` pixels. |
| **4** | **Wall `discard` causes accidental X-ray see-through** | Medium | Never `discard` masked environment geometry — keep `depth_draw_opaque` and output solid `#000000` so occluded walls stay opaque silhouettes. |
| **5** | **DoF near-blur bleeding bright halos onto `#000000` void or flickering on tiny objects** | Medium | Use dedicated simplified `FocusTargetArea` volumes (`Area3D` on a dedicated focus layer) + damped exponential lerp (`speed ≈ 6–8`) + minimum focus clamp (`>= 0.35 m`) instead of raw jittery mesh raycasts. |
| **6** | **Godot 4.7 Stencil Buffer + Shadows / Transparent meshes conflict** | Medium | Keep Approach B stencil portal content on `render_priority = 0` opaque/alpha-scissor materials and mask on `render_priority = -2`; test forward shadows early in Phase 2. |
| **7** | **Orphan Python sidecar process stays open after game crash/quit** | Medium | Pass Godot's parent PID (`OS.get_process_id()`) as `--parent-pid` to `tracker.py`; sidecar checks parent liveness every 1 s and self-exits immediately if parent dies! |
| **8** | **PyInstaller bundle size (~100+ MB) & Windows Defender false positives** | Medium | Keep sidecar optional & decoupled behind UDP; for commercial release, swap `tracker.py` for a tiny native C++/ONNX Runtime binary using the identical UDP JSON protocol. |
| **9** | **Motion sickness from aggressive head-tracked off-axis frustum** | Low-Med | Clamp head parallax offset tightly (`±0.12 m`), heavily smooth with 1-Euro Filter (low latency + zero jitter), and make head-parallax an opt-in toggle (`default = gentle` or `off`). |
| **10** | **Automated CI/Claude testing blocked by lack of physical webcam** | Medium | Ship `SyntheticUdpSender` + keyboard fallback from Day 1 so Claude can run headless + windowed verification screenshots and assert every blink/cut/DoF state deterministically! |

---

## 5. Phased Implementation Plan & Verification Gates for Claude

Claude should execute **one phase at a time**, running the exact verification gate before advancing:

### Phase 0 — Project Globals & Procedural Noise Assets
- **Create**:
  - `project.godot` `[shader_globals]`: `memory_reveal_data` (`sampler2D`), `memory_reveal_count` (`int`), `memory_global_fade` (`float`).
  - Procedural generator script (or baked textures): `assets/textures/memory_window/ink_splatter_512.png`, `stipple_dots_512.png`, `window_blob_512.png`.
  - Clean SVG icons: `assets/ui/memory_window/eye_icon.svg`, `metronome_icon.svg`, `reticle_arc.svg`.
- **Gate**: Assets import cleanly via bounded Godot CLI `--import --quit`; zero warnings.

### Phase 1 — World-Space Painterly Memory Void + Diorama Demo Scene
- **Create**:
  - `scripts/memory_window/memory_reveal_volume.gd` (`MemoryRevealVolume`, `Node3D` with tweenable `radius`, `ellipsoid_scale`, `smoothness`)
  - `scripts/memory_window/memory_reveal_manager.gd` (`MemoryRevealManager`, packs `32×2` `FORMAT_RGBAF` `ImageTexture` into `memory_reveal_data`)
  - `assets/shaders/memory_window/memory_void_reveal.gdshader`
  - `assets/shaders/memory_window/memory_sky_reveal.gdshader`
  - `scenes/prototypes/memory_window_demo.tscn` (Living Room Diorama: unmasked foreground prop + 2 separated wall/floor memory islands + pure `#000000` void + Outdoor Backyard beat with masked sky dome).
- **Gate**: `--check-only` passes on all scripts; capture 2 visual verification screenshots (foreground focus + camera angle shift) confirming islands stay world-locked, void is literal `#000000`, and stippled ink contours match the reference aesthetic.

### Phase 2 — Dynamic Rack-Focus DoF, Stencil 3D Window & Eyelid Overlay
- **Create**:
  - `scripts/memory_window/memory_camera_rig.gd` (clamped diorama parallax + raycast `CameraAttributesPractical` rack-focus DoF + toggleable `set_frustum()` off-axis head parallax)
  - `assets/shaders/memory_window/eyelid_blink_overlay.gdshader` + `scripts/memory_window/eyelid_overlay.gd`
  - `assets/shaders/memory_window/memory_window_mask.gdshader` + `memory_window_content.gdshader` (Godot 4.7 native `stencil_mode` 3D portal beat!)
- **Gate**: Visual screenshots prove (a) crisp foreground / blurred background vs blurred foreground / crisp background rack-focus, (b) Stencil 3D window clips interior cleanly with organic painterly edges, (c) eyelid overlay hides (`visible = false`) at rest and closes cleanly to `#000000`.

### Phase 3 — Blink State Machine, Calibration & `MemoryBeatDirector`
- **Create**:
  - `scripts/memory_window/blink_state_machine.gd` (adaptive baseline, Schmitt hysteresis, `45 ms` debounce, `650 ms` held-closed, `300 ms` refractory cooldown, face-lost freeze)
  - `scripts/memory_window/blink_service.gd` (unified API supporting `ManualInputSource` Space/LMB + `MediaPipeUdpSource` `PacketPeerUDP` + `SyntheticTestSource`)
  - `scripts/memory_window/memory_beat_data.gd`, `memory_hotspot.gd` (3D white Eye Icon), `memory_beat_director.gd` (Metronome gating, hotspot override, atomic blink-cut swap at `closure >= 0.98`, closed-eyes audio)
  - Calibration HUD panel + diegetic Metronome/Eye reticle UI.
- **Gate**: Headless Godot regression test (`tests/test_memory_blink_system.gd` with 120 s SceneTree watchdog!) verifying:
  1. Protected blink does NOT skip before metronome.
  2. Hovering eye hotspot + blink triggers hotspot and does NOT skip scene.
  3. Armed metronome + blink executes atomic beat transition.
  4. `face == false` freezes blink detection (zero false skips).
  5. Sustained closure `>= 0.65 s` triggers `eyes_held_closed` audio state.

### Phase 4 — Live Webcam MediaPipe Sidecar (`tools/blink_tracker/`)
- **Create**:
  - `tools/blink_tracker/requirements.txt` (`mediapipe`, `opencv-python`, `numpy`)
  - `tools/blink_tracker/tracker.py` (`FaceLandmarker` in `RunningMode.VIDEO` @ `320×240`, outputs `blink_l/r`, `squint_l/r`, `ear_l/r`, `head_xyz`, `head_rpy`, parent-PID auto-exit watchdog)
  - `tools/blink_tracker/mock_udp_sender.py` (replays recorded/synthetic blink & head-pose curves to `127.0.0.1:4242` for deterministic testing without a camera).
- **Gate**: End-to-end test piping `mock_udp_sender.py` → Godot `BlinkService` confirms `< 35 ms` response, clean calibration convergence, and smooth head-parallax toggle; manual webcam smoke test verifies real blink & glasses resilience.

### Phase 5 — Polish, Audio & Integration Decision
- Wire procedural Metronome tick, eyelid shutter whoosh, hotspot focus chime, and closed-eyes ambient audio.
- Playtest calibration & pacing; tune `splatter_amp`, `droplet_band`, `boil_fps`, and `dof_blur_amount`.
- Decide with user whether to keep as a standalone memory module/game or wire into `PARALLAX` as Mirror Lore Vignettes / Rift Windows!
