# 04 — Implementation Strategy & Godot 4.7 Technical Blueprint

> Complete, concrete engineering specification designed for **Godot 4.7.2 (Forward+)** in `d:\Desktop\Godot\parallax`. Every shader technique, global uniform workaround, stencil syntax, camera API, and script contract below is verified against Godot 4.5–4.7 capabilities.

---

## 1. Strategic Architecture Overview

Build the system as a **clean, decoupled module** (`scripts/memory_window/`, `assets/shaders/memory_window/`, `scenes/prototypes/memory_window_demo.tscn`, and optional `tools/blink_tracker/`) so it:
1. **Proves the full look, feel, and blink loop in isolation first** (zero risk to existing `PARALLAX` combat/levels).
2. **Respects all existing `PARALLAX` conventions** (explicit `const Ref := preload(...)`, single `HUD` pattern, zero `SubViewport` mirror cameras, locked 60 FPS @ 1080p, watchdog-guarded tests).
3. Can later plug into `PARALLAX` (as Mirror Memory Vignettes / Rift Windows / Intro/Lore Memories) OR serve as the core engine of a standalone narrative game.

### High-Level Module Graph

```text
[Webcam] -> tools/blink_tracker/tracker.py (MediaPipe FaceLandmarker, 320x240 VIDEO)
                │  UDP 127.0.0.1:4242 (30-60 Hz JSON packet)
                ▼
         BlinkService (Node / Autoload)
         ├── MediaPipeUdpSource (PacketPeerUDP, non-blocking)
         ├── ManualInputSource (Space / LMB hold-to-close fallback)
         ├── SyntheticTestSource (deterministic scripted blinks for CI/QA)
         ├── BlinkCalibration (adaptive open/closed baseline + Schmitt thresholds)
         └── BlinkStateMachine (OPEN / CLOSING / CLOSED / HELD_CLOSED + signals)
                │
                ├──► EyelidOverlay (CanvasLayer + eyelid_blink_overlay.gdshader)
                ├──► MemoryBeatDirector (metronome, safe-gating, atomic blink-cuts, audio)
                └──► MemoryCameraRig (Camera3D + CameraAttributesPractical DoF + optional head-pose set_frustum)
                         │
                         ▼
                 MemoryRevealManager (packs up to 32 3D volumes into 32x2 RGBAF ImageTexture)
                 -> RenderingServer.global_shader_parameter_set("memory_reveal_data", tex)
                         │
                         ├──► memory_void_reveal.gdshader (World-space multi-island painterly void)
                         ├──► memory_sky_reveal.gdshader  (Masked 3D sky dome in outdoor scenes)
                         └──► memory_portal_mask/content.gdshader (Godot 4.7 native stencil_mode 3D window)
```

---

## 2. Solving Godot 4's Global Uniform Array Limit (`RGBAF` Data Texture)

**Verified Godot 4 Engine Constraint**: `[shader_globals]` in `project.godot` does **NOT** support `vec4[]` array uniforms.

**Production Solution**: Declare **three tiny shader globals** in `project.godot` under `[shader_globals]`:
- `memory_reveal_data` (`sampler2D`) — a `32 × 2` `Image.FORMAT_RGBAF` (32-bit float per channel) `ImageTexture`.
- `memory_reveal_count` (`int`) — active reveal volume count (`0..32`).
- `memory_global_fade` (`float`) — global scene visibility fade (`0.0 = total black void`, `1.0 = normal`).

### Exact `32 × 2` `RGBAF` Texel Packing Layout
- **Row `y = 0`, column `x = i`**: `vec4(world_center.x, world_center.y, world_center.z, radius)`
  - If `radius <= 0.0`, slot `i` is inactive.
- **Row `y = 1`, column `x = i`**: `vec4(inv_scale.x, inv_scale.y, inv_scale.z, smoothness)`
  - `inv_scale` (`1.0 / ellipsoid_axis`) lets each memory island be a **sphere OR a stretched ellipsoid** (e.g., wide oval along a living-room wall or flat ellipse across a backyard lawn!).
  - `smoothness` controls smooth-minimum (`smin`) blending radius so two nearby memory islands melt together like wet ink droplets!

