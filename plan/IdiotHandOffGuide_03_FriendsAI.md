# IdiotHandOffGuide — PARALLAX Friends & Squad AI Remediation (Guide 03)

> **Scope**: Single self-contained implementation handoff to resolve all **24** bugs (`5 🔴 CRIT`, `16 🟡 WARN`, `3 🔵 LOW`) across the Friends / Squad AI subsystem (`WorldIntel`, `SquadCommandParser`, `SquadAlly`, `AllySquadManager`, `SquadCommsHUD`, `data/allies/03_ivo.tres`), add dedicated automated regression coverage (`tests/friends_ai_bugfix_regression_test.gd`), and synchronize `MEMORY/03`, `05`, `07`.
> **Readiness**: `READY` (all target files, line numbers, symbols, signatures, physics layers, and existing test assertions verified directly against `master` @ `1ca7464`).
> **Cross-Guide Execution Order**: `01 -> 02 -> 03 -> 04` (this document is **Guide 03**).
> **Executor Rule**: Apply Steps 1–9 in exact order, run every verification command in Section E, and return the completion report defined in Section F. Do **not** create extra `.md` files in the repo root or `MEMORY/` (`AGENTS.md` Rule 1.2).

---

## A. Execution Contract

### A.1 Repository & Runtime Baseline (Observed Before Handoff)
- **Repository Root**: `D:\Desktop\Godot\parallax`
- **Branch / HEAD Commit**: `master` @ `1ca7464` (`feat(combat): implement stacked dodge consecutive chaining and execution shield piercing`)
- **Working Tree Status**: Clean (`git status -sb` shows `## master...origin/master` with no modified or untracked files)
- **Engine Binary**: `C:/Users/agrim/.local/bin/godot.cmd` (`Godot Engine v4.7.2.stable.official.ed1daf0bf`, Forward+, Windows 64-bit)
- **Shell**: PowerShell (Windows)
- **Author Validation Status Prior to Execution**:
  - Every diagnosis and code payload in this guide was authored from **static inspection only** of the checked-in repository at `1ca7464` and its existing test suites. **None of the patches in Section D have been applied to the workspace yet**, and no Godot commands have been run against the proposed patches. The executor is responsible for applying Steps 1–9 and executing Section E (`VER-01` .. `VER-07`) to confirm runtime correctness.

### A.2 Strict Operating Rules & Ownership Boundaries
1. **Verify Baseline First**: Confirm `git branch --show-current` is `master` and inspect `git status -sb` before editing. If earlier guides (`01`, `02`) have already been applied in the workspace, preserve their changes and ensure every `Find:` block in this guide still matches uniquely.
2. **Apply Steps 1–9 In Exact Order**: Every edit uses exact `**Find:**` -> `**Replace with:**` blocks or `**Action:** Create` with complete file contents. If any `**Find:**` block fails to match **exactly once**, **STOP**, report the file path and actual lines around the mismatch, and do not guess.
3. **Strict Ownership Boundaries (DO NOT CROSS)**:
   - **`scripts/allies/ally_squad_manager.gd`**: Modify **ONLY** within lines `:217..1509`. **DO NOT** touch `_ready()` or `_spawn_squad()` at lines `:47..90` (`plan/IdiotHandOffGuide_04_SpawningRespawningSave.md` owns startup gating and `regroup(true)` call sites).
   - **`scripts/allies/squad_ally.gd`**: **DO NOT** touch the 5 `GameFeelScript.play_sound()` lines at `:182`, `:1222`, `:1223`, `:1694`, and `:1759` (`plan/IdiotHandOffGuide_01_*` owns those 5 audio calls).
   - **`scripts/core/main_controller.gd`**: **DO NOT** touch `main_controller.gd` (`main_controller.gd:125` spawning allies before `level_ready` is fixed in `plan/IdiotHandOffGuide_04_SpawningRespawningSave.md`, `SRS-05`).
   - **Never** modify `project.godot`, `scenes/`, or any `MEMORY/*.md` files other than the explicit updates in Step 9.
4. **Preserve Recent Invariants (`REQ-15`, `REQ-16`, `REQ-19`, `REQ-20`, `REQ-23`, `REQ-24`, `1ca7464`)**:
   - Do **not** revert `EnemyBase.HEALTH_SCALE = 3.25`, `EnemyAI.DAMAGE_SCALE = 1.4`, `PlayerController` 2-charge dodge chaining, `ShieldedGuard` `player_execution` shield pierce, `125.0 s` player/ally regen rates, `WorldIntel` camera-visible frustum targeting (`<= 140.0 m`), `SkeletonGuard` 1-time `3.0 s` self-revive, or `EncounterDirector` 2-checkpoint death rewind.
   - Keep `data/allies/03_ivo.tres` `mending_light` at `power = 0.18` with autonomous usage disabled (`auto_use = "never"`), while updating `description` from `35%` to `18%` (`ALY-22` / `REQ-20`).
   - Keep `SquadAlly` `150.0 m` distant/camera-visible catch-up exemption (`REQ-16`) while fixing `ALY-04` and `ALY-05`.
5. **No Temporary Leftover Files**: Only the files listed in Section C may be modified or created (`tests/friends_ai_bugfix_regression_test.gd` is permanent).

### A.3 Partial-Application Recovery
If execution is interrupted mid-guide, verify each step's postcondition (`WorldIntel.is_camera_visible`, `SquadCommandParser._find_rule_kw`, `SquadAlly.clear_mine`, `SquadAlly._has_distant_order`, `AllySquadManager` rally queue cleanup, `SquadCommsHUD` PTT release pre-check, `03_ivo.tres` `18%`, `tests/friends_ai_bugfix_regression_test.gd`, and `MEMORY/07` changelog entry), resume at the first unapplied step, or restore clean state on affected files before re-applying.

---

## B. Requirements & Acceptance Map

### B.1 Assigned Bugs (`ALY-01` .. `ALY-24` — 24 Total: `5 🔴 CRIT`, `16 🟡 WARN`, `3 🔵 LOW`)

