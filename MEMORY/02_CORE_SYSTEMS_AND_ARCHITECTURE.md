# PARALLAX — Core Systems, Architecture & Dimension-Shift Rules

> Technical implementation blueprint mapped from GDD Sections 4 & 11. Keep node paths, autoload names, signal signatures, and physics layers synchronized with this file whenever scripts change.

---

## 1. Scene Tree & Script Architecture

### 1.1 Main Scene Hierarchy (`scenes/main/main.tscn`)
```text
Main (Node)
├── LevelRoot (Node3D)                    # Owns Entrance, Hall, Gallery, Mechanism, Execution Arena geometry & gates
├── Player (CharacterBody3D)              # scripts/player/player_controller.gd -> SpringArm3D -> Camera3D, Skeleton/Mesh, Sword Hitbox (Area3D)
├── RealmManager (Node)                   # scripts/core/realm_manager.gd (Authoritative Reality/Mirror state & safe-shift checks)
├── EncounterDirector (Node)              # scripts/core/encounter_director.gd (Linear section FSM, gates, checkpoints)
├── WorldEnvironment (WorldEnvironment)   # Warm Reality / Cool Mirror environment & light tweening
└── HUD (CanvasLayer)                     # scenes/ui/hud.tscn (Single persistent HUD across all 5 sections)
```
**Autoloads (`project.godot`)**:
- `RunState` (`scripts/core/score_manager.gd`): Holds score, combo chain, elapsed run timer, per-encounter no-hit flags, and checkpoint banked score.
- `LeaderboardStore` (`scripts/core/leaderboard_store.gd` — or accessed statically/autoloaded): Handles `user://leaderboard.cfg` Top 5 persistence & settings.
- `_mcp_game_helper` (`addons/godot_ai/runtime/game_helper.gd`): Already enabled for `godot-ai` MCP testing.

