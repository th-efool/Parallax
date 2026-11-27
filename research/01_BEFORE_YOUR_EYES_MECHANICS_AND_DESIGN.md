# 01 — *Before Your Eyes*: Core Mechanics, Pacing & Narrative Architecture

> Deep-dive study of GoodbyeWorld Games' *Before Your Eyes* (originally the 2014 USC student thesis prototype *Close Your*, released commercially in 2021 on PC, followed by Netflix Mobile/iOS and PlayStation VR2).
> Key creators referenced in primary postmortems & GDC 2023 (*"Learning From Loss: Designing the Experimental Narrative of 'Before Your Eyes'"*): **Will Hellwarth** (Founder/Studio Director), **Graham Parkes** (Writer/Creative Director), **Oliver Lewin** (Game Director/Composer), **Bela Messex** (Lead Designer/Programmer), **Hana Lee** (Lead Artist), **Griffin Libby** (Art Director), **Brieyh'leai Simmons** (3D Artist), **Dillon Terry** (Audio), and **Richard Beare** (Electrical Engineer / adaptive eye-tracking overhaul).

---

## 1. The Core Premise & Why Blinking Works Mechanically

*Before Your Eyes* takes place in the afterlife aboard the Ferryman's boat as protagonist Benjamin Brynn relives his life from infancy to death. Instead of using blinking as a mere "button replacement", the game aligns **human physiology** directly with **theme**:

- **Involuntary agency loss**: Every other video game gives the player a "Pause" or "Next Dialogue" button. By tying time-progression to a biological reflex you *cannot* hold back forever, the game turns the player's own dry eyes into the antagonist.
- **Selective memory**: You never see a full, continuous life — only isolated emotional fragments separated by abrupt blackouts, mirroring how real autobiographical memory works.

---

## 2. The Five Distinct Blink Verbs (Critical Design Taxonomy)

A common mistake when indie devs try to copy *Before Your Eyes* is wiring `on_blink -> load_next_scene()` globally. **The real game does NOT do that.** Instead, blinking behaves differently depending on the current **Beat State**:

| # | Blink State / Verb | Trigger Condition | Gameplay Effect | Narrative / Psychological Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Protected / Ignored Blink** | Early in a scene, before the Metronome appears, and no eye hotspot is hovered. | Eyelids visually blink (or subtle micro-cut), **scene does NOT skip**. | Protects essential exposition and stops involuntary blinks from breaking story comprehension. |
| **2** | **Metronome-Armed Time-Skip** | A ticking **Metronome icon** appears at the bottom center of the screen (with subtle audio tick). | **Next blink hard-cuts forward in time** (minutes, months, or years) to the next memory beat — cutting off active dialogue/action mid-sentence if needed! | Creates agonizing emotional tension: you physically strain not to blink to hear the end of a parent's sentence or linger on a happy memory. |
| **3** | **Gaze/Cursor + Blink Interaction (Eye Icon)** | Player moves reticle/cursor over a floating white **Eye Icon** hotspot in 3D space and blinks. | Interacts with that anchor: chooses dialogue/path, turns a page, focuses/expands a hidden memory island, paints a brush stroke, plays a piano key, or examines an object. | Replaces "Left Click" with an intimate, intentional act of looking + blinking — making attention itself the interaction verb. |
| **4** | **Sustained Eyes-Closed State** | Player closes their eyes and **keeps them closed** past a duration threshold (`~0.6–1.0 s+`). | Screen stays pure black; scene shifts into **pure auditory storytelling** (hidden whispered dialogue, memories heard in the dark, Ferryman commentary, or "staying safe" from something painful). Opening eyes reveals the changed scene. | Uses darkness as a playable space, not just a transition frame; deepens immersion massively (especially on PSVR2 and dark-room PC play). |
| **5** | **Climax / Uncontrollable Resistance** | High-emotion sequences where the Metronome arms early, or repeated rapid blinks accelerate aging/time-lapse montages. | Forces rapid-fire cuts through years of life (each blink = a new montage frame/year). | Physicalizes "life flashing before your eyes" with visceral cadence. |

### Why Metronome Gating Is Non-Negotiable
In Graham Parkes's GDC 2023 postmortem (*"A seven-year blink of an eye"*), the team explained that unrestricted blinking made players either **miss 80% of the story** or feel punished for having human tear ducts. **The Metronome solves both problems**:
1. It acts as an unmistakable diegetic contract: *"You are safe to blink until the metronome appears; once it ticks, your next blink lets go of this moment."*
2. Designers author an explicit **minimum hold time** (`min_protected_duration`) per beat before arming the metronome, guaranteeing every scene establishes its context before becoming vulnerable to a blink.

---

## 3. Interaction & Camera Grammar

### 3.1 Semi-Fixed First-Person Diorama Camera (NOT Free FPS Locomotion)
- You do **not** walk around with `WASD` in *Before Your Eyes*. Each memory places the camera at a deliberately staged vantage point (sitting at a toy piano, standing in the backyard, lying in bed, sitting in a classroom, facing an easel).
- Moving the **mouse** (PC), **tilting/touching** (Mobile), or **turning your head** (PSVR2) rotates and gently translates the camera within **tightly clamped yaw/pitch/sway bounds** around the diorama.
- **Why clamping matters**:
  1. Every camera angle is framed like a curated painting; the player never walks into unmodeled void edges.
  2. Artists only need to build the remembered slice of a room (saving massive 3D asset cost across 140+ scenes!).
  3. Subtle translational sway + shallow Depth of Field amplifies the "looking through a 3D window into a miniature memory box" feel.

