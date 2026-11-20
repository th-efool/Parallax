# IdiotHandOffGuide 05 — Enemy Marking, Region-Radius Detection & Free-Leash Ally Commands

---

## A. Execution Contract

| Item | Value |
| :--- | :--- |
| **Requested Outcome** | Add an aim-based Enemy Marking system (`T` / `MMB` to toggle `M1..M4`, `X` to clear all), automatic `18.0 m` region-radius detection around marked enemies (persisting `10.0 s` after combat death), clean tactical mark pins (`MarkPin` + `MarkRegionPin`) without reviving hidden overhead text tags, full offline parser + online LLM Director + strategy/combo/`massacre` mark targeting, and a **free leash** for allies under any command other than passive `follow` / `ceasefire` so they never distance-teleport back to the player. |
| **Repository Root** | `D:\Desktop\Godot\parallax` |
| **Shell & Engine** | PowerShell on Windows 11 · Godot `4.7.2.stable` Forward+ (`C:/Users/agrim/.local/bin/godot.cmd`) |
| **Git Baseline** | Branch `master` @ `1ca7464` *(with uncommitted Guides 01–04 + overhead `show_tags`/`show_state_icon` cleanup edits in working tree — preserve all existing uncommitted changes intact)* |
| **Readiness** | **`READY`** |
| **Required Inputs / Env** | None beyond existing workspace files (`user://` settings optional; tests call `SquadAIConfig.force_offline()` so no API keys are required). |

### Operational Sequence for the Executor
1. **Verify baseline first**: Run `git rev-parse --abbrev-ref HEAD`, `git rev-parse --short HEAD`, and confirm every target file in Section C exists and contains its expected anchor blocks before editing. **Preserve** all existing uncommitted changes in the working tree.
2. **Apply `STEP-01` through `STEP-09` in strict numerical order**, using the exact supplied code blocks (`Replace block` / `Create`). Do not improvise alternative signatures or omit type annotations.
3. **Run all verification checks (`VER-01` through `VER-04`)** in Section E using the mandatory `AGENTS.md` §3 bounded PowerShell timeout wrapper (`30 s` for `--check-only`, `90 s` max for headless regression suites; killing timed-out trees with exit code `124`).
4. **Report** applied step IDs, changed files, exact check pass/fail counts, and any blockers or mismatches.

### Error, Mismatch & Partial-Application Rules
- **Absent or mismatched edit target**: Stop immediately before applying dependent later steps. Report the exact file path, step ID, and what the file currently contains at that region.
- **Partially applied handoff**: Inspect each step's **Postcondition** in order (`STEP-01` -> `STEP-09`), confirm passing postconditions for already-applied steps, and resume cleanly at the first unapplied step.
- **Unfamiliar runtime/parse failure**: Capture full Godot stdout/stderr and report the failing step ID and exact error line. Never silence assertions or skip failing tests.
- **Documentation & Cleanup Hygiene (`AGENTS.md` Rules 1.2 & 3)**: Never create additional `.md` files in the repo root or `MEMORY/` (updates go only in `MEMORY/03`, `05`, `07` in `STEP-09`). Never commit `.godot/`. Leave no scratch `.gd` files behind.

---

## B. Requirements & Acceptance Map

| Req ID | Externally Observable Behavior & Constraints | Implementing Step(s) | Verification ID(s) |
| :--- | :--- | :--- | :--- |
| **`MRK-01`** | Pressing `mark_enemy` (`T` key or `Mouse Middle Button`) aims from the active camera center up to `180.0 m` (screen-center tolerance `max(64 px, 14% min viewport)` or `9.5°` half-cone with world LoS check to chest/head, excluding player/ally RIDs) to toggle mark slots `M1..M4` (FIFO eviction when exceeding `MAX_MARKS = 4`). Re-pressing while aiming at an already-marked enemy unmarks it. Pressing `clear_marks` (`X` key) clears all marks and active linger zones. Audio (`ui_confirm`/`ui_back`) + HUD toast feedback. | `STEP-02`, `STEP-06` | `VER-01`, `VER-02`, `VER-05` |
| **`MRK-02`** | Every marked enemy stays registered in `WorldIntel._entries` regardless of distance (`> 40.0 m` `RANGE_M`) and even when the camera turns away. Every other live, active, hittable enemy within `mark_region_radius` (`18.0 m`, `\|dy\| <= 10.0 m`) of any marked enemy is also detected into `WorldIntel._entries` with `in_mark_region = true` and `near_mark_num = M#`. | `STEP-02` | `VER-01`, `VER-02`, `VER-05` |
| **`MRK-03`** | Dead/inactive/freed marked enemies are pruned by `WorldIntel.prune_marks()`. When a marked enemy dies in combat (`e.is_dead`), its position spawns an `18.0 m` detection zone lingering for `10.0 s` (`MARK_REGION_LINGER_SEC`) so allies finish surviving enemies nearby. Manual `unmark_enemy()`, `clear_marks()`, and `AllySquadManager.regroup(true)` clear marks/zones cleanly. | `STEP-02`, `STEP-04` | `VER-01`, `VER-02` |
| **`MRK-04`** | Keeps `WorldIntel.show_tags = false` and `EnemyAI.show_state_icon = false` (`IntelTag`/`StateIcon` remain hidden). Marked enemies display a sleek pulsing Cracked-Mirror gold diamond + downward chevron + compact `M# · Xm` pin (`MarkPin`, `wl_kind = "mark"`, `max_dist = 200 m`; cyan `M# · MIRROR` when currently unhittable in Reality). Region-detected enemies display a minimal hollow amber diamond (`MarkRegionPin`, `wl_kind = "mark_nearby"`, `max_dist = 200 m`, no text clutter). Center aim reticle appears only when aiming at a candidate enemy; `F10` cinematic mode hides all pins & reticle. | `STEP-01`, `STEP-02`, `STEP-06` | `VER-01`, `VER-02`, `VER-05` |
| **`MRK-05`** | `WorldIntel.resolve()` resolves: empty `""` or `"marked_or_nearest"` -> primary hittable mark (`get_primary_marked(true)`) if one exists else nearest; `"marked"`/`"mark"`/`"tagged"`/`"pinged"` -> primary hittable mark; `"M1"`..`"M4"`/`"mark 1"` -> exact slot (`node_for_mark`); region queries (`"caster near M1"`, `"around the mark"`, `"marked group/area/region"`) -> best enemy inside the `18.0 m` marked radius without player-distance score penalty pushing > 60 m enemies negative; explicit `"nearest"`/`"closest"` keeps strict nearest behavior. Reality `PhantomTwin`s remain filtered by `is_hittable_now()` while still holding their mark pin & radiating region detection. | `STEP-02` | `VER-01`, `VER-02`, `VER-03` |
| **`MRK-06`** | `SquadCommandParser` recognizes `"marked"`, `"tagged"`, `"pinged"`, `"the mark"`, `"marked group/area/region"`, `"around/near the mark"`, `"M1"`..`"M4"`, `"mark 1..4"`, verb-less `"M1!"` -> `attack`, `"that one"` -> `"marked_or_nearest"`, and marked skill targets (`"Ivo mirror barrage M1"`, `"Sera shadowstep marked"`). Zero regressions to existing parser/skill boundary rules. | `STEP-03` | `VER-01`, `VER-02`, `VER-03`, `VER-04` |
| **`MRK-07`** | `AllySquadManager._active_enemies_near()` (`radius >= 20.0`), `pick_enemy_for()` (`massacre` / auto priority bonus for marks & region), `execute_strategy()` (empty target defaults to primary mark; `$distinct` & `$weakest_distinct` prioritize marked -> mark-region -> others), `_start_combo()` (empty target defaults to primary mark), and `_tick_combos()` (`70.0 s` timeout when marks/distant allies are active). | `STEP-04` | `VER-01`, `VER-02`, `VER-03` |
| **`MRK-08`** | `WorldIntel.describe_text(max_rows = 18)` puts `[MARKED M#]` and `[NEAR M#]` rows at the top before distance rows; `SquadComms.build_system_prompt()` & `tools()` include a `MARKED TARGETS` section and Rule `(12)` so online voice/chat Director commands leverage marks accurately; `tool_to_command("start_combo")` preserves empty target `""` when omitted. | `STEP-02`, `STEP-07` | `VER-01`, `VER-02`, `VER-04` |
| **`MRK-09`** | `SquadAlly.has_free_leash()` returns `true` whenever `current` (not `done`) or any queued command (not `done`) has `verb` not in `["follow", "ceasefire"]`. Under `has_free_leash()`, `_catch_up()` NEVER distance-teleports (`> 19.5 m`, `> 30 m`, `> 150 m`), NEVER `vertical_trap`-teleports, and NEVER treats lower terrain elevation (`y < player.y - 6.0`) as a pit fall. | `STEP-05` | `VER-01`, `VER-02`, `VER-03` |
| **`MRK-10`** | Under `has_free_leash()`: true void/pit falls (`_in_pit_kill_zone()` or `y < -20.0`) rescue strictly to `_last_safe_pos` (staying on the distant battlefield), falling back to `_blink_to(player)` only when `not _has_safe_pos`; `_update_stuck()` performs a local hop + lateral `_unstick_nudge()` instead of blinking back to the player. | `STEP-05` | `VER-01`, `VER-02` |
| **`MRK-11`** | Allies on passive `follow`, `ceasefire`, or `current == null` (with no non-follow/ceasefire queue entries) retain exact existing `FOLLOW_LEASH` (`19.5 m`), wall LoS catch-up, and stuck blink behavior (`aly05_catchup_wall_los_and_req16_exemption` passes). | `STEP-05` | `VER-02`, `VER-03` |
| **`MRK-12`** | `SquadAlly` scales approach timeouts via `_approach_timeout(base_sec, target_pos, cmd)` (`<= 45.0 s`) in `_run_taunt_cmd()`, `_kite_logic()`, `_run_skill()`, `_run_surround()`, and `_run_hit_and_run()`; removes the `28.0 m` rejection cap in `_run_ranged()` for explicit or marked/mark-region targets; and defaults omitted target args to `""` so unspecified commands target active marks. | `STEP-05` | `VER-01`, `VER-02` |
| **`MRK-13`** | New headless regression test `tests/enemy_marking_free_leash_regression_test.gd` (`12` focused checks, explicit preloads, `120 s` SceneTree watchdog) passes 100%, alongside existing `friends_ai_bugfix_regression_test.gd` and `squad_ai_unit_test.gd`. | `STEP-08` | `VER-02`, `VER-03`, `VER-04` |
| **`MRK-14`** | `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`, `MEMORY/05_UI_SCORING_AND_AUDIO.md`, and `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` updated in place (`AGENTS.md` Rule 1.3; zero extra `.md` files). | `STEP-09` | Inspection (`VER-01`–`VER-04` pass first) |

---

## C. File-Change Manifest

| Step ID | Operation | Exact Path (Relative to Repo Root) | Purpose Summary |
| :--- | :--- | :--- | :--- |
| `STEP-01` | Modify | `scripts/ui/world_label_overlay.gd` | Add `"mark"` diamond+chevron+ID renderer, `"mark_nearby"` hollow pip renderer, long-range fade span |
| `STEP-02` | Modify | `scripts/allies/world_intel.gd` | Aim-based `M1..M4` marking, `18 m` region-radius scan + `10 s` death linger, `MarkPin`/`MarkRegionPin`, mark/region `resolve()`, `describe_text()` priority |
| `STEP-03` | Modify | `scripts/allies/squad_command_parser.gd` | Add mark & mark-region target keywords/regex + vocab preservation |
| `STEP-04` | Modify | `scripts/allies/ally_squad_manager.gd` | Clear marks on `regroup(true)`, include & prioritize marks/regions in `_active_enemies_near`, `pick_enemy_for`, `execute_strategy`, `_start_combo`, `_tick_combos` |
| `STEP-05` | Modify | `scripts/allies/squad_ally.gd` | `has_free_leash()`, safe local unstick & `_last_safe_pos` pit rescue, `_approach_timeout()`, `""` target defaults, `_run_ranged` mark exemption |
| `STEP-06` | Modify | `scripts/ui/squad_comms_hud.gd` | `mark_enemy` (`T`/`MMB`) + `clear_marks` (`X`) input handling, center lock-on reticle, HUD key hint + active marks bar, `F10` pin hiding |
| `STEP-07` | Modify | `addons/parallax_squad_ai/squad_comms.gd` | Inject `MARKED TARGETS` & Rule `(12)` into LLM prompt, update tool target docs, omit default `"nearest"` on `start_combo` |
| `STEP-08` | Create | `tests/enemy_marking_free_leash_regression_test.gd` | 12-check headless regression suite covering `MRK-01`..`MRK-12` |
| `STEP-09` | Modify | `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`, `MEMORY/05_UI_SCORING_AND_AUDIO.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` | Synchronize architecture/UI docs & append dated changelog entry |

---

## D. Ordered Implementation Steps

### STEP-01 — Extend `WorldLabelOverlay` for Tactical Mark Pins

- **Prerequisites**: Baseline verified.
- **Target**: `scripts/ui/world_label_overlay.gd`
- **Action**: Three `Replace block` edits in order.

#### Edit 1A — Update `wl_kind` docstring contract
Exact Original:
```gdscript
## opts:
##   px: int font size in HUD pixels (default 18)
##   offset: Vector2 extra screen offset (default 0,0), e.g. to stack several labels on one enemy
##   font: "body" | "display" | "flavor" (default "body")
##   max_dist: float metres from the camera beyond which the label is hidden (default 40)
##   kind: "text" | "bar" — "bar" draws a health bar from meta "hp_ratio" (0..1) with the label text beside it
```
Replacement:
```gdscript
## opts:
##   px: int font size in HUD pixels (default 18)
##   offset: Vector2 extra screen offset (default 0,0), e.g. to stack several labels on one enemy
##   font: "body" | "display" | "flavor" (default "body")
##   max_dist: float metres from the camera beyond which the label is hidden (default 40)
##   kind: "text" | "bar" | "mark" | "mark_nearby"
```

#### Edit 1B — Scale distance fade span cleanly for 200 m tactical mark pins
Exact Original:
```gdscript
		var p: Vector2 = cam.unproject_position(wp) * k + (l.get_meta("wl_offset", Vector2.ZERO) as Vector2)
		if p.x < -200.0 or p.y < -200.0 or p.x > s.x + 200.0 or p.y > s.y + 200.0:
			continue
		var fade: float = clampf((max_d - dist) / FADE_M, 0.0, 1.0)
		items.append([dist, l, p, fade])
```
Replacement:
```gdscript
		var p: Vector2 = cam.unproject_position(wp) * k + (l.get_meta("wl_offset", Vector2.ZERO) as Vector2)
		if p.x < -200.0 or p.y < -200.0 or p.x > s.x + 200.0 or p.y > s.y + 200.0:
			continue
		var fade_span: float = 20.0 if max_d > 80.0 else FADE_M
		var fade: float = clampf((max_d - dist) / fade_span, 0.0, 1.0)
		items.append([dist, l, p, fade])
```

#### Edit 1C — Render `"mark"` and `"mark_nearby"` indicators in `_draw_label()`
Exact Original:
```gdscript
func _draw_label(l: Label3D, p: Vector2, fade: float) -> void:
	var font: Font = _font_for(l)
	var px: int = int(l.get_meta("wl_px", 18))
	var col: Color = l.modulate
	col.a *= fade
	var ocol: Color = l.outline_modulate
	ocol.a = 0.85 * col.a
	if String(l.get_meta("wl_kind", "text")) == "bar":
		var ratio: float = clampf(float(l.get_meta("hp_ratio", 1.0)), 0.0, 1.0)
		var r := Rect2(p.x - 48.0, p.y - 4.0, 96.0, 8.0)
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.75 * col.a))
		draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), Color(col.r, col.g, col.b, col.a))
		if not l.text.is_empty():
			_line(font, Vector2(r.end.x + 6.0, p.y + float(px) * 0.38), l.text, px, Color(1, 1, 1, 0.9 * col.a), ocol, false)
		return
```
Replacement:
```gdscript
func _draw_label(l: Label3D, p: Vector2, fade: float) -> void:
	var font: Font = _font_for(l)
	var px: int = int(l.get_meta("wl_px", 18))
	var col: Color = l.modulate
	col.a *= fade
	var ocol: Color = l.outline_modulate
	ocol.a = 0.85 * col.a
	var kind: String = String(l.get_meta("wl_kind", "text"))
	if kind == "bar":
		var ratio: float = clampf(float(l.get_meta("hp_ratio", 1.0)), 0.0, 1.0)
		var r := Rect2(p.x - 48.0, p.y - 4.0, 96.0, 8.0)
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.75 * col.a))
		draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), Color(col.r, col.g, col.b, col.a))
		if not l.text.is_empty():
			_line(font, Vector2(r.end.x + 6.0, p.y + float(px) * 0.38), l.text, px, Color(1, 1, 1, 0.9 * col.a), ocol, false)
		return
	if kind == "mark":
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.0055)
		var rr: float = 9.0 + pulse * 2.5
		var ring := PackedVector2Array([
			Vector2(p.x, p.y - rr),
			Vector2(p.x + rr, p.y),
			Vector2(p.x, p.y + rr),
			Vector2(p.x - rr, p.y),
			Vector2(p.x, p.y - rr),
		])
		draw_polyline(ring, Color(0.0, 0.0, 0.0, 0.78 * col.a), 4.2, true)
		draw_polyline(ring, col, 2.0, true)
		var core := PackedVector2Array([
			Vector2(p.x, p.y - 4.2),
			Vector2(p.x + 4.2, p.y),
			Vector2(p.x, p.y + 4.2),
			Vector2(p.x - 4.2, p.y),
		])
		draw_colored_polygon(core, col)
		var chev := PackedVector2Array([
			Vector2(p.x - 6.0, p.y + rr + 3.0),
			Vector2(p.x, p.y + rr + 8.5),
			Vector2(p.x + 6.0, p.y + rr + 3.0),
		])
		draw_polyline(chev, Color(0.0, 0.0, 0.0, 0.8 * col.a), 4.0, true)
		draw_polyline(chev, col, 2.0, true)
		if not l.text.is_empty():
			_line(font, Vector2(p.x, p.y - rr - 6.0), l.text, px, col, ocol, true)
		return
	if kind == "mark_nearby":
		var dr: float = 6.2
		var pip := PackedVector2Array([
			Vector2(p.x, p.y - dr),
			Vector2(p.x + dr, p.y),
			Vector2(p.x, p.y + dr),
			Vector2(p.x - dr, p.y),
			Vector2(p.x, p.y - dr),
		])
		draw_polyline(pip, Color(0.0, 0.0, 0.0, 0.7 * col.a), 3.4, true)
		draw_polyline(pip, col, 1.6, true)
		return
```

- **Postcondition**: `WorldLabelOverlay` cleanly renders `"mark"` and `"mark_nearby"` pins up to `200.0 m`.

---
### STEP-02 — Implement Aim Marking, `18 m` Region Scan, Pins & Priority Resolution in `WorldIntel`