### 1.2 Core Script & Scene Contract Table
| System / Path | Responsibility | Minimum Public Interface / Data |
| :--- | :--- | :--- |
| `scenes/player/player.tscn`<br>`scripts/player/player_controller.gd` | CharacterBody3D locomotion, over-shoulder camera, light/heavy/landing attacks, dodge, damage intake, checkpoint respawn. | `health`, `max_health`, `current_state`, `apply_damage(amount: int, source: Node)`, `respawn_at(transform: Transform3D)`, signals `health_changed`, `player_died` |
| `scripts/core/realm_manager.gd` | Authoritative owner of active realm; runs safety physics checks; toggles realm actors, lighting & audio; disables `Q` in Boss Phase 2. | `enum Realm { REALITY, MIRROR }`, `current_realm: Realm`, `shift_locked: bool`, `request_shift()`, `can_shift_to_realm(target: Realm) -> bool`, `force_merge_realms()`, signal `realm_changed(new_realm: Realm)`, signal `shift_rejected()` |
| `scripts/core/realm_reactive.gd` | Base/component contract attached to or inherited by any platform, prop, light, or actor that responds to Reality vs Mirror. | `enum Affinity { REALITY_ONLY, MIRROR_ONLY, BOTH_STATEFUL }`, `realm_affinity: Affinity`, `set_realm_active(is_active: bool)`, virtual `on_realm_changed(active_realm: int)` |
| `scenes/props/realm_platform.tscn`<br>`scripts/environment/realm_platform.gd` | Swaps/toggles visual meshes and `StaticBody3D` collision shapes for stepping stones and the Gallery bridge (`RepairedGeometry` stays disabled until repaired). | `reality_node`, `mirror_node`, `repaired_node`, `repaired_node_path`, `is_permanently_repaired: bool`, `repair_for_reality()` |
| `scenes/environment/colosseum_greybox.tscn`<br>`scripts/environment/colosseum_greybox_builder.gd` | Deterministic collision-complete greybox generator along `+Z` (`Z = -5..105m`) for Stages 01–05 with switches, gates, breakables, mechanism puzzle, perimeter containment walls, `PitKillZone`s, `SectionTriggerVolume`s, and live placed enemies (`spawn_enemies`). | `ColosseumGreyboxBuilder`: `build_greybox()`, `get_key_anchors() -> Dictionary`, signal `hall_mirror_hint_pulsed` |
| `scripts/environment/pit_kill_zone.gd` (`PitKillZone`) | Chasm kill-plane volume beneath Stage 01 Entry Gap and Stage 03 Collapsed Gallery; forces lethal damage & checkpoint respawn if player falls below `kill_y_threshold`. | `is_point_inside_zone(world_pos)`, `trigger_pit_death(actor)`, signal `pit_fall_triggered(actor)` |
| `scripts/environment/section_trigger_volume.gd` (`SectionTriggerVolume`) | Stage entry trigger volume advancing `EncounterDirector.advance_to_section()`, saving checkpoint, sealing rear entry gate (`seal_gate_for_encounter()`), starting combat encounters, and restarting incomplete encounters on section reset. | `trigger_for_player(player)`, `has_triggered`, signal `section_triggered(section_id, encounter_id)` |
| `scenes/enemies/enemy_base.tscn`<br>`scripts/enemies/enemy_base.gd` | Shared health, damage flash hook, stagger, death, score/encounter hooks, and strict Golden Collision Rule shutdown. | `health`, `max_health`, `realm_affinity`, `is_active`, `apply_damage(amount: int, is_heavy: bool, source_type: String)`, `evaluate_for_realm(...)`, `reset_enemy()`, signals `health_changed`, `damaged`, `staggered`, `died`, `realm_activity_changed` |
| `scripts/enemies/enemy_ai.gd` | State machine for Skeleton, Phantom, Shielded Guard, and extended by The Warden. | `enum State { IDLE, CHASE, WINDUP, ATTACK, RECOVER, STAGGER, DEAD }`, `step_ai(delta)`, `start_windup(...)`, `enter_stagger(...)`, signals `state_changed`, `attack_telegraphed`, `attack_started`, `recovery_started` |
| `scripts/enemies/skeleton_guard.gd` | Stage 02 Reality-only (`100` HP / `15` dmg) Hall of Echoes melee enemy; triggers Mirror hint on first kill. | `reset_hall_hint_flag()`, signal `mirror_hint_requested` |
| `scripts/enemies/phantom_twin.gd` | Stage 02 Mirror-only (`80` HP / `20` dmg) lunging combatant; awards Mirror Kill bonus in Mirror. | `lunge_speed`, `lunge_trigger_range`, `start_windup(...)` |
| `scripts/enemies/shielded_guard.gd` | Stage 03 `BOTH_STATEFUL` (`250` HP / `20` dmg) elite; blocks Light and caps Heavy to `10` chip in Reality, unshielded & staggerable in Mirror. | `is_shield_raised()`, `on_realm_changed(...)`, signals `shield_deflected`, `shield_state_changed` |
| `scripts/enemies/warden_boss.gd` | Stage 05 Final Boss (`1000` shared HP); Phase 1 Reality armor + Mirror `1.40s` chest-rune recovery window, `<=500` HP plane shatter & `force_merge_realms()`, Phase 2 Cleave/Lunge cadence. | `enum Phase`, `enum BossMove`, `is_chest_rune_exposed`, `select_next_move(...)`, `complete_phase2_transition_now()`, signals `boss_phase_changed`, `chest_rune_exposed_changed`, `mirror_plane_shattered`, `boss_defeated` |
| `scenes/props/breakable_prop.tscn`<br>`scripts/environment/breakable_prop.gd` | Authored intact -> warning -> broken collapse via `AnimationPlayer` + one-shot area damage. | `enum PropState { INTACT, BREAKING, BROKEN }`, `trigger_break(by_heavy_attack: bool)`, damage radius `2.5m` (pillar), idempotent guard |
| `scripts/core/hitbox_3d.gd` (`Hitbox3D`)<br>`scripts/core/hurtbox_3d.gd` (`Hurtbox3D`) | Single-hit-per-swing `Area3D` combat plumbing (Layer 7) + standardized damage receiver with i-frames and `RunState.register_hit()` hook. | `begin_swing()`, `end_swing()`, `pulse_radial_targets()`, `receive_hit()`, `hit_targets_this_swing` deduplication |
| `scripts/environment/encounter_gate.gd` (`EncounterGate`) | Section connector gate synced across both realms and linked to `EncounterDirector.encounter_cleared` / switches. | `open_gate(permanent)`, `close_gate()`, `unlock_and_open()`, `starts_open`, `linked_encounter_id` |
| `scripts/environment/interact_switch.gd` (`InteractSwitch`) | Contextual `E: Interact` trigger for Stage 01 Mirror Switch and Stage 03 Bridge Anchor (`repair_for_reality()`). | `enum SwitchRole`, `required_realm`, `blocking_prop_path`, `can_interact()`, `interact()` |
| `scripts/environment/mechanism_puzzle.gd` (`MechanismPuzzle`) | Stage 04 Mechanism Chamber weight/plate puzzle triggered by airborne Landing Attack (`F`) in Mirror. | `on_landing_slam_impact()`, `is_solved`, `is_plate_pressed`, `linked_gate_path` |
| `scripts/core/encounter_director.gd` | Owns linear 5-stage FSM, gate open/close, enemy spawning/activation per room, section checkpoints. | `enum Section { ENTRY, HALL_COMBAT, COLLAPSED_GALLERY, MECHANISM_CHAMBER, EXECUTION_ARENA, COMPLETE }`, `current_section`, `active_enemy_count`, signal `section_changed(section_id)` |
| `scripts/core/score_manager.gd` (`RunState`) | Tracks live score, combo hits/timer, run timer, and per-encounter no-hit flags; calculates rank & time bonus. | `add_score_event(type: String, eligible_for_combo: bool)`, `register_hit()`, `on_player_damaged()`, `begin_encounter(id)`, `end_encounter(id)`, `finalize_run() -> Dictionary` |
| `scripts/core/leaderboard_store.gd` | Offline `ConfigFile` manager for `user://leaderboard.cfg` and `user://settings.cfg`. | `save_run(initials: String, score: int, time_sec: float, rank: String)`, `get_top_five() -> Array[Dictionary]`, `reset_leaderboard()` |
| `scenes/ui/hud.tscn` *(pending)*<br>`scripts/ui/hud_controller.gd` | Persistent single-instance HUD controller listening to Player, RealmManager, EncounterDirector, RunState, and WardenBoss signals. | `HUDController`: `bind_singletons()`, `bind_player(...)`, `bind_boss(...)`, `set_interact_prompt(...)`, `mark_tutorial_completed(...)`, `hp_text`, `active_realm_chip`, `score_text`, `combo_text`, `timer_text`, `boss_bar_visible`, `boss_hp_percent`, optional `@export NodePath` bindings |
| `scripts/ui/{title_screen,pause_menu,results_screen,leaderboard_screen,options_screen,death_overlay}_controller.gd` | Complete deterministic logic controllers for all 6 non-HUD screens in GDD Section 9.2 (`TitleScreenController`, `PauseMenuController`, `ResultsScreenController`, `LeaderboardScreenController`, `OptionsScreenController`, `DeathOverlayController`). | Opening quote card (`<= 5.0s`), `Escape` pause/timer freeze + confirm dialogs, Top-5 3-letter initials submission, Top-5 formatted rows, audio/display/sensitivity settings + 2-step leaderboard reset, and non-blocking `0.65s` death/respawn fade |
| `scripts/core/audio_manager.gd` (`AudioManager`) | Signal-driven audio router connecting `RealmManager`, `PlayerController`, `EnemyBase`, `ShieldedGuard`, `WardenBoss`, `BreakableProp`, and `EncounterGate` to the 12 `.wav` SFX cues and `colosseum_drone_loop.wav`. | `bind_to_world(root_node)`, `play_sfx(sfx_key)`, `start_ambient_drone()`, `stop_ambient_drone()`, `last_played_sfx`, signals `sfx_played`, `music_state_changed` |
| `scripts/environment/realm_environment_controller.gd` (`RealmEnvironmentController`) | Tweens `WorldEnvironment` & `DirectionalLight3D` between Reality (`#9C8468` / `#FF9933`), Mirror (`#141D2E` / `#33B5FF`), and Merged palettes over `0.20s`, and drives `realm_shift_pulse.gdshader`'s `shift_progress` (`0.0 -> 1.0`). | `transition_to_state(state_name)`, `apply_state_immediate(state_name)`, `get_pulse_shader_material()`, `shift_pulse_progress`, signals `environment_transition_started`, `environment_transition_completed` |

