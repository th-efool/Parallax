# 03 — Blink Detection Technology, Signal Processing & Indie Dev Recreations

> Forensic technical research on how *Before Your Eyes* implemented real-world blink tracking across PC, Mobile, and VR; how Unity, Unreal, and Godot indie developers have recreated it; exact mathematical formulas (EAR vs MediaPipe Blendshapes); false-positive rejection; and Godot 4.7 backend trade-offs.

---

## 1. How *Before Your Eyes* Actually Built Its Blink Tracker

### 1.1 Evolution Across 7 Years (PC Steam Build)
1. **Student Prototype (*Close Your*, 2014)**:
   - Built at USC using early OpenCV / facial-tracking prototypes in Unity. Worked in controlled showcase booths with ring lights, but broke constantly under real bedroom lighting, head tilt, and eyeglasses.
2. **Commercial PC Architecture (2021 Steam Release)**:
   - GoodbyeWorld Games initially licensed the **ULSee Inc.** Unity facial-landmark SDK as a lightweight RGB webcam tracker.
   - Out-of-the-box tracking still suffered from false blinks under dim lighting, backlighting, glasses reflections, and posture shifts. The studio brought on electrical engineer **Richard Beare** to heavily rewrite the adaptive filtering and eye-state detection layer on top of facial landmarks.
   - **Decoupled Helper-Process Architecture**: Across commercial Unity webcam-tracking games (and documented in Steam Community / Linux Proton reverse-engineering threads analyzing companion binaries in `StreamingAssets` such as `PBP.exe`), heavy computer-vision frame capture + ML landmark inference is isolated in a **background companion process** outside the engine's render thread.
   - That process streams a lightweight normalized scalar (`blinkValue` in `[0.0, 1.0]`, plus a `faceDetected` boolean) to the engine every frame. If `faceDetected == false` (player leans away, covers camera, or room goes black), the engine **freezes blink evaluation** instead of mistaking lost tracking for closed eyes.

### 1.2 Multi-Platform Implementations

| Platform | Hardware / SDK | How Blink Is Measured | Strengths | Weaknesses |
| :--- | :--- | :--- | :--- | :--- |
| **PC (Steam)** | Standard RGB USB/Laptop Webcam + Custom ULSee / Adaptive CV | 2D/3D eye landmark vertical-to-horizontal ratio + adaptive baseline | Works on any cheap webcam | Sensitive to dim light, heavy backlighting, thick frames/glare |
| **iOS (Netflix Mobile)** | Front TrueDepth Camera + **Apple ARKit** | Native `ARFaceAnchor.BlendShapeLocation.eyeBlinkLeft` / `eyeBlinkRight` (`0.0–1.0`) | Far more accurate than raw 2D webcam; handles head rotation smoothly | Requires holding/propping phone steady; still needs ambient light on non-IR paths |
| **Android (Netflix Mobile)** | Front RGB Selfie Camera + ML Face Mesh | Software ML eye-closure score | Broad device reach | Lighting & posture dependent |
| **PS VR2** | Internal Infrared (IR) Eye-Tracking Cameras | Direct hardware IR eyelid closure + gaze vector | **Gold standard**: works in pitch darkness, millimeter precision, true gaze-aiming without mouse | Headset slipping off the "sweet spot" can disrupt calibration |

---

## 2. Exact Detection Math: EAR vs. MediaPipe Blendshapes (and Why to Fuse Both)

### 2.1 Classical Geometry: Eye Aspect Ratio (Soukupová & Čech, 2016)
The foundational computer-vision metric computes the ratio of vertical eyelid aperture to horizontal eye width using 6 landmarks per eye:

$$\text{EAR} = \frac{\|p_2 - p_6\| + \|p_3 - p_5\|}{2 \|p_1 - p_4\|}$$

- **MediaPipe 478-Landmark Canonical Indices**:
  - **Left Eye**: Outer corner $p_1 = 33$, Upper-outer $p_2 = 160$, Upper-inner $p_3 = 158$, Inner corner $p_4 = 133$, Lower-inner $p_5 = 153$, Lower-outer $p_6 = 144$.
  - **Right Eye**: Outer corner $p_1 = 362$, Upper-outer $p_2 = 385$, Upper-inner $p_3 = 387$, Inner corner $p_4 = 263$, Lower-inner $p_5 = 373$, Lower-outer $p_6 = 380$.
- **Typical Ranges**:
  - Open eye: `EAR ≈ 0.25 – 0.35` (varies strongly by individual eye shape and downward gaze!).
  - Closed eye: `EAR < 0.16 – 0.21`.
- **Main Weakness of Raw EAR Alone**: Looking downward at the bottom of your monitor naturally lowers your upper eyelid, dropping raw EAR by 25–40% and causing false blink triggers unless compensated by head pitch or adaptive baselines!