- **Prerequisites**: `STEP-01` complete.
- **Target**: `scripts/allies/world_intel.gd`
- **Action**: Six `Replace block` edits in order.

#### Edit 2A — Add mark constants, signal, and state fields
Exact Original:
```gdscript
const REFRESH_SEC: float = 0.25
const RANGE_M: float = 40.0
const CAMERA_MAX_M: float = 140.0

## Classic enemy classes -> descriptor defaults (archetypes carry their own in EnemyArchetype).
const CLASS_LOOKS: Dictionary = {
	"skeleton": {"name": "Skeleton Guard", "color": "bone-white", "words": "skeleton bones undead"},
	"phantom": {"name": "Phantom Twin", "color": "glowing cyan, translucent", "words": "phantom ghost spectral twin mirror"},
	"shield": {"name": "Shielded Guard", "color": "steel and gold", "words": "shielded guard knight armored"},
	"warden": {"name": "The Warden", "color": "dark iron, glowing rune", "words": "warden boss giant"},
}
const PROP_WORDS: Dictionary = {
	"1H_Sword": "sword", "1H_Sword_Offhand": "second sword", "2H_Sword": "greatsword",
	"1H_Axe": "axe", "1H_Axe_Offhand": "second axe", "2H_Axe": "two-handed greataxe",
	"Badge_Shield": "crest shield", "Rectangle_Shield": "tower shield", "Round_Shield": "round shield",
	"Spike_Shield": "spiked shield", "Barbarian_Round_Shield": "round shield", "Mug": "mug",
}
const COLOR_WORDS: Array[String] = ["purple", "violet", "blue", "cyan", "green", "pale", "white", "bone", "gold", "golden",
	"steel", "silver", "red", "black", "dark", "iron", "glowing", "orange", "brown", "grey", "gray"]
const SIDE_WORDS: Dictionary = {"left": "left", "right": "right", "front": "ahead", "ahead": "ahead",
	"forward": "ahead", "behind": "behind", "back": "behind", "rear": "behind"}

var _ids: Dictionary = {}         # enemy instance_id -> "E#"
var _seq: int = 0
var _looks: Dictionary = {}       # instance_id -> descriptor dict (static part)
var _entries: Array[Dictionary] = []
var _timer: float = 0.0
var show_tags: bool = false
```
Replacement:
```gdscript
signal marks_changed(marked_entries: Array)

const REFRESH_SEC: float = 0.25
const RANGE_M: float = 40.0
const CAMERA_MAX_M: float = 140.0
const MARK_AIM_MAX_DIST: float = 180.0
const MARK_REGION_RADIUS: float = 18.0
const MARK_REGION_LINGER_SEC: float = 10.0
const MAX_MARKS: int = 4

## Classic enemy classes -> descriptor defaults (archetypes carry their own in EnemyArchetype).
const CLASS_LOOKS: Dictionary = {
	"skeleton": {"name": "Skeleton Guard", "color": "bone-white", "words": "skeleton bones undead"},
	"phantom": {"name": "Phantom Twin", "color": "glowing cyan, translucent", "words": "phantom ghost spectral twin mirror"},
	"shield": {"name": "Shielded Guard", "color": "steel and gold", "words": "shielded guard knight armored"},
	"warden": {"name": "The Warden", "color": "dark iron, glowing rune", "words": "warden boss giant"},
}
const PROP_WORDS: Dictionary = {
	"1H_Sword": "sword", "1H_Sword_Offhand": "second sword", "2H_Sword": "greatsword",
	"1H_Axe": "axe", "1H_Axe_Offhand": "second axe", "2H_Axe": "two-handed greataxe",
	"Badge_Shield": "crest shield", "Rectangle_Shield": "tower shield", "Round_Shield": "round shield",
	"Spike_Shield": "spiked shield", "Barbarian_Round_Shield": "round shield", "Mug": "mug",
}
const COLOR_WORDS: Array[String] = ["purple", "violet", "blue", "cyan", "green", "pale", "white", "bone", "gold", "golden",
	"steel", "silver", "red", "black", "dark", "iron", "glowing", "orange", "brown", "grey", "gray"]
const SIDE_WORDS: Dictionary = {"left": "left", "right": "right", "front": "ahead", "ahead": "ahead",
	"forward": "ahead", "behind": "behind", "back": "behind", "rear": "behind"}

var _ids: Dictionary = {}         # enemy instance_id -> "E#"
var _seq: int = 0
var _looks: Dictionary = {}       # instance_id -> descriptor dict (static part)
var _entries: Array[Dictionary] = []
var _timer: float = 0.0
var show_tags: bool = false
var _marks: Array[Dictionary] = []       # {"iid": int, "ref": WeakRef, "num": int, "marked_ms": int, "last_pos": Vector3}
var _mark_zones: Array[Dictionary] = []  # {"pos": Vector3, "expires_ms": int, "mark_num": int}
var mark_region_radius: float = MARK_REGION_RADIUS
```

#### Edit 2B — Update `refresh()` to prune marks, include far marks & `18 m` region neighbors, and update mark pins
Exact Original:
```gdscript
func refresh() -> void:
	_entries.clear()
	if not is_inside_tree() or get_tree() == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return
	var pf: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else Vector3.FORWARD
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or not (n is EnemyAI):
			if is_instance_valid(n):
				_hide_tag(n)
			continue
		var e: EnemyAI = n as EnemyAI
		if e.is_dead or not e.is_inside_tree() or not e.is_hittable_now():
			_hide_tag(e)
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
Replacement:
```gdscript
func refresh() -> void:
	_entries.clear()
	prune_marks()
	if not is_inside_tree() or get_tree() == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return
	var pf: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else Vector3.FORWARD
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or not (n is EnemyAI):
			if is_instance_valid(n):
				_hide_tag(n)
				_hide_mark_pins(n)
			continue
		var e: EnemyAI = n as EnemyAI
		if e.is_dead or not e.is_inside_tree() or not e.is_active:
			_hide_tag(e)
			_hide_mark_pins(e)
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		var m_num: int = mark_number_of(e)
		var is_m: bool = m_num > 0
		var near_num: int = 0 if is_m else _region_match_for_pos(e.global_position)
		var in_region: bool = near_num > 0
		if not e.is_hittable_now():
			_hide_tag(e)
			if is_m:
				_update_mark_pins(e, true, m_num, false, d)
			else:
				_hide_mark_pins(e)
			continue
		var cam_vis: bool = is_camera_visible(e)
		if d > RANGE_M and not cam_vis and not is_m and not in_region:
			_hide_tag(e)
			_hide_mark_pins(e)
			continue
		var entry: Dictionary = _describe(e, player, pf, d, m_num, near_num)
		_entries.append(entry)
		_update_tag(e, entry)
		_update_mark_pins(e, is_m, m_num, in_region, d)
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
```

#### Edit 2C — Record mark metadata in `_describe()`
Exact Original:
```gdscript
func _describe(e: EnemyAI, player: Node3D, pf: Vector3, d: float) -> Dictionary:
```
Replacement:
```gdscript
func _describe(e: EnemyAI, player: Node3D, pf: Vector3, d: float, mark_num: int = 0, near_mark_num: int = 0) -> Dictionary:
```

Exact Original:
```gdscript
	return {
		"id": id_of(e), "node": e, "kind": look["kind"], "name": look["name"], "model": look["model"],
		"size": look["size"], "color": look["color"], "weapon": look["weapon"], "ranged": look["ranged"],
		"realm": look["realm"], "hp": e.health, "max_hp": e.max_health,
		"hp_pct": int(round(100.0 * float(e.health) / float(maxi(1, e.max_health)))),
		"dist": d, "bearing": bearing, "targeting": tname, "state": state,
		"words": String(look["words"]), "pos": e.global_position,
	}
```
Replacement:
```gdscript
	return {
		"id": id_of(e), "node": e, "kind": look["kind"], "name": look["name"], "model": look["model"],
		"size": look["size"], "color": look["color"], "weapon": look["weapon"], "ranged": look["ranged"],
		"realm": look["realm"], "hp": e.health, "max_hp": e.max_health,
		"hp_pct": int(round(100.0 * float(e.health) / float(maxi(1, e.max_health)))),
		"dist": d, "bearing": bearing, "targeting": tname, "state": state,
		"words": String(look["words"]), "pos": e.global_position,
		"marked": mark_num > 0, "mark_num": mark_num,
		"in_mark_region": near_mark_num > 0, "near_mark_num": near_mark_num,
	}