### GDScript Update Pattern (`MemoryRevealManager`)
```gdscript
# Pre-allocate once; update dirty slots only; zero per-frame allocations!
const MAX_VOLUMES := 32
var _img: Image
var _tex: ImageTexture

func _ready() -> void:
	_img = Image.create_empty(MAX_VOLUMES, 2, false, Image.FORMAT_RGBAF)
	_tex = ImageTexture.create_from_image(_img)
	RenderingServer.global_shader_parameter_set("memory_reveal_data", _tex)
	RenderingServer.global_shader_parameter_set("memory_reveal_count", 0)
	RenderingServer.global_shader_parameter_set("memory_global_fade", 1.0)
```
Every frame that any `MemoryRevealVolume` (a lightweight `Node3D` gizmo with `@export var radius`, `@export var ellipsoid_scale`, `@export var smoothness`, `@export var active`) moves or tweens its radius, `MemoryRevealManager` writes its two pixels via `_img.set_pixel(i, 0, ...)` and `_img.set_pixel(i, 1, ...)` and calls `_tex.update(_img)` once!

---

## 3. Shader Blueprint 1 — World-Space Painterly Memory Void (`memory_void_reveal.gdshader`)

This reproduces the **exact visual look** of all 3 reference screenshots.

### Key Architectural Requirements
1. **Pure `#000000` Depth-Preserving Void**:
   - Use `render_mode blend_mix, depth_draw_opaque, cull_back, fog_disabled;` (plus `unshaded` for pure *Before Your Eyes* hand-painted flat lighting, **OR** a custom `void light()` toon shader that multiplies lighting by `v_reveal_mask`).
   - **Never `discard` walls** (keeps depth occlusion intact so background rooms don't leak through dark gaps!).
   - Set `WorldEnvironment` background to `BG_COLOR` (`Color(0, 0, 0, 1)`), disable environment ambient light on void pixels, and turn off global sky reflection on masked materials.
2. **Smooth-Union Multi-Island SDF + Triplanar Ink Splatter + Stipple Droplets**:
   ```glsl
   shader_type spatial;
   render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, fog_disabled;

   global uniform sampler2D memory_reveal_data : filter_nearest, repeat_disable;
   global uniform int memory_reveal_count;
   global uniform float memory_global_fade;

   uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
   uniform vec4 albedo_tint : source_color = vec4(1.0);
   uniform sampler2D ink_splatter_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
   uniform sampler2D stipple_dots_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

   uniform bool exempt_from_mask = false;          // TRUE for foreground props (cat, toy piano)
   uniform float splatter_scale = 0.45;            // World-space brush frequency (repeats / meter)
   uniform float splatter_amp = 0.42;              // How far ink teeth distort the volume boundary (meters)
   uniform float droplet_band = 0.28;              // Outer scatter zone width for detached paint flecks (meters)
   uniform float droplet_threshold = 0.72;         // Higher = fewer floating ink dots
   uniform float boil_fps = 8.0;                   // 0 = static, 8 = subtle hand-drawn animation boil
   uniform float boil_amp = 0.015;                 // Tiny brush-edge wobble
   uniform float toon_shade_strength : hint_range(0.0, 1.0) = 0.35; // Soft baked directional wrap
   uniform vec3 key_light_dir = vec3(0.4, 0.85, 0.35);

   varying vec3 w_pos;
   varying vec3 w_nrm;

   float smin(float a, float b, float k) {
       if (k <= 0.001) return min(a, b);
       float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
       return mix(b, a, h) - k * h * (1.0 - h);
   }

   float sample_triplanar(sampler2D tex, vec3 p, vec3 n, float scale) {
       vec3 bw = pow(abs(n), vec3(4.0));
       bw /= max(dot(bw, vec3(1.0)), 1e-4);
       float x = texture(tex, p.zy * scale).r;
       float y = texture(tex, p.xz * scale).r;
       float z = texture(tex, p.xy * scale).r;
       return x * bw.x + y * bw.y + z * bw.z;
   }

   void vertex() {
       w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
       w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
   }

   void fragment() {
       vec3 base_col = texture(albedo_tex, UV).rgb * albedo_tint.rgb;
       // Gentle stylized directional wrap shading (keeps flat pastel readability, never muddy)
       float ndl = dot(normalize(w_nrm), normalize(key_light_dir)) * 0.5 + 0.5;
       float wrap_light = mix(1.0, mix(0.76, 1.06, smoothstep(0.25, 0.75, ndl)), toon_shade_strength);
       base_col *= wrap_light;

       if (exempt_from_mask) {
           ALBEDO = base_col * clamp(memory_global_fade, 0.0, 1.0);
       } else {
           // 1. Evaluate multi-island ellipsoid SDF
           float sdf = 1e5;
           int count = clamp(memory_reveal_count, 0, 32);
           for (int i = 0; i < count; i++) {
               vec4 r0 = texelFetch(memory_reveal_data, ivec2(i, 0), 0);
               if (r0.w <= 0.0001) continue;
               vec4 r1 = texelFetch(memory_reveal_data, ivec2(i, 1), 0);
               vec3 local_d = (w_pos - r0.xyz) * max(r1.xyz, vec3(0.001));
               float d = length(local_d) - r0.w;
               sdf = smin(sdf, d, r1.w);
           }

           // 2. Stepped line-boil offset + world-space triplanar ink splatter
           vec3 boil_off = boil_fps > 0.0
               ? vec3(sin(floor(TIME * boil_fps) * 12.9898), cos(floor(TIME * boil_fps) * 78.233), 0.0) * boil_amp
               : vec3(0.0);
           vec3 n = normalize(w_nrm);
           float macro_n = sample_triplanar(ink_splatter_tex, w_pos + boil_off, n, splatter_scale * 0.35);
           float detail_n = sample_triplanar(ink_splatter_tex, w_pos + boil_off * 1.5, n, splatter_scale);
           float warped_sdf = sdf - ((macro_n * 0.55 + detail_n * 0.45) - 0.5) * 2.0 * splatter_amp;

           // 3. Crisp anti-aliased main painterly silhouette
           float aa = max(fwidth(warped_sdf), 0.012);
           float mask = 1.0 - smoothstep(-aa, aa, warped_sdf);

           // 4. Detached outer stipple/ink-droplet scatter (signature Before Your Eyes border)
           if (warped_sdf > 0.0 && warped_sdf < droplet_band) {
               float t_band = 1.0 - (warped_sdf / droplet_band); // 1 near edge -> 0 at outer rim
               float dots = sample_triplanar(stipple_dots_tex, w_pos, n, splatter_scale * 2.8);
               float dot_thresh = mix(0.98, droplet_threshold, t_band * t_band);
               float dot_aa = max(fwidth(dots), 0.03);
               float droplet = smoothstep(dot_thresh - dot_aa, dot_thresh + dot_aa, dots);
               mask = max(mask, droplet);
           }

           ALBEDO = base_col * mask * clamp(memory_global_fade, 0.0, 1.0);
       }
   }
   ```
3. **Outdoor Sky Masking (`memory_sky_reveal.gdshader`)**:
   - Place a large inverted sphere (`radius ≈ 40–60 m`, `cull_front`) around outdoor memories (like the backyard scene) with painted gradient sky + flat cloud textures, using the **exact same `memory_reveal_data` SDF** (or a directional angular cone mask around a sky anchor point) so the sky cuts cleanly into pure black splatter too!

---

## 4. Shader Blueprint 2 — Godot 4.7 Native Stencil 3D Memory Window (`stencil_mode`)

For sequences where the player looks **literally through a floating painterly 3D window/portal** into a memory (or peers through a Mirror Rift inside `PARALLAX` without any `SubViewport` overhead):

### Window Frame Mask Shader (`memory_window_mask.gdshader`)
```glsl
shader_type spatial;
// Renders BEFORE portal content; writes stencil ID = 1 ONLY inside painterly ink silhouette
render_mode unshaded, depth_draw_never, cull_disabled;
stencil_mode write, compare_always, 1;

uniform sampler2D window_shape_tex : hint_default_white; // Organic brush blob / tear shape
uniform sampler2D splatter_noise_tex : hint_default_white, repeat_enable;
uniform float open_amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    float shape = texture(window_shape_tex, UV).r;
    float noise = texture(splatter_noise_tex, UV * 3.0).r;
    float edge = shape + (noise - 0.5) * 0.25;
    if (edge < (1.0 - open_amount)) {
        discard; // Outside painterly window -> do NOT stamp stencil!
    }
    ALPHA = 0.0; // Invisible mask; stamps stencil = 1 cleanly
}
```
*(Set `render_priority = -2` on the mask material; set `render_priority = 0` on memory-interior materials.)*

### Window Interior Content Shader (`memory_window_content.gdshader`)
```glsl
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
// Only draws pixels visible THROUGH the painterly 3D window!
stencil_mode read, compare_equal, 1;
```
**Pro-Tip for Multiple Windows**: Assign distinct Stencil Reference IDs (`1`, `2`, `3`) to separate floating memory fragments so you can have 3 floating 3D memory windows open simultaneously in a black void without any geometry bleeding between them!

---

## 5. Shader Blueprint 3 — Anatomical Eyelid Blink Overlay (`eyelid_blink_overlay.gdshader`)

Applied to a full-screen `ColorRect` (`mouse_filter = IGNORE`) on a high `CanvasLayer` (`layer = 90`). Driven by `blink_closure` (`0.0 = open`, `1.0 = fully shut`):

- **Curved Eyelid Arcs**: Parabolic arch (`arch = (SCREEN_UV.x - 0.5)^2 * curve_strength`) so eyelids close from top & bottom with natural almond eye curvature instead of mechanical straight bars.
- **Soft Eyelash Feather + Micro-Defocus**: As `blink_closure` ramps from `0.0 -> 0.85`, mix a subtle 5-tap radial screen blur (`hint_screen_texture`) + darkened vignette before snapping to solid `#000000` at `blink_closure >= 0.96`.
- **Atomic Cut Window**: `MemoryBeatDirector` hooks the exact frame `blink_closure >= 0.98` to swap scenes/beats with **zero visual pop**.

---

## 6. Camera Rig: Dynamic Rack-Focus DoF + Optional Head-Tracked 3D Window Frustum

### 6.1 Constrained Diorama Sway + Gaze Raycast Rack-Focus (`MemoryCameraRig.gd`)
1. **Diorama Look-Around**:
   - Normalized cursor offset `m = (mouse_pos / viewport_size) * 2.0 - Vector2.ONE` (clamped `[-1, 1]`).
   - Smoothly damp (`exp(-speed * delta)`) yaw (`±18°`), pitch (`±12°`), AND subtle lateral/vertical camera translation (`±0.18 m` X, `±0.10 m` Y) — that tiny **lateral translation** is what makes the foreground cat shift cleanly across the background Mom & black void!
2. **Dynamic Rack-Focus DoF (`CameraAttributesPractical`)**:
   - Every physics/render frame, raycast from `camera.project_ray_origin(cursor_pos)` along `camera.project_ray_normal(cursor_pos)` against focusable memory layers (or explicit `FocusTargetArea` `Area3D`s around foreground/midground/background subjects).
   - Smoothly interpolate `focus_dist` (`speed ≈ 7.0`):
     - `attrs.dof_blur_far_enabled = true`
     - `attrs.dof_blur_near_enabled = true`
     - `attrs.dof_blur_far_distance = focus_dist + depth_of_field_half_band` (e.g. `+ 0.65 m`)
     - `attrs.dof_blur_far_transition = max(0.8, focus_dist * 0.45)`
     - `attrs.dof_blur_near_distance = max(0.05, focus_dist - depth_of_field_half_band)`
     - `attrs.dof_blur_near_transition = max(0.45, focus_dist * 0.35)`
     - `attrs.dof_blur_amount = 0.14` (tweakable; gives creamy Living Room foreground/background separation!).
   - **Important Godot 4.7 Note**: `CameraAttributesPractical` DoF requires **Forward+** or **Mobile** renderer (already Forward+ in `PARALLAX`!). Disable DoF gracefully if `LeaderboardStore` drops to ultra-low integrated GPU preset if needed, or keep `dof_blur_quality` medium (`RenderingServer.camera_attributes_set_dof_blur_quality()`).

### 6.2 Optional Head-Tracked Off-Axis Frustum ("True Physical 3D Window")
When webcam head-pose `(head_x, head_y, head_z)` is enabled in Options:
- Map smoothed, clamped head position relative to virtual monitor plane (`screen_w = 0.52 m`, `screen_h = 0.29 m`, resting `head_z = 0.65 m`) directly into Godot 4's `Camera3D.set_frustum(frustum_height, offset, z_near, z_far)`.
- Keep camera position anchored to the offset eye point (`base_pos + Vector3(head_x, head_y, head_z - 0.65) * parallax_scale`) while its frustum stays pinned to the virtual window rectangle!
- Result: Physically tilting your head 10 cm right lets you peek *behind* the foreground cat and through the painterly void window!

---

## 7. Decoupled Blink Tracker Protocol (`tools/blink_tracker/tracker.py` → Godot)

### UDP Packet Schema (`127.0.0.1:4242`, UTF-8 JSON, ~30–60 Hz)
```json
{
  "v": 1,
  "ts_ms": 1732692012450,
  "face": true,
  "blink_l": 0.08,
  "blink_r": 0.11,
  "squint_l": 0.04,
  "squint_r": 0.05,
  "ear_l": 0.31,
  "ear_r": 0.30,
  "head_xyz": [0.02, -0.01, 0.62],
  "head_rpy": [2.1, -4.5, 0.8]
}
```
- **Why JSON over localhost UDP?** Packet size is `< 200 bytes` (fits in a single MTU with `< 0.1 ms` serialization), trivially inspectable in logs, and any language (Python, C++, Rust, or a GDScript test harness!) can emit identical packets.
- **Process Lifecycle**:
  - `BlinkService` spawns the sidecar on demand via `OS.create_process()` when Webcam Mode is enabled, stores its PID, and cleanly terminates it via `OS.kill(pid)` on `_exit_tree()` / `NOTIFICATION_WM_CLOSE_REQUEST` (plus the sidecar itself self-terminates if it receives no heartbeat or parent PID exits — zero zombie Python processes!).

---

## 8. `MemoryBeatDirector` & Data-Driven Scene Flow

Model every memory moment as a Godot `Resource` (`MemoryBeatData`):
```gdscript
class_name MemoryBeatData extends Resource

@export var beat_id: StringName
@export var scene_anchor_path: NodePath          # Camera anchor inside the active diorama pod
@export var active_volume_ids: Array[StringName] # Which painterly islands bloom in this beat
@export var min_protected_sec: float = 4.0       # Safe duration before Metronome arms
@export var max_auto_advance_sec: float = 0.0    # 0 = waits indefinitely for blink after metronome
@export var allow_closed_eyes_audio: bool = false
@export var closed_eyes_audio: AudioStream
@export var beat_dialogue_audio: AudioStream
@export var next_beat_id: StringName
```

### Exact Blink Routing Priority (Zero Ambiguity)
When `BlinkStateMachine` emits `blink_committed`:
1. If `calibration_active` or `paused`: **ignore**.
2. If cursor is hovering an active `MemoryHotspot` (white Eye Icon): **trigger hotspot action** (may bloom a new painterly island, play dialogue, or branch `next_beat_id`). Do NOT blindly skip!
3. Else if `metronome_armed == true`: **execute atomic blink-cut** (`EyelidOverlay` closes → at `closure >= 0.98`, switch to `next_beat_id`, tween new reveal islands, rack camera/DoF → open eyelids).
4. Else: **visual micro-blink only** (eyelids blink gently, optional subtle audio/visual pulse, memory stays intact).
