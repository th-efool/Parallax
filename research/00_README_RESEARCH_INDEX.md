# Before Your Eyes — Blink & 3D Memory Window Research Index

> **Purpose**: Deep technical, artistic, and gameplay-design research into *Before Your Eyes* (GoodbyeWorld Games) — covering its real-life blink mechanic, its signature "looking into a memory through a painterly 3D window/void" visual pipeline, how other indie developers have recreated these techniques, and a complete **Godot 4.7 (Forward+)** architecture blueprint & needs evaluation ready for Claude to implement.
> **Date**: 2026-11-27
> **Workspace Target**: `d:\Desktop\Godot\parallax` (Godot `4.7.2.stable`, Forward+ renderer, Windows 64-bit)
> **Scope**: Research, technical strategy, needs evaluation, risk analysis, and implementation handoff specification. *(No gameplay/code files modified in this phase.)*

---

## 1. Research Documents Map

| File | Focus Area | Who Should Read It First |
| :--- | :--- | :--- |
| **[00_README_RESEARCH_INDEX.md](00_README_RESEARCH_INDEX.md)** | Executive summary, key discoveries, recommended stack, document reading order | Human + Claude (Start Here) |
| **[01_BEFORE_YOUR_EYES_MECHANICS_AND_DESIGN.md](01_BEFORE_YOUR_EYES_MECHANICS_AND_DESIGN.md)** | Complete breakdown of *Before Your Eyes*'s blink grammar, metronome pacing, eye-icon hotspots, closed-eye audio, diorama camera rules, 140+ scene architecture, and GDC 2023 postmortem lessons | Design + Narrative + Gameplay implementation |
| **[02_3D_WINDOW_MEMORY_VISUAL_ARCHITECTURE.md](02_3D_WINDOW_MEMORY_VISUAL_ARCHITECTURE.md)** | Forensic breakdown of the 3 reference screenshots, why it feels like a "3D window into memory", world-space painterly multi-island void masks, dynamic rack-focus DoF, Godot 4.7 native Stencil Buffer 3D windows, optional head-tracked off-axis frustum parallax, and eyelid shutter shaders | Technical Art + Shaders + Camera Rig |
| **[03_BLINK_DETECTION_TECH_AND_DEV_RECREATIONS.md](03_BLINK_DETECTION_TECH_AND_DEV_RECREATIONS.md)** | How *Before Your Eyes* implemented webcam/ARKit/PSVR2 tracking (`ULSee`, Richard Beare's adaptive rewrite, companion helper process), how other Unity/Unreal/Godot indie devs recreated it, EAR vs MediaPipe Blendshapes math, hysteresis/calibration/false-positive filtering, and Godot 4.7 backend options | Computer Vision + Input Pipeline |
| **[04_IMPLEMENTATION_STRATEGY_AND_GODOT4_BLUEPRINT.md](04_IMPLEMENTATION_STRATEGY_AND_GODOT4_BLUEPRINT.md)** | Complete Godot 4.7 Forward+ technical blueprint: `ImageTexture` (`RGBAF`) global shader uniform workaround, spatial reveal shader, stencil portal shader, eyelid overlay shader, rack-focus & off-axis `Camera3D` rig, Python MediaPipe UDP sidecar protocol, `BlinkInputProvider` abstraction, and `MemoryBeatDirector` state machine | Claude (Core Implementation Spec) |
| **[05_NEEDS_EVALUATION_RISKS_AND_CLAUDE_HANDOFF.md](05_NEEDS_EVALUATION_RISKS_AND_CLAUDE_HANDOFF.md)** | Full hardware/software/art/audio needs evaluation, 60 FPS GPU & CPU performance budget, 10-item technical & UX risk register, integration paths with `PARALLAX`, and a phased (Phase 0–5) implementation & automated verification plan (including synthetic UDP testing without a webcam) | Planning + QA + Claude Execution Roadmap |

---

## 2. Executive Summary — What Actually Makes It Feel So Good

The unforgettable feel of *Before Your Eyes* does **not** come from a single gimmick. It emerges from **four tightly interlocked illusions** working together:

1. **World-Space Painterly Memory Islands in Pure Black Void (NOT a 2D Screen Vignette)**
   - Forensic inspection of the game's living-room and backyard scenes proves the black void cuts directly across 3D geometry in **world space**, leaving separate glowing/colored "islands" of memory (e.g., a TV patch on the left wall, a pitch-black vertical void gap in the middle, and a window + piano patch on the right) bounded by jagged, stippled ink-splatter contours.
   - Because the reveal mask is locked in **3D world space** rather than screen space, panning or tilting the camera creates true 3D parallax against the void — while unmasked foreground objects (like a cat on a toy piano) float cleanly **in front of** the black void.
2. **Dynamic Gaze-Driven Rack-Focus Depth of Field (The "3D Viewmaster / Window" Illusion)**
   - As the player looks from a close foreground prop (`~0.8 m`) to a background memory island (`~4.0 m`), shallow Depth of Field dynamically racks focus between depth planes. Combined with the surrounding `#000000` void stripping peripheral depth cues, the foreground prop acts like a physical window frame and the background memory pops like a stereoscopic 3D diorama.
3. **Metronome-Gated Biological Tension (Blink Grammar)**
   - *Before Your Eyes* does **not** jump time on *every* blink (that would destroy dialogue and cause frustration). Instead, scenes protect critical beats until a **Metronome** icon appears — arming the next blink as an irreversible time-skip. That turns an involuntary bodily reflex into emotional tension ("don't blink, stay in this moment a second longer").
4. **Zero-Frame Blink Cuts + Decoupled CV Tracking**
   - Every scene swap, time-jump, or object transformation executes cleanly at the exact frame the simulated eyelid shutter reaches `100%` black (`~50–100 ms`), hiding loading/swaps completely. Under the hood, webcam computer vision runs in a **decoupled background process** so heavy ML inference never stalls the game's render loop.

---

## 3. Recommended Strategy & Tech Stack for Godot 4.7.2 (Forward+)

| Subsystem | Recommended Approach | Why It Wins for Godot 4.7 |
| :--- | :--- | :--- |
| **Memory Void Visuals (Primary)** | **World-Space Multi-Volume SDF + Triplanar Ink-Splatter Reveal Shader** packed into a `32×2` `Image.FORMAT_RGBAF` global `sampler2D` | Recreates the *exact* multi-island painterly void from the screenshots; bypasses Godot 4's no-global-array limit; preserves depth buffer (`depth_draw_opaque` + `#000000` unlit void) so walls never turn X-ray. |
| **3D Window / Portal Variant (Bonus)** | **Godot 4.5–4.7 Native Stencil Buffer (`stencil_mode write/read`)** | Zero extra `SubViewport` cameras; lets players literally peer *through* an irregular paint-splatter 3D window into another memory or realm with true 3D parallax at almost zero GPU cost. |
| **3D Depth & "Window" Feel** | **Dynamic Raycast Rack-Focus DoF (`CameraAttributesPractical`)** + **Optional Head-Tracked Off-Axis Projection (`Camera3D.set_frustum()`)** | Reproduces the exact foreground/background diorama pop; MediaPipe already outputs 3D head pose for free, enabling optional physical head-tilt "3D window" peeking! |
| **Blink Detection Backend** | **Decoupled MediaPipe `FaceLandmarker` Sidecar (Python → localhost UDP → Godot `PacketPeerUDP`)** + **First-Class Keyboard/Mouse Fallback** | Zero main-thread frame drops; uses MediaPipe's ARKit-grade `eyeBlinkLeft`/`eyeBlinkRight` blendshapes fused with Soukupová–Čech EAR; requires zero Godot engine recompilation; trivial to mock with a synthetic UDP script during automated testing. *(Long-term commercial option: C++/ONNX Runtime sidecar or `godot-cameragdextension` to shrink distribution size.)* |
| **Rollout Strategy** | **Phase 1 Standalone Prototype Scene First** (`scenes/prototypes/memory_window_demo.tscn`) | Proves the shader, DoF, stencil portal, blink state machine, and feel in total isolation before deciding whether/how to integrate into `PARALLAX` (which currently uses a third-person combat loop). |

---

## 4. Recommended Reading Order for Claude (Before Coding)

1. Read `02_3D_WINDOW_MEMORY_VISUAL_ARCHITECTURE.md` to internalize the exact visual anatomy and shader constraints.
2. Read `03_BLINK_DETECTION_TECH_AND_DEV_RECREATIONS.md` to understand the blink state machine, hysteresis thresholds, calibration, and pitfalls.
3. Read `04_IMPLEMENTATION_STRATEGY_AND_GODOT4_BLUEPRINT.md` for exact Godot 4.7 shader syntax, node hierarchy, UDP packet schema, and script contracts.
4. Execute sequentially using the checklist & test gates in `05_NEEDS_EVALUATION_RISKS_AND_CLAUDE_HANDOFF.md`.