```

#### Edit 2D — Surface `[MARKED M#]` / `[NEAR M#]` first in `entry_line()`, `describe_text()`, plus `describe_marks_text()`
Exact Original:
```gdscript
func entry_line(en: Dictionary) -> String:
	var s: String = "%s %s — %s %s%s, %s | %d%% HP | %.0fm %s | %s | targeting %s" % [
		en["id"], en["name"], ("" if en["size"] == "normal" else String(en["size"]) + " "), en["color"],
		(" " + String(en["model"])) if not String(en["model"]).is_empty() else "", en["weapon"],
		int(en["hp_pct"]), float(en["dist"]), en["bearing"], en["realm"], en["targeting"]]
	if bool(en["ranged"]):
		s += " | ranged"
	if not String(en["state"]).is_empty():
		s += " | " + String(en["state"])
	return s


## Battlefield table for the Director prompt (nearest first).
func describe_text(max_rows: int = 14) -> String:
	if _entries.is_empty():
		return "No enemies within %dm." % int(RANGE_M)
	var rows: PackedStringArray = []
	for i in range(mini(max_rows, _entries.size())):
		rows.append("- " + entry_line(_entries[i]))
	if _entries.size() > max_rows:
		rows.append("- (+%d more farther away)" % (_entries.size() - max_rows))
	return "\n".join(rows)
```
Replacement:
```gdscript
func entry_line(en: Dictionary) -> String:
	var tag_prefix: String = ""
	if bool(en.get("marked", false)):
		tag_prefix = "[MARKED M%d] " % int(en.get("mark_num", 1))
	elif bool(en.get("in_mark_region", false)):
		tag_prefix = "[NEAR M%d] " % int(en.get("near_mark_num", 1))
	var s: String = "%s%s %s — %s %s%s, %s | %d%% HP | %.0fm %s | %s | targeting %s" % [
		tag_prefix, en["id"], en["name"], ("" if en["size"] == "normal" else String(en["size"]) + " "), en["color"],
		(" " + String(en["model"])) if not String(en["model"]).is_empty() else "", en["weapon"],
		int(en["hp_pct"]), float(en["dist"]), en["bearing"], en["realm"], en["targeting"]]
	if bool(en["ranged"]):
		s += " | ranged"
	if not String(en["state"]).is_empty():
		s += " | " + String(en["state"])
	return s


## Battlefield table for the Director prompt (marked targets & region neighbors first, then nearest).
func describe_text(max_rows: int = 18) -> String:
	if _entries.is_empty():
		return "No enemies within %dm or marked." % int(RANGE_M)
	var ordered: Array[Dictionary] = []
	for en in _entries:
		if bool(en.get("marked", false)):
			ordered.append(en)
	for en in _entries:
		if not bool(en.get("marked", false)) and bool(en.get("in_mark_region", false)):
			ordered.append(en)
	for en in _entries:
		if not bool(en.get("marked", false)) and not bool(en.get("in_mark_region", false)):
			ordered.append(en)
	var rows: PackedStringArray = []
	for i in range(mini(max_rows, ordered.size())):
		rows.append("- " + entry_line(ordered[i]))
	if ordered.size() > max_rows:
		rows.append("- (+%d more farther away)" % (ordered.size() - max_rows))
	return "\n".join(rows)


func describe_marks_text() -> String:
	prune_marks()
	var summaries: Array[Dictionary] = get_marked_summaries()
	if summaries.is_empty() and _mark_zones.is_empty():
		return "- none"
	var lines: PackedStringArray = []
	for sm in summaries:
		var m_num: int = int(sm.get("num", 1))
		var e: EnemyAI = sm.get("node", null) as EnemyAI
		var eid: String = id_of(e) if e != null else "?"
		var nearby_n: int = 0
		for en in _entries:
			if bool(en.get("in_mark_region", false)) and int(en.get("near_mark_num", 0)) == m_num:
				nearby_n += 1
		var realm_note: String = " (Mirror-only/unhittable right now)" if not bool(sm.get("hittable", true)) else ""
		lines.append("- M%d (%s): %s, %.0fm away, %d nearby in %dm region%s" % [
			m_num, eid, String(sm.get("name", "Enemy")), float(sm.get("dist", 0.0)), nearby_n, int(mark_region_radius), realm_note])
	for z in _mark_zones:
		var m_num2: int = int((z as Dictionary).get("mark_num", 1))
		var rem_s: int = maxi(1, int(ceil(float(int((z as Dictionary).get("expires_ms", 0)) - Time.get_ticks_msec()) / 1000.0)))
		var nearby_z: int = 0
		for en2 in _entries:
			if bool(en2.get("in_mark_region", false)) and int(en2.get("near_mark_num", 0)) == m_num2:
				nearby_z += 1
		lines.append("- M%d linger zone (%ds left): %d enemy(ies) inside %dm region" % [
			m_num2, rem_s, nearby_z, int(mark_region_radius)])
	return "\n".join(lines)
```

#### Edit 2E — Update `resolve()` for marks, `M1..M4`, region queries, and long-range descriptor scoring
Exact Original:
```gdscript
func resolve(selector: String, asker: Node3D = null) -> EnemyAI:
	if _entries.is_empty():
		refresh()
	if _entries.is_empty():
		return null
	var s: String = " " + selector.to_lower().strip_edges().trim_prefix("desc:") + " "
	# Explicit ID anywhere in the text ("E3", "e 3", "enemy 3").
	var rx := RegEx.new()
	rx.compile("\\b(?:e|enemy|target)\\s*#?\\s*(\\d+)\\b")
	var m: RegExMatch = rx.search(s)
	if m != null:
		var byid: EnemyAI = node_for_id("E" + m.get_string(1))
		if byid != null and byid.is_hittable_now():
			return byid
		if byid != null:
			return null
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
		var raw_node: Variant = en.get("node")
		if not is_instance_valid(raw_node) or not (raw_node is EnemyAI):
			continue
		var en_node: EnemyAI = raw_node as EnemyAI
		if en_node.is_dead or not en_node.is_active or not en_node.is_inside_tree() or not en_node.is_hittable_now():
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
	# A description that matches nothing at all should not silently pick a random enemy far away.
	if any_desc and best_score < 0.5 and ref_node == null:
		return null
	return best
```
Replacement:
```gdscript
func resolve(selector: String, asker: Node3D = null) -> EnemyAI:
	if _entries.is_empty():
		refresh()
	if _entries.is_empty():
		return null
	var s_raw: String = selector.to_lower().strip_edges()
	var s: String = " " + s_raw.trim_prefix("desc:") + " "
	var wants_region: bool = s.contains(" group") or s.contains(" area") or s.contains(" region") or s.contains(" pack") or s.contains(" cluster") or s.contains(" around ") or s.contains(" near ") or s.contains(" next to ") or s.contains(" beside ") or s.contains(" by ") or s_raw in ["marked_group", "marked_area", "marked_region"]
	var rx_mark := RegEx.new()
	rx_mark.compile("\\b(?:m|mark)\\s*#?\\s*([1-4])\\b")
	var mm: RegExMatch = rx_mark.search(s)
	if mm != null and not wants_region:
		return node_for_mark(int(mm.get_string(1)), true)
	# Explicit ID anywhere in the text ("E3", "e 3", "enemy 3").
	var rx := RegEx.new()
	rx.compile("\\b(?:e|enemy|target)\\s*#?\\s*(\\d+)\\b")
	var m: RegExMatch = rx.search(s)
	if m != null:
		var byid: EnemyAI = node_for_id("E" + m.get_string(1))
		if byid != null and byid.is_hittable_now():
			return byid
		if byid != null:
			return null
	if (s_raw.is_empty() or s_raw == "marked_or_nearest"):
		var pm_def: EnemyAI = get_primary_marked(true)
		if pm_def != null:
			return pm_def
	if (s_raw in ["marked", "mark", "tagged", "pinged", "the mark"]) and not wants_region:
		return get_primary_marked(true)
	var mark_ref_pos: Vector3 = Vector3.INF
	var mark_ref_slot: int = 0
	if mm != null and wants_region:
		mark_ref_slot = int(mm.get_string(1))
		mark_ref_pos = _position_for_mark_slot(mark_ref_slot)
		if mark_ref_pos == Vector3.INF:
			return null
	elif wants_region and (s.contains(" marked") or s.contains(" the mark ") or s.contains(" tagged") or s.contains(" pinged") or s_raw in ["marked_group", "marked_area", "marked_region"]):
		mark_ref_pos = _position_for_primary_mark_or_zone()
		if mark_ref_pos == Vector3.INF:
			return null
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
	var strict_nearest: bool = s_raw == "nearest" or s_raw == "closest"
	var has_other_desc: bool = false
	for t0 in tokens:
		if t0 in COLOR_WORDS or t0 in ["axe", "sword", "shield", "orb", "blades", "caster", "mage", "brute", "rogue", "knight", "barbarian", "skeleton", "phantom", "ghost", "stalker", "hexcaster", "warden", "big", "huge", "small", "giant", "archer", "ranged", "glowing", "hooded", "armored", "greataxe", "twin", "stunned", "fleeing", "enraged", "wounded", "hurt", "dying"] or SIDE_WORDS.has(t0):
			has_other_desc = true
			break
	if not wants_region and not has_other_desc and ref_node == null and (s.contains(" marked") or s.contains(" tagged") or s.contains(" pinged") or s.contains(" the mark ")):
		return get_primary_marked(true)
	var best: EnemyAI = null
	var best_score: float = -INF
	var best_match_score: float = 0.0
	var any_desc: bool = false
	for en in _entries:
		var raw_node: Variant = en.get("node")
		if not is_instance_valid(raw_node) or not (raw_node is EnemyAI):
			continue
		var en_node: EnemyAI = raw_node as EnemyAI
		if en_node.is_dead or not en_node.is_active or not en_node.is_inside_tree() or not en_node.is_hittable_now():
			continue
		if mark_ref_pos != Vector3.INF:
			if en_node.global_position.distance_to(mark_ref_pos) > mark_region_radius + 0.5 or absf(en_node.global_position.y - mark_ref_pos.y) > 10.0:
				continue
		var match_score: float = 0.0
		var words: String = String(en["words"])
		for t in tokens:
			if t.length() < 3 or t in ["the", "one", "guy", "that", "this", "with", "and", "who", "kill", "attack", "him", "her", "them", "enemy", "please", "now", "get", "go", "hit", "marked", "mark", "tagged", "pinged", "group", "area", "region", "pack", "cluster", "around"]:
				continue
			if t in COLOR_WORDS or t in ["axe", "sword", "shield", "orb", "blades", "caster", "mage", "brute", "rogue", "knight", "barbarian", "skeleton", "phantom", "ghost", "stalker", "hexcaster", "warden", "big", "huge", "small", "giant", "archer", "ranged", "glowing", "hooded", "armored", "greataxe", "twin"]:
				any_desc = true
				if words.contains(t):
					match_score += 3.0
				elif t in ["caster", "mage", "archer", "ranged"] and bool(en["ranged"]):
					match_score += 3.0
				elif t in ["big", "huge", "giant"] and String(en["size"]) in ["big", "huge"]:
					match_score += 2.0
				elif t in ["blades"] and String(en["weapon"]).contains("sword"):
					match_score += 2.0
				else:
					match_score -= 1.5
			if SIDE_WORDS.has(t):
				any_desc = true
				match_score += 2.0 if String(en["bearing"]).contains(String(SIDE_WORDS[t])) else -1.0
			if t in ["stunned", "fleeing", "enraged", "wounded", "hurt", "dying"]:
				any_desc = true
				if t in ["wounded", "hurt", "dying"]:
					match_score += (100.0 - float(en["hp_pct"])) / 40.0
				elif String(en["state"]).contains(t):
					match_score += 3.0
		if ref_node != null and is_instance_valid(ref_node):
			any_desc = true
			if ref_mode == "targeting":
				var tn: String = String(en["targeting"]).to_lower()
				var rn: String = "player" if ref_node is PlayerController else String(ref_node.call("get_display_name")).to_lower()
				match_score += 4.0 if tn == rn else -2.0
			else:
				match_score -= en_node.global_position.distance_to(ref_node.global_position) * 0.25
		if mark_ref_pos != Vector3.INF:
			any_desc = true
			match_score += 2.0 if bool(en.get("in_mark_region", false)) or bool(en.get("marked", false)) else 1.0
			match_score -= en_node.global_position.distance_to(mark_ref_pos) * 0.04
		var score: float = match_score
		# Superlatives / default ordering.
		var d: float = en_node.global_position.distance_to(origin)
		if s.contains("farthest") or s.contains("furthest") or s.contains("farther") or s.contains("further") or s.contains("distant"):
			score += d * 0.05
		elif s.contains("strongest") or s.contains("toughest") or s.contains("biggest"):
			score += float(en["hp"]) * 0.01
		elif s.contains("weakest") or s.contains("lowest"):
			score += (100.0 - float(en["hp_pct"])) * 0.03
		elif mark_ref_pos == Vector3.INF:
			if strict_nearest or not any_desc:
				score -= d * 0.05
			else:
				score -= clampf(d * 0.015, 0.0, 2.0)
		if not strict_nearest and bool(en.get("in_mark_region", false)) and mark_ref_pos == Vector3.INF and not any_desc:
			score += 3.0
		if en_node.is_aggroed():
			score += 0.3
		if score > best_score:
			best_score = score
			best_match_score = match_score
			best = en_node
	# A description that matches nothing at all should not silently pick a random enemy far away.
	if any_desc and best_match_score < 0.5 and ref_node == null and mark_ref_pos == Vector3.INF:
		return null
	return best
```

#### Edit 2F — Add complete mark management, aim ray/cone selection, `18 m` region helpers, and tactical `MarkPin`/`MarkRegionPin` management
Exact Original:
```gdscript
# ------------------------------------------------------------------ overhead ID tags

func _update_tag(e: EnemyAI, en: Dictionary) -> void:
	if not show_tags:
		_hide_tag(e)
		return
	var tag: Label3D = e.get_node_or_null("IntelTag") as Label3D
	if tag == null:
		tag = Label3D.new()
		tag.name = "IntelTag"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.0011
		tag.font_size = 22
		tag.outline_size = 6
		tag.outline_modulate = Color(0, 0, 0, 0.9)
		tag.font = UITheme.body_font()
		tag.modulate = Color(1.0, 0.86, 0.5, 0.95)
		e.add_child(tag)
		tag.position = Vector3(0, 2.45, 0)
		WorldLabelOverlay.adopt(tag, {"px": 14, "offset": Vector2(0, -16), "max_dist": 30.0})
	# Mirror insight reveals more: exact health and the exposed weak point.
	if e.mirror_insight:
		tag.text = "%s · %d%% · WEAK" % [String(en["id"]), int(en["hp_pct"])]
		tag.modulate = Color(0.55, 0.9, 1.0, 0.95)
	else:
		tag.text = String(en["id"])
		tag.modulate = Color(1.0, 0.86, 0.5, 0.95)
	tag.visible = show_tags and not bool(tag.get_meta("cinematic_hidden", false)) and float(en["dist"]) < 28.0


func _hide_tag(n: Node) -> void:
	var tag: Node3D = n.get_node_or_null("IntelTag") as Node3D
	if tag != null:
		tag.visible = false
```
Replacement:
```gdscript
# ------------------------------------------------------------------ aiming & tactical marks

func prune_marks() -> void:
	var now_ms: int = Time.get_ticks_msec()
	var changed: bool = false
	for i in range(_mark_zones.size() - 1, -1, -1):
		if now_ms > int((_mark_zones[i] as Dictionary).get("expires_ms", 0)):
			_mark_zones.remove_at(i)
			changed = true
	for i in range(_marks.size() - 1, -1, -1):
		var rec: Dictionary = _marks[i]
		var obj: Object = (rec["ref"] as WeakRef).get_ref()
		if obj == null or not is_instance_valid(obj) or not (obj is EnemyAI):
			_marks.remove_at(i)
			changed = true
			continue
		var e: EnemyAI = obj as EnemyAI
		if e.is_dead:
			_mark_zones.append({
				"pos": e.global_position,
				"expires_ms": now_ms + int(MARK_REGION_LINGER_SEC * 1000.0),
				"mark_num": int(rec["num"]),
			})
			_hide_mark_pins(e)
			_marks.remove_at(i)
			changed = true
		elif not e.is_inside_tree() or not e.is_active:
			_hide_mark_pins(e)
			_marks.remove_at(i)
			changed = true
		else:
			rec["last_pos"] = e.global_position
	if changed:
		marks_changed.emit(get_marked_summaries())


func _next_mark_slot() -> int:
	var used: Dictionary = {}
	for rec in _marks:
		used[int((rec as Dictionary)["num"])] = true
	for n in range(1, MAX_MARKS + 1):
		if not used.has(n):
			return n
	return 1


func has_marks() -> bool:
	prune_marks()
	return not _marks.is_empty()


func has_mark_zones() -> bool:
	prune_marks()
	return not _mark_zones.is_empty()


func has_hittable_mark() -> bool:
	return get_primary_marked(true) != null


func mark_number_of(e: Node) -> int:
	if e == null or not is_instance_valid(e):
		return 0
	var iid: int = e.get_instance_id()
	for rec in _marks:
		var d: Dictionary = rec as Dictionary
		if int(d["iid"]) == iid:
			var obj: Object = (d["ref"] as WeakRef).get_ref()
			if obj == e:
				return int(d["num"])
	return 0


func is_marked(e: Node) -> bool:
	return mark_number_of(e) > 0


func is_in_mark_region(e: Node) -> bool:
	if e == null or not is_instance_valid(e) or not (e is Node3D):
		return false
	if is_marked(e):
		return false
	return _region_match_for_pos((e as Node3D).global_position) > 0


func is_marked_or_in_region(e: Node) -> bool:
	return is_marked(e) or is_in_mark_region(e)


func node_for_mark(num: int, require_hittable: bool = true) -> EnemyAI:
	prune_marks()
	for rec in _marks:
		var d: Dictionary = rec as Dictionary
		if int(d["num"]) == num:
			var obj: Object = (d["ref"] as WeakRef).get_ref()
			if is_instance_valid(obj) and obj is EnemyAI:
				var e: EnemyAI = obj as EnemyAI
				if not e.is_dead and e.is_active and e.is_inside_tree() and (not require_hittable or e.is_hittable_now()):
					return e
	return null


func get_primary_marked(require_hittable: bool = true) -> EnemyAI:
	prune_marks()
	for rec in _marks:
		var obj: Object = ((rec as Dictionary)["ref"] as WeakRef).get_ref()
		if is_instance_valid(obj) and obj is EnemyAI:
			var e: EnemyAI = obj as EnemyAI
			if not e.is_dead and e.is_active and e.is_inside_tree() and (not require_hittable or e.is_hittable_now()):
				return e
	return null


func get_marked_enemies(require_hittable: bool = true) -> Array[EnemyAI]:
	prune_marks()
	var out: Array[EnemyAI] = []
	for rec in _marks:
		var obj: Object = ((rec as Dictionary)["ref"] as WeakRef).get_ref()
		if is_instance_valid(obj) and obj is EnemyAI:
			var e: EnemyAI = obj as EnemyAI
			if not e.is_dead and e.is_active and e.is_inside_tree() and (not require_hittable or e.is_hittable_now()):
				out.append(e)
	return out


func get_marked_summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if (is_inside_tree() and get_tree() != null) else null
	for rec in _marks:
		var d: Dictionary = rec as Dictionary
		var obj: Object = (d["ref"] as WeakRef).get_ref()
		if not is_instance_valid(obj) or not (obj is EnemyAI):
			continue
		var e: EnemyAI = obj as EnemyAI
		var dist: float = e.global_position.distance_to(player.global_position) if player != null else 0.0
		out.append({
			"num": int(d["num"]),
			"id": id_of(e),
			"name": String(_look_of(e).get("name", e.name)),
			"dist": dist,
			"hittable": e.is_hittable_now(),
			"node": e,
		})
	return out


func _position_for_mark_slot(slot: int) -> Vector3:
	for rec in _marks:
		var d: Dictionary = rec as Dictionary
		if int(d["num"]) == slot:
			var obj: Object = (d["ref"] as WeakRef).get_ref()
			if is_instance_valid(obj) and obj is EnemyAI and not (obj as EnemyAI).is_dead:
				return (obj as EnemyAI).global_position
	for z in _mark_zones:
		var zd: Dictionary = z as Dictionary
		if int(zd["mark_num"]) == slot:
			return zd["pos"] as Vector3
	return Vector3.INF


func _position_for_primary_mark_or_zone() -> Vector3:
	var pm: EnemyAI = get_primary_marked(false)
	if pm != null:
		return pm.global_position
	if not _mark_zones.is_empty():
		return (_mark_zones[-1] as Dictionary)["pos"] as Vector3
	return Vector3.INF


func _region_match_for_pos(pos: Vector3) -> int:
	var now_ms: int = Time.get_ticks_msec()
	for rec in _marks:
		var obj: Object = ((rec as Dictionary)["ref"] as WeakRef).get_ref()
		if not is_instance_valid(obj) or not (obj is EnemyAI):
			continue
		var me: EnemyAI = obj as EnemyAI
		if me.is_dead or not me.is_active or not me.is_inside_tree():
			continue
		if pos.distance_to(me.global_position) <= mark_region_radius and absf(pos.y - me.global_position.y) <= 10.0:
			return int((rec as Dictionary)["num"])
	for z in _mark_zones:
		var zd: Dictionary = z as Dictionary
		if now_ms <= int(zd.get("expires_ms", 0)):
			var zp: Vector3 = zd["pos"] as Vector3
			if pos.distance_to(zp) <= mark_region_radius and absf(pos.y - zp.y) <= 10.0:
				return int(zd.get("mark_num", 1))
	return 0


func mark_enemy(e: EnemyAI) -> int:
	if e == null or not is_instance_valid(e) or e.is_dead or not e.is_active or not e.is_inside_tree():
		return 0
	prune_marks()
	var existing: int = mark_number_of(e)
	if existing > 0:
		return existing
	while _marks.size() >= MAX_MARKS:
		var evicted: Dictionary = _marks.pop_front()
		var old_obj: Object = (evicted["ref"] as WeakRef).get_ref()
		if is_instance_valid(old_obj) and old_obj is Node:
			_hide_mark_pins(old_obj as Node)
	var num: int = _next_mark_slot()
	_marks.append({
		"iid": e.get_instance_id(),
		"ref": weakref(e),
		"num": num,
		"marked_ms": Time.get_ticks_msec(),
		"last_pos": e.global_position,
	})
	refresh()
	marks_changed.emit(get_marked_summaries())
	return num


func unmark_enemy(e: EnemyAI) -> bool:
	if e == null:
		return false
	var iid: int = e.get_instance_id()
	var removed: bool = false
	for i in range(_marks.size() - 1, -1, -1):
		if int((_marks[i] as Dictionary)["iid"]) == iid:
			_marks.remove_at(i)
			removed = true
	if is_instance_valid(e):
		_hide_mark_pins(e)
	if removed:
		refresh()
		marks_changed.emit(get_marked_summaries())
	return removed


func clear_marks() -> void:
	for rec in _marks:
		var obj: Object = ((rec as Dictionary)["ref"] as WeakRef).get_ref()
		if is_instance_valid(obj) and obj is Node:
			_hide_mark_pins(obj as Node)
	_marks.clear()
	_mark_zones.clear()
	refresh()
	marks_changed.emit(get_marked_summaries())


func peek_aim_candidate(max_dist: float = MARK_AIM_MAX_DIST) -> EnemyAI:
	return _pick_aim_candidate(max_dist)


func mark_enemy_at_aim(max_dist: float = MARK_AIM_MAX_DIST) -> Dictionary:
	var target: EnemyAI = _pick_aim_candidate(max_dist)
	if target == null:
		return {"action": "none", "enemy": null, "mark_num": 0, "nearby_count": 0}
	var ename: String = String(_look_of(target).get("name", target.name))
	if is_marked(target):
		unmark_enemy(target)
		return {"action": "unmarked", "enemy": target, "name": ename, "mark_num": 0, "nearby_count": 0}
	var num: int = mark_enemy(target)
	var nearby_cnt: int = 0
	for en in _entries:
		if bool(en.get("in_mark_region", false)) and int(en.get("near_mark_num", 0)) == num:
			nearby_cnt += 1
	return {"action": "marked", "enemy": target, "name": ename, "mark_num": num, "nearby_count": nearby_cnt}


func _pick_aim_candidate(max_dist: float = MARK_AIM_MAX_DIST) -> EnemyAI:
	if not is_inside_tree() or get_tree() == null or get_viewport() == null:
		return null
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(cam):
		return null
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var has_vp: bool = vp_size.x > 1.0 and vp_size.y > 1.0
	var center: Vector2 = vp_size * 0.5
	var px_tol: float = maxf(64.0, minf(vp_size.x, vp_size.y) * 0.14) if has_vp else 0.0
	var cos_tol: float = cos(deg_to_rad(9.5))
	var cam_pos: Vector3 = cam.global_position
	var cam_fwd: Vector3 = -cam.global_transform.basis.z.normalized()
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state if cam.get_world_3d() != null else null
	var base_excl: Array[RID] = []
	for p_n in get_tree().get_nodes_in_group("player"):
		if p_n is CollisionObject3D:
			base_excl.append((p_n as CollisionObject3D).get_rid())
	for a_n in get_tree().get_nodes_in_group("squad_ally"):
		if a_n is CollisionObject3D:
			base_excl.append((a_n as CollisionObject3D).get_rid())
	var best: EnemyAI = null
	var best_err: float = INF
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or not (n is EnemyAI):
			continue
		var e: EnemyAI = n as EnemyAI
		if e.is_dead or not e.is_active or not e.is_inside_tree():
			continue
		var dist: float = cam_pos.distance_to(e.global_position)
		if dist > max_dist:
			continue
		var best_pt_err: float = INF
		var any_front: bool = false
		for h_off in [1.2, 1.7, 0.7]:
			var pt: Vector3 = e.global_position + Vector3.UP * float(h_off)
			if cam.is_position_behind(pt):
				continue
			var dir_to: Vector3 = (pt - cam_pos).normalized()
			var ang_cos: float = cam_fwd.dot(dir_to)
			var px_err: float = cam.unproject_position(pt).distance_to(center) if has_vp else 0.0
			var inside_cone: bool = (has_vp and px_err <= px_tol) or ang_cos >= cos_tol
			if not inside_cone:
				continue
			any_front = true
			var err: float = (px_err / px_tol) if has_vp else ((1.0 - ang_cos) * 20.0)
			if err < best_pt_err:
				best_pt_err = err
		if not any_front:
			continue
		if space != null and not _has_mark_los(space, cam_pos, e, base_excl):
			continue
		var total_err: float = best_pt_err + dist * 0.002
		if total_err < best_err:
			best_err = total_err
			best = e
	return best


func _has_mark_los(space: PhysicsDirectSpaceState3D, from_pos: Vector3, enemy: EnemyAI, base_excl: Array[RID]) -> bool:
	var world_mask: int = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY
	if RealmManager.instance != null:
		if RealmManager.instance.is_merged:
			world_mask = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR
		elif RealmManager.instance.current_realm == RealmManager.Realm.MIRROR:
			world_mask = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_MIRROR
	var excl: Array[RID] = base_excl.duplicate()
	excl.append(enemy.get_rid())
	for h_off in [1.15, 1.75]:
		var pt: Vector3 = enemy.global_position + Vector3.UP * float(h_off)
		var q := PhysicsRayQueryParameters3D.create(from_pos, pt, world_mask, excl)
		if space.intersect_ray(q).is_empty():
			return true
	return false


# ------------------------------------------------------------------ overhead ID tags & tactical mark pins

func _update_mark_pins(e: EnemyAI, is_m: bool, mark_num: int, in_region: bool, dist: float) -> void:
	if is_m:
		var old_r: Node3D = e.get_node_or_null("MarkRegionPin") as Node3D
		if old_r != null:
			old_r.visible = false
		var pin: Label3D = e.get_node_or_null("MarkPin") as Label3D
		if pin == null:
			pin = Label3D.new()
			pin.name = "MarkPin"
			pin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			pin.no_depth_test = true
			pin.fixed_size = true
			pin.pixel_size = 0.0011
			pin.font_size = 22
			pin.outline_size = 6
			pin.outline_modulate = Color(0.02, 0.02, 0.04, 0.92)
			pin.font = UITheme.body_font()
			e.add_child(pin)
			pin.position = Vector3(0.0, 2.55, 0.0)
			WorldLabelOverlay.adopt(pin, {"px": 15, "offset": Vector2(0.0, -18.0), "max_dist": 200.0, "kind": "mark"})
		if e.is_hittable_now():
			pin.text = "M%d · %.0fm" % [mark_num, dist]
			pin.modulate = Color(1.0, 0.84, 0.34, 0.98)
		else:
			pin.text = "M%d · MIRROR" % mark_num
			pin.modulate = Color(0.45, 0.88, 1.0, 0.92)
		pin.visible = not bool(pin.get_meta("cinematic_hidden", false))
	elif in_region:
		var old_m: Node3D = e.get_node_or_null("MarkPin") as Node3D
		if old_m != null:
			old_m.visible = false
		var rpin: Label3D = e.get_node_or_null("MarkRegionPin") as Label3D
		if rpin == null:
			rpin = Label3D.new()
			rpin.name = "MarkRegionPin"
			rpin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			rpin.no_depth_test = true
			rpin.fixed_size = true
			rpin.pixel_size = 0.0011
			rpin.font_size = 18
			rpin.outline_size = 5
			rpin.outline_modulate = Color(0.02, 0.02, 0.04, 0.9)
			e.add_child(rpin)
			rpin.position = Vector3(0.0, 2.35, 0.0)
			WorldLabelOverlay.adopt(rpin, {"px": 12, "offset": Vector2(0.0, -12.0), "max_dist": 200.0, "kind": "mark_nearby"})
		rpin.text = ""
		rpin.modulate = Color(1.0, 0.70, 0.25, 0.88)
		rpin.visible = not bool(rpin.get_meta("cinematic_hidden", false))
	else:
		_hide_mark_pins(e)


func _hide_mark_pins(n: Node) -> void:
	for nm in ["MarkPin", "MarkRegionPin"]:
		var p: Node3D = n.get_node_or_null(nm) as Node3D
		if p != null:
			p.visible = false


func _update_tag(e: EnemyAI, en: Dictionary) -> void:
	if not show_tags:
		_hide_tag(e)
		return
	var tag: Label3D = e.get_node_or_null("IntelTag") as Label3D
	if tag == null:
		tag = Label3D.new()
		tag.name = "IntelTag"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.0011
		tag.font_size = 22
		tag.outline_size = 6
		tag.outline_modulate = Color(0, 0, 0, 0.9)
		tag.font = UITheme.body_font()
		tag.modulate = Color(1.0, 0.86, 0.5, 0.95)
		e.add_child(tag)
		tag.position = Vector3(0, 2.45, 0)
		WorldLabelOverlay.adopt(tag, {"px": 14, "offset": Vector2(0, -16), "max_dist": 30.0})
	# Mirror insight reveals more: exact health and the exposed weak point.
	if e.mirror_insight:
		tag.text = "%s · %d%% · WEAK" % [String(en["id"]), int(en["hp_pct"])]
		tag.modulate = Color(0.55, 0.9, 1.0, 0.95)
	else:
		tag.text = String(en["id"])
		tag.modulate = Color(1.0, 0.86, 0.5, 0.95)
	tag.visible = show_tags and not bool(tag.get_meta("cinematic_hidden", false)) and float(en["dist"]) < 28.0


func _hide_tag(n: Node) -> void:
	var tag: Node3D = n.get_node_or_null("IntelTag") as Node3D
	if tag != null:
		tag.visible = false
```

- **Postcondition**: `WorldIntel` maintains `M1..M4` marks, keeps `18.0 m` region enemies detected (`10.0 s` linger on combat death), draws `MarkPin` & `MarkRegionPin` with `show_tags` remaining `false`, and resolves marked / region / explicit / default queries accurately.

---

### STEP-03 — Extend Offline `SquadCommandParser` for Mark & Region Phrasing

- **Prerequisites**: `STEP-02` complete.
- **Target**: `scripts/allies/squad_command_parser.gd`
- **Action**: Three `Replace block` edits in order.

#### Edit 3A — Add mark & mark-region entries to `TARGET_WORDS` (region phrases before `"marked"`)
Exact Original:
```gdscript
const TARGET_WORDS: Dictionary = {
	"brute": "brute", "big one": "brute", "grave": "brute", "caster": "caster", "hexcaster": "caster",
	"mage": "caster", "wizard": "caster", "stalker": "stalker", "shade": "stalker", "rogue": "stalker",
	"phantom": "phantom", "ghost": "phantom", "twin": "phantom", "shielded guard": "shield", "shield": "shield",
	"knight": "shield", "skeleton": "skeleton", "warden": "warden", "boss": "warden",
	"strongest": "strongest", "toughest": "strongest", "weakest": "weakest", "wounded": "weakest",
	"nearest": "nearest", "closest": "nearest", "that one": "nearest", "them": "nearest",
}
```
Replacement:
```gdscript
const TARGET_WORDS: Dictionary = {
	"marked group": "marked_group", "marked area": "marked_area", "marked region": "marked_region",
	"around the mark": "marked_region", "near the mark": "marked_region",
	"marked": "marked", "tagged": "marked", "pinged": "marked",
	"brute": "brute", "big one": "brute", "grave": "brute", "caster": "caster", "hexcaster": "caster",
	"mage": "caster", "wizard": "caster", "stalker": "stalker", "shade": "stalker", "rogue": "stalker",
	"phantom": "phantom", "ghost": "phantom", "twin": "phantom", "shielded guard": "shield", "shield": "shield",
	"knight": "shield", "skeleton": "skeleton", "warden": "warden", "boss": "warden",
	"strongest": "strongest", "toughest": "strongest", "weakest": "weakest", "wounded": "weakest",
	"nearest": "nearest", "closest": "nearest", "that one": "marked_or_nearest", "them": "nearest",
}
```

#### Edit 3B — Recognize `M1..M4`, `mark 1..4`, `"marked"`, `"tagged"`, `"pinged"`, `"the mark"` in `_has_descriptor()`
Exact Original:
```gdscript
static func _has_descriptor(t: String) -> bool:
	var rx := RegEx.new()
	rx.compile("\\b(?:e|enemy)\\s*#?\\s*\\d+\\b")
	if rx.search(t) != null:
		return true
	for w in DESCRIPTOR_WORDS:
		if t.contains(" " + w + " ") or t.contains(" " + w + "s "):
			return true
	return false
```
Replacement:
```gdscript
static func _has_descriptor(t: String) -> bool:
	var rx := RegEx.new()
	rx.compile("\\b(?:e|enemy)\\s*#?\\s*\\d+\\b")
	if rx.search(t) != null:
		return true
	var rx_mark := RegEx.new()
	rx_mark.compile("\\b(?:m|mark)\\s*#?\\s*[1-4]\\b")
	if rx_mark.search(t) != null:
		return true
	for mw in ["marked", "tagged", "pinged", "the mark"]:
		if t.contains(" " + mw + " "):
			return true
	for w in DESCRIPTOR_WORDS:
		if t.contains(" " + w + " ") or t.contains(" " + w + "s "):
			return true
	return false
```

#### Edit 3C — Protect mark vocabulary from typo snapping in `_build_vocab()`
Exact Original:
```gdscript
		for w in ["everyone", "everybody", "please", "there", "their", "these", "those", "where", "about", "right", "behind", "nearest", "closest",
				"while", "whilst", "whereas", "meanwhile", "others", "other", "rest", "else", "after", "afterwards", "seconds", "times", "front", "rear", "around"]:
			_vocab[w] = true
```
Replacement:
```gdscript
		for w in ["everyone", "everybody", "please", "there", "their", "these", "those", "where", "about", "right", "behind", "nearest", "closest",
				"marked", "mark", "tagged", "pinged", "group", "area", "region", "cluster",
				"while", "whilst", "whereas", "meanwhile", "others", "other", "rest", "else", "after", "afterwards", "seconds", "times", "front", "rear", "around"]:
			_vocab[w] = true
```

- **Postcondition**: `"M1!"`, `"attack marked"`, `"Sera kite the caster near M1"`, `"Ivo mirror barrage M1"`, `"nuke the marked group"`, `"attack that one"` all produce exact commands targeting marks / mark regions without breaking existing parser checks.

---
### STEP-04 — Wire Mark Awareness & Strategy Priority into `AllySquadManager`

- **Prerequisites**: `STEP-03` complete.
- **Target**: `scripts/allies/ally_squad_manager.gd`
- **Action**: Five `Replace block` edits in order.

#### Edit 4A — Clear marks & linger zones on `regroup(true)` (respawn / new run)
Exact Original:
```gdscript
	_combos.clear()
	if full_heal:
		_rally.clear()
		_rally_cooldown.clear()
		_rally_scan = 0.0
	_roster_dirty = true
```
Replacement:
```gdscript
	_combos.clear()
	if full_heal:
		_rally.clear()
		_rally_cooldown.clear()
		_rally_scan = 0.0
		if intel != null:
			intel.clear_marks()
	_roster_dirty = true
```

#### Edit 4B — Include & prioritize marked / `18 m`-region enemies in `_active_enemies_near()`, `resolve_enemy()`, and `pick_enemy_for()`
Exact Original:
```gdscript
func _active_enemies_near(pos: Vector3, radius: float) -> Array[EnemyAI]:
	var out: Array[EnemyAI] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = node as EnemyAI
		if e == null or e.is_dead or not e.is_active or not e.is_inside_tree() or not e.is_hittable_now():
			continue
		var in_radius: bool = e.global_position.distance_to(pos) <= radius and absf(e.global_position.y - pos.y) < 5.0
		var cam_vis: bool = radius >= 25.0 and intel != null and intel.is_camera_visible(e)
		if in_radius or cam_vis:
			out.append(e)
	return out


func resolve_enemy(selector: String, near: Vector3) -> EnemyAI:
	var sel: String = selector.strip_edges().to_lower()
	# "ally:Sera" / "Sera's target": whatever that ally is fighting.
	if sel.begins_with("ally:") or sel.ends_with("'s target"):
		var mate: SquadAlly = find_ally(sel.trim_prefix("ally:").trim_suffix("'s target"))
		if mate != null:
			var et: EnemyAI = mate._engage_target
			if (et == null or not is_instance_valid(et)) and mate.current != null:
				et = mate.current.data.get("enemy", null) as EnemyAI
			if et != null and is_instance_valid(et) and not et.is_dead and et.is_active and et.is_hittable_now():
				return et
		sel = "nearest"
	# Shared knowledge base: IDs ("E3"), types, looks, colours, weapons, sides, "near Sera", "hitting Ivo"...
	if intel != null:
		return intel.resolve(sel)
	var cands: Array[EnemyAI] = _active_enemies_near(near, 25.0)
	if cands.is_empty():
		return null
	var filtered: Array[EnemyAI] = []
	if sel in ["brute", "caster", "stalker", "phantom", "shield", "skeleton", "warden"]:
		for e in cands:
			if _enemy_kind(e) == sel:
				filtered.append(e)
	elif not (sel in ["", "nearest", "strongest", "weakest", "any", "them", "it"]):
		for e in cands:
			var dn: String = String(e.call("get_display_name")) if e.has_method("get_display_name") else String(e.name)
			if dn.to_lower().contains(sel) or String(e.name).to_lower().contains(sel):
				filtered.append(e)
	if filtered.is_empty():
		filtered = cands
	var best: EnemyAI = null
	var bs: float = INF
	for e in filtered:
		var s: float = e.global_position.distance_to(near)
		if sel == "strongest":
			s = -float(e.health)
		elif sel == "weakest":
			s = float(e.health) / float(maxi(1, e.max_health))
		if e.is_aggroed():
			s -= 0.5 if sel in ["strongest", "weakest"] else 4.0
		if s < bs:
			bs = s
			best = e
	return best


## No-stacking auto-target: prefers enemies threatening the player / this ally and penalises enemies that
## other allies already hold.
func pick_enemy_for(ally: SquadAlly, player: Node3D, radius: float, any: bool) -> EnemyAI:
	var center: Vector3 = ally.global_position
	var pool: Array[EnemyAI] = _active_enemies_near(center, radius)
	if player != null:
		for e in _active_enemies_near(player.global_position, radius):
			if not pool.has(e):
				pool.append(e)
	var best: EnemyAI = null
	var bs: float = INF
	for e in pool:
		var t: Node3D = e.get_current_target()
		if not any and not e.is_aggroed() and e.global_position.distance_to(center) > ally.profile.aggro_radius * 0.7:
			continue
		var s: float = e.global_position.distance_to(center)
		if t == player:
			s -= 3.0
		elif t == ally:
			s -= 2.0
		for o in allies:
			if o != ally and is_instance_valid(o) and o._engage_target == e:
				s += 4.0
		if s < bs:
			bs = s
			best = e
	return best
```
Replacement:
```gdscript
func _active_enemies_near(pos: Vector3, radius: float) -> Array[EnemyAI]:
	var out: Array[EnemyAI] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = node as EnemyAI
		if e == null or e.is_dead or not e.is_active or not e.is_inside_tree() or not e.is_hittable_now():
			continue
		var in_radius: bool = e.global_position.distance_to(pos) <= radius and absf(e.global_position.y - pos.y) < 5.0
		var vis_or_marked: bool = radius >= 20.0 and intel != null and (intel.is_camera_visible(e) or intel.is_marked_or_in_region(e))
		if in_radius or vis_or_marked:
			out.append(e)
	return out


func resolve_enemy(selector: String, near: Vector3, asker: Node3D = null) -> EnemyAI:
	var sel: String = selector.strip_edges().to_lower()
	# "ally:Sera" / "Sera's target": whatever that ally is fighting.
	if sel.begins_with("ally:") or sel.ends_with("'s target"):
		var mate: SquadAlly = find_ally(sel.trim_prefix("ally:").trim_suffix("'s target"))
		if mate != null:
			var et: EnemyAI = mate._engage_target
			if (et == null or not is_instance_valid(et)) and mate.current != null:
				et = mate.current.data.get("enemy", null) as EnemyAI
			if et != null and is_instance_valid(et) and not et.is_dead and et.is_active and et.is_hittable_now():
				return et
		sel = "nearest"
	# Shared knowledge base: marks ("M1", "marked"), IDs ("E3"), types, looks, colours, weapons, sides...
	if intel != null:
		return intel.resolve(sel, asker)
	var cands: Array[EnemyAI] = _active_enemies_near(near, 25.0)
	if cands.is_empty():
		return null
	var filtered: Array[EnemyAI] = []
	if sel in ["brute", "caster", "stalker", "phantom", "shield", "skeleton", "warden"]:
		for e in cands:
			if _enemy_kind(e) == sel:
				filtered.append(e)
	elif not (sel in ["", "nearest", "strongest", "weakest", "any", "them", "it", "marked_or_nearest"]):
		for e in cands:
			var dn: String = String(e.call("get_display_name")) if e.has_method("get_display_name") else String(e.name)
			if dn.to_lower().contains(sel) or String(e.name).to_lower().contains(sel):
				filtered.append(e)
	if filtered.is_empty():
		filtered = cands
	var best: EnemyAI = null
	var bs: float = INF
	for e in filtered:
		var s: float = e.global_position.distance_to(near)
		if sel == "strongest":
			s = -float(e.health)
		elif sel == "weakest":
			s = float(e.health) / float(maxi(1, e.max_health))
		if e.is_aggroed():
			s -= 0.5 if sel in ["strongest", "weakest"] else 4.0
		if s < bs:
			bs = s
			best = e
	return best


## No-stacking auto-target: prefers enemies threatening the player / this ally (or marked packs in massacre)
## and penalises enemies that other allies already hold.
func pick_enemy_for(ally: SquadAlly, player: Node3D, radius: float, any: bool) -> EnemyAI:
	var center: Vector3 = ally.global_position
	var pool: Array[EnemyAI] = _active_enemies_near(center, radius)
	if player != null:
		for e in _active_enemies_near(player.global_position, radius):
			if not pool.has(e):
				pool.append(e)
	var best: EnemyAI = null
	var bs: float = INF
	for e in pool:
		var t: Node3D = e.get_current_target()
		var is_mark_target: bool = intel != null and intel.is_marked_or_in_region(e)
		if not any and not is_mark_target and not e.is_aggroed() and e.global_position.distance_to(center) > ally.profile.aggro_radius * 0.7:
			continue
		var s: float = e.global_position.distance_to(center)
		if intel != null:
			if intel.is_marked(e):
				s -= 200.0 if any else 3.0
			elif intel.is_in_mark_region(e):
				s -= 150.0 if any else 1.5
		if t == player:
			s -= 3.0
		elif t == ally:
			s -= 2.0
		for o in allies:
			if o != ally and is_instance_valid(o) and o._engage_target == e:
				s += 8.0 if (any and is_mark_target) else 4.0
		if s < bs:
			bs = s
			best = e
	return best
```

#### Edit 4C — Prioritize marked enemies & their `18 m` region pack in `execute_strategy()` (`$distinct`, `$weakest_distinct`, default target)
Exact Original:
```gdscript
	var near: Vector3 = _player.global_position if _player != null else Vector3.ZERO
	var primary: EnemyAI = resolve_enemy(target_sel if not target_sel.is_empty() else "nearest", near)
	var primary_id: String = intel.id_of(primary) if primary != null and intel != null else "nearest"
	var by_dist: Array[EnemyAI] = []
	var by_hp: Array[EnemyAI] = []
	if intel != null:
		intel.refresh()
		for en in intel.get_entries():
			var raw_node: Variant = en.get("node")
			if not is_instance_valid(raw_node) or not (raw_node is EnemyAI):
				continue
			var en_node: EnemyAI = raw_node as EnemyAI
			if not en_node.is_dead and en_node.is_active and en_node.is_inside_tree() and en_node.is_hittable_now():
				by_dist.append(en_node)
		by_hp = by_dist.duplicate()
		by_hp.sort_custom(func(x: EnemyAI, y: EnemyAI) -> bool: return float(x.health) / float(maxi(1, x.max_health)) < float(y.health) / float(maxi(1, y.max_health)))
```
Replacement:
```gdscript
	var near: Vector3 = _player.global_position if _player != null else Vector3.ZERO
	var primary: EnemyAI = resolve_enemy(target_sel, near)
	var primary_id: String = intel.id_of(primary) if primary != null and intel != null else "nearest"
	var by_dist: Array[EnemyAI] = []
	var by_hp: Array[EnemyAI] = []
	if intel != null:
		intel.refresh()
		var mark_list: Array[EnemyAI] = []
		var region_list: Array[EnemyAI] = []
		var other_list: Array[EnemyAI] = []
		for en in intel.get_entries():
			var raw_node: Variant = en.get("node")
			if not is_instance_valid(raw_node) or not (raw_node is EnemyAI):
				continue
			var en_node: EnemyAI = raw_node as EnemyAI
			if en_node.is_dead or not en_node.is_active or not en_node.is_inside_tree() or not en_node.is_hittable_now():
				continue
			if bool(en.get("marked", false)):
				mark_list.append(en_node)
			elif bool(en.get("in_mark_region", false)):
				region_list.append(en_node)
			else:
				other_list.append(en_node)
		by_dist.append_array(mark_list)
		by_dist.append_array(region_list)
		by_dist.append_array(other_list)
		var hp_cmp := func(x: EnemyAI, y: EnemyAI) -> bool: return float(x.health) / float(maxi(1, x.max_health)) < float(y.health) / float(maxi(1, y.max_health))
		var pack_hp: Array[EnemyAI] = []
		pack_hp.append_array(mark_list)
		pack_hp.append_array(region_list)
		pack_hp.sort_custom(hp_cmp)
		var other_hp: Array[EnemyAI] = other_list.duplicate()
		other_hp.sort_custom(hp_cmp)
		by_hp.append_array(pack_hp)
		by_hp.append_array(other_hp)
```

#### Edit 4D — Default omitted combo targets to primary mark in `_start_combo()`
Exact Original:
```gdscript
	var near: Vector3 = _player.global_position if _player != null else Vector3.ZERO
	if resolve_enemy(String(args.get("target", "nearest")), near) == null:
```
Replacement:
```gdscript
	var near: Vector3 = _player.global_position if _player != null else Vector3.ZERO
	if resolve_enemy(String(args.get("target", "")), near) == null:
```

#### Edit 4E — Scale combo timeout to `70.0 s` when engaging marked or distant enemies in `_tick_combos()`
Exact Original:
```gdscript
		_combo_coordinate(rec)
		if float(rec["t"]) > 40.0:
			_abort_combo(int(id), "timed out")
			return
```
Replacement:
```gdscript
		_combo_coordinate(rec)
		var combo_timeout: float = 40.0
		if intel != null and intel.has_marks():
			combo_timeout = 70.0
		else:
			for part_v in parts.values():
				if is_instance_valid(part_v) and part_v is Node3D and _player != null and (_player as Node3D).global_position.distance_to((part_v as Node3D).global_position) > 25.0:
					combo_timeout = 70.0
					break
		if float(rec["t"]) > combo_timeout:
			_abort_combo(int(id), "timed out")
			return
```

- **Postcondition**: `AllySquadManager` clears marks on `regroup(true)` and routes `divide_and_conquer`, `guerrilla`, `pick_off_wounded`, `focus_fire`, `massacre`, and two-ally combos onto distant marked targets and their `18.0 m` region pack.

---

### STEP-05 — Implement Free Leash, Safe Pit Rescue, Local Unstick & Distant Approach Scaling in `SquadAlly`

- **Prerequisites**: `STEP-04` complete.
- **Target**: `scripts/allies/squad_ally.gd`
- **Action**: Twelve `Replace block` edits in order.

#### Edit 5A — Add `has_free_leash()` right after `_is_massacre()`
Exact Original:
```gdscript
func _is_ceasefire() -> bool:
	return current != null and current.verb == "ceasefire"


func _is_massacre() -> bool:
	return current != null and current.verb == "massacre"
```
Replacement:
```gdscript
func _is_ceasefire() -> bool:
	return current != null and current.verb == "ceasefire"


func _is_massacre() -> bool:
	return current != null and current.verb == "massacre"


## Allies executing any non-passive command (anything other than follow / ceasefire) roam freely without
## distance-teleportation back to the player.
func has_free_leash() -> bool:
	if current != null and not current.done and not (current.verb in ["follow", "ceasefire"]):
		return true
	for q in queue:
		if q != null and not q.done and not (q.verb in ["follow", "ceasefire"]):
			return true
	return false
```

#### Edit 5B — Honor active marks when `"attack"` omits target
Exact Original:
```gdscript
func _run_attack(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		if cmd.data.has("enemy"):
			finish_current("target down")
			say_event("kill", 0)
			return
		e = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
```
Replacement:
```gdscript
func _run_attack(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		if cmd.data.has("enemy"):
			finish_current("target down")
			say_event("kill", 0)
			return
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
```

#### Edit 5C — Honor marks & scale approach timeout in `_run_taunt_cmd()`
Exact Original:
```gdscript
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
```
Replacement:
```gdscript
		if targets.is_empty():
			var fallback: EnemyAI = _resolve_enemy(String(cmd.args.get("target", "")), player)
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
				if cmd.timer > _approach_timeout(10.0, anchor, cmd):
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
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null or not _enemy_ok(e):
			say("Nothing to taunt.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
	if global_position.distance_to(e.global_position) > 7.0:
		if cmd.timer > _approach_timeout(12.0, e.global_position, cmd):
			say("Can't get close enough to taunt.", "refuse", 1)
			finish_current("out of range")
			return
```

#### Edit 5D — Honor marks & scale approach timeout in `_kite_logic()`
Exact Original:
```gdscript
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		var near_pos: Vector3 = global_position
		e = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
```
Replacement:
```gdscript
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		var near_pos: Vector3 = global_position
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
```

Exact Original:
```gdscript
		"approach":
			cmd.data["approach_t"] = float(cmd.data.get("approach_t", 0.0)) + delta
			if float(cmd.data["approach_t"]) > 9.0:
				_kite_fallback(cmd, e, "Can't reach it — I'll fight from here.")
				return
```
Replacement:
```gdscript
		"approach":
			cmd.data["approach_t"] = float(cmd.data.get("approach_t", 0.0)) + delta
			if float(cmd.data["approach_t"]) > _approach_timeout(9.0, e.global_position, cmd):
				_kite_fallback(cmd, e, "Can't reach it — I'll fight from here.")
				return
```

#### Edit 5E — Honor marks when `"nuke"` omits target
Exact Original:
```gdscript
func _run_nuke(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if cmd.step.is_empty():
		var e: EnemyAI = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
```
Replacement:
```gdscript
func _run_nuke(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if cmd.step.is_empty():
		var e: EnemyAI = _resolve_enemy(String(cmd.args.get("target", "")), player)
```

#### Edit 5F — Honor marks in `_run_charger()` and `_run_finisher()`
Exact Original:
```gdscript
		e = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
		if e == null:
			say("No one to charge.", "refuse", 1)
			_post_combo(cmd, "failed", {})
			finish_current("no target")
			return
		cmd.data["enemy"] = e
		cmd.step = "approach"
```
Replacement:
```gdscript
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null:
			say("No one to charge.", "refuse", 1)
			_post_combo(cmd, "failed", {})
			finish_current("no target")
			return
		cmd.data["enemy"] = e
		cmd.step = "approach"
```

Exact Original:
```gdscript
		"waiting":
			var watch: EnemyAI = e if e != null else _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
```
Replacement:
```gdscript
		"waiting":
			var watch: EnemyAI = e if e != null else _resolve_enemy(String(cmd.args.get("target", "")), player)
```

#### Edit 5G — Honor marks & scale approach timeout in `_run_skill()`
Exact Original:
```gdscript
		match s.target_kind:
			"enemy":
				tgt = _resolve_enemy(tsel if not tsel.is_empty() else "nearest", player)
				if tgt == null and _engage_target != null and _enemy_ok(_engage_target):
					tgt = _engage_target
```
Replacement:
```gdscript
		match s.target_kind:
			"enemy":
				tgt = _resolve_enemy(tsel, player)
				if tgt == null and _engage_target != null and _enemy_ok(_engage_target):
					tgt = _engage_target
```

Exact Original:
```gdscript
	if tgt != null and need > 0.0 and tgt.global_position.distance_to(global_position) > need - 0.3:
		_move_to(tgt.global_position, profile.move_speed * 1.2, delta)
		if cmd.timer > 10.0:
			say("Can't get in range.", "refuse", 1)
			finish_current("out of range")
		return
```
Replacement:
```gdscript
	if tgt != null and need > 0.0 and tgt.global_position.distance_to(global_position) > need - 0.3:
		_move_to(tgt.global_position, profile.move_speed * 1.2, delta)
		if cmd.timer > _approach_timeout(10.0, tgt.global_position, cmd):
			say("Can't get in range.", "refuse", 1)
			finish_current("out of range")
		return
```

#### Edit 5H — Honor marks & scale approach timeout in `_run_surround()`
Exact Original:
```gdscript
		e = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
		if e == null:
			finish_current("no target")
			return
		cmd.data["enemy"] = e
	var axis: Vector3 = (player.global_position - e.global_position) if player != null else -e.get_facing_direction()
	axis.y = 0.0
	if axis.length_squared() < 0.01:
		axis = Vector3.FORWARD
	if String(cmd.args.get("side", "")) == "rear":
		_sneak_attack(delta, cmd, e)
		return
	var ang: float = deg_to_rad(float(cmd.args.get("angle", 120.0)))
	var slot: Vector3 = e.global_position + axis.normalized().rotated(Vector3.UP, ang) * maxf(1.4, profile.attack_range * 0.85)
	if not bool(cmd.data.get("in_slot", false)) and global_position.distance_to(slot) > 1.0:
		cmd.step = "flanking"
		_move_to(slot, profile.move_speed * 1.15, delta, false)
		if cmd.timer > 6.0:
			cmd.data["in_slot"] = true
		return
```
Replacement:
```gdscript
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null:
			finish_current("no target")
			return
		cmd.data["enemy"] = e
	var axis: Vector3 = (player.global_position - e.global_position) if player != null else -e.get_facing_direction()
	axis.y = 0.0
	if axis.length_squared() < 0.01:
		axis = Vector3.FORWARD
	if String(cmd.args.get("side", "")) == "rear":
		_sneak_attack(delta, cmd, e)
		return
	var ang: float = deg_to_rad(float(cmd.args.get("angle", 120.0)))
	var slot: Vector3 = e.global_position + axis.normalized().rotated(Vector3.UP, ang) * maxf(1.4, profile.attack_range * 0.85)
	if not bool(cmd.data.get("in_slot", false)) and global_position.distance_to(slot) > 1.0:
		cmd.step = "flanking"
		_move_to(slot, profile.move_speed * 1.15, delta, false)
		if cmd.timer > _approach_timeout(6.0, slot, cmd):
			cmd.data["in_slot"] = true
		return
```

#### Edit 5I — Honor marks & scale approach vs raid timer in `_run_hit_and_run()`
Exact Original:
```gdscript
		e = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
		if e == null:
			say("No target for a raid.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
		cmd.step = "in"
	match cmd.step:
		"in":
			if global_position.distance_to(e.global_position) > profile.attack_range:
				_move_to(e.global_position, profile.move_speed * 1.3, delta, false)
			elif _attack_cd <= 0.0:
				_melee(e)
				cmd.step = "out"
				cmd.data["out_t"] = 0.0
		"out":
			cmd.data["out_t"] = float(cmd.data.get("out_t", 0.0)) + delta
			var away: Vector3 = global_position - e.global_position
			away.y = 0.0
			if away.length() < 5.5 and float(cmd.data["out_t"]) < 2.0:
				_move_dir(away.normalized(), profile.move_speed * 1.3, delta)
			else:
				_halt(delta)
				set_facing(e.global_position - global_position)
				if float(cmd.data["out_t"]) > 2.2:
					cmd.step = "in"
	if cmd.timer > 16.0:
		finish_current("raid over")
```
Replacement:
```gdscript
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null:
			say("No target for a raid.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
		cmd.step = "in"
	if not bool(cmd.data.get("engaged", false)):
		if global_position.distance_to(e.global_position) <= 8.0:
			cmd.data["engaged"] = true
		elif cmd.timer > _approach_timeout(16.0, e.global_position, cmd):
			say("Can't reach target for a raid.", "refuse", 1)
			finish_current("out of range")
			return
	match cmd.step:
		"in":
			if global_position.distance_to(e.global_position) > profile.attack_range:
				_move_to(e.global_position, profile.move_speed * 1.3, delta, false)
			elif _attack_cd <= 0.0:
				_melee(e)
				cmd.step = "out"
				cmd.data["out_t"] = 0.0
		"out":
			cmd.data["out_t"] = float(cmd.data.get("out_t", 0.0)) + delta
			var away: Vector3 = global_position - e.global_position
			away.y = 0.0
			if away.length() < 5.5 and float(cmd.data["out_t"]) < 2.0:
				_move_dir(away.normalized(), profile.move_speed * 1.3, delta)
			else:
				_halt(delta)
				set_facing(e.global_position - global_position)
				if float(cmd.data["out_t"]) > 2.2:
					cmd.step = "in"
	if bool(cmd.data.get("engaged", false)):
		cmd.data["raid_t"] = float(cmd.data.get("raid_t", 0.0)) + delta
		if float(cmd.data["raid_t"]) > 16.0:
			finish_current("raid over")
```

#### Edit 5J — Lift `28.0 m` cap for explicit or marked/mark-region targets in `_run_ranged()`
Exact Original:
```gdscript
		var sel: String = String(cmd.args.get("target", ""))
		e = _resolve_enemy(sel if not sel.is_empty() else "nearest", player)
		if e == null or e.global_position.distance_to(global_position) > 28.0:
			if not cmd.data.has("enemy"):
				say("Nothing in range to shoot at.", "refuse", 1)
			finish_current("no target" if not cmd.data.has("enemy") else "area clear")
			return
```
Replacement:
```gdscript
		var sel: String = String(cmd.args.get("target", ""))
		e = _resolve_enemy(sel, player)
		var in_mark_scope: bool = not sel.is_empty() and sel != "nearest"
		if not in_mark_scope and e != null and manager != null:
			var intel_r: WorldIntel = manager.get("intel") as WorldIntel
			in_mark_scope = intel_r != null and intel_r.is_marked_or_in_region(e)
		if e == null or (not in_mark_scope and e.global_position.distance_to(global_position) > 28.0):
			if not cmd.data.has("enemy"):
				say("Nothing in range to shoot at.", "refuse", 1)
			finish_current("no target" if not cmd.data.has("enemy") else "area clear")
			return
```

#### Edit 5K — Replace distance-teleporting in `_update_stuck()` / `_catch_up()` with Free Leash + safe pit rescue + `_unstick_nudge()` + `_approach_timeout()`
Exact Original:
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
```
Replacement:
```gdscript
func _has_distant_order() -> bool:
	return has_free_leash()


func _distant_order_cam_visible() -> bool:
	if current == null or manager == null:
		return false
	var intel_node: WorldIntel = manager.get("intel") as WorldIntel
	if intel_node == null:
		return false
	var en: EnemyAI = current.data.get("enemy", null) as EnemyAI
	return en != null and (intel_node.is_camera_visible(en) or intel_node.is_marked_or_in_region(en))


func _approach_timeout(base_sec: float, target_pos: Vector3, cmd: SquadCommand = null) -> float:
	if cmd != null and cmd.data.has("approach_limit"):
		return float(cmd.data["approach_limit"])
	var spd: float = maxf(profile.move_speed if profile != null else 5.0, 3.0)
	var d: float = global_position.distance_to(target_pos)
	var lim: float = clampf(maxf(base_sec, d / spd + 8.0), base_sec, 45.0)
	if cmd != null:
		cmd.data["approach_limit"] = lim
	return lim


func _unstick_nudge() -> void:
	var fwd: Vector3 = facing_direction.normalized() if facing_direction.length_squared() > 0.001 else Vector3.FORWARD
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var sign_k: float = 1.0 if slot_index % 2 == 0 else -1.0
	for cand in [side * sign_k, -side * sign_k, -fwd]:
		var dir: Vector3 = cand as Vector3
		if _side_open(dir):
			velocity.x = dir.x * 3.5
			velocity.z = dir.z * 3.5
			return


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
		if has_free_leash():
			if _in_pit_kill_zone() or global_position.y < -20.0:
				if _has_safe_pos:
					global_position = _last_safe_pos + Vector3.UP * 0.05
					velocity = Vector3.ZERO
					_last_pos = global_position
				else:
					_blink_to(p)
				return
			_steer_dir = Vector3.ZERO
			_steer_timer = 0.0
			if is_on_floor():
				velocity.y = 4.5
			_unstick_nudge()
		elif global_position.distance_to(p.global_position) > 6.0:
			_blink_to(p)


## Catch-up: allies are mirror echoes — passive follow/ceasefire allies blink back to the player when left behind,
## whereas allies under ANY active command (has_free_leash() == true) never distance-teleport and only rescue
## back to their own last safe ground position on real pit/void falls.
func _catch_up(player: Node3D) -> void:
	var free_leash: bool = has_free_leash()
	var in_pit: bool = _in_pit_kill_zone() or global_position.y < -20.0
	if free_leash:
		if not in_pit:
			return
		if _has_safe_pos:
			global_position = _last_safe_pos + Vector3.UP * 0.05
			velocity = Vector3.ZERO
			_last_pos = global_position
		else:
			_blink_to(player)
		return
	var d: Vector3 = player.global_position - global_position
	var cam_exempt: bool = _distant_order_cam_visible()
	var far: float = 150.0 if cam_exempt else FOLLOW_LEASH
	var fallen_pit: bool = in_pit or global_position.y < player.global_position.y - 6.0
	var vertical_trap: bool = d.y > 3.0 and Vector2(d.x, d.z).length() < 10.0
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
				if hit.is_empty() and d.length() < (150.0 if cam_exempt else 40.0):
					return
	if player is PlayerController and (player as PlayerController).is_currently_airborne():
		if fallen_pit and _has_safe_pos:
			global_position = _last_safe_pos + Vector3.UP * 0.05
			velocity = Vector3.ZERO
			_last_pos = global_position
		return
	_blink_to(player)
```

#### Edit 5L — Forward `self` as `asker` in `_resolve_enemy()`
Exact Original:
```gdscript
func _resolve_enemy(selector: String, player: Node3D) -> EnemyAI:
	if manager != null and manager.has_method("resolve_enemy"):
		return manager.call("resolve_enemy", selector, player.global_position if player != null else global_position) as EnemyAI
	return _nearest_enemy(global_position, 20.0)
```
Replacement:
```gdscript
func _resolve_enemy(selector: String, player: Node3D) -> EnemyAI:
	if manager != null and manager.has_method("resolve_enemy"):
		return manager.call("resolve_enemy", selector, player.global_position if player != null else global_position, self) as EnemyAI
	return _nearest_enemy(global_position, 20.0)
```

- **Postcondition**: Any ally running a non-`follow`/`ceasefire` command has `has_free_leash() == true`, never auto-teleports for distance or height differences, recovers locally on ledges/voids via `_last_safe_pos` and `_unstick_nudge()`, scales travel timeouts smoothly, and lets passive `follow`/`ceasefire` allies blink normally.

---
### STEP-06 — Add `T` / `MMB` Mark & `X` Clear Input, Lock-On Reticle & HUD Readout in `SquadCommsHUD`

- **Prerequisites**: `STEP-05` complete.
- **Target**: `scripts/ui/squad_comms_hud.gd`
- **Action**: Five `Replace block` edits in order.

#### Edit 6A — Add `mark_enemy` (`T`, `MMB`) & `clear_marks` (`X`) actions and `_aim_candidate` state
Exact Original:
```gdscript
const ACTIONS: Dictionary = {
	"squad_chat": [KEY_ENTER, KEY_KP_ENTER],
	"push_to_talk": [KEY_V],
	"toggle_command_log": [KEY_L],
	"cinematic_mode": [KEY_F10],
}
const ROLE_GLYPH: Dictionary = {"vanguard": "◆", "skirmisher": "➶", "artillery": "✦"}

var comms: SquadComms = null
var _chat_panel: UIFrame = null
var _chat_edit: LineEdit = null
var _chat_open: bool = false
var _mic_btn: Control = null
var _roster: Array = []
var _roster_timer: float = 0.0
var _subs: Array[Dictionary] = []        # {speaker, text, color, t, final}
var _notes: Array[Dictionary] = []       # {text, level, t}
var _log: Array[Dictionary] = []
var _log_visible: bool = true
var _mic_level: float = 0.0
var _cinematic: bool = false
var _ptt_held_key: bool = false
var _ptt_held_mouse: bool = false
```
Replacement:
```gdscript
const ACTIONS: Dictionary = {
	"squad_chat": [KEY_ENTER, KEY_KP_ENTER],
	"push_to_talk": [KEY_V],
	"toggle_command_log": [KEY_L],
	"cinematic_mode": [KEY_F10],
	"mark_enemy": [KEY_T],
	"clear_marks": [KEY_X],
}
const MOUSE_ACTIONS: Dictionary = {
	"mark_enemy": [MOUSE_BUTTON_MIDDLE],
}
const ROLE_GLYPH: Dictionary = {"vanguard": "◆", "skirmisher": "➶", "artillery": "✦"}

var comms: SquadComms = null
var _chat_panel: UIFrame = null
var _chat_edit: LineEdit = null
var _chat_open: bool = false
var _mic_btn: Control = null
var _roster: Array = []
var _roster_timer: float = 0.0
var _subs: Array[Dictionary] = []        # {speaker, text, color, t, final}
var _notes: Array[Dictionary] = []       # {text, level, t}
var _log: Array[Dictionary] = []
var _log_visible: bool = true
var _mic_level: float = 0.0
var _cinematic: bool = false
var _ptt_held_key: bool = false
var _ptt_held_mouse: bool = false
var _aim_candidate: EnemyAI = null
```

Exact Original:
```gdscript
static func _ensure_actions() -> void:
	for a in ACTIONS.keys():
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k in (ACTIONS[a] as Array):
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k) as Key
			InputMap.action_add_event(a, ev)