### 2.2 Modern ML: MediaPipe `FaceLandmarker` Blendshapes (ARKit-Compatible)
Google's **MediaPipe Tasks Vision `FaceLandmarker`** (`face_landmarker.task`, ~3.7 MB) with `output_face_blendshapes=True` directly outputs **52 ARKit-compatible facial expression scores (`0.0 – 1.0`)** trained on diverse faces, ethnicities, lighting, and head angles:
- `eyeBlinkLeft`: `0.0` (fully open) → `1.0` (fully closed)
- `eyeBlinkRight`: `0.0` (fully open) → `1.0` (fully closed)
- `eyeSquintLeft` / `eyeSquintRight`: Distinguishes smiling/squinting from genuine blinks!
- **BONUS**: Setting `output_facial_transformation_matrixes=True` ALSO outputs a **4×4 3D head-pose transformation matrix** (`tx, ty, tz, pitch, yaw, roll`) in the **exact same inference pass (~5–12 ms on CPU at 320×240)**! That powers optional 3D-window head-tracking parallax for free.

### 2.3 Recommended Hybrid Metric (Best-in-Class Accuracy)
Fuse MediaPipe Blendshapes (primary) with adaptive per-user baseline & EAR sanity check:

```text
raw_blink_L = eyeBlinkLeft
raw_blink_R = eyeBlinkRight
# Both eyes must close together (rejects one-eyed winks & side-angle occlusion)
combined_closure = min(raw_blink_L, raw_blink_R) * 0.65 + ((raw_blink_L + raw_blink_R) * 0.5) * 0.35
# Compensate against smiling/squinting false positives
squint_penalty = max(0.0, ((eyeSquintLeft + eyeSquintRight) * 0.5) - 0.45) * 0.25
effective_closure = clamp(combined_closure - squint_penalty, 0.0, 1.0)
```

*(Optionally cross-verify with normalized `1.0 - (EAR / user_open_ear_baseline)` if `eyeBlink` confidence is noisy under thick glasses.)*

---

## 3. Signal Processing & Calibration — How to Eliminate False Positives

A raw threshold (`if score > 0.5: blink()`) feels terrible in playtesting. Every serious blink-controlled game needs a **5-stage signal filter**:

1. **Adaptive 2-Step Calibration (Takes ~5 Seconds)**:
   - *Step A — Neutral Open Baseline (2.0 s)*: Player looks normally at screen center → record median `open_baseline` (`μ_open`) and noise floor (`σ_open`).
   - *Step B — Deliberate Blink Sample (2 blinks)*: Player blinks normally twice → record peak `closed_peak` (`μ_closed`).
   - Compute dynamic Schmitt-trigger thresholds:
     - `T_close = lerp(μ_open, μ_closed, 0.62)` (clamped to `[0.42, 0.72]`)
     - `T_open  = lerp(μ_open, μ_closed, 0.34)` (clamped to `[0.20, 0.48]`)
   - *Why this works*: Handles narrow eyes, wide eyes, high/low webcam angles, and glasses automatically!
2. **Hysteresis (Schmitt Trigger)**:
   - Eyes transition `OPEN -> CLOSING` only when `effective_closure >= T_close`.
   - Eyes transition `CLOSED -> OPEN` only when `effective_closure <= T_open`.
   - The deadband (`T_close - T_open ≈ 0.20–0.28`) completely eliminates rapid flickering/chattering when the player squints near the threshold.
3. **Temporal Debounce & Minimum Closure Duration**:
   - Human spontaneous blink duration: **100–400 ms** (average ~150–250 ms; peak closure lasts ~50–100 ms).
   - Require `effective_closure >= T_close` for **`>= 45 ms`** (2 consecutive frames @ 30 FPS) to ignore 1-frame webcam compression glitches, while still triggering snappily within a normal blink!
4. **Distinguishing Quick Blink vs. Sustained Eyes-Closed**:
   - Emit `eyes_closed` immediately upon crossing `45 ms` (drives eyelid shutter closing and arms/fires quick blink-cuts).
   - Emit `eyes_held_closed` if eyes remain closed `>= 650 ms` (activates hidden-audio / darkness listening mode).
   - Emit `eyes_opened(duration_sec)` when crossing back below `T_open`.
   - Enforce a **refractory cooldown (`250–350 ms`)** after `eyes_opened` so double-triggers never skip two memories at once!
5. **Face-Lost Safety Freeze & Slow Baseline Drift**:
   - If `face_detected == false` (or packet age `> 250 ms`), **freeze state** and display a subtle non-intrusive HUD warning (`"Face tracking paused — center in camera"`). Never fire a blink on lost face!
   - When `state == OPEN` and `effective_closure` is stable for `> 3 s`, slowly EMA-adapt `μ_open` (`alpha = 0.005`) to survive changing afternoon sunlight or screen brightness shifts!

---

## 4. How Other Indie Devs Recreated This (Cross-Engine Survey)

