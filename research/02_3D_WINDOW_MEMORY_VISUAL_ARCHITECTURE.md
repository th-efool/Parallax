# 02 — The "3D Window Into Memory" Visual Architecture

> **Core Question Answered**: *Why does Before Your Eyes look so uncannily like peering into a floating memory through a weird, painterly 3D window — and how do we replicate (and even elevate) that exact effect in Godot 4.7 Forward+?*

---

## 1. Forensic Visual Breakdown of the Reference Screenshots

Inspecting the three provided reference frames reveals **six distinct optical tricks** stacked together. Crucially, the signature black void is **NOT** a simple 2D screen-space vignette!

### Evidence From the Three Shots
1. **Backyard Scene (`media_1795764535240_5b3e2a47.jpg`)**:
   - The black void cuts across the **grass ground** (forming a dark river between the blue trampoline on the left and the blue house on the right), slices cleanly into the **white picket fence**, eats a dark ink splotch out of the **blue house's right window**, AND masks the **sky** itself into an arched organic opening around the utility pole and painted cloud.
   - Edges are **sharp-yet-organic ink/brush splatters** with tiny detached stipple dots scattered just outside the boundary — NOT a soft Gaussian vignette blur.
2. **Living Room — Foreground Focus (`media_1795764577986_67ec8f41.jpg`)**:
   - Behind the toy piano and cat, there are **TWO separate revealed islands of 3D geometry**:
     - Left island: TV + wooden cabinet + small patch of floor & wallpaper.
     - Middle gap: **Solid `#000000` vertical void** cutting straight through the wall and floor from ceiling to carpet.
     - Right island: Barred window + desk + lamp + Mom at upright piano + floor & wallpaper.
   - Meanwhile, the **foreground blue toy piano and cat** sit 100% unmasked and razor-sharp **in front of** the black void!