```
Replacement:
```gdscript
static func _ensure_actions() -> void:
	for a in ACTIONS.keys():
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			for k in (ACTIONS[a] as Array):
				var ev := InputEventKey.new()
				ev.physical_keycode = int(k) as Key
				InputMap.action_add_event(a, ev)
	for ma in MOUSE_ACTIONS.keys():
		var created: bool = false
		if not InputMap.has_action(ma):
			InputMap.add_action(ma)
			created = true
		if created or InputMap.action_get_events(ma).size() <= ACTIONS.get(ma, []).size():
			for b in (MOUSE_ACTIONS[ma] as Array):
				var mb := InputEventMouseButton.new()
				mb.button_index = int(b) as MouseButton
				if not InputMap.action_has_event(ma, mb):
					InputMap.action_add_event(ma, mb)
```

#### Edit 6B — Update chat bar placeholder hint with mark examples
Exact Original:
```gdscript
	_chat_edit.placeholder_text = "e.g.  Sera, kite the brute  ·  everyone massacre  ·  Brannoc guard Ivo  ·  jump 3 times"
```
Replacement:
```gdscript
	_chat_edit.placeholder_text = "e.g.  attack marked  ·  M1!  ·  Sera kite the caster near M1  ·  divide and conquer"
```

#### Edit 6C — Handle `mark_enemy` & `clear_marks` input and add mark action helpers
Exact Original:
```gdscript
	elif event.is_action_pressed("toggle_command_log") and not event.is_echo():
		_log_visible = not _log_visible
		SquadAIConfig.show_command_log = _log_visible
		SquadAIConfig.save()
		queue_redraw()