| Ecosystem | Popular Recreations / Tools | How They Wired It | Lessons Learned |
| :--- | :--- | :--- | :--- |
| **Unity** | *MediapipeUnityPlugin* (`homuler`), *OpenCV for Unity*, dozens of 48h/72h game-jam entries on itch.io (*Retina Racer*, blink-horror games, *Weeping Angel* prototypes) | Webcam texture → MediaPipe FaceMesh/Landmarker → EAR or `eyeBlink` blendshapes → FullScreenPass URP eyelid shader + scene-skip event. | Running OpenCV/MediaPipe synchronously on Unity's main thread tanks FPS from 60 to 18; async worker threads or external sidecar processes are mandatory. |
| **Unreal Engine** | Live Link Face (iOS ARKit), MediaPipe4U plugin | Streams `EyeBlinkLeft` / `EyeBlinkRight` into a Material Parameter Collection (MPC) driving a post-process eyelid material. | Streaming normalized `0.0–1.0` eyelid floats to a global shader parameter makes visual feedback feel eerily physical because the screen's eyelids mirror partial squints! |
| **Godot 4** | **AgniGames Eye Detection Plugin** (Godot Asset Library), **`j20001970/GDMP`** (Godot MediaPipe GDExtension), custom Python+UDP bridges on GitHub/Reddit (`r/godot`) | Either a Python+MediaPipe helper process (`EyeDetectionHelper` / custom UDP script) or native GDMP C++ GDExtension emitting `eyes_closed`/`eyes_opened` signals to GDScript. | Godot 4's core `CameraServer` still lacks full native Windows Media Foundation out-of-the-box without `godot-cameragdextension`, which makes a decoupled MediaPipe sidecar dramatically cleaner and faster to ship on Windows today. |

---

## 5. Godot 4.7 Blink-Tracking Backend Evaluation (Options Matrix)

| Option | Architecture | Latency | Distribution / Packaging | Godot 4.7 Stability | Bonus Features | Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Option 1: Custom Python MediaPipe Sidecar + Localhost UDP** | `tools/blink_tracker/tracker.py` (`opencv-python` + `mediapipe` `FaceLandmarker` in `RunningMode.VIDEO` @ `320×240` or `640×480`) → UDP `127.0.0.1:4242` → Godot `PacketPeerUDP` | **16–33 ms** (30–60 Hz, zero game-thread stall) | Dev: runs via local venv; Ship: `PyInstaller --onedir --noconsole` bundled beside `.exe` (~90–140 MB) | **100% Immune** to Godot 4.7 C++ ABI changes | Gives `eyeBlinkL/R`, `eyeSquintL/R`, `EAR`, **AND 3D Head Pose `(x,y,z,pitch,yaw,roll)`** for 3D-window parallax! | **BEST FOR PROTOTYPING & PRODUCTION V1** |
| **Option 2: AgniGames Eye Detection Plugin** | Asset Library addon wrapping a prebuilt PyInstaller MediaPipe helper | ~33 ms | Must manually copy `dist/EyeDetectionHelper` beside exported `.exe` | Good (Windows-only) | Basic `eyes_closed`, `eye_opened`, `face_detectable_state` | Good shortcut, but **no blendshape scores, no squint filter, no 3D head pose**, and Windows-only black box. |
| **Option 3: `j20001970/GDMP` (GDExtension)** | Native C++ MediaPipe compiled into Godot GDExtension | ~12–20 ms (in-process) | Small native `.dll/.so` (~25–40 MB) | **Medium Risk**: requires matching Godot 4.7 GDExtension binary build | Full MediaPipe graphs | Great native speed, but high C++ build/ABI maintenance burden on bleeding-edge Godot `4.7.2`. |
| **Option 4: Native C++ / Rust Sidecar + ONNX Runtime (`godot-cameragdextension` or MediaFoundation)** | Lightweight C++/Rust binary capturing Windows MediaFoundation frames + running BlazeFace/FaceMesh ONNX | **8–16 ms** | Tiny (~15–25 MB), zero Python runtime, minimal AV false flags | **100% Immune** to Godot ABI changes | Full control over metrics + head pose | **BEST COMMERCIAL SHIPPING UPGRADE (Phase 6)** — swaps cleanly behind the exact same UDP protocol! |
| **Option 5: Built-in Synthetic / Accessibility Provider** | Mouse (`LMB`) / Keyboard (`Space` or `B`) press-and-hold = close eyes, release = open eyes | **0 ms** | 0 MB (pure GDScript) | **100%** | Automated test injection (`SyntheticBlinkProvider`) | **MANDATORY FIRST-CLASS PARTNER** alongside Option 1. |

### Key Strategic Insight: Protocol-First Decoupling
By defining a tiny, versioned **UDP JSON (or 32-byte binary) contract** between *any* tracker process and Godot's `BlinkInputProvider` autoload:
1. Claude can build and test the entire Godot 4.7 game loop **today** using `KeyboardBlinkProvider` + a `SyntheticBlinkTestDriver` (even with no physical webcam attached!).
2. Option 1 (Python MediaPipe `FaceLandmarker` sidecar) plugs right in for real webcam playtesting in 1 day.
3. If we ever ship commercially on Steam and want a 20 MB zero-Python executable, we swap the sidecar binary for Option 4 (C++/ONNX) **without changing a single line of GDScript**!