### 3.2 Eye-Icon Hotspots & Reticle Language
Looking closely at the backyard reference screenshot (`media_1795764535240_5b3e2a47.jpg`):
- Interactive anchors display a crisp, minimalist **white line-art Eye Icon** floating directly in 3D world space (e.g., on the painted cloud and on the backyard house stairs).
- Surrounding the cursor/focus area are subtle translucent dark **ink/brush reticle arcs** that tighten when hovering a valid eye hotspot, giving clear affordance that *"blinking right now will trigger THIS object, not skip the scene"* (or will trigger the memory branch).
- **Priority Rule**: Hovering an active Eye Hotspot **overrides** a Metronome time-skip on that blink (unless the hotspot *itself* advances time), preventing accidental skips while interacting.

### 3.3 Dynamic Rack-Focus Depth of Field Tied to Gaze/Cursor
Looking closely at the two living-room reference screenshots (`media_1795764546346_a02b668b.jpg` and `media_1795764577986_67ec8f41.jpg`):
- In the first shot, the cursor/gaze focuses on the **cat sitting on the foreground blue toy piano** (`~0.8 m` away) → the cat is razor-sharp while the TV (`left`) and Mom at the upright piano (`right`) behind it dissolve into soft bokeh blur.
- In the second shot, the player looks past the cat toward **Mom at the piano** (`~4.0 m` away) → Mom, the wallpaper, and the window snap into sharp focus while the foreground cat and blue toy piano melt into creamy near-field blur.
- **Gameplay payoff**: Focus isn't merely cosmetic — shifting focus directs narrative attention, reveals background expressions, and physically emulates how human eyes accommodate between near and far planes.

### 3.4 Painting, Drawing & Micro-Interactions
- In several childhood/artist sequences, the mouse cursor becomes a live brush on a 3D canvas (or follows musical piano notes / constellation stars), while blinking commits the stroke or jumps forward to show the contrast between idealized childhood imagination and messy reality (the famous painted-boat memory).

---

## 4. Scene Management & Narrative Architecture (140+ Scenes)

Lead designer/programmer **Bela Messex** documented a crucial architectural reality: *Before Your Eyes* spans **over 140 distinct scenes/vignettes** that must transition **instantaneously inside a single human blink (`~100–180 ms`)**.

### How to Architect Instant Blink Transitions
1. **No Cold Scene Loads on Blink**:
   - Loading a heavy 3D scene from disk *after* detecting a blink creates a 500ms–2s hitch that completely destroys the illusion.
   - Instead, group memories into **Chapters / Diorama Pods** (e.g., 5–15 beats sharing a master environment or pre-instantiated sibling scene roots positioned in isolated dark void coordinates / toggled via visibility + active `Camera3D` + active reveal volumes).
   - Background-load (`ResourceLoader.load_threaded_request()` in Godot 4) the *next* chapter while the player is still inside the current chapter!
2. **Interruptible Audio & Dialogue State Machine**:
   - Because a player might blink **0.2 seconds** after the metronome appears OR **45 seconds** later, every dialogue line, animation track, and music stem must support **clean mid-phrase interruption** (rapid `30–60 ms` audio fade-out instead of harsh click, plus state flags recording whether the player heard line X before blinking so later scenes/dialogue can subtly react).
3. **Hard-Cut Masking Inside Peak Blink Closure**:
   - The instant a qualifying blink is confirmed:
     - `t = 0.00–0.05 s`: Eyelid shutter slams closed (`0.0 -> 1.0`).
     - `t = 0.05–0.09 s`: Screen is 100% pure black → **swap active memory pod / camera transform / reveal volumes / lighting / audio state atomically** in 1 frame.
     - `t = 0.09–0.22 s`: Eyelid shutter opens (`1.0 -> 0.0`) directly onto the new memory, often with a subtle focus rack or ink-bloom expansion!

---

## 5. Hard-Won Lessons & Pitfalls from GoodbyeWorld Games

| Pitfall Discovered in Production | Exact Mitigation Built Into the Design |
| :--- | :--- |
| **False-positive blinks from squinting, laughing, glasses glare, or low light** | Adaptive calibration screen before gameplay + temporal debounce + face-lost safety freeze (if face tracking drops, **never** trigger a blink). |
| **Players accidentally skipping emotional climaxes** | Metronome gating (`min_protected_duration`) + explicit hotspot priority over time-skip. |
| **Eye strain / dry eyes during long staring contests** | Keep armed-metronome segments punchy (`5–25 s` of bonus content after arming), followed by safe un-gated breathing room where blinking is free. |
| **Players without webcams (or playing in pitch dark / accessibility needs)** | First-class **"No-Webcam / Click-to-Blink" mode** (Left Click or Spacebar acts as closing/opening eyes, supporting hold-to-keep-closed). While developers note webcam mode maximizes emotional impact, fallback mode is mandatory for accessibility and QA. |
| **Tracking drifts when player slouches or leans** | Quick one-button **Recalibrate** accessible at any time from Pause or HUD corner, plus continuous slow drift adaptation of the open-eye baseline. |