func _blocked_by_menu() -> bool:
```
Replacement:
```gdscript
	elif event.is_action_pressed("mark_enemy") and not event.is_echo():
		_handle_mark_enemy()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("clear_marks") and not event.is_echo():
		_handle_clear_marks()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("toggle_command_log") and not event.is_echo():
		_log_visible = not _log_visible
		SquadAIConfig.show_command_log = _log_visible
		SquadAIConfig.save()
		queue_redraw()


func _intel() -> WorldIntel:
	if AllySquadManager.instance != null and AllySquadManager.instance.intel != null:
		return AllySquadManager.instance.intel
	if is_inside_tree() and get_tree() != null:
		return get_tree().get_first_node_in_group("world_intel") as WorldIntel
	return null


func _is_finisher_open() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	var pl: Node = get_tree().get_first_node_in_group("player")
	return pl != null and pl.has_method("is_finisher_window_open") and bool(pl.call("is_finisher_window_open"))


func _handle_mark_enemy() -> void:
	var intel_n: WorldIntel = _intel()
	if intel_n == null:
		return
	var res: Dictionary = intel_n.mark_enemy_at_aim()
	var act: String = String(res.get("action", "none"))
	match act:
		"marked":
			if AudioManager.instance != null:
				AudioManager.instance.play_sfx("ui_confirm", -4.0)
			var m_num: int = int(res.get("mark_num", 1))
			var nearby: int = int(res.get("nearby_count", 0))
			var nm: String = String(res.get("name", "Enemy"))
			var extra: String = "  ·  +%d nearby in %dm" % [nearby, int(intel_n.mark_region_radius)] if nearby > 0 else ""
			_on_notify("Marked %s [M%d]%s" % [nm, m_num, extra], "info")
		"unmarked":
			if AudioManager.instance != null:
				AudioManager.instance.play_sfx("ui_back", -4.0)
			_on_notify("Unmarked %s" % String(res.get("name", "Enemy")), "info")
		_:
			_on_notify("No enemy in sights to mark", "info")
	queue_redraw()