3. **Living Room — Background Focus (`media_1795764546346_a02b668b.jpg`)**:
   - When the camera shifts slightly right/up and shifts focus onto Mom at the piano:
     - The **exact same ink-splatter outline** hugs the wallpaper above the window and around the upright piano — proving the mask is **anchored in 3D world space** on the scene geometry, NOT painted in 2D screen coordinates!
     - The foreground cat + blue toy piano blur heavily (near-field DoF) while overlapping cleanly in front of the dark void, creating a stark stereoscopic "peering past a window sill into a floating memory island" sensation.
   - *(Note on Screenshot 2's diagonal grey bars on the far left/right edges with the red `N` logo: those slanted diagonal panel borders are Netflix Mobile trailer video-editing crops, NOT part of the in-game shader! Look inside the crop — the actual in-game void is purely the organic stippled black silhouette.)*

---

## 2. The 6 Optical Pillars Behind the "3D Window-ish" Feel

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                    THE 6-LAYER "MEMORY WINDOW" STACK                    │
├─────────────────────────────────────────────────────────────────────────┤
│ Layer 6: Eyelid Shutter Post-Process (CanvasLayer)                      │
│          Curved top/bottom shutters + defocus blur + atomic blink-cut   │
├─────────────────────────────────────────────────────────────────────────┤
│ Layer 5: Dynamic Rack-Focus DoF (CameraAttributesPractical)             │
│          Raycast autofocus smoothly shifts focus between 0.8m <-> 5.0m  │
├─────────────────────────────────────────────────────────────────────────┤
│ Layer 4: Camera Parallax / Optional Off-Axis 3D Frustum                 │
│          Clamped diorama sway + optional head-pose set_frustum() window │
├─────────────────────────────────────────────────────────────────────────┤
│ Layer 3: World-Space Multi-Island Painterly Void Mask (Spatial Shader)  │
│          SDF sphere/ellipsoid islands + triplanar ink splatter + stipple│
│          -> Depth-preserving unlit #000000 outside islands              │
├─────────────────────────────────────────────────────────────────────────┤
│ Layer 2: Stylized Low-Poly / Hand-Painted Unlit-or-Toon Surface Art     │
│          Pastel flat color blocks, zero muddy PBR shadows, crisp contrast│
├─────────────────────────────────────────────────────────────────────────┤
│ Layer 1: Pure Black Clear Color (#000000) + Masked Sky Dome Mesh        │
│          Sky is a physical 3D dome sharing the same world-space reveal! │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why It Feels "Weird But So Good"
1. **Selective Spatial Existence**: Only the objects the protagonist *remembers* exist in color. Forgotten walls, hallways, and sky collapse into pitch black `#000000` with painterly ink borders.
2. **Depth Separation Without Background Clutter**: Because the black void eliminates distant room corners and ambient bounce light, foreground objects (cat/piano) and mid-ground islands (Mom, TV) read like **layered paper theater / shadow-box planes floating in space**.
3. **Dynamic Accommodation (DoF Rack-Focus)**: Shifting crisp focus between the near foreground prop and a distant memory island mimics physical eye accommodation — tricking the brain into perceiving immense miniature/window depth even on a flat 2D monitor.
4. **Painted Edges on 3D Geometry**: The eye expects 3D polygons to have straight geometric edges. Seeing 2D watercolor/ink-splatter brush strokes wrap seamlessly around 3D walls, floors, fences, and sky creates an unmistakable "living illustration inside a 3D window" aesthetic.

---

## 3. Three Rendering Techniques Compared (Which Should We Build?)

When indie devs recreate a "3D window into a memory" in Unity, Unreal, or Godot, they generally choose between **three distinct architectures**. Each solves a slightly different creative goal — and in Godot 4.7 Forward+, we can combine the best of them!

### Approach A: World-Space Multi-Island Painterly Reveal Shader *(Exact Before Your Eyes Look)*
- **How it works**:
  - Scene background (`WorldEnvironment` -> `Background`) is pure `#000000` (`BG_COLOR`).
  - Sky (for outdoor scenes like the backyard) is an **inverted 3D hemisphere/dome mesh** wearing the same reveal shader (so clouds/sky also cut off cleanly into black ink splatter!).
  - A manager node defines `N` active **3D Reveal Volumes** (spheres or ellipsoids placed around remembered anchors: e.g., `Island_TV`, `Island_MomPiano`, `Island_SkyCloud`, `Island_Trampoline`, plus an optional dynamic `GazeRevealSphere` following where the player looks!).
  - Every world surface computes its signed distance `d` to the **smooth union (`smin`)** of active reveal volumes, perturbs `d` using **world-space triplanar FBM + Voronoi ink splatter noise**, and evaluates a hard anti-aliased edge plus a detached stipple-dot scatter band.
  - **CRITICAL DETAIL — Do NOT use `discard` for walls!**
    - If a wall outside the reveal island uses `discard`, you will see *through* the dark part of the wall into whatever room or sky sits behind it (breaking occlusion!).
    - Instead, keep `depth_draw_opaque` and set `ALBEDO = vec3(0.0); EMISSION = vec3(0.0); SPECULAR = 0.0; ROUGHNESS = 1.0;` (or use an `unshaded` stylized toon lighting pass where `mask == 0.0` outputs literal `vec3(0.0)`!).
    - Result: Darkened walls remain **solid opaque black silhouettes** that properly occlude objects behind them, blend seamlessly into the `#000000` clear color, and still allow unmasked foreground objects (like the cat & toy piano, marked `exempt_from_mask = true` or covered by a near reveal sphere) to render cleanly on top!
- **Pros**: Exact match to all 3 reference screenshots; islands can grow/shrink/merge organically like ink spreading on paper; zero extra camera passes; runs at 60+ FPS even on integrated GPUs.
- **Cons**: Requires every masked environment material to include the reveal shader include (`memory_reveal.gdshaderinc`).

### Approach B: Godot 4.7 Native Stencil Buffer "3D Memory Window" *(True Portal Window Into Another Scene/Realm)*
- **How it works**:
  - Starting in **Godot 4.5+ (supported natively in our Godot 4.7.2 Forward+)**, spatial shaders support native `stencil_mode` (`write` / `read`, `compare_equal`, reference IDs `1..255`) directly on the GPU — **with ZERO extra `SubViewport` cameras**!
  - You place a 3D floating quad, picture frame, mirror shard, or irregular paint-splatter cutout mesh in the world as the **Window Mask**:
    - Mask shader: `render_mode depth_draw_never;` + `stencil_mode write, compare_always, 1;` + organic ink-splatter `ALPHA_SCISSOR_THRESHOLD` (so the window itself has ragged painterly edges instead of a boring rectangle!).
  - Every object inside the **Memory World** (occupying the same 3D space behind the window!) uses:
    - `stencil_mode read, compare_equal, 1;`
  - As the player moves or tilts the camera, they **literally peer through a floating 3D paint-splatter window into a full 3D memory world with true parallax**!
- **Pros**: Insane "non-Euclidean 3D window / magic box" wow-factor (think *Antichamber* / *Moncage* / *Gorogoa* / *Viewfinder* meets *Before Your Eyes*); zero SubViewport render-target overhead; multiple independent windows possible via Stencil IDs `1, 2, 3...`.
- **Cons**: Stencil masking clips cleanly along a screen-projected 3D frame (it feels like looking *through a floating window/tear in reality*), whereas Approach A paints *onto* the 3D walls/floors inside the memory. Also, stencil shaders need careful render-priority ordering with shadows and transparency.

### Approach C: Off-Axis Frustum Head-Tracking Parallax *(The "Johnny Lee 3D Hologram Window" Multiplier)*
- **How it works**:
  - Because our blink detector (MediaPipe `FaceLandmarker`) **already tracks the player's 3D head position `(x, y, z)` for free**, we can feed smoothed head offsets into Godot 4's `Camera3D.set_frustum(size, offset, z_near, z_far)`.
  - Physically leaning left/right/up/down shifts the asymmetric projection frustum so the monitor screen behaves like a **real glass window into a 3D box** — letting you physically peek *around* the foreground cat to see Mom behind it!
- **Pros**: Mind-blowing physical "3D window" sensation; zero extra GPU cost; complements BOTH Approach A and Approach B.
- **Cons**: Must be **opt-in / subtle (clamped & damped)** so players who slouch or lack webcams still get smooth mouse-driven parallax, and never get motion-sick.

### Comparison Matrix

| Criterion | Approach A: World-Space Painterly Void | Approach B: Stencil 3D Window Portal | Approach C: Head-Tracked Off-Axis Frustum |
| :--- | :--- | :--- | :--- |
| **Matches *Before Your Eyes* screenshots?** | **100% Exact Match** | Complementary (Portal/Tear variant) | Amplifies 3D Window depth feel |
| **GPU Cost @ 1080p (Godot 4.7 Forward+)** | Very Low (~0.3–0.6 ms) | Ultra Low (~0.1–0.2 ms, no SubViewport) | Zero (~0.01 ms CPU math) |
| **Dynamic Ink-Bloom Growth on Gaze/Blink?** | **Yes** (tween radius + noise phase) | **Yes** (scale/dissolve stencil mask quad) | N/A (Camera projection layer) |
| **Works in `PARALLAX` (Third-Person or Vignette)?** | Great for full memory scenes & Mirror insights | **Incredible** for floating Mirror Rifts / Memory Tears inside an active 3D arena! | Best for first-person / diorama memory scenes |
| **Recommended Role** | **Primary Core Shader (Must Build)** | **Secondary Mode / Bonus Window System** | **Optional Camera Enhancer (Toggleable)** |

---

## 4. The Painterly Edge Math — Avoiding Generic "Soft Dissolve" Slop

Generic noise dissolve shaders look cheap and digital (fuzzy Perlin clouds). Look closely at the uploaded *Before Your Eyes* screenshots to see **what makes the ink contour look hand-crafted**:

1. **Multi-Frequency Domain Warping (Brush Wobble + Fine Bristle Grain)**:
   - Low-frequency 3D/triplanar noise (`scale ≈ 0.35 m⁻¹`) bends the circular island into an organic hand-painted oval/cloud.
   - High-frequency splatter texture (`scale ≈ 2.2 m⁻¹`, Voronoi/ink-blot texture sampled via triplanar mapping) breaks the rim into jagged, brush-dabbed teeth.
2. **Hard Anti-Aliased Cutoff (NOT Wide Soft Gradient!)**:
   - Use `fwidth(edge_field)` to keep the ink transition crisp (`1.5–2.5 px` anti-aliased edge) at any camera distance — just like gouache or ink on black paper.
3. **Detached Stipple / Paint-Droplet Scatter Band**:
   - Look closely around the wallpaper edge in Screenshot 3 and the sky rim in Screenshot 1: there are tiny isolated circular flecks floating `5–25 cm` outside the main silhouette!
   - **Shader recipe**: In the narrow outer band where `sdf > 0.0 && sdf < droplet_band`, evaluate a high-frequency cellular/Voronoi dot mask (`cell_dist < droplet_radius * (1.0 - sdf / droplet_band)`). Any fragment hitting a droplet snaps back to `visible = 1.0`, creating authentic scattered paint flecks outside the main edge!
4. **Subtle Stepped "Line Boil" (Optional 8–12 FPS Painterly Pulse)**:
   - Quantizing `floor(TIME * 8.0)` into a tiny (`1–2%`) noise offset makes the ink border subtly breathe like hand-drawn animation on 2s/3s — alive without jittering distractingly.
5. **Stylized Lighting Hygiene**:
   - Realistic PBR specular highlights and soft SSAO shadows muddy the stark graphic contrast against `#000000`.
   - Use either `render_mode unshaded` with baked/hand-painted light gradients + vertex-color ambient occlusion, **OR** a custom 2-band stylized toon `light()` function with zero dark-void specular leakage (`SPECULAR = 0.0` outside the mask, and multiply `DIFFUSE_LIGHT` & `SPECULAR_LIGHT` by `reveal_mask` so lights NEVER illuminate the `#000000` black void!).
   - **Watch out for Godot 4 DirectionalLight / OmniLight + SSAO + Fog**:
     - If you only set `ALBEDO = vec3(0.0)` in a standard lit shader, **specular reflections, ambient IBL sky reflection, and volumetric/distance fog** will turn the "black void" dark grey!
     - **Rule**: In a lit shader, override `void light()` (or set `SPECULAR = 0.0; ROUGHNESS = 1.0;` + `render_mode fog_disabled;` on masked materials, or set `fog_enabled = false` in memory scenes) so `mask == 0.0` outputs **literal `#000000` (`rgb(0,0,0)`)** identical to the clear color!

---

## 5. Related Games That Solved Adjacent "Memory / Window" Visuals

Studying peer games reveals useful techniques we can borrow:

| Game | Studio / Engine | Technique Used | Takeaway for Our System |
| :--- | :--- | :--- | :--- |
| ***The Unfinished Swan*** | Giant Sparrow (Custom/PS) | Pure white unlit void + paint-splat decals & world-space reveal masks painted onto invisible collision geometry. | Proves player-triggered spatial reveal (splatting/gazing to grow islands) creates instant curiosity and tactile joy. |
| ***Before I Forget*** | 3-Fold Games (Unity) | Desaturated/blank sketch memory spaces that bloom outward in radial world-space color waves when interacting with memory objects. | Great reference for **animated island bloom** (`radius: 0 -> target` with ease-out cubic + subtle saturation wave). |
| ***What Remains of Edith Finch*** | Giant Sparrow (Unreal) | Abrupt perspective/framing shifts per memory (comic panels, bathtub diorama, peephole, fish-factory daydream) with razor-sharp focus framing. | Reinforces framing each memory with a distinct foreground silhouette anchor + tailored camera FOV. |
| ***Moncage*** | Optillusion (Unity) | 5-sided cube where each face is a **Stencil-Buffer 3D Window** looking into a completely separate 3D diorama world. | Gold standard for **Approach B (Stencil 3D Window)** — proves multiple isolated 3D memories can coexist via unique Stencil IDs at ultra-high FPS. |
| ***Viewfinder*** | Sad Owl Studios (Unity) | Holding a 2D photograph up as a 3D frame and stamping it into real 3D geometry. | Inspires hybrid transitions: a 2D painted memory card expanding into a full 3D revealed diorama on blink! |
| ***A Memoir Blue*** | Cloisters Interactive (Unity) | Seamless blend of 2D hand-drawn characters inside 3D stylized memory vignettes surrounded by water/void. | Shows how 2D billboard/cutout elements (like *Before Your Eyes*'s painted clouds and eye icons) mix harmoniously with 3D low-poly props. |