---

## 2. Physics Layers & Collision Configuration

Configured in `project.godot` under `[layer_names/3d_physics]`:

| Bit / Layer | Name | Purpose | Collides With |
| :--- | :--- | :--- | :--- |
| **Layer 1** | `Player` | Player `CharacterBody3D` | `World_Shared` + Active Realm Layer (`World_Reality` OR `World_Mirror`) + `Enemy` (active) |
| **Layer 2** | `Enemy` | Skeletons, Phantoms, Guard, Warden (active only) | `World_Shared` + Active Realm Layer + `Player` |
| **Layer 3** | `World_Shared` | Floors, walls, gates, repaired bridge, arena perimeter present in both realms | `Player`, `Enemy` |
| **Layer 4** | `World_Reality` | Reality-only walls/bridges/pillars (disabled or unmasked when in Mirror) | `Player` (in Reality), `Enemy` (in Reality) |
| **Layer 5** | `World_Mirror` | Mirror stepping stones, spectral bridge, suspended weight (disabled in Reality) | `Player` (in Mirror), `Enemy` (in Mirror) |
| **Layer 6** | `Interactable` | Mirror switch, bridge anchor, pressure plate, breakable hurtbox | Detected by Player interact `Area3D` / Sword `Area3D` |
| **Layer 7** | `Hitbox` | Sword swing / enemy strike / landing shockwave `Area3D` shapes | Opposing character hurtbox layers; never push physics bodies |

> **Golden Collision Rule**: Hiding a mesh (`visible = false`) is NEVER enough for an inactive realm actor. Inactive realm geometry must disable its `CollisionShape3D.disabled = true` (or sit strictly on its dedicated `World_Reality` / `World_Mirror` layer while Player collision mask swaps). Inactive enemies must disable collision shapes, disable hitboxes, and pause `_physics_process` / AI state so they can neither deal nor receive damage.