func _handle_clear_marks() -> void:
	var intel_n: WorldIntel = _intel()
	if intel_n == null:
		return
	if not intel_n.has_marks() and not intel_n.has_mark_zones():
		return
	intel_n.clear_marks()
	if AudioManager.instance != null:
		AudioManager.instance.play_sfx("ui_back", -4.0)
	_on_notify("Cleared all enemy marks", "info")
	queue_redraw()


func _blocked_by_menu() -> bool:
```

#### Edit 6D — Include `MarkPin` and `MarkRegionPin` in `set_cinematic()`
Exact Original:
```gdscript
	for e in get_tree().get_nodes_in_group("enemy"):
		for nm in ["FloatingHPBar", "StateIcon", "IntelTag"]:
			var l: Node3D = (e as Node).get_node_or_null(nm) as Node3D
			if l != null:
				l.set_meta("cinematic_hidden", on)
				if on:
					l.visible = false
				elif nm == "FloatingHPBar":
					l.visible = true
```
Replacement:
```gdscript
	for e in get_tree().get_nodes_in_group("enemy"):
		for nm in ["FloatingHPBar", "StateIcon", "IntelTag", "MarkPin", "MarkRegionPin"]:
			var l: Node3D = (e as Node).get_node_or_null(nm) as Node3D
			if l != null:
				l.set_meta("cinematic_hidden", on)
				if on:
					l.visible = false
				elif nm == "FloatingHPBar":
					l.visible = true
	if not on:
		var intel_n: WorldIntel = _intel()
		if intel_n != null:
			intel_n.refresh()
```

#### Edit 6E — Update `_process()` and `_draw()` with aim reticle, mark hint, and active-mark bar
Exact Original:
```gdscript
	if _mic_btn != null:
		_mic_btn.position = Vector2(s.x - 108.0, s.y * 0.5 + 60.0)
		_mic_btn.visible = SquadAIConfig.voice_allowed()
		_mic_btn.queue_redraw()
	queue_redraw()


func _draw() -> void:
	if _cinematic:
		return
	var s: Vector2 = size
	# Minimal squad readout directly under the player's own health cluster (top-left, ends at y ~136).
	var end_y: float = _draw_roster(Vector2(36.0, 150.0))
	_draw_subtitles(s)
	_draw_notes(s)
	if _log_visible:
		_draw_log(Vector2(s.x - 470.0, s.y * 0.30))
	if not _chat_open and SquadAIConfig.chat_allowed() and not _roster.is_empty():
		var hint: String = "ENTER orders" + ("  ·  V talk" if SquadAIConfig.voice_allowed() else "") + "  ·  L log"
		_text(UITheme.body_font(), Vector2(36.0, end_y + 12.0), hint, 13, Color(0.95, 0.9, 0.78, 0.6), 3)
```
Replacement:
```gdscript
	var intel_n: WorldIntel = _intel()
	if intel_n != null and not _chat_open and not _cinematic and not _blocked_by_menu() and not _is_finisher_open():
		_aim_candidate = intel_n.peek_aim_candidate()
	else:
		_aim_candidate = null
	if _mic_btn != null:
		_mic_btn.position = Vector2(s.x - 108.0, s.y * 0.5 + 60.0)
		_mic_btn.visible = SquadAIConfig.voice_allowed()
		_mic_btn.queue_redraw()
	queue_redraw()


func _draw() -> void:
	if _cinematic:
		return
	var s: Vector2 = size
	# Minimal squad readout directly under the player's own health cluster (top-left, ends at y ~136).
	var end_y: float = _draw_roster(Vector2(36.0, 150.0))
	_draw_subtitles(s)
	_draw_notes(s)
	if _log_visible:
		_draw_log(Vector2(s.x - 470.0, s.y * 0.30))
	if not _chat_open and SquadAIConfig.chat_allowed() and not _roster.is_empty():
		var hint: String = "ENTER orders" + ("  ·  V talk" if SquadAIConfig.voice_allowed() else "") + "  ·  T/MMB mark  ·  X clear  ·  L log"
		_text(UITheme.body_font(), Vector2(36.0, end_y + 12.0), hint, 13, Color(0.95, 0.9, 0.78, 0.6), 3)
		_draw_marks_bar(Vector2(36.0, end_y + 30.0))
	_draw_mark_reticle(s)


func _draw_marks_bar(pos: Vector2) -> void:
	var intel_n: WorldIntel = _intel()
	if intel_n == null or not intel_n.has_marks():
		return
	var parts: PackedStringArray = []
	for sm in intel_n.get_marked_summaries():
		parts.append("M%d %s (%.0fm)" % [int(sm.get("num", 1)), String(sm.get("name", "Enemy")), float(sm.get("dist", 0.0))])
	if parts.is_empty():
		return
	_text(UITheme.body_font(), pos, "MARKED:  " + "  ·  ".join(parts), 13, Color(1.0, 0.86, 0.42, 0.92), 3)


func _draw_mark_reticle(s: Vector2) -> void:
	if _aim_candidate == null or not is_instance_valid(_aim_candidate) or _aim_candidate.is_dead:
		return
	var intel_n: WorldIntel = _intel()
	if intel_n == null:
		return
	var already: bool = intel_n.is_marked(_aim_candidate)
	var col: Color = Color(1.0, 0.42, 0.32, 0.88) if already else Color(1.0, 0.86, 0.38, 0.85)
	var c: Vector2 = s * 0.5
	var r: float = 12.0
	var corners: Array[Vector2] = [c + Vector2(0.0, -r), c + Vector2(r, 0.0), c + Vector2(0.0, r), c + Vector2(-r, 0.0)]
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		draw_line(a, a.lerp(b, 0.35), col, 1.8, true)
		draw_line(b, b.lerp(a, 0.35), col, 1.8, true)
	var lbl: String = "T / MMB  UNMARK" if already else "T / MMB  MARK"
	var body: Font = UITheme.body_font()
	var w: float = body.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(body, Vector2(c.x - w * 0.5, c.y + r + 18.0), lbl, 13, col, 3)
```

- **Postcondition**: Pressing `T` / `MMB` marks or unmarks aimed distant enemies cleanly with visual reticle, pin updates, audio cue, and toast; `X` clears all marks; `F10` hides pins & reticle cleanly.

---

### STEP-07 — Expose Marked Targets & Rules to the Online LLM Director in `SquadComms`

- **Prerequisites**: `STEP-06` complete.
- **Target**: `addons/parallax_squad_ai/squad_comms.gd`
- **Action**: Three `Replace block` edits in order.

#### Edit 7A — Update tool parameter descriptions for `M1..M4`, `"marked"`, `"marked group"`, and default-to-mark behavior
Exact Original:
```gdscript
				"target": {"type": "string", "description": "Enemy: an ID from BATTLEFIELD (e.g. \"E3\") — always prefer IDs; or nearest/strongest/weakest; or 'ally:<Name>' = whatever that ally is fighting. bodyguard: an ally name, 'player' or 'objective'. revive: an ally name. interact: 'chest' or blank. ranged: optional enemy (blank = keep shooting the nearest until clear)."},
```
Replacement:
```gdscript
				"target": {"type": "string", "description": "Enemy: a player mark ('M1'..'M4', 'marked', or 'marked group' for enemies inside a mark's 18 m radius — leave blank to default to M1 when marked), OR a BATTLEFIELD ID ('E3'), nearest/strongest/weakest, or 'ally:<Name>'. bodyguard: ally name/'player'/'objective'. revive: ally name. interact: 'chest'/blank. ranged: optional enemy (blank = keep shooting marked/nearest until clear)."},