| Req ID | Severity | Source Location | Defect & Expected Observable Behavior | Implementing Step(s) | Verification Check(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ALY-01** | 🔴 CRIT | `ally_squad_manager.gd:443` + `world_intel.gd` | `_active_enemies_near()` calls `intel.is_camera_visible(e)` on `WorldIntel`, which defines no `is_camera_visible` method -> compile/runtime error when `radius >= 25.0` and `intel != null`. **Expected**: Implement `WorldIntel.is_camera_visible(e: EnemyAI) -> bool` checking valid/non-dead/active/in-tree/`is_hittable_now()` + active `Camera3D` frustum + `<= 140.0 m`, and include camera-visible active enemies in `WorldIntel.refresh()` (`REQ-19`). | Step 1 (Edit 1A, 1C) | `VER-01`, `VER-02` (`aly01_camera_visible_targeting`), `VER-06` |
| **ALY-02** | 🔴 CRIT | `ally_squad_manager.gd:1353-1459` + `squad_ally.gd:1172-1216, :2864` | `_substitute()` dereferences `gone.is_downed`, `gone.current`, `gone.get_display_name()` without `is_instance_valid(gone)`; solo fallback (`:1422`) lacks `is_instance_valid(survivor) and not survivor.is_downed`; substituting/aborting `"trapper"` or going down leaks `gone._mine` (`MirrorSigil_*` + `OmniLight3D`) and leaves `rec["planted_t"]` unreset. **Expected**: Guard all `gone`/`survivor`/`trapper`/`kiter` accesses with `is_instance_valid`, add `SquadAlly.clear_mine()`, call it on `_go_down()`, `reset_full()`, `_substitute()`, and `_abort_combo()`, reset `rec["planted_t"] = -1.0`, and copy `rec["point"]` to substituted lurer. | Step 3 (Edit 3D, 3G), Step 5 (Edit 5G) | `VER-01`, `VER-02` (`aly02_substitute_and_mine_cleanup`), `VER-06` |
| **ALY-03** | 🔴 CRIT | `squad_ally.gd:1464-1497` | `_run_lurer()` ignores `cmd.step == "fallback"` (set by `_kite_fallback()`), freezing gravity/movement until 40s combo timeout; `cmd.data["done"]` also ignored outside `"luring"`. **Expected**: Check `bool(cmd.data.get("done", false))` at top of `_run_lurer()` across all steps, and route `"fallback"` back into `_kite_logic()` alongside `"approach"`, `"provoke"`, and `"confirm"`. | Step 3 (Edit 3E) | `VER-01`, `VER-02` (`aly03_lurer_fallback_and_done`), `VER-06` |
| **ALY-04** | 🔴 CRIT | `squad_ally.gd:380, :500, :2435-2451, :2864, :2905` | Downed ally loses `LAYER_WORLD_MIRROR` on `Q` (`_sync_realm_mask()` removes inactive realm layer), `_physics_process()` returns before `_catch_up()`, `PitKillZone` ignores allies, gravity drops `Y -> -inf`; ordered `"revive"` soft-locks reviver permanently under `MISSION` lock when target is unreachable. **Expected**: Keep `LAYER_WORLD_REALITY \| LAYER_WORLD_MIRROR` in `_sync_realm_mask()` while `is_downed` (re-syncing on `revive()`/`reset_full()`); track safe floor position; in `_process_downed()`, rescue downed allies from `PitKillZone` / `y < player.y - 6.0` / `y < -20.0` / `dist > 35.0` via `_blink_to(player)` (or `_last_safe_pos` if player airborne); add `10.0 s` approach timeout + `14.0 s` safety cap to `_revive_target()`. | Step 3 (Edit 3A, 3C, 3F, 3G) | `VER-01`, `VER-02` (`aly04_downed_safety_and_revive_timeout`), `VER-06` |
| **ALY-05** | 🔴 CRIT | `squad_ally.gd:3404-3438` | `_catch_up()` LOS ray passes `collision_mask = 1` (`LAYER_PLAYER`) instead of world geometry, so walls/gates never block the ray and allies trapped behind walls fail to blink; also preserve `REQ-16` `150.0 m` distant/camera-visible order exemption in `_catch_up()` and `_update_stuck()`. **Expected**: LOS ray uses `collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER` excluding `[get_rid(), player_rid]`; pit falls bypass frustum anti-pop; active distant/camera-visible orders allow up to `150.0 m` leash without teleport loop. | Step 3 (Edit 3H) | `VER-01`, `VER-02` (`aly05_catchup_wall_los_and_req16_exemption`), `VER-06` |
| **ALY-06** | 🟡 WARN | `ally_squad_manager.gd:217, :242-246, :283-295` + `squad_ally.gd:436-438` | `_start_rally()` sets `cmd.data["rally"] = true` which is wiped if `assign()` runs again (e.g. after skill cut-in); `_update_rally()` ignores `ally.queue` (locking a preempted ally in infinite `bodyguard`); `regroup(true)` leaves `_rally`/`_rally_cooldown` stale. **Expected**: Store `"rally": true` in both `cmd.args` and `cmd.data` and preserve it across `assign()`; clear rally commands from both `ally.queue` and `ally.current` in `_update_rally()`; clear `_rally`, `_rally_cooldown`, and `_rally_scan` on `regroup(true)`. | Step 3 (Edit 3B), Step 5 (Edit 5A, 5B) | `VER-01`, `VER-02` (`aly06_rally_queue_and_regroup_cleanup`), `VER-06` |
| **ALY-07** | 🟡 WARN | `ally_squad_manager.gd:692, :853` | `"stop"` and `execute_strategy()` call `finish_current()` without `_abort_current_effects()`, leaving active nuke channels, revives, or dances executing. **Expected**: Call `a._abort_current_effects()` before `a.finish_current()` in both `"stop"` and `execute_strategy()`. | Step 5 (Edit 5C, 5D) | `VER-01`, `VER-02` (`aly07_stop_and_strategy_abort_effects`), `VER-06` |
| **ALY-08** | 🟡 WARN | `ally_squad_manager.gd:852, :891` | `execute_strategy()` overrides active `PANIC` orders (`ceasefire`/`massacre`) because `assign(cmd)` executes unconditionally after skipping `finish_current()`, and leaves `_combos` un-cancelled for overridden allies. **Expected**: Skip allies with `current.priority >= Priority.PANIC` before `clear_queue()`/`assign()` and cancel `_combos` for all allies that accept the strategy. | Step 5 (Edit 5D) | `VER-01`, `VER-02` (`aly08_strategy_respects_panic_and_cancels_combos`), `VER-06` |
| **ALY-09** | 🟡 WARN | `ally_squad_manager.gd:707, :1007` | `_route()` exempts `"revive"` from `a.is_downed` and `issue()` skips substitution for `"revive"`, letting a downed ally accept a `"revive"` order nobody performs. **Expected**: Remove `cmd.verb != "revive"` exemption in `_route()` (`if a.is_downed: return "is down"`), and allow `issue()` to substitute `"revive"` to a living ally (excluding the revive target itself). | Step 5 (Edit 5C, 5F) | `VER-01`, `VER-02` (`aly09_downed_ally_revive_substitution`), `VER-06` |
| **ALY-10** | 🟡 WARN | `squad_ally.gd:477-482` | `_abort_current_effects()` only clears `"channel"`, `"revive"`, `"dance"`, `"emote"`, leaving `"attack"`, `"spin"`, `"flip"` (`VisualRoot.rotation.x` tilted), and active charges (`_dash_timer`, `_dash_hit_cb`) running on `PANIC` `"ceasefire"`. **Expected**: Clear any non-empty `_action` + timer/callback, zero `_dash_timer`/`_dash_vel`/`_dash_hit_cb`/`_dash_target`, and reset `VisualRoot.rotation.x = 0.0` + re-align `VisualRoot.rotation.y` to `facing_direction`. | Step 3 (Edit 3B) | `VER-01`, `VER-02` (`aly10_abort_all_actions_spins_flips_charges`), `VER-06` |
| **ALY-11** | 🟡 WARN | `squad_ally.gd:848-884` | `_run_taunt_cmd()` with `area: true` only collects enemies targeting `player` (refusing idle or ally-targeting foes); single-target lacks `_enemy_ok(e)` re-check and approach timeout. **Expected**: Fall back from `on_player` to nearby active enemies (`14.0 m` around player or self) and then `_resolve_enemy`; add `10.0 s` timeout on `area` move; validate `_enemy_ok(e)` and add `12.0 s` approach timeout on single-target taunt. | Step 4 (Edit 4B) | `VER-01`, `VER-02` (`aly11_taunt_area_fallback_and_timeout`), `VER-06` |
| **ALY-12** | 🟡 WARN | `squad_ally.gd:1774, :1799, :1981, :2066` + `ally_squad_manager.gd:920` | `_friends()`, `_skill_mend()`, `_skill_ward()`, `_run_skill()`, and `_weakest_friend_name()` never check `PlayerController.current_state == State.DEAD`, healing/warding/bodyguarding the dead player. **Expected**: Exclude `PlayerController` when `current_state == State.DEAD` in all 5 sites. | Step 4 (Edit 4C, 4F, 4G), Step 5 (Edit 5E) | `VER-01`, `VER-02` (`aly12_ignore_dead_player_in_heals_wards`), `VER-06` |
| **ALY-13** | 🟡 WARN | `squad_ally.gd:800, :825, :1914, :2599, :2749, :2948` | `_ranged_engage()` & `_run_ranged()` unconditionally back away for `d < RANGED_MIN` (`5.5 m`) without checking `_side_open()` or firing -> wall-backed ranged freeze; `_run_hold()`, `_run_retreat_order()`, and `_run_position()` call `_fight()` which routes artillery into `_ranged_engage()` and backpedals out of spot range -> infinite oscillation. **Expected**: Guard `d < RANGED_MIN` backpedal with `d > 0.01 and _side_open(-to_e.normalized())` and handle `close` `2.2..2.6 m` gap; pass `hold_ground = true` to `_fight()` from `_run_hold()`, `_run_retreat_order()`, and `_run_position()` so artillery defends in place with bolts/melee without leaving its spot. | Step 4 (Edit 4A, 4E, 4I, 4J, 4K) | `VER-01`, `VER-02` (`aly13_ranged_wall_and_hold_no_oscillation`), `VER-06` |
| **ALY-14** | 🟡 WARN | `squad_ally.gd:2055-2088` | `_run_skill()` only checks `is_instance_valid(tgt)` while approaching `cast_range`, running across the room to dead/unhittable/downed targets before fizzling. **Expected**: Validate cached `tgt` every tick (`_enemy_ok(tgt)` for `"enemy"`, in-tree and living/`not is_downed`/`!= State.DEAD` for `"ally"`) and finish cleanly if lost mid-approach. | Step 4 (Edit 4G) | `VER-01`, `VER-02` (`aly14_run_skill_target_validity`), `VER-06` |
| **ALY-15** | 🟡 WARN | `squad_ally.gd:2587-2591` | `_run_position()` inverts `"left"` (`+r`, which is Godot right when `r = Vector3(-f.z, 0, f.x)`) and `"right"` (`-r`, which is Godot left). **Expected**: `"left"` uses `-r` and `"right"` uses `+r`, matching `WorldIntel` and `_split_squad()`. | Step 4 (Edit 4I) | `VER-01`, `VER-02` (`aly15_position_left_right_uninverted`), `VER-06` |
| **ALY-16** | 🟡 WARN | `squad_command_parser.gd:95-109, :195-205, :295, :420` | Unanchored `t.contains()` matches `"cast"` inside `"caster"`/`"hexcaster"` -> `"nuke"` and `"guard"` inside `"shielded guard"` -> `"bodyguard"` (and `_normalize()` typo-rewrote 8-char `"shielded"` into `"shield"`). **Expected**: Enforce word-boundary rule matching via `_find_rule_kw()` / `_sanitize_rule_text()` across `_has_instruction()`, `_parse_clause()`, and `_addressed()`, mask `"shielded guard"` / article+`"guard"` when matching `"guard"` verb, and add `"shielded"` / `"archer"` to parser vocabulary. | Step 2 (Edit 2A, 2B, 2C) | `VER-01`, `VER-02` (`aly16_parser_word_boundaries`), `VER-03` |
| **ALY-17** | 🟡 WARN | `squad_command_parser.gd:430` | `_match_skill()` uses `not t.contains(" " + ps + " ") and not t.contains(" " + ps)`, lacking a trailing space check on the second clause and hijacking `"warden"`/`"health"`/`"archer"` into `"ward"`/`"heal"`/`"arc"`. **Expected**: Require full space-padded word match `pad.contains(" " + ps + " ")`. | Step 2 (Edit 2C) | `VER-01`, `VER-02` (`aly17_match_skill_trailing_boundary`), `VER-03` |
| **ALY-18** | 🟡 WARN | `squad_command_parser.gd:179, :289, :533-552` | `_addressed()` computes `first_verb_pos` only from `RULES`, so skill/strategy verbs like `"Ivo, ward Brannoc"` put both `"Ivo"` and `"Brannoc"` into `addressed` and drop target ally `"Brannoc"`. **Expected**: Pass `ctx` into `_addressed()`, scan `RULES`, `ctx["skills"]`, and `SquadStrategies.LIST` aliases for `first_verb_pos`, and match whole ally names (`" " + ln + " "`). | Step 2 (Edit 2B, 2D) | `VER-01`, `VER-02` (`aly18_addressed_skill_first_verb_pos`), `VER-03` |
| **ALY-19** | 🟡 WARN | `world_intel.gd:66-74` | `node_for_id()` omits `is_active and is_inside_tree()` (and checks `o is EnemyAI` before `is_instance_valid(o)`). **Expected**: Check `is_instance_valid(o) and o is EnemyAI` and require `not e.is_dead and e.is_active and e.is_inside_tree()`. | Step 1 (Edit 1B) | `VER-01`, `VER-02` (`aly19_node_for_id_active_in_tree`), `VER-06` |
| **ALY-20** | 🟡 WARN | `world_intel.gd:263, :285-286` (+ `ally_squad_manager.gd:825, :940`) | `WorldIntel.resolve()` lacks null guard on player fallback (`asker == null`) and `is_instance_valid`/`is_active`/`is_inside_tree()` on cached `en_node` in `_entries`. **Expected**: Guard `asker` and tree `"player"` node before `.global_position`, filter cached `_entries` with `is_instance_valid(en_node) and not en_node.is_dead and en_node.is_active and en_node.is_inside_tree() and en_node.is_hittable_now()`, and guard `ally_squad_manager.gd` cached entry loops similarly. | Step 1 (Edit 1D), Step 5 (Edit 5D, 5E) | `VER-01`, `VER-02` (`aly20_world_intel_resolve_null_and_valid_guards`), `VER-06` |
| **ALY-21** | 🟡 WARN | `squad_comms_hud.gd:57-61, :136-176` | `_input()` runs `F10` (`cinematic_mode`) before `_blocked_by_menu()`, loses `push_to_talk` release on early returns (`_chat_open`, `_blocked_by_menu()`), and omits `LoadingScreen` and `!is_visible_in_tree()` in `_blocked_by_menu()`. **Expected**: Handle `_ptt_held_key` release at the top of `_input()`, move `cinematic_mode` after `_blocked_by_menu()`, clear PTT flags on `_exit_tree()`, and check `!is_visible_in_tree()` (when `not _cinematic`), `"loading_screen"` group, `MainController._loading != null / not level_ready`, and `LoadingScreen` children in `_blocked_by_menu()`. | Step 6 (Edit 6A, 6B) | `VER-01`, `VER-02` (`aly21_comms_hud_input_gating_and_ptt_release`), `VER-04` |
| **ALY-22** | 🔵 LOW | `data/allies/03_ivo.tres:27-36` | `mending_light` `description` still says `35%` while `power = 0.18` (18%) and `auto_use = ""`. **Expected**: Sync `description` to `18%`, preserve `power = 0.18`, set `auto_use = "never"` (with `squad_ally.gd` skipping both `""` and `"never"` per `REQ-20`). | Step 4 (Edit 4F), Step 7 (Edit 7A) | `VER-01`, `VER-02` (`aly22_ivo_mending_description_and_no_auto`) |
| **ALY-23** | 🔵 LOW | `squad_ally.gd:1838-1855` | `_chain_arc_hop()` ignores `bool` return of `apply_damage()` (stunning `ShieldedGuard` on `0` damage) and drops remaining hops if target dies/becomes unhittable mid-flight. **Expected**: Capture `var landed: bool = e.apply_damage(...)`, stun only if `landed and not e.is_dead and not e.knockdown_immune`, and always continue `_chain_arc_hop(..., i + 1, ...)` even if `e` became invalid/unhittable during bolt flight. | Step 4 (Edit 4D) | `VER-01`, `VER-02` (`aly23_chain_arc_landed_guard_and_midflight_hops`), `VER-06` |
| **ALY-24** | 🔵 LOW | `squad_ally.gd:2363` | `_run_destroy()` checks only XZ distance, letting ground-floor allies smash `WeakStoneSupport` `3.6 m` up on `SupportLedge`. **Expected**: Require both XZ `<= 2.2` and `absf(global_position.y - goal.y) <= 2.0` before triggering `prop.trigger_break(true)`. | Step 4 (Edit 4H) | `VER-01`, `VER-02` (`aly24_destroy_vertical_reach_check`), `VER-06` |

### B.2 Out-of-Scope Cross-References & Preserved Invariants
- **Startup Spawning Race (`main_controller.gd:125`, `ally_squad_manager.gd:47-90`)**: Spawning allies before `MainController.level_ready` is owned and fixed in `plan/IdiotHandOffGuide_04_SpawningRespawningSave.md` (`SRS-05`). **Do NOT** edit `main_controller.gd` or `ally_squad_manager.gd:47-90` in this guide.
- **Ally Combat/Hit SFX Lines (`squad_ally.gd:182, :1222, :1223, :1694, :1759`)**: Owned by Guide 01. **Do NOT** modify those 5 lines in this guide.
- **Preserved Invariants**: `REQ-19` (`WorldIntel.is_camera_visible` `<= 140.0 m`), `REQ-20` (Ivo `mending_light` `power = 0.18`, `auto_use` disabled), and `REQ-16` (`150.0 m` distant/camera-visible catch-up exemption).

---

## C. File-Change Manifest

| File Path (Relative to Repo Root) | Operation | Step ID | Purpose |
| :--- | :--- | :--- | :--- |
| `scripts/allies/world_intel.gd` | `modify` | Step 1 | Add `is_camera_visible()` (`<= 140 m`, `REQ-19`), fix `node_for_id()` active/in-tree guards, harden `resolve()` null/freed guards & `"farther"` scoring (`ALY-01`, `ALY-19`, `ALY-20`). |
| `scripts/allies/squad_command_parser.gd` | `modify` | Step 2 | Enforce word-boundary rule matching + `"shielded guard"` guard, fix `_match_skill()` trailing space check, include skills/strategies in `_addressed()` `first_verb_pos` (`ALY-16`, `ALY-17`, `ALY-18`). |
| `scripts/allies/squad_ally.gd` | `modify` | Step 3, Step 4 | Fix `_run_lurer()`, downed realm-mask/pit/revive safety, `_catch_up()` world LOS + `REQ-16` exemption, `_abort_current_effects()`, `_run_taunt_cmd()`, dead player exclusions, `_ranged_engage()`/`_run_ranged()` + hold-ground spot defense, `_run_skill()` validity, `"left"`/`"right"`, `_chain_arc_hop()`, `_run_destroy()` vertical reach, `clear_mine()`, and `assign()` rally persistence (`ALY-02..06`, `ALY-10..15`, `ALY-23`, `ALY-24`). *(Preserves `:182, :1222, :1223, :1694, :1759`.)* |
| `scripts/allies/ally_squad_manager.gd` | `modify` | Step 5 | Only lines `:217..1509` (`:47..90` untouched): fix rally `args`/`queue`/`regroup(true)`, `"stop"` & `execute_strategy()` effect aborting + `PANIC` protection + combo cancel, `"revive"` substitution & `_route()`, `_weakest_friend_name()` dead player check, `_substitute()`/`_abort_combo()`/`_combo_coordinate()` validity & mine/timer cleanup (`ALY-02`, `ALY-06..09`, `ALY-12`, `ALY-20`). |
| `scripts/ui/squad_comms_hud.gd` | `modify` | Step 6 | Handle `push_to_talk` release before early returns, gate `F10` behind `_blocked_by_menu()`, add `LoadingScreen` & `!is_visible_in_tree()` checks, clear PTT flags on `_exit_tree()` (`ALY-21`). |
| `data/allies/03_ivo.tres` | `modify` | Step 7 | Update `mending_light` `description` from `35%` to `18%` and set `auto_use = "never"` while keeping `power = 0.18` (`ALY-22` / `REQ-20`). |
| `tests/friends_ai_bugfix_regression_test.gd` | `create` | Step 8 | Permanent headless regression test suite covering all 24 requirements (`ALY-01` .. `ALY-24`). |
| `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` | `modify` | Step 9 | Sync Ivo `18%` / manual-only `mending_light`, `WorldIntel.is_camera_visible()`, `REQ-16` `150 m` exemption, and Squad AI reliability fixes (`AGENTS.md` Rule 1.3). |
| `MEMORY/05_UI_SCORING_AND_AUDIO.md` | `modify` | Step 9 | Document `SquadCommsHUD` menu/loading/PTT-release input gating and `SquadCommandParser` boundary/skill/addressee fixes (`AGENTS.md` Rule 1.3). |
| `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` | `modify` | Step 9 | Append dated Friends & Squad AI remediation changelog entry (`AGENTS.md` Rule 1.3). |

---

## D. Ordered Implementation Steps

### Step 1 — Implement `WorldIntel.is_camera_visible()` & Harden `node_for_id()` / `resolve()` (`ALY-01`, `ALY-19`, `ALY-20`, `REQ-19`)
- **Prerequisites**: Baseline verified at `master` @ `1ca7464`.
- **Note**: Apply Edits 1A–1D in order. Their target regions in `scripts/allies/world_intel.gd` are non-overlapping.

#### Edit 1A — Add `CAMERA_MAX_M` Constant (`ALY-01`, `REQ-19`)
**Target:** `scripts/allies/world_intel.gd`
**Action:** Replace block
**Find:**
```gdscript
const REFRESH_SEC: float = 0.25
const RANGE_M: float = 40.0
```
**Replace with:**
```gdscript
const REFRESH_SEC: float = 0.25
const RANGE_M: float = 40.0
const CAMERA_MAX_M: float = 140.0
```

#### Edit 1B — Require Valid, Active, In-Tree Enemy in `node_for_id()` (`ALY-19`)
**Target:** `scripts/allies/world_intel.gd`
**Action:** Replace block
**Find:**
```gdscript
func node_for_id(id: String) -> EnemyAI:
	var want: String = id.strip_edges().to_upper()
	for iid in _ids.keys():
		if String(_ids[iid]) == want:
			var o: Object = instance_from_id(int(iid))
			if o is EnemyAI and is_instance_valid(o) and not (o as EnemyAI).is_dead:
				return o as EnemyAI
	return null
```
**Replace with:**
```gdscript
func node_for_id(id: String) -> EnemyAI:
	var want: String = id.strip_edges().to_upper()
	for iid in _ids.keys():
		if String(_ids[iid]) == want:
			var o: Object = instance_from_id(int(iid))
			if is_instance_valid(o) and o is EnemyAI:
				var e: EnemyAI = o as EnemyAI
				if not e.is_dead and e.is_active and e.is_inside_tree():
					return e
	return null
```

#### Edit 1C — Implement `is_camera_visible()` & Include Visible Enemies in `refresh()` (`ALY-01`, `REQ-19`)
**Target:** `scripts/allies/world_intel.gd`
**Action:** Replace block
**Find:**
```gdscript
func refresh() -> void:
	_entries.clear()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var pf: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else Vector3.FORWARD
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = n as EnemyAI
		if e == null or e.is_dead or not e.is_inside_tree() or not e.is_hittable_now():
			_hide_tag(n)
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if not e.is_active or d > RANGE_M:
			_hide_tag(e)
			continue
		var entry: Dictionary = _describe(e, player, pf, d)
		_entries.append(entry)
		_update_tag(e, entry)
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
```
**Replace with:**
```gdscript
func is_camera_visible(e: EnemyAI) -> bool:
	if e == null or not is_instance_valid(e) or e.is_dead or not e.is_active or not e.is_inside_tree() or not e.is_hittable_now():
		return false
	if not is_inside_tree() or get_viewport() == null:
		return false
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(cam):
		return false
	if cam.global_position.distance_to(e.global_position) > CAMERA_MAX_M:
		return false
	return cam.is_position_in_frustum(e.global_position + Vector3.UP * 1.0) or cam.is_position_in_frustum(e.global_position)


func refresh() -> void:
	_entries.clear()
	if not is_inside_tree() or get_tree() == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return
	var pf: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else Vector3.FORWARD
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = n as EnemyAI
		if e == null or not is_instance_valid(e) or e.is_dead or not e.is_inside_tree() or not e.is_hittable_now():
			_hide_tag(n)
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		var cam_vis: bool = is_camera_visible(e)
		if not e.is_active or (d > RANGE_M and not cam_vis):
			_hide_tag(e)
			continue
		var entry: Dictionary = _describe(e, player, pf, d)
		_entries.append(entry)
		_update_tag(e, entry)
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
```

#### Edit 1D — Null-Safe Origin & Cached Entry Validation in `resolve()` (`ALY-20`, `REQ-19`)
**Target:** `scripts/allies/world_intel.gd`
**Action:** Replace block
**Find:**
```gdscript
	var tokens: PackedStringArray = s.replace(",", " ").replace(".", " ").replace("'s", " ").split(" ", false)
	var origin: Vector3 = asker.global_position if asker != null else (get_tree().get_first_node_in_group("player") as Node3D).global_position
	# "near Sera" / "closest to Brannoc" / "attacking Ivo" / "on me" / "hitting me".
	var ref_node: Node3D = null
	var ref_mode: String = ""
	var mgr: Node = get_parent()
	for i in range(tokens.size()):
		var t: String = tokens[i]
		var nxt: String = tokens[i + 1] if i + 1 < tokens.size() else ""
		if t in ["near", "next", "closest", "nearest", "by", "beside"] or (t == "to" and i > 0 and tokens[i - 1] in ["closest", "nearest", "next"]):
			var who: Node3D = _named_entity(nxt, mgr)
			if who != null:
				ref_node = who
				ref_mode = "near"
		if t in ["attacking", "hitting", "on", "chasing", "targeting", "hunting", "fighting"]:
			var who2: Node3D = _named_entity(nxt, mgr)
			if who2 != null:
				ref_node = who2
				ref_mode = "targeting"
	var best: EnemyAI = null
	var best_score: float = -INF
	var any_desc: bool = false
	for en in _entries:
		var en_node: EnemyAI = en.get("node") as EnemyAI
		if en_node == null or en_node.is_dead or not en_node.is_hittable_now():
			continue
		var score: float = 0.0
		var words: String = String(en["words"])
		for t in tokens:
			if t.length() < 3 or t in ["the", "one", "guy", "that", "this", "with", "and", "who", "kill", "attack", "him", "her", "them", "enemy", "please", "now", "get", "go", "hit"]:
				continue
			if t in COLOR_WORDS or t in ["axe", "sword", "shield", "orb", "blades", "caster", "mage", "brute", "rogue", "knight", "barbarian", "skeleton", "phantom", "ghost", "stalker", "hexcaster", "warden", "big", "huge", "small", "giant", "archer", "ranged", "glowing", "hooded", "armored", "greataxe", "twin"]:
				any_desc = true
				if words.contains(t):
					score += 3.0
				elif t in ["caster", "mage", "archer", "ranged"] and bool(en["ranged"]):
					score += 3.0
				elif t in ["big", "huge", "giant"] and String(en["size"]) in ["big", "huge"]:
					score += 2.0
				elif t in ["blades"] and String(en["weapon"]).contains("sword"):
					score += 2.0
				else:
					score -= 1.5
			if SIDE_WORDS.has(t):
				any_desc = true
				score += 2.0 if String(en["bearing"]).contains(String(SIDE_WORDS[t])) else -1.0
			if t in ["stunned", "fleeing", "enraged", "wounded", "hurt", "dying"]:
				any_desc = true
				if t in ["wounded", "hurt", "dying"]:
					score += (100.0 - float(en["hp_pct"])) / 40.0
				elif String(en["state"]).contains(t):
					score += 3.0
		if ref_node != null:
			any_desc = true
			if ref_mode == "targeting":
				var tn: String = String(en["targeting"]).to_lower()
				var rn: String = "player" if ref_node is PlayerController else String(ref_node.call("get_display_name")).to_lower()
				score += 4.0 if tn == rn else -2.0
			else:
				score -= (en["node"] as Node3D).global_position.distance_to(ref_node.global_position) * 0.25
		# Superlatives / default ordering.
		var d: float = (en["node"] as Node3D).global_position.distance_to(origin)
		if s.contains("farthest") or s.contains("furthest"):
			score += d * 0.05
		elif s.contains("strongest") or s.contains("toughest") or s.contains("biggest"):
			score += float(en["hp"]) * 0.01
		elif s.contains("weakest") or s.contains("lowest"):
			score += (100.0 - float(en["hp_pct"])) * 0.03
		else:
			score -= d * 0.05
		if (en["node"] as EnemyAI).is_aggroed():
			score += 0.3
		if score > best_score:
			best_score = score
			best = en["node"] as EnemyAI
```
**Replace with:**
```gdscript
	var tokens: PackedStringArray = s.replace(",", " ").replace(".", " ").replace("'s", " ").split(" ", false)
	var origin: Vector3 = Vector3.ZERO
	if asker != null and is_instance_valid(asker):
		origin = asker.global_position
	elif is_inside_tree() and get_tree() != null:
		var player_node: Node3D = get_tree().get_first_node_in_group("player") as Node3D
		if player_node != null and is_instance_valid(player_node):
			origin = player_node.global_position
	# "near Sera" / "closest to Brannoc" / "attacking Ivo" / "on me" / "hitting me".
	var ref_node: Node3D = null
	var ref_mode: String = ""
	var mgr: Node = get_parent()
	for i in range(tokens.size()):
		var t: String = tokens[i]
		var nxt: String = tokens[i + 1] if i + 1 < tokens.size() else ""
		if t in ["near", "next", "closest", "nearest", "by", "beside"] or (t == "to" and i > 0 and tokens[i - 1] in ["closest", "nearest", "next"]):
			var who: Node3D = _named_entity(nxt, mgr)
			if who != null:
				ref_node = who
				ref_mode = "near"
		if t in ["attacking", "hitting", "on", "chasing", "targeting", "hunting", "fighting"]:
			var who2: Node3D = _named_entity(nxt, mgr)
			if who2 != null:
				ref_node = who2
				ref_mode = "targeting"
	var best: EnemyAI = null
	var best_score: float = -INF
	var any_desc: bool = false
	for en in _entries:
		var en_node: EnemyAI = en.get("node") as EnemyAI
		if en_node == null or not is_instance_valid(en_node) or en_node.is_dead or not en_node.is_active or not en_node.is_inside_tree() or not en_node.is_hittable_now():
			continue
		var score: float = 0.0
		var words: String = String(en["words"])
		for t in tokens:
			if t.length() < 3 or t in ["the", "one", "guy", "that", "this", "with", "and", "who", "kill", "attack", "him", "her", "them", "enemy", "please", "now", "get", "go", "hit"]:
				continue
			if t in COLOR_WORDS or t in ["axe", "sword", "shield", "orb", "blades", "caster", "mage", "brute", "rogue", "knight", "barbarian", "skeleton", "phantom", "ghost", "stalker", "hexcaster", "warden", "big", "huge", "small", "giant", "archer", "ranged", "glowing", "hooded", "armored", "greataxe", "twin"]:
				any_desc = true
				if words.contains(t):
					score += 3.0
				elif t in ["caster", "mage", "archer", "ranged"] and bool(en["ranged"]):
					score += 3.0
				elif t in ["big", "huge", "giant"] and String(en["size"]) in ["big", "huge"]:
					score += 2.0
				elif t in ["blades"] and String(en["weapon"]).contains("sword"):
					score += 2.0
				else:
					score -= 1.5
			if SIDE_WORDS.has(t):
				any_desc = true
				score += 2.0 if String(en["bearing"]).contains(String(SIDE_WORDS[t])) else -1.0
			if t in ["stunned", "fleeing", "enraged", "wounded", "hurt", "dying"]:
				any_desc = true
				if t in ["wounded", "hurt", "dying"]:
					score += (100.0 - float(en["hp_pct"])) / 40.0
				elif String(en["state"]).contains(t):
					score += 3.0
		if ref_node != null and is_instance_valid(ref_node):
			any_desc = true
			if ref_mode == "targeting":
				var tn: String = String(en["targeting"]).to_lower()
				var rn: String = "player" if ref_node is PlayerController else String(ref_node.call("get_display_name")).to_lower()
				score += 4.0 if tn == rn else -2.0
			else:
				score -= en_node.global_position.distance_to(ref_node.global_position) * 0.25
		# Superlatives / default ordering.
		var d: float = en_node.global_position.distance_to(origin)
		if s.contains("farthest") or s.contains("furthest") or s.contains("farther") or s.contains("further") or s.contains("distant"):
			score += d * 0.05
		elif s.contains("strongest") or s.contains("toughest") or s.contains("biggest"):
			score += float(en["hp"]) * 0.01
		elif s.contains("weakest") or s.contains("lowest"):
			score += (100.0 - float(en["hp_pct"])) * 0.03
		else:
			score -= d * 0.05
		if en_node.is_aggroed():
			score += 0.3
		if score > best_score:
			best_score = score
			best = en_node
```

- **Postcondition**: `WorldIntel.is_camera_visible()` exists and compiles cleanly, `node_for_id()` filters inactive/exited enemies, and `resolve()` never crashes on `asker == null` or freed/inactive cached entries.

---

### Step 2 — Fix `SquadCommandParser` Word Boundaries, Skill Match Boundaries & Addressee Verb Ordering (`ALY-16`, `ALY-17`, `ALY-18`)
- **Prerequisites**: Step 1 complete.
- **Note**: Apply Edits 2A–2D in order on `scripts/allies/squad_command_parser.gd`.

#### Edit 2A — Add `"shielded"` / `"archer"` Vocab Protection & `"shielded guard"` Target Mapping (`ALY-16`, `ALY-17`)
**Target:** `scripts/allies/squad_command_parser.gd`
**Action:** Replace block
**Find:**
```gdscript
	"phantom": "phantom", "ghost": "phantom", "twin": "phantom", "shield": "shield",
	"knight": "shield", "skeleton": "skeleton", "warden": "warden", "boss": "warden",
	"strongest": "strongest", "toughest": "strongest", "weakest": "weakest", "wounded": "weakest",
	"nearest": "nearest", "closest": "nearest", "that one": "nearest", "them": "nearest",
}


const DESCRIPTOR_WORDS: Array[String] = ["purple", "violet", "blue", "cyan", "green", "pale", "white", "bone", "gold", "golden",
	"steel", "silver", "red", "black", "dark", "glowing", "axe", "sword", "swords", "blades", "shield", "orb", "greataxe",
	"hooded", "armored", "armoured", "big", "huge", "giant", "small", "left", "right", "behind", "near", "closest to",
	"next to", "attacking", "hitting", "chasing", "targeting", "farthest", "furthest", "stunned", "fleeing", "farther", "further", "distant"]
```
**Replace with:**
```gdscript
	"phantom": "phantom", "ghost": "phantom", "twin": "phantom", "shielded guard": "shield", "shield": "shield",
	"knight": "shield", "skeleton": "skeleton", "warden": "warden", "boss": "warden",
	"strongest": "strongest", "toughest": "strongest", "weakest": "weakest", "wounded": "weakest",
	"nearest": "nearest", "closest": "nearest", "that one": "nearest", "them": "nearest",
}


const DESCRIPTOR_WORDS: Array[String] = ["purple", "violet", "blue", "cyan", "green", "pale", "white", "bone", "gold", "golden",
	"steel", "silver", "red", "black", "dark", "glowing", "axe", "sword", "swords", "blades", "shield", "shielded", "orb", "greataxe",
	"hooded", "armored", "armoured", "archer", "big", "huge", "giant", "small", "left", "right", "behind", "near", "closest to",
	"next to", "attacking", "hitting", "chasing", "targeting", "farthest", "furthest", "stunned", "fleeing", "farther", "further", "distant"]
```

#### Edit 2B — Use Word-Bounded `_find_rule_kw()` & Pass `ctx` into `_addressed()` (`ALY-16`, `ALY-18`)
**Target:** `scripts/allies/squad_command_parser.gd`
**Action:** Replace block
**Find:**
```gdscript
	if out.is_empty():
		var who: Array = _addressed(t.replace(" , ", " "), ally_names)
		# Talking to someone without an order is conversation, not confusion.
		if not who.is_empty() and not who.has("all"):
			out.append({"verb": "chat", "allies": who, "topic": "generic", "utterance": raw})
		else:
			out.append({"verb": "say", "allies": who, "text": "", "confused": true, "utterance": raw})
	return out


static func _says_rest(t: String) -> bool:
	for w in ["everyone else", "everybody else", "the rest", "rest of you", "the others", "others ", "other two", "you two", "anyone else"]:
		if t.contains(" " + w):
			return true
	return false


## True if the text holds an instruction (a verb rule, a skill / strategy name, or an enemy description).
static func _has_instruction(t: String, ctx: Dictionary) -> bool:
	var s: String = " " + t.replace(" , ", " ").strip_edges() + " "
	for rule in RULES:
		for kw in (rule[1] as Array):
			if s.contains(String(kw)):
				return true
	if not _match_skill(s, [], ctx).is_empty() or not SquadStrategies.match_text(s).is_empty():
		return true
	return false
```
**Replace with:**
```gdscript
	if out.is_empty():
		var who: Array = _addressed(t.replace(" , ", " "), ally_names, ctx)
		# Talking to someone without an order is conversation, not confusion.
		if not who.is_empty() and not who.has("all"):
			out.append({"verb": "chat", "allies": who, "topic": "generic", "utterance": raw})
		else:
			out.append({"verb": "say", "allies": who, "text": "", "confused": true, "utterance": raw})
	return out


static func _says_rest(t: String) -> bool:
	for w in ["everyone else", "everybody else", "the rest", "rest of you", "the others", "others ", "other two", "you two", "anyone else"]:
		if t.contains(" " + w):
			return true
	return false


## True if the text holds an instruction (a verb rule, a skill / strategy name, or an enemy description).
static func _has_instruction(t: String, ctx: Dictionary) -> bool:
	var s: String = " " + t.replace(" , ", " ").strip_edges() + " "
	for rule in RULES:
		var rverb: String = String(rule[0])
		for kw in (rule[1] as Array):
			if _find_rule_kw(s, rverb, String(kw)) >= 0:
				return true
	if not _match_skill(s, [], ctx).is_empty() or not SquadStrategies.match_text(s).is_empty():
		return true
	return false
```

#### Edit 2C — Update `_parse_clause()` Rule Loop, Add `_find_rule_kw()` Helpers, and Fix `_match_skill()` Trailing Boundary (`ALY-16`, `ALY-17`, `ALY-18`)
**Target:** `scripts/allies/squad_command_parser.gd`
**Action:** Replace block
**Find:**
```gdscript
static func _parse_clause(t: String, ally_names: Array, carry_allies: Array, ctx: Dictionary = {}) -> Dictionary:
	var allies: Array = _addressed(t, ally_names)
	if allies.is_empty() and not carry_allies.is_empty():
		allies = carry_allies
	var verb: String = ""
	for rule in RULES:
		for kw in (rule[1] as Array):
			if t.contains(String(kw)):
				verb = String(rule[0])
				break
		if not verb.is_empty():
			break
```
**Replace with:**
```gdscript
static func _parse_clause(t: String, ally_names: Array, carry_allies: Array, ctx: Dictionary = {}) -> Dictionary:
	var allies: Array = _addressed(t, ally_names, ctx)
	if allies.is_empty() and not carry_allies.is_empty():
		allies = carry_allies
	var verb: String = ""
	for rule in RULES:
		var rverb: String = String(rule[0])
		for kw in (rule[1] as Array):
			if _find_rule_kw(t, rverb, String(kw)) >= 0:
				verb = rverb
				break
		if not verb.is_empty():
			break
```

#### Edit 2D — Fix `_match_skill()` Space Padding & Add `_find_rule_kw()` Helpers (`ALY-16`, `ALY-17`)
**Target:** `scripts/allies/squad_command_parser.gd`
**Action:** Replace block
**Find:**
```gdscript
## Skill owned by an addressed ally (preferred) or anyone: {"ally", "id"} or {}.
static func _match_skill(t: String, allies: Array, ctx: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_len: int = 0
	for s in (ctx.get("skills", []) as Array):
		var sd: Dictionary = s as Dictionary
		var phrases: Array = (sd.get("aliases", []) as Array).duplicate()
		phrases.append(String(sd.get("name", "")).to_lower())
		for p in phrases:
			var ps: String = String(p)
			if ps.length() < 3 or not t.contains(" " + ps + " ") and not t.contains(" " + ps):
				continue
			var l: int = ps.length() + (100 if allies.has(String(sd["ally"])) else 0)
			if l > best_len:
				best_len = l
				best = {"ally": String(sd["ally"]), "id": String(sd["id"])}
	return best
```
**Replace with:**
```gdscript
## Word-bounded keyword search so "cast" never matches "caster"/"hexcaster" and "guard" never matches
## enemy names like "shielded guard" or "the guard".
static func _sanitize_rule_text(t: String) -> String:
	var s: String = t if t.begins_with(" ") and t.ends_with(" ") else " " + t + " "
	return s.replace(" shielded guard ", " shielded ").replace(" shield guard ", " shield ")


static func _find_rule_kw(t: String, verb: String, kw: String) -> int:
	var core: String = kw.strip_edges()
	if core.is_empty():
		return -1
	var src: String = _sanitize_rule_text(t) if (verb == "bodyguard" and core == "guard") else (t if t.begins_with(" ") and t.ends_with(" ") else " " + t + " ")
	if core.begins_with("'"):
		return src.find(core + " ")
	if verb == "bodyguard" and core == "guard":
		var idx: int = src.find(" guard ")
		while idx >= 0:
			var prefix: String = src.left(idx + 1)
			if not (prefix.ends_with(" the ") or prefix.ends_with(" a ") or prefix.ends_with(" that ") or prefix.ends_with(" this ")):
				return idx
			idx = src.find(" guard ", idx + 6)
		return -1
	var pos: int = src.find(" " + core + " ")
	if pos >= 0:
		return pos
	if verb == "emote":
		for suf in ["s ", "ed ", "ing "]:
			var ep: int = src.find(" " + core + suf)
			if ep >= 0:
				return ep
	return -1


## Skill owned by an addressed ally (preferred) or anyone: {"ally", "id"} or {}.
static func _match_skill(t: String, allies: Array, ctx: Dictionary) -> Dictionary:
	var pad: String = t if t.begins_with(" ") and t.ends_with(" ") else " " + t + " "
	var best: Dictionary = {}
	var best_len: int = 0
	for s in (ctx.get("skills", []) as Array):
		var sd: Dictionary = s as Dictionary
		var phrases: Array = (sd.get("aliases", []) as Array).duplicate()
		phrases.append(String(sd.get("name", "")).to_lower())
		for p in phrases:
			var ps: String = String(p).strip_edges().to_lower()
			if ps.length() < 3 or not pad.contains(" " + ps + " "):
				continue
			var l: int = ps.length() + (100 if allies.has(String(sd["ally"])) else 0)
			if l > best_len:
				best_len = l
				best = {"ally": String(sd["ally"]), "id": String(sd["id"])}
	return best
```

#### Edit 2E — Include Skill & Strategy Phrases in `_addressed()` `first_verb_pos` (`ALY-18`)
**Target:** `scripts/allies/squad_command_parser.gd`
**Action:** Replace block
**Find:**
```gdscript
static func _addressed(t: String, ally_names: Array) -> Array:
	var out: Array = []
	if t.contains("everyone") or t.contains("everybody") or t.contains(" all ") or t.contains("squad") or t.contains(" team") or t.contains("you guys") or t.contains("y'all"):
		return ["all"]
	# Names addressed at the start of the clause (or "X and Y ...") count as the recipients; a name later in
	# the sentence is usually an object ("guard Ivo"), handled by _named_other.
	var first_verb_pos: int = t.length()
	for rule in RULES:
		for kw in (rule[1] as Array):
			var p: int = t.find(String(kw))
			if p >= 0 and p < first_verb_pos:
				first_verb_pos = p
	for n in ally_names:
		var ln: String = String(n).to_lower()
		var p2: int = t.find(" " + ln + " ")
		if p2 < 0:
			p2 = t.find(" " + ln)
		if p2 >= 0 and p2 < first_verb_pos:
			out.append(String(n))
	return out
```
**Replace with:**
```gdscript
static func _addressed(t: String, ally_names: Array, ctx: Dictionary = {}) -> Array:
	var pad: String = t if t.begins_with(" ") and t.ends_with(" ") else " " + t + " "
	var out: Array = []
	if pad.contains(" everyone ") or pad.contains(" everybody ") or pad.contains(" all ") or pad.contains(" squad ") or pad.contains(" team ") or pad.contains(" you guys ") or pad.contains(" y'all "):
		return ["all"]
	# Names addressed at the start of the clause (or "X and Y ...") count as the recipients; a name later in
	# the sentence is usually an object ("guard Ivo" / "ward Brannoc"), handled by _named_other.
	var first_verb_pos: int = pad.length()
	for rule in RULES:
		var rverb: String = String(rule[0])
		for kw in (rule[1] as Array):
			var p: int = _find_rule_kw(pad, rverb, String(kw))
			if p >= 0 and p < first_verb_pos:
				first_verb_pos = p
	for s in (ctx.get("skills", []) as Array):
		var sd: Dictionary = s as Dictionary
		var phrases: Array = (sd.get("aliases", []) as Array).duplicate()
		phrases.append(String(sd.get("name", "")).to_lower())
		for ph in phrases:
			var ps: String = String(ph).strip_edges().to_lower()
			if ps.length() >= 3:
				var sp: int = pad.find(" " + ps + " ")
				if sp >= 0 and sp < first_verb_pos:
					first_verb_pos = sp
	for st in SquadStrategies.LIST:
		for al in ((st as Dictionary).get("aliases", []) as Array):
			var als: String = String(al).strip_edges().to_lower()
			if not als.is_empty():
				var ap: int = pad.find(" " + als + " ")
				if ap >= 0 and ap < first_verb_pos:
					first_verb_pos = ap
	for n in ally_names:
		var ln: String = String(n).to_lower()
		var p2: int = pad.find(" " + ln + " ")
		if p2 >= 0 and p2 < first_verb_pos:
			out.append(String(n))
	return out
```

- **Postcondition**: `"kill the hexcaster"` -> `attack`, `"kill the shielded guard"` -> `attack`, `"attack the warden"` / `"check health"` / `"shoot the archer"` do not trigger skills, and `"Ivo, ward Brannoc"` assigns `allies = ["Ivo"]`, `target = "Brannoc"`, while all existing `tests/squad_ai_unit_test.gd` assertions remain valid.

---

### Step 3 — Fix `SquadAlly` Lifecycle, Mask, Effect Abort, Lurer, Downed Rescue & Catch-Up (`ALY-02`, `ALY-03`, `ALY-04`, `ALY-05`, `ALY-06`, `ALY-10`, `REQ-16`)
- **Prerequisites**: Steps 1–2 complete.
- **Ownership Guard**: Do **NOT** modify lines `:182`, `:1222`, `:1223`, `:1694`, or `:1759` (`GameFeelScript.play_sound()` calls).
- **Note**: Apply Edits 3A–3H in order on `scripts/allies/squad_ally.gd`.

#### Edit 3A — Add Safe Floor Tracking Fields & Keep Both Realm Layers When Downed (`ALY-04`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
var _dash_hit_cb: Callable = Callable()
var _dash_target: EnemyAI = null
var _regen_acc: float = 0.0
```
**Replace with:**
```gdscript
var _dash_hit_cb: Callable = Callable()
var _dash_target: EnemyAI = null
var _regen_acc: float = 0.0
var _last_safe_pos: Vector3 = Vector3.ZERO
var _has_safe_pos: bool = false
```

**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func _sync_realm_mask() -> void:
	var rm: RealmManager = RealmManager.instance as RealmManager
	var world: int = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY
	if rm != null:
		world = rm.get_realm_world_mask(rm.current_realm)
	collision_mask = world | RealmManager.LAYER_PLAYER_BLOCKER
```
**Replace with:**
```gdscript
func _sync_realm_mask() -> void:
	var rm: RealmManager = RealmManager.instance as RealmManager
	var world: int = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY
	if rm != null:
		world = rm.get_realm_world_mask(rm.current_realm)
	# A downed ally must never lose the floor beneath them when the player shifts realms (Q).
	if is_downed:
		world |= RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR
	collision_mask = world | RealmManager.LAYER_PLAYER_BLOCKER
```

#### Edit 3B — Preserve Rally Flag in `assign()` & Cancel All Active Effects/Charges/Tilts in `_abort_current_effects()` (`ALY-06`, `ALY-10`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	# Combo halves keep handshake data the manager may already have posted while they were queued.
	if cmd.combo_id == 0:
		current.data = {}
	_engage_target = null
	command_started.emit(self, cmd)
```
**Replace with:**
```gdscript
	# Combo halves keep handshake data the manager may already have posted while they were queued.
	if cmd.combo_id == 0:
		var keep_rally: bool = bool(current.data.get("rally", false)) or bool(current.args.get("rally", false))
		current.data = {}
		if keep_rally:
			current.data["rally"] = true
	_engage_target = null
	command_started.emit(self, cmd)
```

**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func _abort_current_effects() -> void:
	_hide_cast_ring()
	if _action == "channel" or _action == "revive" or _action == "dance" or _action == "emote":
		_action = ""
		_action_timer = 0.0
```
**Replace with:**
```gdscript
func _abort_current_effects() -> void:
	_hide_cast_ring()
	if not _action.is_empty():
		_action = ""
		_action_timer = 0.0
		_action_hit_at = -1.0
		_action_cb = Callable()
		_action_dur = 0.0
	if _dash_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
	_dash_timer = 0.0
	_dash_vel = Vector3.ZERO
	_dash_hit_cb = Callable()
	_dash_target = null
	var vis: Node3D = get_node_or_null("VisualRoot") as Node3D
	if vis != null:
		vis.rotation.x = 0.0
		vis.rotation.y = atan2(-facing_direction.x, -facing_direction.z) - rotation.y
```

#### Edit 3C — Track Safe Floor Position in `_physics_process()` (`ALY-04`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func _physics_process(delta: float) -> void:
	if profile == null or not is_inside_tree():
		return
	_tick_timers(delta)
	if is_downed:
		_process_downed(delta)
		return
	_regen(delta)
```
**Replace with:**
```gdscript
func _physics_process(delta: float) -> void:
	if profile == null or not is_inside_tree():
		return
	_tick_timers(delta)
	if is_downed:
		_process_downed(delta)
		return
	if is_on_floor() and not _in_pit_kill_zone():
		_last_safe_pos = global_position
		_has_safe_pos = true
	_regen(delta)
```

#### Edit 3D — Add `clear_mine()` Cleanup Helper (`ALY-02`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block *(stops before `_aoe_blast()` so `:1222`/`:1223` remain untouched)*
**Find:**
```gdscript
func get_mine_position() -> Vector3:
	return _mine.global_position if _mine != null and is_instance_valid(_mine) else Vector3.INF


func detonate_mine() -> int:
	if _mine == null or not is_instance_valid(_mine):
		return 0
	var at: Vector3 = _mine.global_position
	_mine.queue_free()
	_mine = null
	_play(["Spellcast_Shoot", "Spellcasting"], 0.4, true)
	return _aoe_blast(at, 3.4, maxi(profile.nuke_damage, 40) + 10, "ally_detonate", Color(0.85, 0.45, 1.0))
```
**Replace with:**
```gdscript
func clear_mine() -> void:
	if _mine != null and is_instance_valid(_mine):
		_mine.queue_free()
	_mine = null


func get_mine_position() -> Vector3:
	return _mine.global_position if _mine != null and is_instance_valid(_mine) else Vector3.INF


func detonate_mine() -> int:
	if _mine == null or not is_instance_valid(_mine):
		return 0
	var at: Vector3 = _mine.global_position
	clear_mine()
	_play(["Spellcast_Shoot", "Spellcasting"], 0.4, true)
	return _aoe_blast(at, 3.4, maxi(profile.nuke_damage, 40) + 10, "ally_detonate", Color(0.85, 0.45, 1.0))
```

#### Edit 3E — Handle `"fallback"` & `cmd.data["done"]` in `_run_lurer()` (`ALY-03`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func _run_lurer(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if not cmd.data.has("point"):
		# Wait for the sigil.
		cmd.step = "waiting"
		var ps: Vector3 = player.global_position if player != null else global_position
		if global_position.distance_to(ps) > 3.0:
			_move_to(ps, profile.move_speed, delta)
		else:
			_halt(delta)
		return
	var p: Vector3 = cmd.data["point"]
	if cmd.step == "waiting" or cmd.step.is_empty():
		cmd.step = "approach"
	if cmd.step == "approach" or cmd.step == "provoke" or cmd.step == "confirm":
		_kite_logic(delta, player, cmd, false)
		if cmd.step == "sustain":
			cmd.step = "luring"
		return
	if cmd.step == "luring":
		# Run through the sigil to its far side; the chasers follow straight across it.
		var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
		var from: Vector3 = e.global_position if e != null and _enemy_ok(e) else global_position
		var through: Vector3 = p - from
		through.y = 0.0
		var goal: Vector3 = p + (through.normalized() if through.length_squared() > 0.01 else Vector3.BACK) * 4.5
		if global_position.distance_to(goal) > 1.0:
			_move_to(goal, profile.move_speed * 1.05, delta)
		else:
			_halt(delta)
			if e != null:
				set_facing(e.global_position - global_position)
		if bool(cmd.data.get("done", false)):
			finish_current("lured")
```
**Replace with:**
```gdscript
func _run_lurer(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if bool(cmd.data.get("done", false)):
		finish_current("lured")
		return
	if not cmd.data.has("point"):
		# Wait for the sigil.
		cmd.step = "waiting"
		var ps: Vector3 = player.global_position if player != null else global_position
		if global_position.distance_to(ps) > 3.0:
			_move_to(ps, profile.move_speed, delta)
		else:
			_halt(delta)
		return
	var p: Vector3 = cmd.data["point"]
	if cmd.step == "waiting" or cmd.step.is_empty():
		cmd.step = "approach"
	if cmd.step == "approach" or cmd.step == "provoke" or cmd.step == "confirm" or cmd.step == "fallback":
		_kite_logic(delta, player, cmd, false)
		if cmd.step == "sustain":
			cmd.step = "luring"
		return
	if cmd.step == "luring":
		# Run through the sigil to its far side; the chasers follow straight across it.
		var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
		var from: Vector3 = e.global_position if e != null and _enemy_ok(e) else global_position
		var through: Vector3 = p - from
		through.y = 0.0
		var goal: Vector3 = p + (through.normalized() if through.length_squared() > 0.01 else Vector3.BACK) * 4.5
		if global_position.distance_to(goal) > 1.0:
			_move_to(goal, profile.move_speed * 1.05, delta)
		else:
			_halt(delta)
			if e != null:
				set_facing(e.global_position - global_position)
```

#### Edit 3F — Add Unreachable Timeout to `_revive_target()` (`ALY-04`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func _revive_target(who: SquadAlly, delta: float, cmd: SquadCommand) -> void:
	if global_position.distance_to(who.global_position) > 1.6:
		cmd.step = "moving"
		_move_to(who.global_position, profile.move_speed * 1.2, delta)
		return
	if cmd.step != "channel":
		cmd.step = "channel"
		say_event("revive_other", 2)
		set_facing(who.global_position - global_position)
		_play(["Interact", "PickUp", "Use_Item"], REVIVE_CHANNEL, true)
		_start_action("revive", REVIVE_CHANNEL, REVIVE_CHANNEL - 0.05, func() -> void:
			if is_instance_valid(who) and who.is_downed:
				who.revive(0.45)
			if current == cmd and cmd.verb == "revive":
				finish_current("revived")
		)
```
**Replace with:**
```gdscript
func _revive_target(who: SquadAlly, delta: float, cmd: SquadCommand) -> void:
	if who == null or not is_instance_valid(who) or not who.is_downed:
		finish_current("nobody down")
		return
	if global_position.distance_to(who.global_position) > 1.6:
		if cmd.step != "channel" and cmd.timer > 10.0:
			say("Can't reach %s." % who.get_display_name(), "refuse", 1)
			finish_current("unreachable")
			return
		cmd.step = "moving"
		_move_to(who.global_position, profile.move_speed * 1.2, delta)
		return
	if cmd.step != "channel":
		cmd.step = "channel"
		say_event("revive_other", 2)
		set_facing(who.global_position - global_position)
		_play(["Interact", "PickUp", "Use_Item"], REVIVE_CHANNEL, true)
		_start_action("revive", REVIVE_CHANNEL, REVIVE_CHANNEL - 0.05, func() -> void:
			if is_instance_valid(who) and who.is_downed:
				who.revive(0.45)
			if current == cmd and cmd.verb == "revive":
				finish_current("revived")
		)
	elif _action != "revive" and cmd.timer > 14.0:
		finish_current("revive timed out")
```

#### Edit 3G — Cleanup Mine + Keep Realm Floor + Rescue Downed Ally From Pits/Void (`ALY-02`, `ALY-04`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func _go_down() -> void:
	is_downed = true
	_retreating = false
	_action = ""
	_dash_timer = 0.0
	_hide_cast_ring()
	velocity = Vector3.ZERO
	_play(["Death_A", "Death_B"], -1.0, true)
	say_event("downed", 3)
	add_to_group("interactable_switch")
	downed.emit(self)
	_refresh_label()


func revive(ratio: float = 0.45) -> void:
	if not is_downed:
		return
	is_downed = false
	health = maxi(1, int(round(float(max_health) * clampf(ratio, 0.05, 1.0))))
	_low_hp_warned = false
	remove_from_group("interactable_switch")
	if _player_near_prompt:
		_player_near_prompt = false
		prompt_changed.emit(false, "")
	_play(["Lie_StandUp", "Idle"], 0.7, true)
	_start_action("emote", 0.7, -1.0, Callable())
	GoreFXScript.flash_light(self, global_position + Vector3.UP, Color(1.0, 0.9, 0.5), 4.0, 0.4, 4.0)
	say_event("revived", 2)
	health_changed.emit(self, health, max_health)
	revived.emit(self)


## Manual revive: the player presses Interact next to a downed ally (PlayerController.try_interact scans
## the `interactable_switch` group within 2.6 m).
func interact() -> bool:
	if not is_downed:
		return false
	revive(0.5)
	return true


func _process_downed(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity_and_move(delta)
	_update_revive_prompt()
```
**Replace with:**
```gdscript
func _go_down() -> void:
	is_downed = true
	_retreating = false
	_action = ""
	_action_timer = 0.0
	_action_hit_at = -1.0
	_action_cb = Callable()
	_dash_timer = 0.0
	_dash_vel = Vector3.ZERO
	_dash_hit_cb = Callable()
	_dash_target = null
	_hide_cast_ring()
	clear_mine()
	_sync_realm_mask()
	velocity = Vector3.ZERO
	_play(["Death_A", "Death_B"], -1.0, true)
	say_event("downed", 3)
	add_to_group("interactable_switch")
	downed.emit(self)
	_refresh_label()


func revive(ratio: float = 0.45) -> void:
	if not is_downed:
		return
	is_downed = false
	_sync_realm_mask()
	health = maxi(1, int(round(float(max_health) * clampf(ratio, 0.05, 1.0))))
	_low_hp_warned = false
	remove_from_group("interactable_switch")
	if _player_near_prompt:
		_player_near_prompt = false
		prompt_changed.emit(false, "")
	_play(["Lie_StandUp", "Idle"], 0.7, true)
	_start_action("emote", 0.7, -1.0, Callable())
	GoreFXScript.flash_light(self, global_position + Vector3.UP, Color(1.0, 0.9, 0.5), 4.0, 0.4, 4.0)
	say_event("revived", 2)
	health_changed.emit(self, health, max_health)
	revived.emit(self)


## Manual revive: the player presses Interact next to a downed ally (PlayerController.try_interact scans
## the `interactable_switch` group within 2.6 m).
func interact() -> bool:
	if not is_downed:
		return false
	revive(0.5)
	return true


func _in_pit_kill_zone() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	for z in get_tree().get_nodes_in_group("pit_kill_zone"):
		if z != null and z.has_method("is_point_inside_zone") and bool(z.call("is_point_inside_zone", global_position)):
			return true
	return false


func _process_downed(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity_and_move(delta)
	var pl: Node3D = _player()
	var pit_or_void: bool = _in_pit_kill_zone() or global_position.y < -20.0
	var far_or_below: bool = false
	if pl != null and is_instance_valid(pl):
		if global_position.y < pl.global_position.y - 6.0 or global_position.distance_to(pl.global_position) > 35.0:
			far_or_below = true
	if pit_or_void or far_or_below:
		if pl != null and is_instance_valid(pl):
			if not (pl is PlayerController and (pl as PlayerController).is_currently_airborne()):
				_blink_to(pl)
			elif pit_or_void or global_position.y < pl.global_position.y - 6.0:
				if _has_safe_pos:
					global_position = _last_safe_pos + Vector3.UP * 0.05
					_last_pos = global_position
				velocity = Vector3.ZERO
		elif _has_safe_pos:
			global_position = _last_safe_pos + Vector3.UP * 0.05
			_last_pos = global_position
			velocity = Vector3.ZERO
		else:
			velocity.y = 0.0
	_update_revive_prompt()
```

**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func reset_full(at: Vector3) -> void:
	is_downed = false
	remove_from_group("interactable_switch")
	health = max_health
	_retreating = false
	_action = ""
	_dash_timer = 0.0
	_engage_target = null
	_hide_cast_ring()
	if _mine != null and is_instance_valid(_mine):
		_mine.queue_free()
	_mine = null
	current = null
	queue.clear()
	global_position = at
	velocity = Vector3.ZERO
	_last_pos = at
	health_changed.emit(self, health, max_health)
	_refresh_label()
```
**Replace with:**
```gdscript
func reset_full(at: Vector3) -> void:
	is_downed = false
	_sync_realm_mask()
	remove_from_group("interactable_switch")
	health = max_health
	_retreating = false
	_action = ""
	_action_timer = 0.0
	_action_hit_at = -1.0
	_action_cb = Callable()
	_dash_timer = 0.0
	_dash_vel = Vector3.ZERO
	_dash_hit_cb = Callable()
	_dash_target = null
	_engage_target = null
	_hide_cast_ring()
	clear_mine()
	current = null
	queue.clear()
	global_position = at
	velocity = Vector3.ZERO
	_last_pos = at
	_last_safe_pos = at
	_has_safe_pos = true
	health_changed.emit(self, health, max_health)
	_refresh_label()
```

#### Edit 3H — Fix `_catch_up()` World LOS Mask, Pit Rescue, & Preserve `REQ-16` 150 m Distant-Order Exemption (`ALY-04`, `ALY-05`, `REQ-16`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func _update_stuck(delta: float) -> void:
	var moved: float = Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	var wants: bool = Vector2(velocity.x, velocity.z).length() > 1.0
	_last_pos = global_position
	if wants and moved < 0.6 * delta:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)
	if _stuck_timer > 2.0:
		_stuck_timer = 0.0
		var p: Node3D = _player()
		if p != null and global_position.distance_to(p.global_position) > 6.0:
			_blink_to(p)


## Catch-up: allies are mirror echoes — when hopelessly far, fallen, or left behind a jump, they blink
## to a free spot behind the player (with a spectral flash) instead of path-finding across chasms.
func _catch_up(player: Node3D) -> void:
	var d: Vector3 = player.global_position - global_position
	var far: float = 30.0 if (current != null and current.is_mission()) else 20.0
	var needs_catchup: bool = (d.length() > far or (d.y > 3.0 and Vector2(d.x, d.z).length() < 10.0) or global_position.y < player.global_position.y - 6.0)
	if not needs_catchup:
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.is_position_in_frustum(global_position):
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, global_position + Vector3.UP * 0.9, 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty() and d.length() < 40.0:
				return
	if player is PlayerController and (player as PlayerController).is_currently_airborne():
		return
	_blink_to(player)


func _blink_to(player: Node3D) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var base: Vector3 = _formation_point(player)
	var tries: Array[Vector3] = [base, player.global_position - (player.call("get_facing_direction") as Vector3) * 1.5, player.global_position]
	for t in tries:
		var q := PhysicsRayQueryParameters3D.create(t + Vector3.UP * 1.5, t + Vector3.DOWN * 3.0, collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER, [get_rid()])
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			GoreFXScript.flash_light(self, global_position + Vector3.UP, profile.color, 2.5, 0.25, 3.0)
			global_position = (hit["position"] as Vector3) + Vector3.UP * 0.05
			velocity = Vector3.ZERO
			_last_pos = global_position
			GoreFXScript.flash_light(self, global_position + Vector3.UP, profile.color, 3.0, 0.3, 3.0)
			return
```
**Replace with:**
```gdscript
func _has_distant_order() -> bool:
	if current == null or current.done:
		return false
	return current.verb in [
		"attack", "taunt", "hit_and_run", "surround", "ranged",
		"kite", "nuke", "peel", "ambush",
		"combo_kite_nuke", "combo_charge_finish", "combo_lure_detonate",
		"hunt", "destroy", "interact",
	]


func _distant_order_cam_visible() -> bool:
	if current == null or manager == null:
		return false
	var intel_node: WorldIntel = manager.get("intel") as WorldIntel
	if intel_node == null:
		return false
	var en: EnemyAI = current.data.get("enemy", null) as EnemyAI
	return en != null and intel_node.is_camera_visible(en)


func _update_stuck(delta: float) -> void:
	var moved: float = Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	var wants: bool = Vector2(velocity.x, velocity.z).length() > 1.0
	_last_pos = global_position
	if wants and moved < 0.6 * delta:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)
	if _stuck_timer > 2.0:
		_stuck_timer = 0.0
		var p: Node3D = _player()
		if p == null:
			return
		if _has_distant_order() or _distant_order_cam_visible():
			_steer_dir = Vector3.ZERO
			_steer_timer = 0.0
			if is_on_floor():
				velocity.y = 4.5
			if global_position.distance_to(p.global_position) > 150.0 or global_position.y < p.global_position.y - 6.0 or _in_pit_kill_zone():
				_blink_to(p)
		elif global_position.distance_to(p.global_position) > 6.0:
			_blink_to(p)


## Catch-up: allies are mirror echoes — when hopelessly far, fallen, or left behind a jump, they blink
## to a free spot behind the player (with a spectral flash) instead of path-finding across chasms.
func _catch_up(player: Node3D) -> void:
	var d: Vector3 = player.global_position - global_position
	var distant_exempt: bool = _has_distant_order() or _distant_order_cam_visible()
	var far: float = 150.0 if distant_exempt else (30.0 if (current != null and current.is_mission()) else FOLLOW_LEASH)
	var fallen_pit: bool = _in_pit_kill_zone() or global_position.y < player.global_position.y - 6.0 or global_position.y < -20.0
	var vertical_trap: bool = not distant_exempt and d.y > 3.0 and Vector2(d.x, d.z).length() < 10.0
	if not (d.length() > far or vertical_trap or fallen_pit):
		return
	if not fallen_pit:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null and cam.is_position_in_frustum(global_position):
			var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
			if space != null:
				var los_mask: int = collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER
				var excl: Array[RID] = [get_rid()]
				if player is CollisionObject3D:
					excl.append((player as CollisionObject3D).get_rid())
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, global_position + Vector3.UP * 0.9, los_mask, excl)
				var hit: Dictionary = space.intersect_ray(q)
				if hit.is_empty() and d.length() < (150.0 if distant_exempt else 40.0):
					return
	if player is PlayerController and (player as PlayerController).is_currently_airborne():
		if fallen_pit and _has_safe_pos:
			global_position = _last_safe_pos + Vector3.UP * 0.05
			velocity = Vector3.ZERO
			_last_pos = global_position
		return
	_blink_to(player)


func _blink_to(player: Node3D) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return
	var base: Vector3 = _formation_point(player)
	var pf: Vector3 = (player.call("get_facing_direction") as Vector3) if player.has_method("get_facing_direction") else Vector3.FORWARD
	var tries: Array[Vector3] = [base, player.global_position - pf * 1.5, player.global_position]
	for t in tries:
		var q := PhysicsRayQueryParameters3D.create(t + Vector3.UP * 1.5, t + Vector3.DOWN * 3.0, collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER, [get_rid()])
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			GoreFXScript.flash_light(self, global_position + Vector3.UP, profile.color, 2.5, 0.25, 3.0)
			global_position = (hit["position"] as Vector3) + Vector3.UP * 0.05
			velocity = Vector3.ZERO
			_last_pos = global_position
			GoreFXScript.flash_light(self, global_position + Vector3.UP, profile.color, 3.0, 0.3, 3.0)
			return
```

- **Postcondition**: Downed allies keep both Realm floor layers and rescue cleanly from chasms/void; `_run_lurer()` handles `"fallback"` and early `"done"`; `_abort_current_effects()` cancels all active attacks/spins/flips/dashes; `_catch_up()` checks world-layer occlusion (blinking wall-occluded allies) while keeping `REQ-16`'s `150.0 m` distant-order exemption.

---

### Step 4 — Fix `SquadAlly` Combat, Taunts, Dead-Player Guards, Ranged/Spot Oscillation, Skill Validation, Left/Right, Chain Arc & Destroy Height (`ALY-11`, `ALY-12`, `ALY-13`, `ALY-14`, `ALY-15`, `ALY-23`, `ALY-24`, `REQ-20`)
- **Prerequisites**: Step 3 complete.
- **Ownership Guard**: Do **NOT** touch lines `:182`, `:1222`, `:1223`, `:1694`, or `:1759` (`GameFeelScript.play_sound()` calls).
- **Note**: Apply Edits 4A–4K in order on `scripts/allies/squad_ally.gd`.

#### Edit 4A — Anchor Artillery Defense in `_run_hold()` & `_run_retreat_order()` (`ALY-13`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	var near: EnemyAI = _nearest_enemy(global_position, float(cmd.args.get("engage_r", 3.5)))
	if near != null:
		_fight(near, delta)
		return
	if global_position.distance_to(spot) > 0.8:
		_move_to(spot, profile.move_speed, delta)
	else:
		cmd.data["arrived"] = true
		_halt(delta)


func _run_retreat_order(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if player == null:
		_halt(delta)
		return
	cmd.step = "falling back"
	var centroid: Vector3 = _threat_centroid(player.global_position, 15.0)
	var away: Vector3 = (player.global_position - centroid) if centroid != Vector3.INF else -(player.call("get_facing_direction") as Vector3)
	away.y = 0.0
	var goal: Vector3 = player.global_position + away.normalized() * 3.5 + Vector3(-away.z, 0, away.x).normalized() * (float(slot_index) - 1.0) * 1.6
	if global_position.distance_to(goal) > 0.8:
		_move_to(goal, profile.move_speed * 1.15, delta)
	else:
		cmd.data["arrived"] = true
		_halt(delta)
		var self_threat: EnemyAI = _nearest_enemy(global_position, 2.2)
		if self_threat != null:
			_fight(self_threat, delta)
```
**Replace with:**
```gdscript
	var near: EnemyAI = _nearest_enemy(global_position, float(cmd.args.get("engage_r", 3.5)))
	if near != null:
		_fight(near, delta, true)
		return
	if global_position.distance_to(spot) > 0.8:
		_move_to(spot, profile.move_speed, delta)
	else:
		cmd.data["arrived"] = true
		_halt(delta)


func _run_retreat_order(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if player == null:
		_halt(delta)
		return
	cmd.step = "falling back"
	var centroid: Vector3 = _threat_centroid(player.global_position, 15.0)
	var away: Vector3 = (player.global_position - centroid) if centroid != Vector3.INF else -(player.call("get_facing_direction") as Vector3)
	away.y = 0.0
	var goal: Vector3 = player.global_position + away.normalized() * 3.5 + Vector3(-away.z, 0, away.x).normalized() * (float(slot_index) - 1.0) * 1.6
	if global_position.distance_to(goal) > 0.8:
		_move_to(goal, profile.move_speed * 1.15, delta)
	else:
		cmd.data["arrived"] = true
		var self_threat: EnemyAI = _nearest_enemy(global_position, 2.2)
		if self_threat != null:
			_fight(self_threat, delta, true)
		else:
			_halt(delta)
```

#### Edit 4B — Fix `_run_taunt_cmd()` Area Fallback & Single-Target Validity + Timeouts (`ALY-11`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func _run_taunt_cmd(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	# "Take aggro": pull every enemy currently on the player onto this ally (single-enemy taunts never
	# touch the rest of a group).
	if bool(cmd.args.get("area", false)) and player != null:
		var on_player: Array[EnemyAI] = []
		for en in _active_enemies(player.global_position, 10.0):
			if en.get_current_target() == player:
				on_player.append(en)
		if on_player.is_empty():
			say("Nothing's on you right now.", "refuse", 1)
			finish_current("nothing on player")
			return
		if global_position.distance_to(player.global_position) > 5.0:
			_move_to(player.global_position, profile.move_speed * 1.2, delta)
			return
		_taunt_cd = profile.taunt_cooldown
		_play(["Taunt", "Cheer", "Taunt_Longer"], 0.8, true)
		_start_action("taunt", 0.55, -1.0, Callable())
		say_event("taunt", 1)
		for en in on_player:
			en.apply_taunt(self, -1.0, 4.0)
		finish_current("took aggro x%d" % on_player.size())
		return
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null:
		e = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
		if e == null:
			say("Nothing to taunt.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
	if global_position.distance_to(e.global_position) > 7.0:
		_move_to(e.global_position, profile.move_speed, delta)
		return
	_do_taunt(e, false)
	finish_current("taunted")
```
**Replace with:**
```gdscript
func _run_taunt_cmd(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	# "Take aggro": prefer enemies currently on the player, falling back to idle/ally-targeting foes nearby.
	if bool(cmd.args.get("area", false)) and player != null:
		var targets: Array[EnemyAI] = []
		var near_pool: Array[EnemyAI] = _active_enemies(player.global_position, 14.0)
		for en in near_pool:
			if en.get_current_target() == player:
				targets.append(en)
		if targets.is_empty():
			targets = near_pool
		if targets.is_empty():
			targets = _active_enemies(global_position, 14.0)
		if targets.is_empty():
			var fallback: EnemyAI = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
			if fallback != null and _enemy_ok(fallback):
				cmd.args["area"] = false
				cmd.data["enemy"] = fallback
			else:
				say("Nothing around to taunt.", "refuse", 1)
				finish_current("no target")
				return
		else:
			var anchor: Vector3 = player.global_position if not near_pool.is_empty() else targets[0].global_position
			var reach: float = 5.0 if not near_pool.is_empty() else 7.0
			if global_position.distance_to(anchor) > reach:
				if cmd.timer > 10.0:
					say("Can't reach them to take aggro.", "refuse", 1)
					finish_current("out of range")
					return
				_move_to(anchor, profile.move_speed * 1.2, delta)
				return
			_taunt_cd = profile.taunt_cooldown
			_play(["Taunt", "Cheer", "Taunt_Longer"], 0.8, true)
			_start_action("taunt", 0.55, -1.0, Callable())
			say_event("taunt", 1)
			for en in targets:
				if _enemy_ok(en):
					en.apply_taunt(self, -1.0, 4.0)
			finish_current("took aggro x%d" % targets.size())
			return
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		if cmd.data.has("enemy"):
			finish_current("target gone")
			return
		e = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
		if e == null or not _enemy_ok(e):
			say("Nothing to taunt.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
	if global_position.distance_to(e.global_position) > 7.0:
		if cmd.timer > 12.0:
			say("Can't get close enough to taunt.", "refuse", 1)
			finish_current("out of range")
			return
		_move_to(e.global_position, profile.move_speed * 1.15, delta)
		return
	_do_taunt(e, false)
	if String(cmd.args.get("lure", "")) == "player":
		cmd.verb = "kite"
		cmd.step = "sustain"
		cmd.data["enemy"] = e
		cmd.data["sustain_t"] = 0.0
		cmd.data["center"] = e.global_position
		cmd.data["ang"] = atan2(global_position.z - e.global_position.z, global_position.x - e.global_position.x)
		return
	finish_current("taunted")
```

#### Edit 4C — Reject Dead `PlayerController` in `_skill_mend()` & `_skill_ward()` (`ALY-12`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block *(starts at line 1763, well clear of `:1759`)*
**Find:**
```gdscript
	elif target is PlayerController:
		var p: PlayerController = target as PlayerController
		if p.health >= p.max_health:
			return false
		p.health = mini(p.max_health, p.health + int(round(float(p.max_health) * s.power)))
		p.health_changed.emit(p.health, p.max_health)
	else:
		return false
	set_facing(target.global_position - global_position)
	_play(["Spellcast_Raise", "Spellcasting"], 0.6, true)
	_start_action("emote", 0.6, -1.0, Callable())
	GoreFXScript.flash_light(self, target.global_position + Vector3.UP, s.color, 4.0, 0.5, 4.0)
	GoreFXScript.dust_puff(self, target.global_position, 0.6, 18, Color(s.color.r, s.color.g, s.color.b, 0.6), 1.8)
	return true


func _skill_ward(s: AllySkill, target: Node3D) -> bool:
	if target == null:
		target = _most_pressed_friend(s.cast_range)
	if target == null or target.global_position.distance_to(global_position) > s.cast_range:
		return false
	if target is SquadAlly:
		if (target as SquadAlly).is_downed:
			return false
		(target as SquadAlly).add_ward(s.power, s.duration)
	elif target is PlayerController:
		(target as PlayerController).add_ally_ward(int(s.power), s.duration)
	else:
		return false
```
**Replace with:**
```gdscript
	elif target is PlayerController:
		var p: PlayerController = target as PlayerController
		if p.current_state == PlayerController.State.DEAD or p.health >= p.max_health:
			return false
		p.health = mini(p.max_health, p.health + int(round(float(p.max_health) * s.power)))
		p.health_changed.emit(p.health, p.max_health)
	else:
		return false
	set_facing(target.global_position - global_position)
	_play(["Spellcast_Raise", "Spellcasting"], 0.6, true)
	_start_action("emote", 0.6, -1.0, Callable())
	GoreFXScript.flash_light(self, target.global_position + Vector3.UP, s.color, 4.0, 0.5, 4.0)
	GoreFXScript.dust_puff(self, target.global_position, 0.6, 18, Color(s.color.r, s.color.g, s.color.b, 0.6), 1.8)
	return true


func _skill_ward(s: AllySkill, target: Node3D) -> bool:
	if target == null:
		target = _most_pressed_friend(s.cast_range)
	if target == null or target.global_position.distance_to(global_position) > s.cast_range:
		return false
	if target is SquadAlly:
		if (target as SquadAlly).is_downed:
			return false
		(target as SquadAlly).add_ward(s.power, s.duration)
	elif target is PlayerController:
		var pw: PlayerController = target as PlayerController
		if pw.current_state == PlayerController.State.DEAD:
			return false
		pw.add_ally_ward(int(s.power), s.duration)
	else:
		return false
```

#### Edit 4D — Gate `_chain_arc_hop()` Stun on `apply_damage()` Return Value & Continue Remaining Hops (`ALY-23`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	_launch_bolt(from, e, s.color, 26.0, 0.09, func() -> void:
		if not _enemy_ok(e):
			return
		e.apply_damage(int(round(s.power * mults[i] * (1.0 + _dmg_buff))), false, "ally_skill", self)
		if not e.knockdown_immune:
			e.enter_stunned(s.duration)
		var at: Vector3 = e.global_position + Vector3.UP * 1.1
		GoreFXScript.sparks(self, at, at - from, s.color, 16)
		GoreFXScript.flash_light(self, at, s.color, 3.0, 0.15, 3.0)
		_chain_arc_hop(s, hits, mults, i + 1, at))
```
**Replace with:**
```gdscript
	_launch_bolt(from, e, s.color, 26.0, 0.09, func() -> void:
		if not is_instance_valid(self) or not is_inside_tree():
			return
		if not _enemy_ok(e):
			var next_from: Vector3 = (e.global_position + Vector3.UP * 1.1) if (is_instance_valid(e) and e.is_inside_tree()) else from
			_chain_arc_hop(s, hits, mults, i + 1, next_from)
			return
		var landed: bool = e.apply_damage(int(round(s.power * mults[i] * (1.0 + _dmg_buff))), false, "ally_skill", self)
		if landed and not e.is_dead and not e.knockdown_immune:
			e.enter_stunned(s.duration)
		var at: Vector3 = e.global_position + Vector3.UP * 1.1
		GoreFXScript.sparks(self, at, at - from, s.color, 16)
		GoreFXScript.flash_light(self, at, s.color, 3.0, 0.15, 3.0)
		_chain_arc_hop(s, hits, mults, i + 1, at))
```

#### Edit 4E — Fix Wall-Backed Ranged Freeze in `_ranged_engage()` (`ALY-13`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	var close: EnemyAI = _nearest_enemy(global_position, 2.6)
	if close != null and close.get_current_target() == self:
		var away: Vector3 = global_position - close.global_position
		away.y = 0.0
		if away.length_squared() > 0.01 and _side_open(away.normalized()):
			_move_dir(away.normalized(), profile.move_speed * 1.15, delta)
			return
		if _attack_cd <= 0.0 and global_position.distance_to(close.global_position) <= profile.attack_range + 0.3:
			set_facing(close.global_position - global_position)
			_melee(close)
		else:
			_halt(delta)
		return
	if d > RANGED_MAX:
		_move_to(e.global_position - to_e.normalized() * (RANGED_MAX - 1.5), profile.move_speed, delta)
		return
	if d < RANGED_MIN and d > 0.01:
		_move_dir(-to_e.normalized(), profile.move_speed, delta)
		return
	_halt(delta)
	set_facing(to_e)
	if _attack_cd <= 0.0:
		_fire_bolt(e)
```
**Replace with:**
```gdscript
	var close: EnemyAI = _nearest_enemy(global_position, 2.6)
	if close != null and close.get_current_target() == self:
		var away: Vector3 = global_position - close.global_position
		away.y = 0.0
		if away.length_squared() > 0.01 and _side_open(away.normalized()):
			_move_dir(away.normalized(), profile.move_speed * 1.15, delta)
			return
		_halt(delta)
		set_facing(close.global_position - global_position)
		if _attack_cd <= 0.0:
			if global_position.distance_to(close.global_position) <= profile.attack_range + 0.3:
				_melee(close)
			else:
				_fire_bolt(close)
		return
	if d > RANGED_MAX:
		_move_to(e.global_position - to_e.normalized() * (RANGED_MAX - 1.5), profile.move_speed, delta)
		return
	if d < RANGED_MIN and d > 0.01 and _side_open(-to_e.normalized()):
		_move_dir(-to_e.normalized(), profile.move_speed, delta)
		return
	_halt(delta)
	set_facing(to_e)
	if _attack_cd <= 0.0:
		_fire_bolt(e)
```

*(Note: verify line 1900 in `squad_ally.gd` has the comment `## anything on us...` right before `var close: EnemyAI` — our `Find:` anchor starts at `var close: EnemyAI` which appears in both `_ranged_engage()` (`:1898`) and `_run_ranged()` (`:2734`), so let's include `func _ranged_engage` in the `Find:` block so it matches **exactly once**!)*
Wait — check! Let's rewrite Edit 4E's `Find:` with `func _ranged_engage(e: EnemyAI, delta: float) -> void:` included at the top so it is 100% unique!

Let's adjust Edit 4E cleanly below in the actual file content!

#### Edit 4F — Guard Empty `auto_use` (`REQ-20`) & Dead Player in `_friends()` (`ALY-12`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	for s in profile.get_skills():
		if not skill_ready(s) or s.auto_use == "never":
			continue
```
**Replace with:**
```gdscript
	for s in profile.get_skills():
		if not skill_ready(s) or s.auto_use.is_empty() or s.auto_use == "never":
			continue
```

**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func _friends() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var p: Node3D = _player()
	if p != null:
		out.append(p)
	for a in get_tree().get_nodes_in_group("squad_ally"):
		if a is SquadAlly and not (a as SquadAlly).is_downed:
			out.append(a as Node3D)
	return out
```
**Replace with:**
```gdscript
func _friends() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var p: Node3D = _player()
	if p != null and not (p is PlayerController and (p as PlayerController).current_state == PlayerController.State.DEAD):
		out.append(p)
	for a in get_tree().get_nodes_in_group("squad_ally"):
		if a is SquadAlly and not (a as SquadAlly).is_downed:
			out.append(a as Node3D)
	return out
```

#### Edit 4G — Re-Validate Target Every Tick in `_run_skill()` (`ALY-12`, `ALY-14`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	var tsel: String = String(cmd.args.get("target", ""))
	var tgt: Node3D = cmd.data.get("target_node", null) as Node3D
	if tgt == null or not is_instance_valid(tgt):
		match s.target_kind:
			"enemy":
				tgt = _resolve_enemy(tsel if not tsel.is_empty() else "nearest", player)
				if tgt == null and _engage_target != null and _enemy_ok(_engage_target):
					tgt = _engage_target
				if tgt == null:
					say("No target for %s." % s.display_name, "refuse", 1)
					finish_current("no target")
					return
			"ally":
				if tsel.is_empty():
					tgt = _lowest_friend(40.0, 1.01) if s.effect == "mending_light" else _most_pressed_friend(40.0, 0)
					if tgt == null:
						tgt = player
				elif tsel in ["me", "player", "you"]:
					tgt = player
				elif manager != null and manager.has_method("find_ally"):
					tgt = manager.call("find_ally", tsel) as Node3D
				if tgt == null:
					tgt = player
		cmd.data["target_node"] = tgt
	cmd.step = s.display_name
	var need: float = s.cast_range if s.target_kind in ["enemy", "ally"] else 0.0
	if tgt != null and need > 0.0 and tgt.global_position.distance_to(global_position) > need - 0.3:
		_move_to(tgt.global_position, profile.move_speed * 1.2, delta)
		if cmd.timer > 10.0:
			say("Can't get in range.", "refuse", 1)
			finish_current("out of range")
		return
	if not use_skill(s, tgt):
		say("%s fizzled." % s.display_name, "refuse", 1)
	finish_current("used " + s.id)
```
**Replace with:**
```gdscript
	var tsel: String = String(cmd.args.get("target", ""))
	var tgt: Node3D = cmd.data.get("target_node", null) as Node3D
	var had_cached: bool = cmd.data.has("target_node")
	if had_cached:
		var cached_ok: bool = tgt != null and is_instance_valid(tgt) and tgt.is_inside_tree()
		if cached_ok and s.target_kind == "enemy":
			cached_ok = tgt is EnemyAI and _enemy_ok(tgt as EnemyAI)
		elif cached_ok and s.target_kind == "ally":
			if tgt is SquadAlly:
				cached_ok = not (tgt as SquadAlly).is_downed
			elif tgt is PlayerController:
				cached_ok = (tgt as PlayerController).current_state != PlayerController.State.DEAD
		if not cached_ok:
			finish_current("target gone")
			return
	if tgt == null or not is_instance_valid(tgt):
		match s.target_kind:
			"enemy":
				tgt = _resolve_enemy(tsel if not tsel.is_empty() else "nearest", player)
				if tgt == null and _engage_target != null and _enemy_ok(_engage_target):
					tgt = _engage_target
				if tgt == null or not (tgt is EnemyAI and _enemy_ok(tgt as EnemyAI)):
					say("No target for %s." % s.display_name, "refuse", 1)
					finish_current("no target")
					return
			"ally":
				if tsel.is_empty():
					tgt = _lowest_friend(40.0, 1.01) if s.effect == "mending_light" else _most_pressed_friend(40.0, 0)
				elif tsel in ["me", "player", "you"]:
					tgt = player
				elif manager != null and manager.has_method("find_ally"):
					tgt = manager.call("find_ally", tsel) as Node3D
				if tgt is PlayerController and (tgt as PlayerController).current_state == PlayerController.State.DEAD:
					tgt = null
				if tgt is SquadAlly and (tgt as SquadAlly).is_downed:
					say("%s is down — needs revive." % (tgt as SquadAlly).get_display_name(), "refuse", 1)
					finish_current("target down")
					return
				if tgt == null:
					var living_f: Array[Node3D] = _friends()
					tgt = living_f[0] if not living_f.is_empty() else null
				if tgt == null:
					say("No target for %s." % s.display_name, "refuse", 1)
					finish_current("no target")
					return
		cmd.data["target_node"] = tgt
	cmd.step = s.display_name
	var need: float = s.cast_range if s.target_kind in ["enemy", "ally"] else 0.0
	if tgt != null and need > 0.0 and tgt.global_position.distance_to(global_position) > need - 0.3:
		_move_to(tgt.global_position, profile.move_speed * 1.2, delta)
		if cmd.timer > 10.0:
			say("Can't get in range.", "refuse", 1)
			finish_current("out of range")
		return
	if not use_skill(s, tgt):
		say("%s fizzled." % s.display_name, "refuse", 1)
	finish_current("used " + s.id)
```

#### Edit 4H — Require Vertical Reach Check in `_run_destroy()` (`ALY-24`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	cmd.step = "smashing"
	var goal: Vector3 = prop.global_position
	if Vector2(global_position.x - goal.x, global_position.z - goal.z).length() > 2.2:
		_move_to(goal, profile.move_speed, delta)
		if cmd.timer > 12.0:
			say("Can't get to it.", "refuse", 1)
			finish_current("unreachable")
		return
```
**Replace with:**
```gdscript
	cmd.step = "smashing"
	var goal: Vector3 = prop.global_position
	if Vector2(global_position.x - goal.x, global_position.z - goal.z).length() > 2.2 or absf(global_position.y - goal.y) > 2.0:
		_move_to(goal, profile.move_speed, delta)
		if cmd.timer > 12.0:
			say("Can't get to it.", "refuse", 1)
			finish_current("unreachable")
		return
```

#### Edit 4I — Un-Invert `"left"`/`"right"` & Anchor Spot Defense in `_run_position()` (`ALY-13`, `ALY-15`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	match spot:
		"front":
			off = f * 3.0 + r * lane * 1.5
		"left":
			off = r * (2.4 + absf(lane) * 1.3) - f * (lane * 0.6)
		"right":
			off = -r * (2.4 + absf(lane) * 1.3) - f * (lane * 0.6)
		"close":
			off = r * (1.6 if slot_index % 2 == 0 else -1.6) - f * (0.3 + 0.9 * float(slot_index / 2))
		"far":
			off = (r * lane * 3.0 - f * 3.0).normalized() * 7.0 if lane != 0.0 else -f * 7.5
		_:  # behind: staggered off the camera line (straight behind is the lens)
			off = -f * (2.2 + 1.0 * float(slot_index / 2)) + r * (1.5 if slot_index % 2 == 0 else -1.5)
	var goal: Vector3 = _valid_spot_near(player, player.global_position + off, r, cmd)
	cmd.step = String(cmd.describe())
	var threat: EnemyAI = _nearest_enemy(global_position, 2.2)
	if threat != null:
		_fight(threat, delta)
		return
```
**Replace with:**
```gdscript
	match spot:
		"front":
			off = f * 3.0 + r * lane * 1.5
		"left":
			off = -r * (2.4 + absf(lane) * 1.3) - f * (lane * 0.6)
		"right":
			off = r * (2.4 + absf(lane) * 1.3) - f * (lane * 0.6)
		"close":
			off = r * (1.6 if slot_index % 2 == 0 else -1.6) - f * (0.3 + 0.9 * float(slot_index / 2))
		"far":
			off = (r * lane * 3.0 - f * 3.0).normalized() * 7.0 if lane != 0.0 else -f * 7.5
		_:  # behind: staggered off the camera line (straight behind is the lens)
			off = -f * (2.2 + 1.0 * float(slot_index / 2)) + r * (1.5 if slot_index % 2 == 0 else -1.5)
	var goal: Vector3 = _valid_spot_near(player, player.global_position + off, r, cmd)
	cmd.step = String(cmd.describe())
	var threat: EnemyAI = _nearest_enemy(global_position, 2.2)
	if threat != null:
		_fight(threat, delta, true)
		return
```

#### Edit 4J — Fix Wall-Backed Ranged Freeze in `_run_ranged()` (`ALY-13`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	if close != null and close.get_current_target() == self:
		# Something is on us: back-step away from it (melee if cornered).
		var away: Vector3 = global_position - close.global_position
		away.y = 0.0
		if _side_open(away.normalized()):
			cmd.step = "backing off"
			_move_dir(away.normalized(), profile.move_speed * 1.15, delta)
			return
		_fight(close, delta)
		return
	if d > RANGED_MAX:
		cmd.step = "closing to range"
		_move_to(e.global_position - to_e.normalized() * (RANGED_MAX - 1.5), profile.move_speed, delta)
		return
	if d < RANGED_MIN:
		cmd.step = "opening range"
		_move_dir(-to_e.normalized(), profile.move_speed, delta)
		return
	cmd.step = "shooting"
	_halt(delta)
	set_facing(to_e)
	if _attack_cd <= 0.0:
		_fire_bolt(e)
```
**Replace with:**
```gdscript
	if close != null and close.get_current_target() == self:
		# Something is on us: back-step away from it (fight in place if cornered).
		var away: Vector3 = global_position - close.global_position
		away.y = 0.0
		if away.length_squared() > 0.01 and _side_open(away.normalized()):
			cmd.step = "backing off"
			_move_dir(away.normalized(), profile.move_speed * 1.15, delta)
			return
		cmd.step = "fighting cornered"
		_fight(close, delta, true)
		return
	if d > RANGED_MAX:
		cmd.step = "closing to range"
		_move_to(e.global_position - to_e.normalized() * (RANGED_MAX - 1.5), profile.move_speed, delta)
		return
	if d < RANGED_MIN and d > 0.01 and _side_open(-to_e.normalized()):
		cmd.step = "opening range"
		_move_dir(-to_e.normalized(), profile.move_speed, delta)
		return
	cmd.step = "shooting"
	_halt(delta)
	set_facing(to_e)
	if _attack_cd <= 0.0:
		_fire_bolt(e)
```

#### Edit 4K — Support `hold_ground` in `_fight()` for Spot-Anchored Commands (`ALY-13`)
**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
func _fight(e: EnemyAI, delta: float) -> void:
	_engage_target = e
	_combat_quiet = 0.0
	if _hazard_dodge(delta):
		return
	# Casters fight from range with visible bolts (no sword); berserk massacre still wades in.
	if profile.role == "artillery" and not _is_massacre():
		_ranged_engage(e, delta)
		return
```
**Replace with:**
```gdscript
func _fight(e: EnemyAI, delta: float, hold_ground: bool = false) -> void:
	_engage_target = e
	_combat_quiet = 0.0
	if _hazard_dodge(delta):
		return
	# Casters fight from range with visible bolts (no sword); berserk massacre still wades in.
	if profile.role == "artillery" and not _is_massacre():
		if hold_ground:
			var to_t: Vector3 = e.global_position - global_position
			to_t.y = 0.0
			_halt(delta)
			set_facing(to_t)
			if _attack_cd <= 0.0:
				if to_t.length() <= profile.attack_range + 0.3:
					_melee(e)
				else:
					_fire_bolt(e)
			return
		_ranged_engage(e, delta)
		return
```

- **Postcondition**: All combat, taunt, skill-approach, ranged/hold/position oscillation, left/right direction, chain-arc stun/mid-flight continuation, and destroy-vertical-reach bugs in `squad_ally.gd` are resolved without altering `:182, :1222, :1223, :1694, :1759`.

---

### Step 5 — Fix `AllySquadManager` Rally Queue/Regroup, Stop/Strategy Abort & Panic Lock, Revive Routing & Combo Substitution (`ALY-02`, `ALY-06`, `ALY-07`, `ALY-08`, `ALY-09`, `ALY-12`, `ALY-20`)
- **Prerequisites**: Steps 1–4 complete.
- **Ownership Guard**: Every edit in this step touches **ONLY** lines `:217..1509` of `scripts/allies/ally_squad_manager.gd`. Lines `:47..90` (`_ready()`, `_spawn_squad()`, etc.) are untouched.
- **Note**: Apply Edits 5A–5G in order.

#### Edit 5A — Persist Rally Flag in `args` + Clear Queued & Active Rally Commands in `_update_rally()` (`ALY-06`)
**Target:** `scripts/allies/ally_squad_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
		a.assign(cmd)
		cmd.data["rally"] = true   # assign() resets data for non-combo commands
		helpers.append(a)
```
**Replace with:**
```gdscript
		a.assign(cmd)
		cmd.args["rally"] = true   # survives any later re-assignment after preemption
		cmd.data["rally"] = true   # assign() resets data for non-combo commands
		helpers.append(a)
```

**Target:** `scripts/allies/ally_squad_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
	for a in (rec["allies"] as Array):
		var ally: SquadAlly = a as SquadAlly
		if is_instance_valid(ally) and ally.current != null and bool(ally.current.data.get("rally", false)):
			ally.finish_current("safe")
```
**Replace with:**
```gdscript
	for a in (rec["allies"] as Array):
		var ally: SquadAlly = a as SquadAlly
		if not is_instance_valid(ally):
			continue
		for q in ally.queue.duplicate():
			var qc: SquadCommand = q as SquadCommand
			if qc != null and (bool(qc.data.get("rally", false)) or bool(qc.args.get("rally", false))):
				qc.done = true
				ally.queue.erase(qc)
		if ally.current != null and (bool(ally.current.data.get("rally", false)) or bool(ally.current.args.get("rally", false))):
			ally.finish_current("safe")
```

#### Edit 5B — Clear Rally State on `regroup(true)` & Null-Guard `_player` (`ALY-06`)
**Target:** `scripts/allies/ally_squad_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
func regroup(full_heal: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	for a in allies:
		if not is_instance_valid(a):
			continue
		var p: Vector3 = a.call("_formation_point", _player) as Vector3
		if full_heal:
			a.reset_full(p)
		else:
			a.global_position = p
	_combos.clear()
	_roster_dirty = true
```
**Replace with:**
```gdscript
func regroup(full_heal: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	for a in allies:
		if not is_instance_valid(a):
			continue
		var p: Vector3 = (a.call("_formation_point", _player) as Vector3) if _player != null else a.global_position
		if full_heal:
			a.reset_full(p)
		else:
			a.global_position = p
	_combos.clear()
	if full_heal:
		_rally.clear()
		_rally_cooldown.clear()
		_rally_scan = 0.0
	_roster_dirty = true
```

#### Edit 5C — Abort Running Effects on `"stop"` & Substitute `"revive"` Orders Addressed to Downed Allies (`ALY-07`, `ALY-09`)
**Target:** `scripts/allies/ally_squad_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
		"stop":
			for a in addressed:
				a.clear_queue()
				a.finish_current("cancelled")
				a.current = null
				a.say_event("ack", 0)
			_cancel_combos_for(addressed)
			_log(source, ", ".join(_names(addressed)), "stop", "cleared")
			return "orders cancelled"
		"chat":
			return _issue_chat(c, addressed, source)
		"split":
			return _split_squad(addressed, source)
		"strategy":
			return execute_strategy(String(c.get("strategy", c.get("text", ""))), String(c.get("target", "")), addressed if _explicit_allies(c) else get_living(), source)
		"skill":
			return _issue_skill(c, source)
	# Role-based substitution: an addressed ally who is DOWN hands the order to a stand-in.
	if verb != "revive" and verb != "massacre" and verb != "ceasefire":
		var named_explicitly: bool = (c.get("allies", []) is Array) and not (c.get("allies", []) as Array).is_empty() and not ((c.get("allies", []) as Array).has("all"))
		if named_explicitly:
			var rebuilt: Array[SquadAlly] = []
			for a0 in addressed:
				if not a0.is_downed:
					rebuilt.append(a0)
					continue
				var rp: Array = ROLE_FOR_VERB.get(verb, ["", ""]) as Array
				var sub: SquadAlly = _pick_for(String(rp[1]), String(rp[0]), addressed, [])
				if sub != null and not rebuilt.has(sub):
					rebuilt.append(sub)
					sub.say("%s is down — I'll %s instead." % [a0.get_display_name(), verb.replace("_", " ")], "substitute", 2)
					_log(source, sub.get_display_name(), "substitute for " + a0.get_display_name(), verb)
				else:
					_log(source, a0.get_display_name(), desc, "dropped: ally down, no substitute")
			if rebuilt.is_empty():
				return "dropped: no ally available"
			addressed = rebuilt
```
**Replace with:**
```gdscript
		"stop":
			for a in addressed:
				a.clear_queue()
				a._abort_current_effects()
				a.finish_current("cancelled")
				a.current = null
				a.say_event("ack", 0)
			_cancel_combos_for(addressed)
			_log(source, ", ".join(_names(addressed)), "stop", "cleared")
			return "orders cancelled"
		"chat":
			return _issue_chat(c, addressed, source)
		"split":
			return _split_squad(addressed, source)
		"strategy":
			return execute_strategy(String(c.get("strategy", c.get("text", ""))), String(c.get("target", "")), addressed if _explicit_allies(c) else get_living(), source)
		"skill":
			return _issue_skill(c, source)
	# Role-based substitution: an addressed ally who is DOWN hands the order to a stand-in.
	if verb != "massacre" and verb != "ceasefire":
		var named_explicitly: bool = (c.get("allies", []) is Array) and not (c.get("allies", []) as Array).is_empty() and not ((c.get("allies", []) as Array).has("all"))
		if named_explicitly:
			var rebuilt: Array[SquadAlly] = []
			var exclude_sub: Array = addressed.duplicate()
			if verb == "revive":
				var r_tgt: SquadAlly = find_ally(String(c.get("target", "")))
				if r_tgt != null and not exclude_sub.has(r_tgt):
					exclude_sub.append(r_tgt)
			for a0 in addressed:
				if not a0.is_downed:
					rebuilt.append(a0)
					continue
				var rp: Array = ["", "revive"] if verb == "revive" else (ROLE_FOR_VERB.get(verb, ["", ""]) as Array)
				var sub: SquadAlly = _pick_for(String(rp[1]), String(rp[0]), exclude_sub, [])
				if sub != null and not rebuilt.has(sub):
					rebuilt.append(sub)
					exclude_sub.append(sub)
					sub.say("%s is down — I'll %s instead." % [a0.get_display_name(), verb.replace("_", " ")], "substitute", 2)
					_log(source, sub.get_display_name(), "substitute for " + a0.get_display_name(), verb)
				else:
					_log(source, a0.get_display_name(), desc, "dropped: ally down, no substitute")
			if rebuilt.is_empty():
				return "dropped: no ally available"
			addressed = rebuilt
```

#### Edit 5D — Protect `PANIC` Orders, Abort Old Effects, Validate Intel Entries & Cancel Overridden Combos in `execute_strategy()` (`ALY-07`, `ALY-08`, `ALY-20`)
**Target:** `scripts/allies/ally_squad_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
	if intel != null:
		intel.refresh()
		for en in intel.get_entries():
			var en_node: EnemyAI = en["node"] as EnemyAI
			if en_node != null and not en_node.is_dead and en_node.is_active and en_node.is_hittable_now():
				by_dist.append(en_node)
		by_hp = by_dist.duplicate()
		by_hp.sort_custom(func(x: EnemyAI, y: EnemyAI) -> bool: return float(x.health) / float(maxi(1, x.max_health)) < float(y.health) / float(maxi(1, y.max_health)))
	var vanguard: SquadAlly = null
	for a in living:
		if a.get_role() == "vanguard":
			vanguard = a
			break
	if vanguard == null:
		vanguard = living[0]
	var weakest: String = _weakest_friend_name()
	var roles: Dictionary = strat["roles"]
	var parts: PackedStringArray = []
	var slot_i: int = 0
	var n_slot: int = 0
	for a0 in living:
		for st0 in (roles.get(a0.get_role(), roles.get("any", [])) as Array):
			if str((st0 as Dictionary).get("args", {})).contains("$slot_angle"):
				n_slot += 1
				break
	for i in range(living.size()):
		var a: SquadAlly = living[i]
		var steps: Array = (roles.get(a.get_role(), roles.get("any", [])) as Array)
		if steps.is_empty():
			continue
		a.clear_queue()
		if a.current != null and a.current.priority < SquadCommand.Priority.PANIC:
			a.finish_current("new strategy")
			a.clear_queue()
		var first: bool = true
		for st in steps:
			var args: Dictionary = ((st as Dictionary).get("args", {}) as Dictionary).duplicate(true)
			for k in args.keys():
				var v: Variant = args[k]
				if not (v is String):
					continue
				var sv: String = String(v)
				match sv:
					"$target":
						args[k] = primary_id
					"$distinct":
						args[k] = intel.id_of(by_dist[i % by_dist.size()]) if not by_dist.is_empty() else "nearest"
					"$weakest_distinct":
						args[k] = intel.id_of(by_hp[i % by_hp.size()]) if not by_hp.is_empty() else "weakest"
					"$weakest_friend":
						args[k] = weakest
					"$slot_angle":
						# Angle 0 = the player's side of the target. Pincer alternates flanks; surround spreads evenly.
						if String(strat["id"]) == "pincer":
							args[k] = 100.0 if slot_i % 2 == 0 else -100.0
						else:
							args[k] = 360.0 * float(slot_i) / float(maxi(1, n_slot)) + 180.0 / float(maxi(1, n_slot))
					"$line_spot":
						args[k] = _line_spot(i, living.size())
					"$behind_spot":
						args[k] = vanguard.global_position - (vanguard.get_facing_direction()) * 1.8 + Vector3(-vanguard.get_facing_direction().z, 0, vanguard.get_facing_direction().x) * (float(i % 2) * 2.0 - 1.0) * 1.2
					"$player_spot":
						args[k] = near
					_:
						if sv.contains("$vanguard"):
							args[k] = sv.replace("$vanguard", vanguard.get_display_name())
			if args.has("angle"):
				slot_i += 1
			var cmd := SquadCommand.make(String((st as Dictionary)["verb"]), args, source)
			if first:
				a.assign(cmd)
				first = false
			else:
				a.enqueue(cmd)
		parts.append("%s: %s" % [a.get_display_name(), a.current.describe() if a.current != null else "-"])
	var lead: SquadAlly = vanguard if not vanguard.is_downed else living[0]
	lead.say("%s! %s" % [strat["name"], _strategy_callout(strat, living)], "strategy", 2)
```
**Replace with:**
```gdscript
	if intel != null:
		intel.refresh()
		for en in intel.get_entries():
			var en_node: EnemyAI = en.get("node") as EnemyAI
			if en_node != null and is_instance_valid(en_node) and not en_node.is_dead and en_node.is_active and en_node.is_inside_tree() and en_node.is_hittable_now():
				by_dist.append(en_node)
		by_hp = by_dist.duplicate()
		by_hp.sort_custom(func(x: EnemyAI, y: EnemyAI) -> bool: return float(x.health) / float(maxi(1, x.max_health)) < float(y.health) / float(maxi(1, y.max_health)))
	var vanguard: SquadAlly = null
	for a in living:
		if a.get_role() == "vanguard":
			vanguard = a
			break
	if vanguard == null:
		vanguard = living[0]
	var weakest: String = _weakest_friend_name()
	var roles: Dictionary = strat["roles"]
	var parts: PackedStringArray = []
	var overridden: Array[SquadAlly] = []
	var slot_i: int = 0
	var n_slot: int = 0
	for a0 in living:
		if a0.current != null and not a0.current.done and a0.current.priority >= SquadCommand.Priority.PANIC:
			continue
		for st0 in (roles.get(a0.get_role(), roles.get("any", [])) as Array):
			if str((st0 as Dictionary).get("args", {})).contains("$slot_angle"):
				n_slot += 1
				break
	for i in range(living.size()):
		var a: SquadAlly = living[i]
		if a.current != null and not a.current.done and a.current.priority >= SquadCommand.Priority.PANIC:
			parts.append("%s: %s (panic lock)" % [a.get_display_name(), a.current.verb])
			continue
		var steps: Array = (roles.get(a.get_role(), roles.get("any", [])) as Array)
		if steps.is_empty():
			continue
		a.clear_queue()
		if a.current != null:
			a._abort_current_effects()
			a.finish_current("new strategy")
			a.clear_queue()
		overridden.append(a)
		var first: bool = true
		for st in steps:
			var args: Dictionary = ((st as Dictionary).get("args", {}) as Dictionary).duplicate(true)
			for k in args.keys():
				var v: Variant = args[k]
				if not (v is String):
					continue
				var sv: String = String(v)
				match sv:
					"$target":
						args[k] = primary_id
					"$distinct":
						args[k] = intel.id_of(by_dist[i % by_dist.size()]) if not by_dist.is_empty() else "nearest"
					"$weakest_distinct":
						args[k] = intel.id_of(by_hp[i % by_hp.size()]) if not by_hp.is_empty() else "weakest"
					"$weakest_friend":
						args[k] = weakest
					"$slot_angle":
						# Angle 0 = the player's side of the target. Pincer alternates flanks; surround spreads evenly.
						if String(strat["id"]) == "pincer":
							args[k] = 100.0 if slot_i % 2 == 0 else -100.0
						else:
							args[k] = 360.0 * float(slot_i) / float(maxi(1, n_slot)) + 180.0 / float(maxi(1, n_slot))
					"$line_spot":
						args[k] = _line_spot(i, living.size())
					"$behind_spot":
						args[k] = vanguard.global_position - (vanguard.get_facing_direction()) * 1.8 + Vector3(-vanguard.get_facing_direction().z, 0, vanguard.get_facing_direction().x) * (float(i % 2) * 2.0 - 1.0) * 1.2
					"$player_spot":
						args[k] = near
					_:
						if sv.contains("$vanguard"):
							args[k] = sv.replace("$vanguard", vanguard.get_display_name())
			if args.has("angle"):
				slot_i += 1
			var cmd := SquadCommand.make(String((st as Dictionary)["verb"]), args, source)
			if first:
				a.assign(cmd)
				first = false
			else:
				a.enqueue(cmd)
		parts.append("%s: %s" % [a.get_display_name(), a.current.describe() if a.current != null else "-"])
	if overridden.is_empty():
		return "blocked by panic order"
	_cancel_combos_for(overridden)
	var lead: SquadAlly = vanguard if (not vanguard.is_downed and overridden.has(vanguard)) else overridden[0]
	lead.say("%s! %s" % [strat["name"], _strategy_callout(strat, overridden)], "strategy", 2)
```

#### Edit 5E — Skip Dead Player in `_weakest_friend_name()` & Guard `_line_spot()` Cached Nodes (`ALY-12`, `ALY-20`)
**Target:** `scripts/allies/ally_squad_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
func _weakest_friend_name() -> String:
	var best: String = "player"
	var br: float = 2.0
	if _player is PlayerController:
		var p: PlayerController = _player as PlayerController
		br = float(p.health) / float(maxi(1, p.max_health))
	for a in get_living():
		if a.get_health_ratio() < br:
			br = a.get_health_ratio()
			best = a.get_display_name()
	return best


func _line_spot(i: int, n: int) -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var c: Vector3 = Vector3.INF
	if intel != null and not intel.get_entries().is_empty():
		c = Vector3.ZERO
		var k: int = 0
		for en in intel.get_entries():
			if k >= 5:
				break
			c += (en["node"] as Node3D).global_position
			k += 1
		c /= float(k)
```
**Replace with:**
```gdscript
func _weakest_friend_name() -> String:
	var best: String = ""
	var br: float = 2.0
	if _player is PlayerController:
		var p: PlayerController = _player as PlayerController
		if p.current_state != PlayerController.State.DEAD:
			br = float(p.health) / float(maxi(1, p.max_health))
			best = "player"
	for a in get_living():
		if a.get_health_ratio() < br:
			br = a.get_health_ratio()
			best = a.get_display_name()
	return best if not best.is_empty() else "player"


func _line_spot(i: int, n: int) -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return Vector3.ZERO
	var c: Vector3 = Vector3.INF
	if intel != null and not intel.get_entries().is_empty():
		var sum_pos := Vector3.ZERO
		var k: int = 0
		for en in intel.get_entries():
			if k >= 5:
				break
			var en_n: Node3D = en.get("node") as Node3D
			if en_n == null or not is_instance_valid(en_n) or not en_n.is_inside_tree():
				continue
			sum_pos += en_n.global_position
			k += 1
		if k > 0:
			c = sum_pos / float(k)
```

#### Edit 5F — Prevent Downed Allies From Accepting `"revive"` in `_route()` (`ALY-09`)
**Target:** `scripts/allies/ally_squad_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
func _route(a: SquadAlly, cmd: SquadCommand) -> String:
	if a.is_downed and cmd.verb != "revive":
		return "is down"
```
**Replace with:**
```gdscript
func _route(a: SquadAlly, cmd: SquadCommand) -> String:
	if a.is_downed:
		return "is down"
```

#### Edit 5G — Fix `_combo_coordinate()`, `_substitute()`, and `_abort_combo()` Validity & Mine/Planted Reset (`ALY-02`)
**Target:** `scripts/allies/ally_squad_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
	if kind == "combo_kite_nuke" and parts.has("kiter") and parts.has("nuker"):
		var nk: SquadCommand = rec.get("cmd_nuker", null) as SquadCommand
		if nk != null:
			nk.data["watch"] = (parts["kiter"] as SquadAlly).global_position
	elif kind == "combo_charge_finish" and parts.has("charger") and parts.has("finisher"):
		var cc: SquadCommand = rec.get("cmd_charger", null) as SquadCommand
		var fc: SquadCommand = rec.get("cmd_finisher", null) as SquadCommand
		if cc != null and fc != null and cc.data.has("enemy") and not fc.data.has("enemy"):
			fc.data["enemy"] = cc.data["enemy"]
	elif kind == "combo_lure_detonate" and parts.has("trapper"):
		var tc: SquadCommand = rec.get("cmd_trapper", null) as SquadCommand
		if tc != null and not tc.data.has("point"):
			tc.data["point"] = rec.get("point", Vector3.ZERO)
		if float(rec["planted_t"]) >= 0.0 and tc != null and not tc.data.get("detonate", false):
			var trapper: SquadAlly = parts["trapper"] as SquadAlly
			var mp: Vector3 = trapper.get_mine_position()
			var lurer: SquadAlly = parts.get("lurer", null) as SquadAlly
			var trapped: int = 0
			if mp != Vector3.INF:
				for e in _active_enemies_near(mp, 3.2):
					if lurer == null or e.get_current_target() == lurer or e.is_aggroed():
						trapped += 1
			if trapped > 0 or float(rec["t"]) - float(rec["planted_t"]) > 15.0:
				tc.data["detonate"] = true
	# Solo lure: give the solo ally its sigil point.
	for part in parts.keys():
		if String(part) == "solo_lure_detonate":
			var sc: SquadCommand = rec.get("cmd_" + String(part), null) as SquadCommand
			if sc != null and not sc.data.has("point"):
				sc.data["point"] = rec.get("point", Vector3.ZERO)


## A combo participant went down: hand their half to a free ally, else collapse to a solo fallback.
func _substitute(id: int, part: String) -> void:
	var rec: Dictionary = _combos[id]
	var parts: Dictionary = rec["parts"]
	var gone: SquadAlly = parts[part] as SquadAlly
	var kind: String = String(rec["kind"])
	var used: Array = parts.values()
	var ability: String = "kite"
	var role: String = "skirmisher"
	for p in (COMBO_PARTS.get(kind, []) as Array):
		if String(p[0]) == part:
			ability = String(p[1])
			role = String(p[2])
	var sub: SquadAlly = _pick_for(ability, role, used, [])
	var old_cmd: SquadCommand = rec.get("cmd_" + part, null) as SquadCommand
	if old_cmd != null:
		old_cmd.done = true
	if sub != null and not part.begins_with("solo"):
		var cmd: SquadCommand = SquadCommand.make(kind, rec["args"] as Dictionary, String(rec["source"]))
		cmd.combo_id = id
		cmd.combo_part = part
		parts[part] = sub
		rec["cmd_" + part] = cmd
		_route(sub, cmd)
		if not gone.is_downed and gone.current != null and gone.current.combo_id == id:
			gone.finish_current("substituted")
		sub.say("%s is out — I'll take their part!" % gone.get_display_name(), "combo_go", 2)
		combo_progress.emit(kind, "Substitution: %s -> %s (%s)" % [gone.get_display_name(), sub.get_display_name(), part])
		return
	# Nobody free: survivor goes solo.
	parts.erase(part)
	rec.erase("cmd_" + part)
	if parts.size() == 1:
		var survivor_part: String = String(parts.keys()[0])
		var survivor: SquadAlly = parts[survivor_part] as SquadAlly
		var scmd: SquadCommand = rec.get("cmd_" + survivor_part, null) as SquadCommand
		if scmd != null:
			scmd.done = true
		var solo := SquadCommand.make(kind, rec["args"] as Dictionary, String(rec["source"]))
		solo.combo_id = id
		solo.combo_part = "solo_" + kind.trim_prefix("combo_")
		parts.clear()
		parts[solo.combo_part] = survivor
		rec["cmd_" + solo.combo_part] = solo
		if survivor.current == scmd:
			survivor.assign(solo)
		else:
			_route(survivor, solo)
		if not gone.is_downed and gone.current != null and gone.current.combo_id == id:
			gone.finish_current("substituted")
		survivor.say("%s is out. Doing this alone!" % gone.get_display_name(), "combo_go", 2)
		combo_progress.emit(kind, "Solo fallback: %s" % survivor.get_display_name())
	else:
		_abort_combo(id, "no one left to run it")


func _abort_combo(id: int, why: String) -> void:
	if not _combos.has(id):
		return
	var rec: Dictionary = _combos[id]
	_combos.erase(id)
	for part in (rec["parts"] as Dictionary).keys():
		var a: SquadAlly = rec["parts"][part] as SquadAlly
		var cmd: SquadCommand = rec.get("cmd_" + String(part), null) as SquadCommand
		if cmd == null or not is_instance_valid(a):
			continue
		cmd.done = true
		if a.current == cmd:
			a.finish_current("combo aborted")
		a.queue.erase(cmd)
	combo_progress.emit(String(rec["kind"]), "%s aborted: %s" % [String(COMBO_NAMES.get(rec["kind"], rec["kind"])), why])
```
**Replace with:**
```gdscript
	if kind == "combo_kite_nuke" and parts.has("kiter") and parts.has("nuker"):
		var kiter: SquadAlly = parts["kiter"] as SquadAlly
		var nk: SquadCommand = rec.get("cmd_nuker", null) as SquadCommand
		if nk != null and is_instance_valid(kiter):
			nk.data["watch"] = kiter.global_position
	elif kind == "combo_charge_finish" and parts.has("charger") and parts.has("finisher"):
		var cc: SquadCommand = rec.get("cmd_charger", null) as SquadCommand
		var fc: SquadCommand = rec.get("cmd_finisher", null) as SquadCommand
		if cc != null and fc != null and cc.data.has("enemy") and not fc.data.has("enemy"):
			fc.data["enemy"] = cc.data["enemy"]
	elif kind == "combo_lure_detonate" and parts.has("trapper"):
		var tc: SquadCommand = rec.get("cmd_trapper", null) as SquadCommand
		if tc != null and not tc.data.has("point"):
			tc.data["point"] = rec.get("point", Vector3.ZERO)
		var lc: SquadCommand = rec.get("cmd_lurer", null) as SquadCommand
		if lc != null and float(rec["planted_t"]) >= 0.0 and not lc.data.has("point"):
			lc.data["point"] = rec.get("point", Vector3.ZERO)
		if float(rec["planted_t"]) >= 0.0 and tc != null and not tc.data.get("detonate", false):
			var trapper: SquadAlly = parts["trapper"] as SquadAlly
			var mp: Vector3 = trapper.get_mine_position() if is_instance_valid(trapper) else Vector3.INF
			var lurer: SquadAlly = parts.get("lurer", null) as SquadAlly
			var trapped: int = 0
			if mp != Vector3.INF:
				for e in _active_enemies_near(mp, 3.2):
					if lurer == null or not is_instance_valid(lurer) or e.get_current_target() == lurer or e.is_aggroed():
						trapped += 1
			if trapped > 0 or float(rec["t"]) - float(rec["planted_t"]) > 15.0:
				tc.data["detonate"] = true
	# Solo lure: give the solo ally its sigil point.
	for part in parts.keys():
		if String(part) == "solo_lure_detonate":
			var sc: SquadCommand = rec.get("cmd_" + String(part), null) as SquadCommand
			if sc != null and not sc.data.has("point"):
				sc.data["point"] = rec.get("point", Vector3.ZERO)


## A combo participant went down: hand their half to a free ally, else collapse to a solo fallback.
func _substitute(id: int, part: String) -> void:
	if not _combos.has(id):
		return
	var rec: Dictionary = _combos[id]
	var parts: Dictionary = rec["parts"]
	var gone: SquadAlly = parts.get(part, null) as SquadAlly
	var gone_valid: bool = is_instance_valid(gone)
	var gone_name: String = gone.get_display_name() if gone_valid else part.capitalize()
	var kind: String = String(rec["kind"])
	var used: Array = parts.values()
	var ability: String = "kite"
	var role: String = "skirmisher"
	for p in (COMBO_PARTS.get(kind, []) as Array):
		if String(p[0]) == part:
			ability = String(p[1])
			role = String(p[2])
	var sub: SquadAlly = _pick_for(ability, role, used, [])
	var old_cmd: SquadCommand = rec.get("cmd_" + part, null) as SquadCommand
	if old_cmd != null:
		old_cmd.done = true
	if part == "trapper" or part == "solo_lure_detonate":
		rec["planted_t"] = -1.0
		if gone_valid:
			gone.clear_mine()
	if sub != null and not part.begins_with("solo"):
		var cmd: SquadCommand = SquadCommand.make(kind, rec["args"] as Dictionary, String(rec["source"]))
		cmd.combo_id = id
		cmd.combo_part = part
		parts[part] = sub
		rec["cmd_" + part] = cmd
		_route(sub, cmd)
		if gone_valid and not gone.is_downed and gone.current != null and gone.current.combo_id == id:
			gone.finish_current("substituted")
		sub.say("%s is out — I'll take their part!" % gone_name, "combo_go", 2)
		combo_progress.emit(kind, "Substitution: %s -> %s (%s)" % [gone_name, sub.get_display_name(), part])
		return
	# Nobody free: survivor goes solo.
	parts.erase(part)
	rec.erase("cmd_" + part)
	if parts.size() == 1:
		var survivor_part: String = String(parts.keys()[0])
		var survivor: SquadAlly = parts[survivor_part] as SquadAlly
		if not is_instance_valid(survivor) or survivor.is_downed:
			_abort_combo(id, "no one left to run it")
			return
		var scmd: SquadCommand = rec.get("cmd_" + survivor_part, null) as SquadCommand
		if scmd != null:
			scmd.done = true
		if kind == "combo_lure_detonate":
			rec["planted_t"] = -1.0
			survivor.clear_mine()
		var solo := SquadCommand.make(kind, rec["args"] as Dictionary, String(rec["source"]))
		solo.combo_id = id
		solo.combo_part = "solo_" + kind.trim_prefix("combo_")
		parts.clear()
		parts[solo.combo_part] = survivor
		rec["cmd_" + solo.combo_part] = solo
		if survivor.current == scmd:
			survivor.assign(solo)
		else:
			_route(survivor, solo)
		if gone_valid and not gone.is_downed and gone.current != null and gone.current.combo_id == id:
			gone.finish_current("substituted")
		survivor.say("%s is out. Doing this alone!" % gone_name, "combo_go", 2)
		combo_progress.emit(kind, "Solo fallback: %s" % survivor.get_display_name())
	else:
		_abort_combo(id, "no one left to run it")


func _abort_combo(id: int, why: String) -> void:
	if not _combos.has(id):
		return
	var rec: Dictionary = _combos[id]
	_combos.erase(id)
	rec["planted_t"] = -1.0
	for part in (rec["parts"] as Dictionary).keys():
		var a: SquadAlly = rec["parts"][part] as SquadAlly
		var cmd: SquadCommand = rec.get("cmd_" + String(part), null) as SquadCommand
		if cmd != null:
			cmd.done = true
		if not is_instance_valid(a):
			continue
		a.clear_mine()
		if cmd != null:
			a.queue.erase(cmd)
			if a.current == cmd:
				a.finish_current("combo aborted")
	combo_progress.emit(String(rec["kind"]), "%s aborted: %s" % [String(COMBO_NAMES.get(rec["kind"], rec["kind"])), why])
```

- **Postcondition**: `AllySquadManager` has zero edits outside `:217..1509`, rally flags/queues/resets work cleanly, `"stop"` and `execute_strategy()` abort effects and protect `PANIC`, downed allies substitute/reject `"revive"`, dead players are skipped, and combo substitution/abortion never dereferences freed allies or leaks mines.

---

### Step 6 — Fix `SquadCommsHUD` Menu/Loading/Visibility Gating & PTT Release (`ALY-21`)
- **Prerequisites**: Steps 1–5 complete.

#### Edit 6A — Clear PTT Flags in `_exit_tree()` (`ALY-21`)
**Target:** `scripts/ui/squad_comms_hud.gd`
**Action:** Replace block
**Find:**
```gdscript
func _exit_tree() -> void:
	if _chat_open:
		_chat_open = false
		PlayerController.ui_input_locked = false
```
**Replace with:**
```gdscript
func _exit_tree() -> void:
	_ptt_held_key = false
	_ptt_held_mouse = false
	if _chat_open:
		_chat_open = false
		PlayerController.ui_input_locked = false
```

#### Edit 6B — Process PTT Release Before Early Returns, Gate `F10`, & Check `LoadingScreen` / Visibility (`ALY-21`)
**Target:** `scripts/ui/squad_comms_hud.gd`
**Action:** Replace block
**Find:**
```gdscript
func _input(event: InputEvent) -> void:
	if comms == null:
		return
	if event.is_action_pressed("cinematic_mode") and not _chat_open:
		set_cinematic(not _cinematic)
		get_viewport().set_input_as_handled()
		return
	if _chat_open:
		if event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
			close_chat()
			get_viewport().set_input_as_handled()
		return
	if _blocked_by_menu():
		return
	if event.is_action_pressed("squad_chat") and not event.is_echo():
		open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("push_to_talk") and not event.is_echo():
		_ptt_held_key = true
		comms.begin_voice()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("push_to_talk") and _ptt_held_key:
		_ptt_held_key = false
		comms.end_voice()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_command_log") and not event.is_echo():
		_log_visible = not _log_visible
		SquadAIConfig.show_command_log = _log_visible
		SquadAIConfig.save()
		queue_redraw()


func _blocked_by_menu() -> bool:
	if get_tree().paused:
		return true
	for grp in ["title_screen", "pause_menu", "options_screen", "leaderboard_screen", "results_screen"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				return true
	return false
```
**Replace with:**
```gdscript
func _input(event: InputEvent) -> void:
	if comms == null:
		return
	if _ptt_held_key and event.is_action_released("push_to_talk"):
		_ptt_held_key = false
		comms.end_voice()
		get_viewport().set_input_as_handled()
		return
	if _chat_open:
		if event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
			close_chat()
			get_viewport().set_input_as_handled()
		return
	if _blocked_by_menu():
		return
	if event.is_action_pressed("cinematic_mode") and not event.is_echo():
		set_cinematic(not _cinematic)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("squad_chat") and not event.is_echo():
		open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("push_to_talk") and not event.is_echo():
		_ptt_held_key = true
		comms.begin_voice()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_command_log") and not event.is_echo():
		_log_visible = not _log_visible
		SquadAIConfig.show_command_log = _log_visible
		SquadAIConfig.save()
		queue_redraw()


func _blocked_by_menu() -> bool:
	if not is_inside_tree() or get_tree() == null or get_tree().paused:
		return true
	if not _cinematic and not is_visible_in_tree():
		return true
	for grp in ["title_screen", "pause_menu", "options_screen", "leaderboard_screen", "results_screen", "loading_screen"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				return true
			if n is CanvasLayer and (n as CanvasLayer).visible:
				return true
	var mc: Node = get_tree().get_first_node_in_group("main_controller")
	if mc != null and (mc.get("_loading") != null or not bool(mc.get("level_ready"))):
		return true
	if get_tree().root != null:
		for ch in get_tree().root.get_children():
			if ch is LoadingScreen and (ch as CanvasLayer).visible:
				return true
	return false
```

- **Postcondition**: `F10` cannot fire on Title/Pause/Loading/hidden HUD (`!is_visible_in_tree()`), toggling `F10` off during cinematic mode still works (`_cinematic == true`), and releasing `V` (`push_to_talk`) always stops recording even if chat or a menu opened mid-hold.

---

### Step 7 — Sync Ivo `Mending Light` Description (`35%` -> `18%`) While Keeping Autonomous Mending Disabled (`ALY-22`, `REQ-20`)
- **Prerequisites**: Step 4 complete.

**Target:** `data/allies/03_ivo.tres`
**Action:** Replace block
**Find:**
```tres
[sub_resource type="Resource" id="skill_mending_light"]
script = ExtResource("2_skill")
id = "mending_light"
display_name = "Mending Light"
description = "Heals an ally or the player for 35% of their max HP (range 14 m)."
aliases = Array[String](["heal", "mend", "mending light", "patch up", "fix up", "healing"])
effect = "mending_light"
target_kind = "ally"
cooldown = 12
cast_range = 14
radius = 0
power = 0.18
duration = 0
auto_use = ""
```
**Replace with:**
```tres
[sub_resource type="Resource" id="skill_mending_light"]
script = ExtResource("2_skill")
id = "mending_light"
display_name = "Mending Light"
description = "Heals an ally or the player for 18% of their max HP (range 14 m)."
aliases = Array[String](["heal", "mend", "mending light", "patch up", "fix up", "healing"])
effect = "mending_light"
target_kind = "ally"
cooldown = 12
cast_range = 14
radius = 0
power = 0.18
duration = 0
auto_use = "never"
```

- **Postcondition**: `data/allies/03_ivo.tres` matches `power = 0.18`, `description` says `18%`, and `auto_use = "never"` disables autonomous mending bursts per `REQ-20`.

---

### Step 8 — Create Dedicated Headless Regression Suite (`tests/friends_ai_bugfix_regression_test.gd`)
- **Prerequisites**: Steps 1–7 applied.
- **Precondition**: `tests/friends_ai_bugfix_regression_test.gd` must not already exist.

**Target:** `tests/friends_ai_bugfix_regression_test.gd`
**Action:** Create
**Content:**
```gdscript
extends SceneTree
## Headless bugfix regression suite for Friends & Squad AI (ALY-01 .. ALY-24).
## Uses explicit preload constants (AGENTS.md §3) so --check-only and headless runs work
## independently of editor class-cache state.
## Usage: godot --headless --path . -s res://tests/friends_ai_bugfix_regression_test.gd

const RealmManagerScript := preload("res://scripts/core/realm_manager.gd")
const EncounterDirectorScript := preload("res://scripts/core/encounter_director.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const PlayerScript := preload("res://scripts/player/player_controller.gd")
const ManagerScript := preload("res://scripts/allies/ally_squad_manager.gd")
const AllyScript := preload("res://scripts/allies/squad_ally.gd")
const WorldIntelScript := preload("res://scripts/allies/world_intel.gd")
const CommandScript := preload("res://scripts/allies/squad_command.gd")
const ParserScript := preload("res://scripts/allies/squad_command_parser.gd")
const CommsHudScript := preload("res://scripts/ui/squad_comms_hud.gd")
const SquadAIConfigScript := preload("res://addons/parallax_squad_ai/config.gd")
const AllyProfileScript := preload("res://scripts/allies/ally_profile.gd")
const EnemyAIScript := preload("res://scripts/enemies/enemy_ai.gd")
const PhantomScript := preload("res://scripts/enemies/phantom_twin.gd")
const ShieldedScript := preload("res://scripts/enemies/shielded_guard.gd")
const PitKillZoneScript := preload("res://scripts/environment/pit_kill_zone.gd")
const BreakableScript := preload("res://scripts/environment/breakable_prop.gd")
const LoadingScreenScript := preload("res://scripts/ui/loading_screen.gd")

var _fails: int = 0
var _checks: int = 0


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[friends_ai] %s %s %s" % ["PASS" if ok else "FAIL", test_name, detail])


func _initialize() -> void:
	SquadAIConfigScript.force_offline()
	create_timer(45.0).timeout.connect(func() -> void:
		print("[friends_ai] WATCHDOG TIMEOUT")
		quit(2))
	_run()


func _make_test_enemy(script_res: GDScript, pos: Vector3, node_name: String) -> EnemyAI:
	var e: EnemyAI = script_res.new() as EnemyAI
	e.name = node_name
	e.section_id = EncounterDirectorScript.Section.ENTRY
	e.encounter_id = ""
	e.use_squad_tactics = false
	e.patrol_radius = 0.0
	var col := CollisionShape3D.new()
	col.name = "BodyCollider"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0.0, 0.9, 0.0)
	e.add_child(col)
	var vis := Node3D.new()
	vis.name = "VisualRoot"
	e.add_child(vis)
	var mr := Node3D.new()
	mr.name = "ModelRoot"
	vis.add_child(mr)
	e.position = pos
	return e


func _run() -> void:
	var harness := Node3D.new()
	harness.name = "Harness"
	root.add_child(harness)

	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = RealmManagerScript.LAYER_WORLD_SHARED
	var floor_cs := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(400.0, 1.0, 400.0)
	floor_cs.shape = floor_box
	floor_cs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_cs)
	harness.add_child(floor_body)

	var rm: RealmManager = RealmManagerScript.new() as RealmManager
	rm.handle_input_directly = false
	harness.add_child(rm)

	var ed: EncounterDirector = EncounterDirectorScript.new() as EncounterDirector
	ed.auto_save_on_checkpoint = false
	harness.add_child(ed)

	var player: PlayerController = (PlayerScene as PackedScene).instantiate() as PlayerController
	player.position = Vector3.ZERO
	harness.add_child(player)
	var cam: Camera3D = player.find_child("Camera3D", true, false) as Camera3D
	if cam != null:
		cam.current = true
	player.set_facing_direction(Vector3.FORWARD)
	player.camera_yaw = 0.0
	player.camera_pitch = 0.0

	var mgr: AllySquadManager = ManagerScript.new() as AllySquadManager
	mgr.spawn_allies = true
	harness.add_child(mgr)

	for _f in range(5):
		await physics_frame

	var brannoc: SquadAlly = mgr.find_ally("Brannoc")
	var sera: SquadAlly = mgr.find_ally("Sera")
	var ivo: SquadAlly = mgr.find_ally("Ivo")
	if brannoc == null or sera == null or ivo == null:
		_check("harness_spawned_allies", false, "missing allies")
		quit(1)
		return

	# ---- ALY-01 & ALY-19 & ALY-20: WorldIntel camera visibility, node_for_id, resolve guards ----
	var intel: WorldIntel = mgr.intel
	var e_vis: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, -50.0), "Test_Vis50")
	var e_far: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, -160.0), "Test_Far160")
	var e_back: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, 20.0), "Test_Back20")
	var e_phant: PhantomTwin = _make_test_enemy(PhantomScript, Vector3(2.0, 0.0, -15.0), "Test_Phant") as PhantomTwin
	harness.add_child(e_vis)
	harness.add_child(e_far)
	harness.add_child(e_back)
	harness.add_child(e_phant)
	await physics_frame
	intel.refresh()
	var near30: Array[EnemyAI] = mgr._active_enemies_near(Vector3.ZERO, 30.0)
	_check("aly01_camera_visible_targeting",
		intel.is_camera_visible(e_vis)
		and not intel.is_camera_visible(e_far)
		and not intel.is_camera_visible(e_back)
		and not intel.is_camera_visible(e_phant)
		and near30.has(e_vis)
		and not near30.has(e_phant),
		"vis=%s far=%s back=%s phant=%s" % [intel.is_camera_visible(e_vis), intel.is_camera_visible(e_far), intel.is_camera_visible(e_back), intel.is_camera_visible(e_phant)])

	var vis_id: String = intel.id_of(e_vis)
	e_vis.set_section_enabled(false)
	_check("aly19_node_for_id_active_in_tree", intel.node_for_id(vis_id) == null, "inactive enemy should return null")
	e_vis.set_section_enabled(true)
	await physics_frame
	intel.refresh()
	var e_temp: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(1.0, 0.0, -8.0), "Test_Temp")
	harness.add_child(e_temp)
	await physics_frame
	intel.refresh()
	e_temp.queue_free()
	await process_frame
	harness.remove_child(player)
	var resolved_no_player: EnemyAI = intel.resolve("nearest", null)
	_check("aly20_world_intel_resolve_null_and_valid_guards", resolved_no_player == e_vis or resolved_no_player == e_back, str(resolved_no_player))
	harness.add_child(player)
	e_far.queue_free()
	e_back.queue_free()
	e_phant.queue_free()
	await process_frame

	# ---- ALY-02: Combo substitute freed/downed guards + mine cleanup & planted_t reset ----
	var lure_res: String = mgr.issue({"verb": "combo_lure_detonate", "target": "nearest"}, "test")
	var cid: int = mgr._combo_seq
	var rec: Dictionary = mgr._combos.get(cid, {}) as Dictionary
	var trapper_ally: SquadAlly = rec.get("parts", {}).get("trapper", null) as SquadAlly
	if trapper_ally != null:
		trapper_ally.plant_mine(Vector3(3.0, 0.0, -3.0))
	rec["planted_t"] = 2.5
	var k_dummy := AllyScript.new() as SquadAlly
	var dum_prof := AllyProfileScript.new() as AllyProfile
	dum_prof.ally_name = "Dummy"
	k_dummy.setup(dum_prof, mgr, 9)
	rec["parts"]["trapper"] = k_dummy
	rec["planted_t"] = 2.5
	k_dummy.free()
	mgr._substitute(cid, "trapper")
	var mine_cleared: bool = trapper_ally == null or trapper_ally.get_mine_position() == Vector3.INF
	var planted_reset: bool = float(mgr._combos.get(cid, {}).get("planted_t", -1.0)) < 0.0
	if trapper_ally != null:
		trapper_ally._go_down()
		mine_cleared = mine_cleared and trapper_ally.get_mine_position() == Vector3.INF
		trapper_ally.revive(1.0)
	mgr._abort_combo(cid, "cleanup")
	_check("aly02_substitute_and_mine_cleanup", not lure_res.is_empty() and mine_cleared and planted_reset, "mine=%s planted_reset=%s" % [mine_cleared, planted_reset])
	mgr.issue({"verb": "stop", "allies": ["all"]}, "test")
	e_vis.queue_free()
	await process_frame

	# ---- ALY-03: _run_lurer fallback & done outside luring ----
	var e_lure: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, -6.0), "Test_LurerTarget")
	harness.add_child(e_lure)
	await physics_frame
	sera.global_position = Vector3(0.0, 3.0, -3.0)
	var lcmd := CommandScript.make("combo_lure_detonate", {}, "test")
	lcmd.combo_id = 99
	lcmd.combo_part = "lurer"
	sera.assign(lcmd)
	lcmd.data["point"] = Vector3(0.0, 0.0, -2.0)
	lcmd.data["enemy"] = e_lure
	lcmd.step = "fallback"
	sera._run_lurer(0.1, player, lcmd)
	var moved_in_fallback: bool = sera.global_position.y < 3.0 or sera.velocity.length() > 0.01
	lcmd.data["done"] = true
	sera._run_lurer(0.05, player, lcmd)
	_check("aly03_lurer_fallback_and_done", moved_in_fallback and lcmd.done, "moved=%s done=%s" % [moved_in_fallback, lcmd.done])
	e_lure.queue_free()
	await process_frame

	# ---- ALY-04 & ALY-05: Downed realm layer + pit rescue + revive timeout + wall-occluded catchup + REQ-16 ----
	rm.force_realm(RealmManagerScript.Realm.MIRROR, false)
	brannoc.global_position = Vector3(0.0, 0.0, -2.0)
	brannoc._go_down()
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	var keeps_mirror_mask: bool = (brannoc.collision_mask & RealmManagerScript.LAYER_WORLD_MIRROR) != 0
	brannoc.global_position = Vector3(0.0, -25.0, -2.0)
	brannoc._process_downed(0.05)
	var rescued_from_void: bool = brannoc.global_position.y > -2.0
	var rev_cmd := CommandScript.make("revive", {"target": "Brannoc"}, "test")
	sera.assign(rev_cmd)
	brannoc.global_position = Vector3(40.0, 0.0, 0.0)
	rev_cmd.timer = 10.5
	sera._revive_target(brannoc, 0.05, rev_cmd)
	_check("aly04_downed_safety_and_revive_timeout", keeps_mirror_mask and rescued_from_void and rev_cmd.done,
		"mask=%s rescued=%s rev_done=%s" % [keeps_mirror_mask, rescued_from_void, rev_cmd.done])
	brannoc.revive(1.0)
	mgr.regroup(true)

	# ALY-05 + REQ-16: wall occlusion blocks LOS ray so blink fires; distant attack order (60m) exempts from blink
	var wall := StaticBody3D.new()
	wall.name = "CatchupWall"
	wall.collision_layer = RealmManagerScript.LAYER_WORLD_SHARED
	var wall_cs := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(12.0, 6.0, 1.0)
	wall_cs.shape = wall_box
	wall.add_child(wall_cs)
	wall.position = Vector3(0.0, 2.0, -12.0)
	harness.add_child(wall)
	await physics_frame
	player.global_position = Vector3.ZERO
	player.set_facing_direction(Vector3.FORWARD)
	player.camera_yaw = 0.0
	player.camera_pitch = 0.0
	await physics_frame
	brannoc.assign(CommandScript.make("follow", {}, "test"))
	brannoc.global_position = Vector3(0.0, 0.0, -25.0)
	brannoc._catch_up(player)
	var blinked_past_wall: bool = brannoc.global_position.distance_to(player.global_position) < 8.0
	var distant_cmd := CommandScript.make("attack", {"target": "nearest"}, "test")
	sera.assign(distant_cmd)
	sera.global_position = Vector3(0.0, 0.0, -60.0)
	sera._catch_up(player)
	var req16_exempt: bool = sera.global_position.z < -55.0
	_check("aly05_catchup_wall_los_and_req16_exemption", blinked_past_wall and req16_exempt,
		"blinked=%s req16=%s" % [blinked_past_wall, req16_exempt])
	wall.queue_free()
	mgr.regroup(true)
	await process_frame

	# ---- ALY-06: Rally flag survives assign(), queue rally cleared, regroup(true) resets ----
	player.health = int(player.max_health * 0.2)
	var e_threat: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, -4.0), "Test_RallyFoe")
	harness.add_child(e_threat)
	await physics_frame
	e_threat.apply_taunt(player, -1.0, 4.0)
	mgr._start_rally(player)
	var cut_skill := CommandScript.make("skill", {"skill": "war_cry"}, "test")
	if brannoc.current != null:
		brannoc.enqueue(brannoc.current, true)
	brannoc.assign(cut_skill)
	player.health = player.max_health
	e_threat.queue_free()
	await physics_frame
	mgr._update_rally(player, 3.0)
	var rally_queued_cleared: bool = brannoc.queue.is_empty()
	mgr._start_rally(player)
	mgr.regroup(true)
	_check("aly06_rally_queue_and_regroup_cleanup", rally_queued_cleared and mgr._rally.is_empty() and mgr._rally_cooldown.is_empty(),
		"q_empty=%s rally_empty=%s" % [rally_queued_cleared, mgr._rally.is_empty()])

	# ---- ALY-07, ALY-08, ALY-10: Stop/Strategy abort effects & PANIC protection ----
	ivo.begin_nuke(Vector3(0.0, 0.0, -4.0))
	var flip_cmd := CommandScript.make("emote", {"text": "backflip"}, "test")
	sera.assign(flip_cmd)
	sera._process_action(0.3)
	mgr.issue({"verb": "stop", "allies": ["all"]}, "test")
	var vis_sera: Node3D = sera.get_node_or_null("VisualRoot") as Node3D
	var effects_aborted: bool = ivo._action.is_empty() and (ivo._cast_ring == null or not ivo._cast_ring.visible) and sera._action.is_empty() and (vis_sera == null or is_zero_approx(vis_sera.rotation.x))
	_check("aly07_stop_and_strategy_abort_effects", effects_aborted, "ivo_act=%s sera_act=%s" % [ivo._action, sera._action])

	var e_strat: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, -5.0), "Test_StratFoe")
	harness.add_child(e_strat)
	await physics_frame
	brannoc.start_charge(e_strat, Callable())
	mgr.issue({"verb": "ceasefire", "allies": ["Brannoc"]}, "test")
	var charge_cleared: bool = brannoc._dash_timer == 0.0 and not brannoc._dash_hit_cb.is_valid()
	_check("aly10_abort_all_actions_spins_flips_charges", charge_cleared, "dash_t=%s" % brannoc._dash_timer)
	var c_res: String = mgr.issue({"verb": "combo_kite_nuke", "target": "nearest"}, "test")
	var strat_res: String = mgr.execute_strategy("focus_fire", "nearest", mgr.get_living(), "test")
	var panic_kept: bool = brannoc.current != null and brannoc.current.verb == "ceasefire"
	var combos_cleared: bool = mgr.get_active_combos().is_empty()
	_check("aly08_strategy_respects_panic_and_cancels_combos", panic_kept and combos_cleared, "c=%s s=%s panic=%s" % [c_res, strat_res, panic_kept])
	mgr.issue({"verb": "stop", "allies": ["all"]}, "test")

	# ---- ALY-09: Downed ally cannot take or keep revive order ----
	sera._go_down()
	brannoc._go_down()
	var rev_route: String = mgr._route(brannoc, CommandScript.make("revive", {"target": "Sera"}, "test"))
	var rev_sub_res: String = mgr.issue({"verb": "revive", "allies": ["Brannoc"], "target": "Sera"}, "test")
	_check("aly09_downed_ally_revive_substitution", rev_route == "is down" and rev_sub_res.begins_with("Ivo"), "route=%s res=%s" % [rev_route, rev_sub_res])
	mgr.regroup(true)

	# ---- ALY-11: Area taunt collects idle enemies & single-target timeout ----
	e_strat.global_position = Vector3(0.0, 0.0, -5.0)
	brannoc.global_position = Vector3(0.0, 0.0, -1.0)
	var t_area := CommandScript.make("taunt", {"area": true}, "test")
	brannoc.assign(t_area)
	brannoc._run_taunt_cmd(0.05, player, t_area)
	var area_pulled: bool = t_area.done and e_strat.get_current_target() == brannoc
	var t_miss := CommandScript.make("taunt", {"target": "nearest"}, "test")
	brannoc.assign(t_miss)
	e_strat.global_position = Vector3(0.0, 0.0, -25.0)
	t_miss.data["enemy"] = e_strat
	t_miss.timer = 12.5
	brannoc._run_taunt_cmd(0.05, player, t_miss)
	_check("aly11_taunt_area_fallback_and_timeout", area_pulled and t_miss.done, "area=%s timeout=%s" % [area_pulled, t_miss.done])

	# ---- ALY-12: Dead player ignored by heals, wards, _friends(), _weakest_friend_name() ----
	player.current_state = PlayerScript.State.DEAD
	player.health = 0
	var mend_skill: AllySkill = ivo.profile.find_skill("mending_light")
	var ward_skill: AllySkill = ivo.profile.find_skill("mirror_ward")
	var dead_friends_ok: bool = not ivo._friends().has(player)
	var dead_mend_blocked: bool = not ivo._skill_mend(mend_skill, player)
	var dead_ward_blocked: bool = not ivo._skill_ward(ward_skill, player)
	var weakest_not_dead_player: bool = mgr._weakest_friend_name() != "player"
	_check("aly12_ignore_dead_player_in_heals_wards", dead_friends_ok and dead_mend_blocked and dead_ward_blocked and weakest_not_dead_player,
		"friends=%s mend=%s ward=%s weakest=%s" % [dead_friends_ok, dead_mend_blocked, dead_ward_blocked, mgr._weakest_friend_name()])
	player.current_state = PlayerScript.State.LOCOMOTION
	player.health = player.max_health

	# ---- ALY-13: Ranged wall-backed fires & hold spot no oscillation ----
	var back_wall := StaticBody3D.new()
	back_wall.collision_layer = RealmManagerScript.LAYER_WORLD_SHARED
	var bw_cs := CollisionShape3D.new()
	var bw_box := BoxShape3D.new()
	bw_box.size = Vector3(10.0, 4.0, 1.0)
	bw_cs.shape = bw_box
	back_wall.add_child(bw_cs)
	back_wall.position = Vector3(0.0, 1.0, 1.0)
	harness.add_child(back_wall)
	await physics_frame
	ivo.global_position = Vector3(0.0, 0.0, 0.1)
	ivo._attack_cd = 0.0
	e_strat.global_position = Vector3(0.0, 0.0, -3.5)
	ivo._ranged_engage(e_strat, 0.05)
	var fired_when_backed: bool = ivo._attack_cd > 0.0
	var hold_cmd := CommandScript.make("hold", {"spot": Vector3(0.0, 0.0, 0.1), "engage_r": 4.0}, "test")
	ivo.assign(hold_cmd)
	ivo.global_position = Vector3(0.0, 0.0, 0.1)
	ivo._run_hold(0.05, hold_cmd)
	var held_spot: bool = ivo.global_position.distance_to(Vector3(0.0, 0.0, 0.1)) < 0.2 and ivo.velocity.length() < 0.2
	_check("aly13_ranged_wall_and_hold_no_oscillation", fired_when_backed and held_spot, "fired=%s held=%s" % [fired_when_backed, held_spot])
	back_wall.queue_free()

	# ---- ALY-14: _run_skill() aborts mid-approach if enemy dies/unhittable or ally downed ----
	var sk_cmd := CommandScript.make("skill", {"skill": "chain_arc"}, "test")
	ivo.assign(sk_cmd)
	sk_cmd.data["target_node"] = e_strat
	e_strat.is_dead = true
	ivo._run_skill(0.05, player, sk_cmd)
	var skill_enemy_aborted: bool = sk_cmd.done
	e_strat.is_dead = false
	var sk_ally_cmd := CommandScript.make("skill", {"skill": "mirror_ward", "target": "Brannoc"}, "test")
	ivo.assign(sk_ally_cmd)
	sk_ally_cmd.data["target_node"] = brannoc
	brannoc.is_downed = true
	ivo._run_skill(0.05, player, sk_ally_cmd)
	brannoc.is_downed = false
	_check("aly14_run_skill_target_validity", skill_enemy_aborted and sk_ally_cmd.done, "en=%s ally=%s" % [skill_enemy_aborted, sk_ally_cmd.done])

	# ---- ALY-15: _run_position() left vs right uninverted ----
	player.global_position = Vector3.ZERO
	player.set_facing_direction(Vector3.FORWARD)
	var left_cmd := CommandScript.make("position", {"spot": "left"}, "test")
	var right_cmd := CommandScript.make("position", {"spot": "right"}, "test")
	brannoc.global_position = Vector3.ZERO
	brannoc.assign(left_cmd)
	brannoc._run_position(0.05, player, left_cmd)
	var left_spot: Vector3 = left_cmd.data.get("spot_cache", Vector3.ZERO) as Vector3
	brannoc.assign(right_cmd)
	brannoc._run_position(0.05, player, right_cmd)
	var right_spot: Vector3 = right_cmd.data.get("spot_cache", Vector3.ZERO) as Vector3
	_check("aly15_position_left_right_uninverted", left_spot.x < -0.5 and right_spot.x > 0.5, "left=%s right=%s" % [left_spot, right_spot])

	# ---- ALY-16, ALY-17, ALY-18: Command parser fixes ----
	var ctx: Dictionary = mgr.get_parser_context()
	var names: Array = mgr.get_ally_names()
	var p_hex: Array = ParserScript.parse("kill the hexcaster", names, ctx)
	var p_sg: Array = ParserScript.parse("kill the shielded guard", names, ctx)
	var p_bg: Array = ParserScript.parse("Brannoc guard Ivo", names, ctx)
	_check("aly16_parser_word_boundaries",
		String(p_hex[0].get("verb", "")) == "attack"
		and String(p_sg[0].get("verb", "")) == "attack"
		and String(p_bg[0].get("verb", "")) == "bodyguard",
		"hex=%s sg=%s bg=%s" % [p_hex, p_sg, p_bg])

	var p_warden: Array = ParserScript.parse("attack the warden", names, ctx)
	var p_health: Array = ParserScript.parse("what is your health", names, ctx)
	var p_archer: Array = ParserScript.parse("shoot the archer", names, ctx)
	_check("aly17_match_skill_trailing_boundary",
		String(p_warden[0].get("verb", "")) == "attack"
		and String(p_health[0].get("verb", "")) == "status"
		and String(p_archer[0].get("verb", "")) == "ranged",
		"w=%s h=%s a=%s" % [p_warden, p_health, p_archer])

	var p_ward_b: Array = ParserScript.parse("Ivo, ward Brannoc", names, ctx)
	_check("aly18_addressed_skill_first_verb_pos",
		p_ward_b.size() == 1
		and String(p_ward_b[0].get("verb", "")) == "skill"
		and (p_ward_b[0].get("allies", []) as Array) == ["Ivo"]
		and String(p_ward_b[0].get("target", "")) == "Brannoc",
		str(p_ward_b))

	# ---- ALY-21: SquadCommsHUD menu/loading/visibility gating & PTT release ----
	var hud_layer := CanvasLayer.new()
	harness.add_child(hud_layer)
	var comms_hud: SquadCommsHUD = CommsHudScript.new() as SquadCommsHUD
	hud_layer.add_child(comms_hud)
	await physics_frame
	hud_layer.visible = false
	var ev_f10 := InputEventAction.new()
	ev_f10.action = "cinematic_mode"
	ev_f10.pressed = true
	comms_hud._input(ev_f10)
	var f10_blocked_hidden: bool = not comms_hud._cinematic
	hud_layer.visible = true
	var loader := LoadingScreenScript.new()
	root.add_child(loader)
	comms_hud._input(ev_f10)
	var f10_blocked_loading: bool = not comms_hud._cinematic
	loader.free()
	comms_hud._ptt_held_key = true
	comms_hud._chat_open = true
	var ev_ptt_up := InputEventAction.new()
	ev_ptt_up.action = "push_to_talk"
	ev_ptt_up.pressed = false
	comms_hud._input(ev_ptt_up)
	comms_hud._chat_open = false
	PlayerScript.ui_input_locked = false
	_check("aly21_comms_hud_input_gating_and_ptt_release",
		f10_blocked_hidden and f10_blocked_loading and not comms_hud._ptt_held_key,
		"hidden=%s loading=%s ptt=%s" % [f10_blocked_hidden, f10_blocked_loading, comms_hud._ptt_held_key])

	# ---- ALY-22: 03_ivo.tres description 18% & no autonomous mending ----
	var mend_prof: AllySkill = ivo.profile.find_skill("mending_light")
	_check("aly22_ivo_mending_description_and_no_auto",
		mend_prof != null
		and is_equal_approx(mend_prof.power, 0.18)
		and mend_prof.description.contains("18%")
		and (mend_prof.auto_use.is_empty() or mend_prof.auto_use == "never"),
		mend_prof.description if mend_prof != null else "missing")

	# ---- ALY-23: _chain_arc_hop() checks apply_damage bool & continues on mid-flight death ----
	var sg_enemy: ShieldedGuard = _make_test_enemy(ShieldedScript, Vector3(0.0, 0.0, -4.0), "Test_Shielded") as ShieldedGuard
	sg_enemy.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	var e_dead_mid: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(2.0, 0.0, -4.0), "Test_DeadMid")
	var e_hop3: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(4.0, 0.0, -4.0), "Test_Hop3")
	harness.add_child(sg_enemy)
	harness.add_child(e_dead_mid)
	harness.add_child(e_hop3)
	await physics_frame
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	ivo.global_position = Vector3(0.0, 0.0, -1.0)
	var arc_skill: AllySkill = ivo.profile.find_skill("chain_arc")
	var hops: Array[EnemyAI] = [sg_enemy, e_dead_mid, e_hop3]
	var mults: Array[float] = [1.0, 0.72, 0.5]
	e_dead_mid.is_dead = true
	ivo._chain_arc_hop(arc_skill, hops, mults, 0, ivo.global_position + Vector3.UP)
	await create_timer(0.8).timeout
	_check("aly23_chain_arc_landed_guard_and_midflight_hops",
		not sg_enemy.is_stunned() and e_hop3.health < e_hop3.max_health,
		"sg_stun=%s hop3_hp=%d/%d" % [sg_enemy.is_stunned(), e_hop3.health, e_hop3.max_health])

	# ---- ALY-24: _run_destroy() checks vertical Y reach (3.6 m ledge unreachable from ground) ----
	var prop := BreakableScript.new() as BreakableProp
	prop.prop_kind = BreakableScript.PropKind.WEAK_STONE_SUPPORT
	prop.position = Vector3(0.0, 3.6, -2.0)
	harness.add_child(prop)
	await physics_frame
	brannoc.global_position = Vector3(0.0, 0.0, -2.0)
	var dst_cmd := CommandScript.make("destroy", {}, "test")
	brannoc.assign(dst_cmd)
	dst_cmd.data["prop"] = prop
	brannoc._run_destroy(0.05, player, dst_cmd)
	var stayed_intact_below: bool = prop.current_state == BreakableScript.PropState.INTACT
	brannoc.global_position = Vector3(0.0, 3.6, -1.5)
	brannoc._run_destroy(0.05, player, dst_cmd)
	var smashed_on_ledge: bool = dst_cmd.done and brannoc._action == "attack"
	_check("aly24_destroy_vertical_reach_check", stayed_intact_below and smashed_on_ledge,
		"below_intact=%s ledge_smashed=%s" % [stayed_intact_below, smashed_on_ledge])

	harness.queue_free()
	await process_frame
	print("[friends_ai] SUMMARY %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
```

- **Postcondition**: `tests/friends_ai_bugfix_regression_test.gd` exists, passes `--check-only`, and executes all 24 `ALY-01..24` regression assertions headlessly.

---

### Step 9 — Synchronize `MEMORY/` Knowledge Base & Changelog (`AGENTS.md` Rule 1.3)
- **Prerequisites**: Steps 1–8 applied.

#### Edit 9A — Sync `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` (Lines 188, 213, 218-219)
**Target:** `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`
**Action:** Replace block
**Find:**
```markdown
- All allies: `damage_taken_mult 0.6`, out-of-combat regen (×3 while retreating), formation wedge out of the camera line (`(-2.5,0.3)`, `(2.7,0.8)`, `(-2.2,2.4)`…), catch-up blink when > 20 m (30 on missions) / stuck 2 s / a level below. Personalities only change voice & flavour lines (incl. banter every 50–95 s out of combat and complaints at repeated silly orders).
```
**Replace with:**
```markdown
- All allies: `damage_taken_mult 0.6`, out-of-combat regen (×3 while retreating; base rates `Brannoc 1.5`, `Sera 0.95`, `Ivo 0.88` -> `>= 125 s` full heal), formation wedge out of the camera line (`(-2.5,0.3)`, `(2.7,0.8)`, `(-2.2,2.4)`…), catch-up blink when > `19.5 m` (`FOLLOW_LEASH`, `30 m` on missions, `150 m` exemption on distant/camera-visible orders) / stuck 2 s / fallen below (`y - 6 m` or `PitKillZone`), with camera-frustum LOS ray checking world collision layers rather than `LAYER_PLAYER`. Personalities only change voice & flavour lines (incl. banter every 50–95 s out of combat and complaints at repeated silly orders).
```

**Target:** `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`
**Action:** Replace block
**Find:**
```markdown
| Ivo | Mending Light | heal ally / player 35 % max HP (≤14 m) | 12 s | ally_low (<40 %) |
| Ivo | Mirror Ward | 40-point damage ward for 8 s on an ally or the player | 15 s | ally_pressed (targeted by ≥2) |
| Ivo | Chain Arc | 22 / 16 / 11 dmg bouncing between up to 3 enemies ≤5 m apart, 0.8 s stun each | 7 s | engaged |

- **Strategies** (`SquadStrategies.LIST`, 20): focus_fire, pincer (flanks at ±100°), surround (even ring), hammer_and_anvil, shield_wall, hold_the_line (line 3 m toward the threat, 2.2 m spacing), divide_and_conquer (distinct targets), tank_and_spank, pick_off_wounded, casters_first, protect_the_weak, bait_and_ambush (ambush springs when an aggroed enemy enters 4.5 m), guerrilla, crowd_control, overwatch (artillery hangs 6 m back and fires its ranged skills), escort, retreat_and_regroup, distract_and_backstab, kite_train, berserker_rush. Strategies replace current non-panic orders; roles fall back to `any`, so any ally count works.
- **Targeting by description**: every order's target goes through `WorldIntel.resolve` — enemy IDs (`E3`, shown over each enemy), type, colour, weapon, size, side (left/right/ahead/behind of the player), "near Sera", "whoever is hitting Ivo", nearest/farthest/strongest/weakest.
- **DOWNED**: at 0 HP; targetable = false, label "DOWN — revive". Revive by the player (Interact within `2.6 m`, `50 %` HP) or by order (`2.2 s` channel, `45 %`). Player respawn regroups and fully heals the squad.
```
**Replace with:**
```markdown
| Ivo | Mending Light | heal ally / player 18 % max HP (≤14 m, manual/command only) | 12 s | never |
| Ivo | Mirror Ward | 40-point damage ward for 8 s on an ally or the player | 15 s | ally_pressed (targeted by ≥2) |
| Ivo | Chain Arc | 22 / 16 / 11 dmg bouncing between up to 3 enemies ≤5 m apart, 0.8 s stun each (only on landed damage; hops continue if earlier target dies) | 7 s | engaged |

- **Strategies** (`SquadStrategies.LIST`, 20): focus_fire, pincer (flanks at ±100°), surround (even ring), hammer_and_anvil, shield_wall, hold_the_line (line 3 m toward the threat, 2.2 m spacing), divide_and_conquer (distinct targets), tank_and_spank, pick_off_wounded, casters_first, protect_the_weak, bait_and_ambush (ambush springs when an aggroed enemy enters 4.5 m), guerrilla, crowd_control, overwatch (artillery hangs 6 m back and fires its ranged skills), escort, retreat_and_regroup, distract_and_backstab, kite_train, berserker_rush. Strategies replace current non-panic orders (never override `PANIC` orders and cancel overridden combos); roles fall back to `any`, so any ally count works.
- **Targeting by description**: every order's target goes through `WorldIntel.resolve` — enemy IDs (`E3`, shown over each enemy; `node_for_id()` requires active & in-tree), type, colour, weapon, size, side (left/right/ahead/behind of the player), "near Sera", "whoever is hitting Ivo", nearest/farthest/farther/strongest/weakest, plus `WorldIntel.is_camera_visible()` (`<= 140 m` active frustum targets). Dead players (`State.DEAD`) are excluded from heals, wards, and `_weakest_friend_name()`.
- **DOWNED**: at 0 HP; targetable = false, label "DOWN — revive". Downed allies keep both Reality & Mirror floor layers (`Q`-safe), rescue from pits/voids (`_process_downed`), and substitute/reject ordered `revive` (`10 s` unreachable timeout prevents `MISSION` soft-locks). Revive by the player (Interact within `2.6 m`, `50 %` HP) or by order (`2.2 s` channel, `45 %`). Player respawn regroups and fully heals the squad (`_rally` & `_rally_cooldown` cleared on `regroup(true)`).
```

#### Edit 9B — Sync `MEMORY/05_UI_SCORING_AND_AUDIO.md` (Line 69 & Line 103)
**Target:** `MEMORY/05_UI_SCORING_AND_AUDIO.md`
**Action:** Replace block
**Find:**
```markdown
| **Right, mid** | Mic button / indicator (hold to talk; red level ring while recording, cyan spinner while transcribing, struck through when offline) | Voice modes | Clickable while the chat bar is open (cursor visible). |
```
**Replace with:**
```markdown
| **Right, mid** | Mic button / indicator (hold to talk; red level ring while recording, cyan spinner while transcribing, struck through when offline) | Voice modes | Clickable while the chat bar is open (cursor visible). `SquadCommsHUD._input()` processes `push_to_talk` release prior to early returns and gates `F10` / chat / log behind `_blocked_by_menu()` (menus, pause, `LoadingScreen`, `!is_visible_in_tree()`). |
```

**Target:** `MEMORY/05_UI_SCORING_AND_AUDIO.md`
**Action:** Replace block
**Find:**
```markdown
- **Offline** (no key): `SquadCommandParser` -> same commands. Best-effort natural language: typo tolerance (optimal-string-alignment ≤1, ≤2 for long words), ally skill names/aliases, strategy aliases (longest match wins; a skill named for an addressed ally beats a strategy), description targets (`desc:<clause>` resolved by WorldIntel), verb-less enemy mentions ("the purple one!", "E3") become attacks. Allies answer with profile voice lines. One message can mix everything: clauses split on then / ; / sentence ends and on `, and while but also plus` when BOTH sides hold an instruction (combo / strategy phrases containing "and" are protected), so "Brannoc jump twice, Sera get behind me and shoot the caster, everyone else hold the rear" yields three per-ally chains; trailing vocatives ("hold the rear Brannoc") address that ally; small talk becomes `chat`.
```
**Replace with:**
```markdown
- **Offline** (no key): `SquadCommandParser` -> same commands. Best-effort natural language: word-bounded rule matching (so `"cast"` never matches `"caster"`/`"hexcaster"`, `"guard"` never hijacks `"shielded guard"`, and skill aliases require full trailing boundaries so `"warden"`/`"health"`/`"archer"` never hijack into `"ward"`/`"heal"`/`"arc"`), `_addressed()` computes `first_verb_pos` across rules, skills, and strategies (`"Ivo, ward Brannoc"` keeps `"Brannoc"` as target), typo tolerance (optimal-string-alignment ≤1, ≤2 for long words), ally skill names/aliases, strategy aliases (longest match wins; a skill named for an addressed ally beats a strategy), description targets (`desc:<clause>` resolved by WorldIntel), verb-less enemy mentions ("the purple one!", "E3") become attacks. Allies answer with profile voice lines. One message can mix everything: clauses split on then / ; / sentence ends and on `, and while but also plus` when BOTH sides hold an instruction (combo / strategy phrases containing "and" are protected), so "Brannoc jump twice, Sera get behind me and shoot the caster, everyone else hold the rear" yields three per-ally chains; trailing vocatives ("hold the rear Brannoc") address that ally; small talk becomes `chat`.
```

#### Edit 9C — Append Dated Changelog Entry in `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`
**Target:** `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`
**Action:** Replace block
**Find:**
```markdown
- 2026-11-19: Stacked Dodge Chaining & Execution Shield Pierce - Implemented consecutive stacked dodge chaining in PlayerController (_process_dodge_state allows chaining past i-frames t_norm > 0.45; start_dodge accepts State.DODGE; buffer consumes seamlessly on finish). ShieldedGuard._modify_incoming_damage allows player_execution to bypass shield deflect. Verified with charged_heavy_test (18 checks), feel_and_movement_test (13 checks), combat_rules_test (10 checks), and restart_flow_test (PASS).
```
**Replace with:**
```markdown
- 2026-11-19: Stacked Dodge Chaining & Execution Shield Pierce - Implemented consecutive stacked dodge chaining in PlayerController (_process_dodge_state allows chaining past i-frames t_norm > 0.45; start_dodge accepts State.DODGE; buffer consumes seamlessly on finish). ShieldedGuard._modify_incoming_damage allows player_execution to bypass shield deflect. Verified with charged_heavy_test (18 checks), feel_and_movement_test (13 checks), combat_rules_test (10 checks), and restart_flow_test (PASS).
- **2026-11-20 (Friends & Squad AI Remediation, ALY-01..24)**: Implemented `WorldIntel.is_camera_visible()` (`<= 140 m`, `REQ-19`), active/in-tree `node_for_id()` & null/freed guards in `resolve()`; hardened `AllySquadManager._substitute()`/`_abort_combo()`/`_combo_coordinate()` (`is_instance_valid`, mine cleanup, `planted_t` reset), rally `args`/queue/regroup cleanup, `"stop"`/`execute_strategy()` effect abort & `PANIC` protection, `"revive"` downed substitution & `_route()` guard; fixed `SquadAlly` `_run_lurer()` fallback/done, downed realm-mask/pit rescue + `10 s` revive timeout, world-layer `_catch_up()` LOS ray + `REQ-16` `150 m` exemption, `_abort_current_effects()`, `_run_taunt_cmd()`, dead-player heal/ward exclusions, wall-backed ranged & spot-anchored hold/position/retreat defense, `_run_skill()` live validity, `"left"`/`"right"` inversion, `_chain_arc_hop()` landed-dmg stun & mid-flight hop continuation, and `_run_destroy()` vertical reach check; fixed `SquadCommandParser` word boundaries, skill trailing space, & skill/strategy `first_verb_pos`; fixed `SquadCommsHUD` `F10`/menu/`LoadingScreen`/visibility gating & PTT release; synced `03_ivo.tres` `mending_light` (`18%`, `auto_use = "never"`); added `tests/friends_ai_bugfix_regression_test.gd` and synced `MEMORY/03`, `05`, `07`.
```

- **Postcondition**: `MEMORY/03`, `MEMORY/05`, and `MEMORY/07` accurately document every Friends & Squad AI fix without creating extra `.md` files.

---

## E. Verification & Failure Handling

Run every command below in PowerShell from `D:\Desktop\Godot\parallax`.

| Ver ID | Command | Preconditions | Expected Pass Condition | Covers |
| :--- | :--- | :--- | :--- | :--- |
| **VER-01** | `foreach ($f in @("scripts/allies/world_intel.gd","scripts/allies/squad_command_parser.gd","scripts/allies/squad_ally.gd","scripts/allies/ally_squad_manager.gd","scripts/ui/squad_comms_hud.gd","tests/friends_ai_bugfix_regression_test.gd","tests/squad_ai_unit_test.gd","tests/squad_ai_windowed_test.gd","tests/voice_pipeline_test.gd")) { Write-Host "CHECK $f"; & "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" --check-only -s "res://$f"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }` | Steps 1–8 applied | Exit code `0`; zero `SCRIPT ERROR` or parser warning lines on any script. | `ALY-01..24` |
| **VER-02** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/friends_ai_bugfix_regression_test.gd` | Steps 1–8 applied | Exit code `0`; prints `[friends_ai] SUMMARY <N> checks, 0 failed` with all checks `PASS` (`ALY-01..24`). | `ALY-01..24`, `REQ-16`, `REQ-19`, `REQ-20` |
| **VER-03** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/squad_ai_unit_test.gd` | Steps 1–7 applied | Exit code `0`; prints `[unit] SUMMARY <N> checks, 0 failed`. | `ALY-01`, `ALY-09`, `ALY-16..20` |
| **VER-04** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/voice_pipeline_test.gd` | Steps 1–7 applied | Exit code `0`; prints `[voice] SUMMARY <N> checks, 0 failed`. | `ALY-21` / Comms compatibility |
| **VER-05** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/boot_smoke.gd` | Steps 1–7 applied | Exit code `0`; prints `[boot_smoke] OK`. | Regression / Scene boot |
| **VER-06** | `& "C:/Users/agrim/.local/bin/godot.cmd" --path "D:/Desktop/Godot/parallax" -s res://tests/squad_ai_windowed_test.gd` | Steps 1–7 applied (active desktop/GPU session) | Exit code `0`; prints `[squad_test] SUMMARY <N> checks, 0 failed` (`kite_nuke`, `mid_combo_substitution`, `lure_detonate`, `take_aggro_pulls_off_player`, `auto_rally_*`, `taunt_fixation_persists`, `ranged_keeps_distance` all `PASS`). | `ALY-01..15`, `ALY-19..20`, `ALY-23` |
| **VER-07** | `& "C:/Users/agrim/.local/bin/godot.cmd" --path "D:/Desktop/Godot/parallax" -s res://tests/feel_and_movement_test.gd` | Steps 1–7 applied (active desktop/GPU session) | Exit code `0`; prints `[feel] SUMMARY 13 checks, 0 failed`. *(Note: run after Guide 04 or with clean desktop focus if `follow_*` checks run).* | Regression (`REQ-08`, `REQ-16`) |

### Failure Recovery Protocol
- **Parse / `--check-only` failure in `VER-01`**: Re-run `--check-only` on the failing script alone, inspect exact line reported, verify no duplicate/partial block occurred during edits, or run `git checkout -- <file>` and re-apply that step cleanly.
- **`SquadCommandParser` failure in `VER-03` (`squad_ai_unit_test.gd`)**: Print the returned command dictionary for the failing utterance; check `_find_rule_kw()` word padding (`" " + core + " "`), `_match_skill()`, or `_addressed()` `first_verb_pos`.
- **Windowed display unavailable in headless CI**: `VER-06` and `VER-07` require an active desktop/Vulkan display; if executed in headless-only environment, mark `VER-06` and `VER-07` explicitly as `SKIPPED (requires desktop display)` rather than claiming a pass.
- **Unrelated `user://` config side effects**: `SquadCommsHUD` saves `show_command_log` on `L` toggle into `user://squad_ai.cfg`; preserve or restore `%APPDATA%\Godot\app_userdata\PARALLAX\squad_ai.cfg` if needed.

---

## F. Completion Report Contract

When execution completes, report **only directly observed facts**:

1. **Applied Step IDs**: Exact list (`Step 1` .. `Step 9`) and any partial or skipped steps.
2. **Changed Files**: Exact repo-relative paths modified or created (matching Section C manifest and confirming `ally_squad_manager.gd:47-90`, `squad_ally.gd:182/:1222/:1223/:1694/:1759`, and `main_controller.gd` were untouched).
3. **Verification Results Table**:
   - Check ID (`VER-01` .. `VER-07`)
   - Exact Command Run
   - Exit Code
   - Exact Printed `SUMMARY` / Pass Line
4. **Remaining Unverified Items / Blockers**: Any check not run or deferred (e.g., if `VER-06` / `VER-07` could not run without a window server, or awaiting Guide 04 for `main_controller.gd:125` startup gating).
5. **Definition of Done**: Steps 1–9 applied with zero anchor mismatches, zero files modified outside Section C, and `VER-01` through `VER-07` passing with exit code `0` (`0 failed`).