---

## 3. Dimension-Shift System Rules (GDD Section 4)

### 3.1 Reality vs Mirror Ruleset Contrast
| Aspect | **Reality** | **Mirror** |
| :--- | :--- | :--- |
| **World Geometry** | Missing Entry gap; broken Gallery bridge span; solid Reality-only barriers; stone anchor housing. | Spectral stepping stones across Entry gap; complete spectral Gallery bridge; suspended Mechanism weight. |
| **Enemies** | Skeleton Guards active; Shielded Guard frontal shield blocks; Warden armored (Phase 1). | Phantom Twins active; Shielded Guard loses shield; Warden exposes chest rune during recovery (Phase 1). |
| **Visuals & Audio** | Warm limestone, ember amber key light, sun banners, dry stone ambience. | Cold blue-black stone, cobalt rim lighting, emissive seams, moon banners, glass harmonics & filtered ambience. |

### 3.2 Exact `Q` Shift Transition Sequence (`RealmManager.request_shift()`)
1. Guard checks: Reject immediately if `shift_locked` (e.g., Warden Phase 2 merged), game paused, or `cooldown_timer > 0.0` (`0.60 s` cooldown).
2. Compute `target_realm` (toggle `REALITY` <-> `MIRROR`). **Never alter `player.global_transform`.**
3. **Safety Validation (`can_shift_to_realm(target_realm)`)**:
   - **Floor Support Check**: Raycast / shape-cast straight down (`~1.5 m`) below player's feet against `World_Shared` + destination realm's layer (`World_Reality` if shifting to Reality, `World_Mirror` if shifting to Mirror). If no valid floor exists beneath the player (except during intentional mid-air jump? -> GDD 4.3/4.5: *"Never remove the floor beneath the player during a successful shift. The destination floor-support test must reject an unsafe toggle"*), **REJECT**.
   - **Penetration / Overlap Check**: Perform `PhysicsDirectSpaceState3D.intersect_shape()` using the player's capsule shape at `player.global_transform` against destination realm layer (`World_Reality` or `World_Mirror`). If overlapping solid geometry, **REJECT**.
4. **If Rejected**: Emit `shift_rejected()`, play low rejection sound, pulse HUD realm indicator amber/red briefly. Do NOT teleport player.
5. **If Safe**:
   - Update `current_realm = target_realm`.
   - Start `0.60 s` cooldown.
   - Update Player collision mask (`Layer 3 | Layer 4` in Reality; `Layer 3 | Layer 5` in Mirror).
   - Call `set_realm_active()` on all registered `RealmReactive` nodes & enemies (or emit `realm_changed(target_realm)`).
   - Trigger brief `0.15–0.25 s` visual shader ripple + WorldEnvironment light/color tween + glass-harmonic SFX. **Never lock player movement/combat control during transition.**
   - Combo timer does **not** reset on realm shift.

---

## 4. Section State Machine, Checkpoints & Performance

### 4.1 `EncounterDirector` Linear Progression
`ENTRY` (Entry Vestibule) -> `HALL_COMBAT` (Hall of Echoes) -> `COLLAPSED_GALLERY` (Bridge + Shielded Guard) -> `MECHANISM_CHAMBER` (Landing Slam Weight Puzzle) -> `EXECUTION_ARENA` (The Warden Boss) -> `COMPLETE` (Exit Gate -> Results).
- Every gate transition, objective completion, and score award must be **idempotent** (guarded by a boolean `already_completed`) so re-entering triggers cannot double-award points or re-lock gates.

### 4.2 Checkpoint & Respawn Contract (GDD Section 11.6)
- **Checkpoints exist at**: Entrance Vestibule start, Hall of Echoes exit (upon Hall clear), Mechanism / Execution Arena entrance. *(Run state stays in memory; no save files between rooms.)*
- **On Player Death**:
  1. Show brief death overlay; respawn player at current section checkpoint transform.
  2. Restore `health = 100` (`max_health`) and reset `combo = x1`.
  3. Reset only the **current failed section's** enemies, gates, and breakables (`Cracked pillar` resets if player died in Hall).
  4. **Retain** banked score from previously completed sections; **discard** unbanked score earned during the failed section.
  5. **Run timer continues** uninterrupted (Restart Run from Pause resets everything).

### 4.3 Performance Target (GDD Section 11.7)
- Target **stable 60 FPS @ 1920x1080** on mid-range Windows PC.
- **Avoid**: Planar real-time mirror reflections (`Viewport` mirror cameras), SDFGI/VoxelGI heavy spikes, systemic physics fracturing of level geometry. Use fake specular/Fresnel shaders + environment glow instead.
- Only enemies belonging to `EncounterDirector.current_section` should be active at any time.