```

Exact Original:
```gdscript
		{"type": "function", "function": {
			"name": "execute_strategy",
			"description": "Run a squad strategy from STRATEGIES. The game assigns every living ally a part by role.",
			"parameters": {"type": "object", "properties": {
				"strategy": {"type": "string", "enum": SquadStrategies.ids()},
				"target": {"type": "string", "description": "Primary enemy ID (optional)."},
```
Replacement:
```gdscript
		{"type": "function", "function": {
			"name": "execute_strategy",
			"description": "Run a squad strategy from STRATEGIES. The game assigns every living ally a part by role.",
			"parameters": {"type": "object", "properties": {
				"strategy": {"type": "string", "enum": SquadStrategies.ids()},
				"target": {"type": "string", "description": "Primary mark/enemy ID such as 'M1', 'marked', or 'E3' (optional; defaults to M1 if marked)."},
```

#### Edit 7B — Inject `MARKED TARGETS` & Rule `(12)` into `build_system_prompt()`
Exact Original:
```gdscript
func build_system_prompt(focus_ally: SquadAlly = null) -> String:
	var roster: String = _manager.get_roster_text() if _manager != null else ""
	var skills: String = _manager.get_skills_text() if _manager != null else ""
	var field: String = _manager.intel.describe_text() if _manager != null and _manager.intel != null else "unknown"
```
Replacement:
```gdscript
func build_system_prompt(focus_ally: SquadAlly = null) -> String:
	var roster: String = _manager.get_roster_text() if _manager != null else ""
	var skills: String = _manager.get_skills_text() if _manager != null else ""
	var marks: String = _manager.intel.describe_marks_text() if _manager != null and _manager.intel != null else "- none"
	var field: String = _manager.intel.describe_text() if _manager != null and _manager.intel != null else "unknown"
```

Exact Original:
```gdscript
		+ "RULES: (1) Turn every order into tool calls in THIS response (parallel calls allowed). (2) Refer to enemies by their BATTLEFIELD ID (E#): when the player describes one by look, colour, weapon, size, position (left/right/behind, near an ally) or behaviour (who it is hitting, stunned, fleeing), pick the matching ID. (3) Use allies' OWN skills when they fit; a skill belongs to exactly one ally. (4) Prefer a STRATEGY when the player describes a plan for the whole squad. (5) Reply only through `say`, in character, 1 short line per speaker, max 2 speakers; no narration. Questions about the fight: answer from BATTLEFIELD/ROSTER via `say`. (6) massacre / ceasefire / scatter are panic orders. Silly orders are fine — jump, dance, emotes, circle, face, backflips; play along in character. (7) A DOWN ally can't act: say so and suggest a revive. Never invent allies, enemies, skills or strategies. (8) One message often mixes everything: simple orders, chains (\"then\", \"after that\"), several allies each with their OWN different chain, plus chat. Decompose it fully: for each ally, emit its steps as separate tool calls IN ORDER (they run as a chain); 'everyone else' = the allies not named elsewhere. Movement words: get behind me/in front/left/right/close/keep distance = position; hold/watch the rear = rearguard; long-distance / shoot / throw = ranged; wait N seconds = wait; bait / run circles / keep it busy = kite (lure_to_player when they want it brought back); sneak attack / backstab / get behind IT = sneak_attack. A taunted or baited enemy chases its taunter until that ally is down, so pair a bait with a sneak_attack or attacks from the others. (9) Plain conversation (greetings, jokes, questions, banter) = only `say`, no orders. (10) The squad auto-rallies to protect anyone at low HP; don't fight that unless told. (11) Every `say` line must describe ONLY what that ally was ordered to do in THIS response (or answer the player's question) — never announce a plan, target or skill you did not issue as a tool call, never narrate other allies, no lore or filler. Default to ONE speaker; use two only when the player addressed several allies.\n" \
		+ focus \
		+ "PERSONALITIES (flavour only):\n%s\n" % "\n".join(personas) \
		+ "ROSTER (live):\n%s\n" % roster \
		+ "SKILLS:\n%s\n" % skills \
		+ "STRATEGIES:\n%s\n" % SquadStrategies.describe_all() \
		+ "BATTLEFIELD (live, nearest first; bearing is relative to the player's facing):\n%s\n" % field \
```
Replacement:
```gdscript
		+ "RULES: (1) Turn every order into tool calls in THIS response (parallel calls allowed). (2) Refer to enemies by their BATTLEFIELD ID (E#) or player mark (M1..M4): when the player describes one by look, colour, weapon, size, position (left/right/behind, near an ally, around/near M#) or behaviour (who it is hitting, stunned, fleeing), pick the matching ID. (3) Use allies' OWN skills when they fit; a skill belongs to exactly one ally. (4) Prefer a STRATEGY when the player describes a plan for the whole squad. (5) Reply only through `say`, in character, 1 short line per speaker, max 2 speakers; no narration. Questions about the fight: answer from BATTLEFIELD/ROSTER via `say`. (6) massacre / ceasefire / scatter are panic orders. Silly orders are fine — jump, dance, emotes, circle, face, backflips; play along in character. (7) A DOWN ally can't act: say so and suggest a revive. Never invent allies, enemies, skills or strategies. (8) One message often mixes everything: simple orders, chains (\"then\", \"after that\"), several allies each with their OWN different chain, plus chat. Decompose it fully: for each ally, emit its steps as separate tool calls IN ORDER (they run as a chain); 'everyone else' = the allies not named elsewhere. Movement words: get behind me/in front/left/right/close/keep distance = position; hold/watch the rear = rearguard; long-distance / shoot / throw = ranged; wait N seconds = wait; bait / run circles / keep it busy = kite (lure_to_player when they want it brought back); sneak attack / backstab / get behind IT = sneak_attack. A taunted or baited enemy chases its taunter until that ally is down, so pair a bait with a sneak_attack or attacks from the others. (9) Plain conversation (greetings, jokes, questions, banter) = only `say`, no orders. (10) The squad auto-rallies to protect anyone at low HP; don't fight that unless told. (11) Every `say` line must describe ONLY what that ally was ordered to do in THIS response (or answer the player's question) — never announce a plan, target or skill you did not issue as a tool call, never narrate other allies, no lore or filler. Default to ONE speaker; use two only when the player addressed several allies. (12) Enemy Marks: [MARKED M#] targets can be far away; all enemies within 18m of a mark appear tagged [NEAR M#]. Allies under any active order have a free leash and run across the arena without teleporting back. When a player mentions 'the marked one'/'M#'/'that one' without specifying another enemy, pass 'M#' or leave target blank (automatically prefers M1).\n" \
		+ focus \
		+ "PERSONALITIES (flavour only):\n%s\n" % "\n".join(personas) \
		+ "ROSTER (live):\n%s\n" % roster \
		+ "SKILLS:\n%s\n" % skills \
		+ "STRATEGIES:\n%s\n" % SquadStrategies.describe_all() \
		+ "MARKED TARGETS:\n%s\n" % marks \
		+ "BATTLEFIELD (live, marked & mark-region first, then nearest; bearing is relative to the player's facing):\n%s\n" % field \
```

#### Edit 7C — Preserve omitted `start_combo` target instead of hardcoding `"nearest"`
Exact Original:
```gdscript
		"start_combo":
			return {"verb": "combo_" + String(args.get("combo", "")), "allies": allies, "target": String(args.get("target", "nearest"))}
```
Replacement:
```gdscript
		"start_combo":
			return {"verb": "combo_" + String(args.get("combo", "")), "allies": allies, "target": String(args.get("target", ""))}
```

- **Postcondition**: Online LLM Director prompts include live `MARKED TARGETS`, `[MARKED M#]`, `[NEAR M#]`, and Rule `(12)`, and omitted combo targets honor active marks.

---
### STEP-08 — Create Headless Regression Suite `tests/enemy_marking_free_leash_regression_test.gd`

- **Prerequisites**: `STEP-07` complete.
- **Target**: `tests/enemy_marking_free_leash_regression_test.gd` *(must not already exist)*
- **Action**: `Create` full file contents below.

```gdscript
extends SceneTree
## Headless regression suite for Enemy Marking, 18 m Region Detection & Free-Leash Ally Commands (MRK-01..MRK-12).
## Usage: godot --headless --path . -s res://tests/enemy_marking_free_leash_regression_test.gd

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
const SquadCommsScript := preload("res://addons/parallax_squad_ai/squad_comms.gd")
const SquadAIConfigScript := preload("res://addons/parallax_squad_ai/squad_ai_config.gd")
const EnemyAIScript := preload("res://scripts/enemies/enemy_ai.gd")
const ArchetypeEnemyScript := preload("res://scripts/enemies/archetype_enemy.gd")
const HexArchetype := preload("res://data/enemies/hollow_hexcaster.tres")
const PhantomScript := preload("res://scripts/enemies/phantom_twin.gd")
const PitKillZoneScript := preload("res://scripts/environment/pit_kill_zone.gd")

var _fails: int = 0
var _checks: int = 0


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[mark_leash] %s %s %s" % ["PASS" if ok else "FAIL", test_name, detail])


func _initialize() -> void:
	SquadAIConfigScript.force_offline()
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("[mark_leash] WATCHDOG TIMEOUT")
		quit(2))
	_run()


func _make_enemy(script_res: GDScript, pos: Vector3, node_name: String) -> EnemyAI:
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


func _make_caster(pos: Vector3, node_name: String) -> ArchetypeEnemy:
	var e: ArchetypeEnemy = ArchetypeEnemyScript.new() as ArchetypeEnemy
	e.archetype = HexArchetype
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
	floor_box.size = Vector3(500.0, 1.0, 500.0)
	floor_cs.shape = floor_box
	floor_cs.position = Vector3(0.0, -0.5, -80.0)
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
	player._update_camera_pivot()

	var mgr: AllySquadManager = ManagerScript.new() as AllySquadManager
	mgr.spawn_allies = true
	harness.add_child(mgr)

	for _f in range(5):
		await physics_frame

	var brannoc: SquadAlly = mgr.find_ally("Brannoc")
	var sera: SquadAlly = mgr.find_ally("Sera")
	var ivo: SquadAlly = mgr.find_ally("Ivo")
	var intel: WorldIntel = mgr.intel
	if brannoc == null or sera == null or ivo == null or intel == null:
		_check("harness_ready", false, "missing allies or intel")
		quit(1)
		return

	# ---- MRK-01: Aim-based marking, toggle unmark, MAX_MARKS FIFO eviction, clear_marks ----
	var m_e1: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -50.0), "Mark_E1")
	var m_e2: EnemyAI = _make_enemy(EnemyAIScript, Vector3(2.0, 0.0, -50.0), "Mark_E2")
	var m_e3: EnemyAI = _make_enemy(EnemyAIScript, Vector3(4.0, 0.0, -50.0), "Mark_E3")
	var m_e4: EnemyAI = _make_enemy(EnemyAIScript, Vector3(-2.0, 0.0, -50.0), "Mark_E4")
	var m_e5: EnemyAI = _make_enemy(EnemyAIScript, Vector3(-4.0, 0.0, -50.0), "Mark_E5")
	for me in [m_e1, m_e2, m_e3, m_e4, m_e5]:
		harness.add_child(me)
	await physics_frame
	var res_mark: Dictionary = intel.mark_enemy_at_aim()
	var res_unmark: Dictionary = intel.mark_enemy_at_aim()
	for me in [m_e1, m_e2, m_e3, m_e4, m_e5]:
		intel.mark_enemy(me)
	var mark_count_capped: int = intel.get_marked_enemies(false).size()
	var fifo_evicted_e1: bool = not intel.is_marked(m_e1) and intel.is_marked(m_e5)
	var nums_in_range: bool = true
	for sm in intel.get_marked_summaries():
		var mn: int = int(sm.get("num", 0))
		if mn < 1 or mn > 4:
			nums_in_range = false
	intel.clear_marks()
	var cleared_clean: bool = not intel.has_marks() and not intel.has_mark_zones()
	_check("mrk01_aim_mark_toggle_and_max_eviction",
		String(res_mark.get("action", "")) == "marked"
		and String(res_unmark.get("action", "")) == "unmarked"
		and mark_count_capped == 4
		and fifo_evicted_e1
		and nums_in_range
		and cleared_clean,
		"mark=%s unmark=%s cap=%d fifo=%s nums=%s" % [res_mark.get("action"), res_unmark.get("action"), mark_count_capped, fifo_evicted_e1, nums_in_range])
	for me in [m_e1, m_e2, m_e3, m_e4, m_e5]:
		me.queue_free()
	await process_frame

	# ---- MRK-02: Far-distance persistence (> 40 m, facing away) & 18 m region-radius detection ----
	player.camera_yaw = PI
	player._update_camera_pivot()
	var e_far_m: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -95.0), "Far_Marked")
	var e_reg_in: EnemyAI = _make_enemy(EnemyAIScript, Vector3(12.0, 0.0, -95.0), "Far_RegionIn")
	var e_reg_out: EnemyAI = _make_enemy(EnemyAIScript, Vector3(35.0, 0.0, -95.0), "Far_RegionOut")
	for fe in [e_far_m, e_reg_in, e_reg_out]:
		harness.add_child(fe)
	await physics_frame
	var m_num2: int = intel.mark_enemy(e_far_m)
	var has_far_m: bool = false
	var has_reg_in: bool = false
	var has_reg_out: bool = false
	for en in intel.get_entries():
		if en.get("node") == e_far_m and bool(en.get("marked", false)):
			has_far_m = true
		elif en.get("node") == e_reg_in and bool(en.get("in_mark_region", false)) and int(en.get("near_mark_num", 0)) == m_num2:
			has_reg_in = true
		elif en.get("node") == e_reg_out:
			has_reg_out = true
	_check("mrk02_far_mark_and_18m_region_detection",
		has_far_m and has_reg_in and not has_reg_out,
		"far=%s in18=%s out18=%s" % [has_far_m, has_reg_in, has_reg_out])

	# ---- MRK-03: Dead mark pruning, 10 s combat-death region linger, clear & regroup reset ----
	e_far_m.is_dead = true
	e_far_m._refresh_active_state()
	intel.refresh()
	var pruned_dead: bool = not intel.is_marked(e_far_m)
	var lingers_zone: bool = intel.has_mark_zones()
	var reg_still_detected: bool = false
	for en2 in intel.get_entries():
		if en2.get("node") == e_reg_in and bool(en2.get("in_mark_region", false)):
			reg_still_detected = true
	intel.clear_marks()
	var zone_cleared: bool = not intel.has_mark_zones()
	intel.mark_enemy(e_reg_in)
	mgr.regroup(true)
	var regroup_cleared: bool = not intel.has_marks() and not intel.has_mark_zones()
	_check("mrk03_dead_mark_prune_and_10s_region_linger",
		pruned_dead and lingers_zone and reg_still_detected and zone_cleared and regroup_cleared,
		"pruned=%s linger=%s reg=%s zclr=%s rclr=%s" % [pruned_dead, lingers_zone, reg_still_detected, zone_cleared, regroup_cleared])
	for fe in [e_far_m, e_reg_in, e_reg_out]:
		fe.queue_free()
	await process_frame

	# ---- MRK-04: Visual pins (MarkPin & MarkRegionPin), HUD input actions, no IntelTag, F10 hiding ----
	player.camera_yaw = 0.0
	player._update_camera_pivot()
	var v1: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -70.0), "Vis_Marked")
	var v2: EnemyAI = _make_enemy(EnemyAIScript, Vector3(8.0, 0.0, -70.0), "Vis_Neighbor")
	harness.add_child(v1)
	harness.add_child(v2)
	var hud_layer := CanvasLayer.new()
	harness.add_child(hud_layer)
	var comms_hud: SquadCommsHUD = CommsHudScript.new() as SquadCommsHUD
	hud_layer.add_child(comms_hud)
	await physics_frame
	var ev_m := InputEventAction.new()
	ev_m.action = "mark_enemy"
	ev_m.pressed = true
	comms_hud._input(ev_m)
	var m_pin: Label3D = v1.get_node_or_null("MarkPin") as Label3D
	var r_pin: Label3D = v2.get_node_or_null("MarkRegionPin") as Label3D
	var itag: Node3D = v1.get_node_or_null("IntelTag") as Node3D
	var pins_ok: bool = (
		not intel.show_tags
		and (itag == null or not itag.visible)
		and m_pin != null and m_pin.visible and String(m_pin.get_meta("wl_kind", "")) == "mark"
		and r_pin != null and r_pin.visible and String(r_pin.get_meta("wl_kind", "")) == "mark_nearby"
	)
	comms_hud.set_cinematic(true)
	var cine_hid: bool = (m_pin != null and not m_pin.visible) and (r_pin != null and not r_pin.visible)
	comms_hud.set_cinematic(false)
	var cine_restored: bool = (m_pin != null and m_pin.visible) and (r_pin != null and r_pin.visible)
	var ev_clr := InputEventAction.new()
	ev_clr.action = "clear_marks"
	ev_clr.pressed = true
	comms_hud._input(ev_clr)
	var x_cleared: bool = not intel.has_marks()
	_check("mrk04_visual_pins_and_hud_input_actions",
		pins_ok and cine_hid and cine_restored and x_cleared,
		"pins=%s cine_h=%s cine_r=%s x_clr=%s" % [pins_ok, cine_hid, cine_restored, x_cleared])
	hud_layer.queue_free()
	v1.queue_free()
	v2.queue_free()
	await process_frame

	# ---- MRK-05: WorldIntel.resolve default/explicit/region/nearest + Reality PhantomTwin mark ----
	var r_close: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -10.0), "Res_Close")
	var r_marked: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -90.0), "Res_Marked")
	var r_caster: ArchetypeEnemy = _make_caster(Vector3(10.0, 0.0, -90.0), "Res_Caster")
	var r_phant: PhantomTwin = _make_enemy(PhantomScript, Vector3(0.0, 0.0, -120.0), "Res_Phant") as PhantomTwin
	var r_phant_phys: EnemyAI = _make_enemy(EnemyAIScript, Vector3(10.0, 0.0, -120.0), "Res_PhantNeighbor")
	for re in [r_close, r_marked, r_caster, r_phant, r_phant_phys]:
		harness.add_child(re)
	await physics_frame
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	await physics_frame
	var mn1: int = intel.mark_enemy(r_marked)
	var res_def: EnemyAI = intel.resolve("", player)
	var res_mrk: EnemyAI = intel.resolve("marked", player)
	var res_m1: EnemyAI = intel.resolve("M%d" % mn1, player)
	var res_caster: EnemyAI = intel.resolve("caster near M%d" % mn1, player)
	var res_near: EnemyAI = intel.resolve("nearest", player)
	intel.clear_marks()
	intel.mark_enemy(r_phant)
	var phant_pin: Label3D = r_phant.get_node_or_null("MarkPin") as Label3D
	var phant_null_in_real: bool = intel.get_primary_marked(true) == null
	var phant_radiates: bool = intel.is_in_mark_region(r_phant_phys) and phant_pin != null and phant_pin.visible
	intel.clear_marks()
	_check("mrk05_resolve_default_explicit_and_region_queries",
		res_def == r_marked and res_mrk == r_marked and res_m1 == r_marked
		and res_caster == r_caster and res_near == r_close
		and phant_null_in_real and phant_radiates,
		"def=%s mrk=%s m1=%s cast=%s near=%s ph_null=%s ph_rad=%s" % [res_def == r_marked, res_mrk == r_marked, res_m1 == r_marked, res_caster == r_caster, res_near == r_close, phant_null_in_real, phant_radiates])
	for re in [r_close, r_marked, r_caster, r_phant, r_phant_phys]:
		re.queue_free()
	await process_frame

	# ---- MRK-06: Offline parser mark phrases & verb-less M1 ----
	var ctx: Dictionary = mgr.get_parser_context()
	var names: Array = mgr.get_ally_names()
	var p_mrk: Array = ParserScript.parse("attack marked", names, ctx)
	var p_m1: Array = ParserScript.parse("M1!", names, ctx)
	var p_reg: Array = ParserScript.parse("Sera kite the caster near M1", names, ctx)
	var p_sk: Array = ParserScript.parse("Ivo mirror barrage M1", names, ctx)
	var p_that: Array = ParserScript.parse("attack that one", names, ctx)
	var p_grp: Array = ParserScript.parse("nuke the marked group", names, ctx)
	_check("mrk06_parser_mark_phrases_and_verbless",
		String(p_mrk[0].get("verb", "")) == "attack" and String(p_mrk[0].get("target", "")).contains("marked")
		and String(p_m1[0].get("verb", "")) == "attack" and String(p_m1[0].get("target", "")).contains("m1")
		and String(p_reg[0].get("verb", "")) == "kite" and String(p_reg[0].get("target", "")).contains("m1")
		and String(p_sk[0].get("verb", "")) == "skill" and String(p_sk[0].get("target", "")).contains("m1")
		and String(p_that[0].get("verb", "")) == "attack" and String(p_that[0].get("target", "")) == "marked_or_nearest"
		and String(p_grp[0].get("verb", "")) == "nuke" and String(p_grp[0].get("target", "")).contains("marked"),
		"mrk=%s m1=%s sk=%s that=%s" % [p_mrk[0], p_m1[0], p_sk[0], p_that[0]])

	# ---- MRK-07: Strategies ($distinct divide_and_conquer) & massacre target far marked pack ----
	var pk_m: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -85.0), "Pack_Mark")
	var pk_r1: EnemyAI = _make_enemy(EnemyAIScript, Vector3(8.0, 0.0, -85.0), "Pack_Reg1")
	var pk_r2: EnemyAI = _make_enemy(EnemyAIScript, Vector3(-8.0, 0.0, -85.0), "Pack_Reg2")
	var pk_close: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -12.0), "Pack_CloseUnmarked")
	for pe in [pk_m, pk_r1, pk_r2, pk_close]:
		harness.add_child(pe)
	await physics_frame
	intel.mark_enemy(pk_m)
	mgr.execute_strategy("divide_and_conquer", "", mgr.get_living(), "test")
	var div_all_in_pack: bool = true
	for a in mgr.get_living():
		var t_str: String = String(a.current.args.get("target", "")) if a.current != null else ""
		var t_node: EnemyAI = intel.resolve(t_str, a)
		if t_node == null or not intel.is_marked_or_in_region(t_node):
			div_all_in_pack = false
	mgr.issue({"verb": "massacre", "allies": ["all"]}, "test")
	var mass_pick: EnemyAI = mgr.pick_enemy_for(brannoc, player, 22.0, true)
	mgr.issue({"verb": "stop", "allies": ["all"]}, "test")
	intel.clear_marks()
	_check("mrk07_strategies_and_massacre_marked_pack",
		div_all_in_pack and mass_pick != null and intel.is_marked_or_in_region(mass_pick),
		"div=%s mass_pick=%s" % [div_all_in_pack, mass_pick.name if mass_pick != null else "null"])
	for pe in [pk_m, pk_r1, pk_r2, pk_close]:
		pe.queue_free()
	await process_frame

	# ---- MRK-08: describe_text() priority + SquadComms system prompt MARKED TARGETS ----
	var d_close: Array[EnemyAI] = []
	for di in range(4):
		var de: EnemyAI = _make_enemy(EnemyAIScript, Vector3(float(di) * 2.0, 0.0, -10.0), "Dist_%d" % di)
		harness.add_child(de)
		d_close.append(de)
	var d_far_m: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -120.0), "Prompt_Marked")
	var d_far_r: EnemyAI = _make_enemy(EnemyAIScript, Vector3(8.0, 0.0, -120.0), "Prompt_Reg")
	harness.add_child(d_far_m)
	harness.add_child(d_far_r)
	await physics_frame
	intel.mark_enemy(d_far_m)
	var field_txt: String = intel.describe_text(2)
	var comms: SquadComms = SquadCommsScript.new() as SquadComms
	harness.add_child(comms)
	await process_frame
	var sys_prompt: String = comms.build_system_prompt(brannoc)
	var combo_blank: Dictionary = SquadCommsScript.tool_to_command("start_combo", {"combo": "kite_nuke"})
	intel.clear_marks()
	_check("mrk08_describe_text_and_director_prompt",
		field_txt.contains("[MARKED M1]") and field_txt.contains("[NEAR M1]")
		and sys_prompt.contains("MARKED TARGETS:") and String(combo_blank.get("target", "x")) == "",
		"field=%s combo=%s" % [field_txt, combo_blank])
	comms.queue_free()
	d_far_m.queue_free()
	d_far_r.queue_free()
	for de in d_close:
		de.queue_free()
	await process_frame

	# ---- MRK-09: Free leash — no distance, >150 m, or lower-Y teleport under any active command ----
	var far_cmd_enemy: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -190.0), "Leash_FarEnemy")
	harness.add_child(far_cmd_enemy)
	await physics_frame
	intel.mark_enemy(far_cmd_enemy)
	brannoc.assign(CommandScript.make("attack", {"target": "M1"}, "test"))
	sera.assign(CommandScript.make("ranged", {"target": "M1"}, "test"))
	ivo.assign(CommandScript.make("hold", {"spot": Vector3(-3.0, 0.0, -190.0)}, "test"))
	brannoc.global_position = Vector3(0.0, -10.0, -190.0)
	sera.global_position = Vector3(3.0, -10.0, -190.0)
	ivo.global_position = Vector3(-3.0, -10.0, -190.0)
	for a in [brannoc, sera, ivo]:
		a._catch_up(player)
		a._last_pos = a.global_position
		a._stuck_timer = 2.5
		a._update_stuck(0.05)
	var stayed_190m: bool = (
		brannoc.has_free_leash() and sera.has_free_leash() and ivo.has_free_leash()
		and brannoc.global_position.z < -180.0
		and sera.global_position.z < -180.0
		and ivo.global_position.z < -180.0
	)
	_check("mrk09_free_leash_no_distance_or_elevation_teleport", stayed_190m,
		"z=[%.1f, %.1f, %.1f]" % [brannoc.global_position.z, sera.global_position.z, ivo.global_position.z])

	# ---- MRK-10: Free leash pit rescue returns to _last_safe_pos (distant battlefield), not player ----
	var pit := PitKillZoneScript.new() as PitKillZone
	pit.position = Vector3(0.0, -10.0, -95.0)
	pit.kill_y_threshold = -2.0
	pit.half_extents = Vector3(10.0, 10.0, 10.0)
	var pit_cs := CollisionShape3D.new()
	var pit_box := BoxShape3D.new()
	pit_box.size = Vector3(20.0, 20.0, 20.0)
	pit_cs.shape = pit_box
	pit.add_child(pit_cs)
	harness.add_child(pit)
	await physics_frame
	brannoc.assign(CommandScript.make("attack", {"target": "M1"}, "test"))
	brannoc._last_safe_pos = Vector3(0.0, 0.0, -90.0)
	brannoc._has_safe_pos = true
	brannoc.global_position = Vector3(0.0, -5.0, -95.0)
	brannoc._catch_up(player)
	var rescued_to_safe: bool = brannoc.global_position.distance_to(Vector3(0.0, 0.0, -90.0)) < 1.0 and brannoc.global_position.distance_to(player.global_position) > 80.0
	_check("mrk10_free_leash_pit_rescue_stays_at_last_safe_pos", rescued_to_safe, str(brannoc.global_position))
	pit.queue_free()
	far_cmd_enemy.queue_free()
	await process_frame

	# ---- MRK-11: Passive follow and ceasefire still catch up normally ----
	brannoc.clear_queue()
	ivo.clear_queue()
	brannoc.assign(CommandScript.make("follow", {}, "test"))
	ivo.assign(CommandScript.make("ceasefire", {}, "test"))
	brannoc.global_position = Vector3(0.0, 0.0, -35.0)
	ivo.global_position = Vector3(2.0, 0.0, -35.0)
	player.camera_yaw = 0.0
	player._update_camera_pivot()
	player.camera_yaw = PI
	player._update_camera_pivot()
	brannoc._catch_up(player)
	ivo._catch_up(player)
	var passive_caught_up: bool = (
		not brannoc.has_free_leash() and not ivo.has_free_leash()
		and brannoc.global_position.distance_to(player.global_position) < 8.0
		and ivo.global_position.distance_to(player.global_position) < 8.0
	)
	_check("mrk11_follow_and_ceasefire_still_catch_up", passive_caught_up,
		"b=%.1f i=%.1f" % [brannoc.global_position.distance_to(player.global_position), ivo.global_position.distance_to(player.global_position)])

	# ---- MRK-12: Distant ranged order (> 28 m) & scaled _approach_timeout ----
	var e_rng_far: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -80.0), "Ranged_FarMark")
	harness.add_child(e_rng_far)
	await physics_frame
	intel.mark_enemy(e_rng_far)
	brannoc.global_position = Vector3.ZERO
	var scaled_lim: float = brannoc._approach_timeout(10.0, Vector3(0.0, 0.0, -90.0))
	ivo.global_position = Vector3.ZERO
	var r_cmd := CommandScript.make("ranged", {}, "test")
	ivo.assign(r_cmd)
	ivo._run_ranged(0.05, player, r_cmd)
	_check("mrk12_ranged_and_approach_timeout_scale_for_distant_mark",
		scaled_lim > 20.0 and scaled_lim <= 45.0
		and not r_cmd.done and r_cmd.step == "closing to range",
		"lim=%.1f done=%s step=%s" % [scaled_lim, r_cmd.done, r_cmd.step])

	harness.queue_free()
	await process_frame
	print("[mark_leash] SUMMARY %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
```

- **Postcondition**: `tests/enemy_marking_free_leash_regression_test.gd` exists cleanly and compiles/runs headless via `--check-only` and `SceneTree`.

---

### STEP-09 — Synchronize Living Memory Files (`MEMORY/03`, `MEMORY/05`, `MEMORY/07`)

- **Prerequisites**: `STEP-01`..`STEP-08` implemented and all `VER-01`..`VER-04` checks passing.
- **Action**: Apply three targeted `Replace block` updates (`AGENTS.md` Rules 1.2 & 1.3 — zero new `.md` files).

#### Edit 9A — `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` (Input Map table + §3.5 Squad Targeting & Free Leash)
Exact Original (`MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`):
```markdown
| `toggle_command_log` | `L` | Shows / hides the squad command-history log. |
| `cinematic_mode` | `F10` | Hide-all: HUD + enemy / ally overhead labels. |
```
Replacement:
```markdown
| `mark_enemy` | `T` / `MMB` | Aim-marks / unmarks an enemy up to `180 m` (`M1..M4`) & detects all foes within `18 m` of it (`SquadCommsHUD` -> `WorldIntel`). |
| `clear_marks` | `X` | Clears all active enemy marks & lingering detection zones. |
| `toggle_command_log` | `L` | Shows / hides the squad command-history log. |
| `cinematic_mode` | `F10` | Hide-all: HUD + enemy / ally overhead labels & mark pins. |
```

Exact Original (`MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`):
```markdown
- All allies: `damage_taken_mult 0.6`, out-of-combat regen (×3 while retreating; base rates `Brannoc 1.5`, `Sera 0.95`, `Ivo 0.88` -> `>= 125 s` full heal), formation wedge out of the camera line (`(-2.5,0.3)`, `(2.7,0.8)`, `(-2.2,2.4)`…), catch-up blink when > `19.5 m` (`FOLLOW_LEASH`, `30 m` on missions, `150 m` exemption on distant/camera-visible orders) / stuck 2 s / fallen below (`y - 6 m` or `PitKillZone`), with camera-frustum LOS ray checking world collision layers rather than `LAYER_PLAYER`. Personalities only change voice & flavour lines (incl. banter every 50–95 s out of combat and complaints at repeated silly orders).
```
Replacement:
```markdown
- All allies: `damage_taken_mult 0.6`, out-of-combat regen (×3 while retreating; base rates `Brannoc 1.5`, `Sera 0.95`, `Ivo 0.88` -> `>= 125 s` full heal), formation wedge out of the camera line (`(-2.5,0.3)`, `(2.7,0.8)`, `(-2.2,2.4)`…), **Free Leash** (`SquadAlly.has_free_leash() == true` whenever `current` or any queued command is not passive `follow` / `ceasefire`): disables distance & elevation teleports (`_catch_up` only rescues true `PitKillZone` / `y < -20 m` void falls to `_last_safe_pos`, and `_update_stuck` performs local hop + `_unstick_nudge()`). Passive `follow`/`ceasefire` retain `FOLLOW_LEASH` (`19.5 m`, `150 m` camera-visible exemption) catch-up blink with world-layer LOS ray. Personalities only change voice & flavour lines (incl. banter every 50–95 s out of combat and complaints at repeated silly orders).
```

Exact Original (`MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`):
```markdown
- **Targeting by description**: every order's target goes through `WorldIntel.resolve` — enemy IDs (`E3`, shown over each enemy; `node_for_id()` requires active & in-tree), type, colour, weapon, size, side (left/right/ahead/behind of the player), "near Sera", "whoever is hitting Ivo", nearest/farthest/farther/strongest/weakest, plus `WorldIntel.is_camera_visible()` (`<= 140 m` active frustum targets). Dead players (`State.DEAD`) are excluded from heals, wards, and `_weakest_friend_name()`.
```
Replacement:
```markdown
- **Enemy Marking & Region Detection + Targeting**: Aiming (`T` / `MMB`, up to `180 m`) toggles up to `4` FIFO marks (`M1..M4`; `X` clears) in `WorldIntel`. Marking keeps that enemy tracked regardless of distance/facing and continuously detects all other active enemies inside an `18.0 m` radius around each mark (`10.0 s` combat-death zone linger). Orders go through `WorldIntel.resolve` — omitted targets & `"that one"` auto-prefer `M1` when marked, supporting `M1..M4`, `"marked"`, `"marked group/area/region"`, `"<desc> near M#"`, internal IDs (`E3`), descriptors, relations, and `is_camera_visible()` (`<= 140 m`). Dead players (`State.DEAD`) are excluded from heals, wards, and `_weakest_friend_name()`.
```

#### Edit 9B — `MEMORY/05_UI_SCORING_AND_AUDIO.md` (World Overlay row + §2.4 Squad AI prompt)
Exact Original (`MEMORY/05_UI_SCORING_AND_AUDIO.md`):
```markdown
| **World, over enemies** | Floating HP bar (`FloatingHPBar`); overhead `IntelTag` (`E3` / `WEAK`) & `StateIcon` (`?`/`!!`/`⚔`) disabled by default (`show_tags = false`, `show_state_icon = false`; `WorldIntel` IDs remain internal). Ally name tags retained. | HP bar within `32 m` (hidden at full cinematic mode) | Screen-projected crisp overlay via `WorldLabelOverlay`. |
```
Replacement:
```markdown
| **World, over enemies** | Floating HP bar (`FloatingHPBar`); overhead `IntelTag` / `StateIcon` disabled by default (`show_tags = false`, `show_state_icon = false`). Marked enemies (`T`/`MMB`) show a pulsing gold `MarkPin` (`M1..M4` diamond + chevron, `<= 200 m`; cyan `MIRROR` when unhittable); `18 m` region-detected neighbors show a hollow amber diamond `MarkRegionPin`. Ally name tags retained. | HP bar `<= 32 m`; Mark pins `<= 200 m` (hidden on `F10` cinematic) | Screen-projected crisp overlay via `WorldLabelOverlay`. |
```

Exact Original (`MEMORY/05_UI_SCORING_AND_AUDIO.md`):
```markdown
- **Online** (a key is found): **one Squad Director** LLM reads every message in plain natural language — no trigger words, typos and half-sentences fine. Its system prompt is **rebuilt on every request**: rules, ally personalities, live ROSTER (HP, distance, current order, skills with cooldowns — deaths / revives show immediately), SKILLS catalogue, STRATEGIES, BATTLEFIELD table from `WorldIntel.describe_text()` (enemy IDs + look / colour / weapon / bearing / target / state), player HP / ward / realm, RECENT EVENTS (last 8 lines: what allies said, orders, downs, skills). One shared conversation history (24 messages incl. tool calls + results; Gemini thought signatures kept); per-ally memory lines are kept too. Tools (parallel): `command_allies`, `use_skill`, `execute_strategy`, `start_combo`, `panic_order`, `say(ally, text)` — allies reply in character only through `say` (max 2 speakers); plain text falls back to the addressed ally. Allies given a direct order in a turn are excluded from a squad-wide strategy in the same turn. Any API failure -> error notification + the same utterance runs through the offline parser.
```
Replacement:
```markdown
- **Online** (a key is found): **one Squad Director** LLM reads every message in plain natural language — no trigger words, typos and half-sentences fine. Its system prompt is **rebuilt on every request**: rules (incl. Rule 12 for marks & Free Leash), ally personalities, live ROSTER (HP, distance, current order, skills with cooldowns — deaths / revives show immediately), SKILLS catalogue, STRATEGIES, `MARKED TARGETS` (`WorldIntel.describe_marks_text()`), prioritized `BATTLEFIELD` table (`WorldIntel.describe_text()`: `[MARKED M#]` & `[NEAR M#]` first + enemy IDs + look / colour / weapon / bearing / target / state), player HP / ward / realm, RECENT EVENTS. One shared conversation history (24 messages incl. tool calls + results; Gemini thought signatures kept); per-ally memory lines are kept too. Tools (parallel): `command_allies`, `use_skill`, `execute_strategy`, `start_combo`, `panic_order`, `say(ally, text)` — allies reply in character only through `say` (max 2 speakers); plain text falls back to the addressed ally. Allies given a direct order in a turn are excluded from a squad-wide strategy in the same turn. Any API failure -> error notification + the same utterance runs through the offline parser.
```

#### Edit 9C — `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` (Append one dated bullet)
Exact Original (`MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`):
```markdown
- **2026-11-20 (Overhead Enemy Tag Cleanup)**: Disabled `WorldIntel.show_tags` (`false`) and `EnemyAI.show_state_icon` (`false`) by default with early hide guards in `_update_tag()` and `_update_state_icon()`, hiding overhead `IntelTag` (`E#` / `E# · HP% · WEAK`) and `StateIcon` (`?`/`!!`/`✦ ✦`/`⚔`) labels while preserving `WorldIntel` IDs, Mirror weak-point glow/damage, enemy `FloatingHPBar`, and ally name boxes.
```
Replacement:
```markdown
- **2026-11-20 (Overhead Enemy Tag Cleanup)**: Disabled `WorldIntel.show_tags` (`false`) and `EnemyAI.show_state_icon` (`false`) by default with early hide guards in `_update_tag()` and `_update_state_icon()`, hiding overhead `IntelTag` (`E#` / `E# · HP% · WEAK`) and `StateIcon` (`?`/`!!`/`✦ ✦`/`⚔`) labels while preserving `WorldIntel` IDs, Mirror weak-point glow/damage, enemy `FloatingHPBar`, and ally name boxes.
- **2026-11-20 (Enemy Marking, `18 m` Region Detection & Free Leash)**: Added camera-aim marking (`T`/`MMB` toggle `M1..M4` up to `180 m`, `X` clear) with world LoS, automatic `18 m` surrounding-enemy detection (`10 s` linger on combat death), sleek `WorldLabelOverlay` `MarkPin`/`MarkRegionPin` indicators (`<= 200 m`), mark/region support across `WorldIntel.resolve()`, `SquadCommandParser`, `AllySquadManager` strategies/combos/`massacre`, `SquadComms` LLM Director prompts, and `SquadAlly.has_free_leash()` eliminating auto-distance teleportation under any active command (`_last_safe_pos` void rescue, local unstick nudge, scaled approach timeouts); verified via `tests/enemy_marking_free_leash_regression_test.gd`.
```

- **Postcondition**: All 3 `MEMORY/` docs match the implemented system; zero new `.md` files created.

---

## E. Verification & Failure Handling

Run every Godot invocation from `D:\Desktop\Godot\parallax` in **PowerShell** wrapped in the mandatory hard wall-clock timeout helper (`AGENTS.md` §3):

### Bounded Timeout Runner (`VER-01` .. `VER-04`)

```powershell
$Godot = "C:/Users/agrim/.local/bin/godot.cmd"

function Invoke-GodotBounded {
    param(
        [string[]]$GodotArgs,
        [int]$TimeoutSec = 90
    )
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath $Godot -ArgumentList $GodotArgs -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        & taskkill /T /F /PID $p.Id | Out-Null
        Write-Host "--- TIMEOUT AFTER ${TimeoutSec}s (exit 124) ---"
        Get-Content $outFile -ErrorAction SilentlyContinue
        Get-Content $errFile -ErrorAction SilentlyContinue
        Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
        return 124
    }
    Get-Content $outFile -ErrorAction SilentlyContinue
    Get-Content $errFile -ErrorAction SilentlyContinue
    $code = $p.ExitCode
    Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
    return $code
}
```

### Verification Matrix

| Check ID | Scope / Requirement(s) | Exact Command (`D:\Desktop\Godot\parallax`) | Expected Pass Condition |
| :--- | :--- | :--- | :--- |
| **`VER-01`** | Static parse & type check on all 7 modified + 1 new script (`MRK-01`..`MRK-13`) | `foreach ($s in @("res://scripts/ui/world_label_overlay.gd","res://scripts/allies/world_intel.gd","res://scripts/allies/squad_command_parser.gd","res://scripts/allies/ally_squad_manager.gd","res://scripts/allies/squad_ally.gd","res://scripts/ui/squad_comms_hud.gd","res://addons/parallax_squad_ai/squad_comms.gd","res://tests/enemy_marking_free_leash_regression_test.gd")) { $rc = Invoke-GodotBounded @("--headless","--path",".","--check-only","-s",$s) 30; if ($rc -ne 0) { throw "CHECK FAILED ($rc): $s" } }` | Exit code `0` for all `8` scripts; zero GDScript parse/type errors. |
| **`VER-02`** | Full new marking + `18 m` region + free-leash regression suite (`MRK-01`..`MRK-13`) | `Invoke-GodotBounded @("--headless","--path",".","-s","res://tests/enemy_marking_free_leash_regression_test.gd") 90` | Exit code `0`; `[mark_leash] SUMMARY 12 checks, 0 failed`; every check `mrk01`..`mrk12` prints `PASS`. |
| **`VER-03`** | Friends & Squad AI regression suite — ensures `aly05` catch-up, parser & HUD gates still pass (`MRK-05`, `MRK-06`, `MRK-07`, `MRK-09`, `MRK-11`, `MRK-13`) | `Invoke-GodotBounded @("--headless","--path",".","-s","res://tests/friends_ai_bugfix_regression_test.gd") 90` | Exit code `0`; `[friends_ai] SUMMARY ... 0 failed`. |
| **`VER-04`** | Squad AI plugin unit tests — parser & `SquadComms` offline/system-prompt regression (`MRK-06`, `MRK-08`, `MRK-13`) | `Invoke-GodotBounded @("--headless","--path",".","-s","res://tests/squad_ai_unit_test.gd") 90` | Exit code `0`; `[unit] SUMMARY ... 0 failed`. |
| **`VER-05`** | Manual / live gameplay spot-check (`MRK-01`, `MRK-04`, `MRK-09`) | Launch game -> Start New Run -> aim crosshair at distant enemy (`> 45 m`) -> press `T` / `MMB` -> press `Enter` and issue `"attack marked"` / `"divide and conquer"` / `"Sera kite the caster near M1"` / `"massacre"` -> run away in the opposite direction -> press `F10` twice -> press `X`. | Center reticle appears on aim; `M1` diamond+chevron + hollow amber neighbor pips appear at range; allies run all the way to the distant group without ever blinking back; `F10` hides & restores pins cleanly; `X` clears all marks. |

### Scoped Failure Recovery
- Preserve all prior uncommitted baseline changes (`Guides 01–04` & `Overhead Enemy Tag Cleanup`)! **Never** run `git reset --hard`.
- To revert ONLY this handoff's changes on an unrecoverable failure:
  ```powershell
  git checkout -- scripts/ui/world_label_overlay.gd scripts/allies/world_intel.gd scripts/allies/squad_command_parser.gd scripts/allies/ally_squad_manager.gd scripts/allies/squad_ally.gd scripts/ui/squad_comms_hud.gd addons/parallax_squad_ai/squad_comms.gd MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md MEMORY/05_UI_SCORING_AND_AUDIO.md MEMORY/07_DEV_STATUS_AND_CHANGELOG.md
  Remove-Item tests/enemy_marking_free_leash_regression_test.gd -ErrorAction SilentlyContinue
  ```

---

## F. Completion Report Contract

When executing this handoff, report concisely using file links (`file:///` with forward slashes):
1. **Applied Steps**: Confirm `STEP-01` .. `STEP-09` applied in order (or exact step stopped at and mismatch/error if blocked).
2. **Changed / Created Files**: Exact list matching Section C.
3. **Verification Results**: Exact exit code and `SUMMARY` line from `VER-01`, `VER-02`, `VER-03`, `VER-04` (and `VER-05` if run), explicitly noting any skipped or failing checks.
4. **Author Validation Status**: All source files, method contracts, and replacement anchors in this guide were verified directly against `master @ 1ca7464` (including the existing uncommitted baseline) at authoring time; **none** of the edits or new test scripts in `STEP-01`..`STEP-09` have been executed yet.
