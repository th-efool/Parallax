# IdiotHandOffGuide 04 — Gate stone beside the gate with big guards, cracked support up a parkour climb, more enemies

## A. Execution contract

- **Outcome:**
  - **Gate stone:** the Mirror Switch that opens the castle gate (the "gate stone") sits to the LEFT of the gate instead of in front of it. It is guarded locally by two enlarged Shielded Guards (×1.35), a Grave Brute and a Hollow Hexcaster, on top of the existing Forecourt Phantom.
  - **Cracked stone support:** it sits on a ledge 3.6 m above the gallery deck, reached by a 3-block parkour climb. The Bridge Anchor switch is on the ledge behind it.
  - **More enemies:** the gallery deck and the esplanade get more enemies. The Hall of Echoes and the clock-tower chamber get theirs in guide 05, which rebuilds those rooms.
- **Root:** `C:\Users\TLSB\Documents\Parallax`, branch `master`.
- **Baseline:** commit `2f37a1b`, plus guides 01–03 if applied. They don't touch `grand_journey_builder.gd` blocks used here, except guide 01's `_configure_atmosphere` edits, which are a different block.
- **Shell:** PowerShell 5.1. `$g = "E:\game making workshop\Godot\Godot_v4.7.2-stable_win64_console.exe"`.
- **Readiness:** READY.
- **Apply guide 04 before guide 05.** Guide 05 moves the stages, and its anchors assume guide 04's text.

Operational sequence:
1. Run G4-0.
2. Apply G4-1 … G4-6 in order. Every replace block must match exactly once; on a mismatch, stop the dependent steps and report.
3. Run G4-V1 … G4-V5.
4. Report as in section F.

## B. Requirements and acceptance map

| ID | Behaviour | Steps | Checks |
|---|---|---|---|
| R1 | `EntryMirrorSwitch` stands at story position (-3.1, 0, 3.2), left of the 4 m gate opening (x -2..2), not on the gate line. The guardian plinths move outward to x ±5.0 and narrow to 1.8 m so the switch and the walking line are clear. | G4-2 | V2, V4 |
| R2 | Gate guards (section ENTRY roamers, not tied to an encounter): `GateWarden_W` / `GateWarden_E` Shielded Guards enlarged ×1.35 (model, body, hurtbox, HP-bar height, attack reach) at (∓3.2, 0, -2.6) flanking the stepping-stone pit; `GateBrute` at (0, 0, -8.5); `GateHexcaster` on the north landing at (3.2, 0, 3.4). | G4-1, G4-2 | V2, V3 |
| R3 | `WeakStoneSupport` sits on `SupportLedge` (top = deck + 3.6 m, x -2..2, z 78.8..82.4). Climb: `ParkourStep_1/2/3` at heights +1.0 / +2.0 / +3.0 east of the deck centre. Invisible blockers stop the player jumping off the ledge over the deck rails into the gorge. `BridgeAnchorSwitch` is on the ledge behind the support, out of interact range until the support is broken. Rubble falls on the ledge's sides. | G4-3 | V2, V4 |
| R4 | `ShieldedGuard_1` moves to (0, 6, 83.2) so it doesn't overlap the new ledge. | G4-3 | V2 |
| R5 | More enemies: 2 skeletons on the gallery south deck (section COLLAPSED_GALLERY) and 1 Hollow Hexcaster on the esplanade (MECHANISM_CHAMBER). | G4-4 | V3 |
| R6 | No regressions: boot, the squad windowed test and the restart test pass. | all | V5 |

## C. File-change manifest

| Path | Op | Step |
|---|---|---|
| `scripts/environment/grand_journey_builder.gd` | modify | G4-1 … G4-4 |
| `scripts/ui/objective_tracker.gd` | modify (hint text) | G4-5 |
| `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` | modify | G4-6 |
| `tests/level_props_test.gd` | create | G4-V3 |

## D. Ordered implementation steps

### G4-0 — Baseline
```powershell
git status --short
Select-String -Path scripts/environment/grand_journey_builder.gd -Pattern 'var sw := _make_switch\("EntryMirrorSwitch", Vector3\(0.0, 0.0, 4.0\)'
```
**Expected:** 1 match. Zero matches means G4-2 is already applied or the file differs: inspect, then report or resume.

Back up the save:
```powershell
$bk = "$env:TEMP\parallax_save_bk_g4"; New-Item -ItemType Directory -Force $bk | Out-Null; Copy-Item "$env:APPDATA\Godot\app_userdata\PARALLAX\*.cfg" $bk -Force -ErrorAction SilentlyContinue
```

### G4-1 — Helper: enlarge an enemy
File `scripts/environment/grand_journey_builder.gd`. Insert directly **before** the line `func _roamer_group(root: Node3D) -> Node3D:` (unique):
```gdscript
## Makes a configured enemy physically bigger: model, body capsule, hurtbox, floating HP-bar height and melee reach
## all scale by `k` (the CharacterBody3D itself is never scaled — Godot physics bodies must stay unscaled).
## Call before the enemy enters the tree (right after _add_roamer / _configure_enemy_actor).
func _enlarge_enemy(e: EnemyBase, k: float) -> void:
	if e == null:
		return
	var vr: Node3D = e.get_node_or_null("VisualRoot") as Node3D
	if vr != null:
		vr.scale = Vector3.ONE * k
	var bc: CollisionShape3D = e.get_node_or_null("BodyCollider") as CollisionShape3D
	if bc != null and bc.shape is CapsuleShape3D:
		var cap := (bc.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		cap.radius *= k
		cap.height *= k
		bc.shape = cap
		bc.position *= k
	var hb: Node3D = e.get_node_or_null("Hurtbox3D") as Node3D
	if hb != null:
		for c in hb.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var bs := ((c as CollisionShape3D).shape as BoxShape3D).duplicate() as BoxShape3D
				bs.size *= k
				(c as CollisionShape3D).shape = bs
				(c as CollisionShape3D).position *= k
	var hp: Node3D = e.get_node_or_null("FloatingHPBar") as Node3D
	if hp != null:
		hp.position *= k
	if e is EnemyAI:
		(e as EnemyAI).attack_range *= lerpf(1.0, k, 0.7)


```
**Postcondition:** `func _enlarge_enemy` appears once.

### G4-2 — Gate stone to the left, plinths outward, gate guards
File `scripts/environment/grand_journey_builder.gd`.

Replace block:
```gdscript
	var sw := _make_switch("EntryMirrorSwitch", Vector3(0.0, 0.0, 4.0), InteractSwitch.SwitchRole.GATE_OPENER, 1,
		NodePath("../Gate01_EntryToHall"), NodePath(), NodePath())
```
with:
```gdscript
	# Gate stone beside the gate (left of the 4 m opening), not on the walking line in front of it.
	var sw := _make_switch("EntryMirrorSwitch", Vector3(-3.1, 0.0, 3.2), InteractSwitch.SwitchRole.GATE_OPENER, 1,
		NodePath("../Gate01_EntryToHall"), NodePath(), NodePath())
```
Replace block:
```gdscript
	for sx in [-1.0, 1.0]:
		_solid(root, "GuardianPlinth_%s" % ("W" if sx < 0.0 else "E"), Vector3(sx * 4.3, 1.2, 3.6), Vector3(2.6, 2.4, 2.4), _m_marble())
		_sword_monument(g[0], Vector3(sx * 4.3, 2.4, 3.6), 0.0, 10.0)
```
with:
```gdscript
	for sx in [-1.0, 1.0]:
		# Narrower plinths pushed out to the gatehouse wings (x 4.1..5.9) so the gate stone has room beside the gate.
		_solid(root, "GuardianPlinth_%s" % ("W" if sx < 0.0 else "E"), Vector3(sx * 5.0, 1.2, 3.6), Vector3(1.8, 2.4, 2.0), _m_marble())
		_sword_monument(g[0], Vector3(sx * 5.0, 2.4, 3.6), 0.0, 10.0)
```
Replace block:
```gdscript
	_add_roamer(rg, "phantom", "ForecourtPhantom", Vector3(3.5, 0.0, -8.0), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
```
with:
```gdscript
	_add_roamer(rg, "phantom", "ForecourtPhantom", Vector3(3.5, 0.0, -8.0), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	# Gate stone guards: two enlarged Shielded Guards flanking the stepping-stone pit, a Grave Brute holding the
	# forecourt and a Hexcaster on the north landing beside the gate stone.
	for gw in [["GateWarden_W", -3.2], ["GateWarden_E", 3.2]]:
		var warden_e: EnemyBase = _add_roamer(rg, "shield", String(gw[0]), Vector3(float(gw[1]), 0.0, -2.6), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
		_enlarge_enemy(warden_e, 1.35)
		if warden_e is EnemyAI:
			(warden_e as EnemyAI).patrol_radius = 0.0
	_add_roamer(rg, "brute", "GateBrute", Vector3(0.0, 0.0, -8.5), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	_add_roamer(rg, "hexcaster", "GateHexcaster", Vector3(3.2, 0.0, 3.4), EncounterDirector.Section.ENTRY, Vector3(0, 0, -2))
```
**Postcondition:** `GateWarden_W`, `GateBrute` and `GateHexcaster` each appear once.

### G4-3 — Cracked support on a parkour ledge
File `scripts/environment/grand_journey_builder.gd`.

Replace block:
```gdscript
	var support := _make_breakable_pillar("WeakStoneSupport", Vector3(0.0, y, 77.0), BreakableProp.PropKind.WEAK_STONE_SUPPORT, 2, 0.0, Vector3.ZERO, 1.5)
	var sup_intact: Node3D = support.get_node("IntactVisual") as Node3D
	for c in sup_intact.get_children():
		if c.name != "FractureSeam":
			c.free()
	var block := BoxMesh.new()
	block.size = Vector3(3.2, 3.4, 1.4)
	_mesh(sup_intact, "BarrierBlock", block, _m_ruin(), Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 0)), true, 0.0, false)
	(sup_intact.get_node("FractureSeam") as Node3D).position = Vector3(0, 1.7, -0.69)
	# Collider = the barrier block (the greybox cylinder let players walk through both ends of the wall).
	var sup_body: StaticBody3D = support.get_node("SolidBody") as StaticBody3D
	for c in sup_body.get_children():
		c.free()
	var sup_cs := CollisionShape3D.new()
	sup_cs.shape = _box_shape(Vector3(3.2, 3.4, 1.4))
	sup_cs.position = Vector3(0, 1.7, 0)
	sup_body.add_child(sup_cs)
```
with:
```gdscript
	# Cracked support stationed HIGH: on a stone ledge 3.6 m above the deck, reached by a 3-step parkour climb
	# (+1.0 / +2.0 / +3.0 m blocks on the east side; jump apex ~1.94 m). The anchor switch hides behind it.
	const LEDGE_H: float = 3.6
	_solid(root, "SupportLedge", Vector3(0.0, y + LEDGE_H * 0.5, 80.6), Vector3(4.0, LEDGE_H, 3.6), _m_wall())
	_solid(root, "ParkourStep_1", Vector3(2.55, y + 0.5, 75.3), Vector3(1.3, 1.0, 1.3), _m_ruin())
	_solid(root, "ParkourStep_2", Vector3(2.55, y + 1.0, 77.0), Vector3(1.3, 2.0, 1.3), _m_ruin())
	_solid(root, "ParkourStep_3", Vector3(2.9, y + 1.5, 78.5), Vector3(1.2, 3.0, 1.2), _m_ruin())
	# The ledge top is above the deck rails' 2.7 m blockers: extra invisible blockers keep jumps off the ledge
	# landing on the deck instead of in the gorge.
	_invisible_wall(root, "LedgeBlocker_W", Vector3(-3.95, y + 4.7, 79.0), Vector3(0.45, 4.0, 10.0))
	_invisible_wall(root, "LedgeBlocker_E", Vector3(3.95, y + 4.7, 79.0), Vector3(0.45, 4.0, 10.0))
	var support := _make_breakable_pillar("WeakStoneSupport", Vector3(0.0, y + LEDGE_H, 80.2), BreakableProp.PropKind.WEAK_STONE_SUPPORT, 2, 0.0, Vector3.ZERO, 1.5)
	var sup_intact: Node3D = support.get_node("IntactVisual") as Node3D
	for c in sup_intact.get_children():
		if c.name != "FractureSeam":
			c.free()
	var block := BoxMesh.new()
	block.size = Vector3(3.2, 3.0, 1.0)
	_mesh(sup_intact, "BarrierBlock", block, _m_ruin(), Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)), true, 0.0, false)
	(sup_intact.get_node("FractureSeam") as Node3D).position = Vector3(0, 1.5, -0.49)
	# Collider = the barrier block (the greybox cylinder let players walk through both ends of the wall).
	var sup_body: StaticBody3D = support.get_node("SolidBody") as StaticBody3D
	for c in sup_body.get_children():
		c.free()
	var sup_cs := CollisionShape3D.new()
	sup_cs.shape = _box_shape(Vector3(3.2, 3.0, 1.0))
	sup_cs.position = Vector3(0, 1.5, 0)
	sup_body.add_child(sup_cs)
```
Replace block (rubble lands on the ledge's sides, not mid-air):
```gdscript
		_mesh(sup_broken, "Rubble", pile, _m_ruin(), Transform3D(Basis.IDENTITY, Vector3(sx * 2.7, 0.05, 0.2)), true, 0.0, false)
		var rcs := CollisionShape3D.new()
		rcs.shape = _box_shape(Vector3(1.6, 0.45, 1.3))
		rcs.position = Vector3(sx * 2.7, 0.22, 0.2)
```
with:
```gdscript
		_mesh(sup_broken, "Rubble", pile, _m_ruin(), Transform3D(Basis.IDENTITY, Vector3(sx * 1.3, 0.05, 0.2)), true, 0.0, false)
		var rcs := CollisionShape3D.new()
		rcs.shape = _box_shape(Vector3(0.9, 0.45, 1.0))
		rcs.position = Vector3(sx * 1.3, 0.22, 0.2)
```
Replace block:
```gdscript
	var anchor := _make_switch("BridgeAnchorSwitch", Vector3(0.0, y, 79.0), InteractSwitch.SwitchRole.BRIDGE_ANCHOR, 1,
```
with:
```gdscript
	var anchor := _make_switch("BridgeAnchorSwitch", Vector3(0.0, y + LEDGE_H, 81.6), InteractSwitch.SwitchRole.BRIDGE_ANCHOR, 1,
```
Replace block:
```gdscript
		_configure_enemy_actor(sg, "ShieldedGuard_1", "gallery_shielded_1", Vector3(0.0, y, 82.0), Color(0.75, 0.58, 0.25))
```
with:
```gdscript
		_configure_enemy_actor(sg, "ShieldedGuard_1", "gallery_shielded_1", Vector3(0.0, y, 83.2), Color(0.75, 0.58, 0.25))
```
Also update the key anchors used by tooling. Replace block:
```gdscript
		"weak_stone_support": Vector3(0.0, Y_GALLERY, 77.0),
		"bridge_anchor": Vector3(0.0, Y_GALLERY, 79.0),
		"shielded_guard": Vector3(0.0, Y_GALLERY, 82.0),
```
with:
```gdscript
		"weak_stone_support": Vector3(0.0, Y_GALLERY + 3.6, 80.2),
		"bridge_anchor": Vector3(0.0, Y_GALLERY + 3.6, 81.6),
		"shielded_guard": Vector3(0.0, Y_GALLERY, 83.2),
```
And the route waypoints (the critical path now climbs the ledge). Replace block:
```gdscript
		[Vector3(0, Y_GALLERY, 65), 0], [Vector3(0, Y_GALLERY, 72), 1], [Vector3(0, Y_GALLERY, 76), 1],
		[Vector3(0, Y_GALLERY, 83), 0], [Vector3(0, Y_GALLERY, 86), 0], [Vector3(0, Y_GALLERY, 90), 0],
```
with:
```gdscript
		[Vector3(0, Y_GALLERY, 65), 0], [Vector3(0, Y_GALLERY, 72), 1], [Vector3(0, Y_GALLERY, 76), 1],
		[Vector3(2.55, Y_GALLERY + 1.0, 75.3), 1], [Vector3(2.55, Y_GALLERY + 2.0, 77.0), 1], [Vector3(2.9, Y_GALLERY + 3.0, 78.5), 1],
		[Vector3(0, Y_GALLERY + 3.6, 79.2), 1],
		[Vector3(0, Y_GALLERY, 83.6), 0], [Vector3(0, Y_GALLERY, 86), 0], [Vector3(0, Y_GALLERY, 90), 0],
```
**Postcondition:** the file contains `SupportLedge`, `ParkourStep_3` and `LedgeBlocker_E`; `BridgeAnchorSwitch` uses `Vector3(0.0, y + LEDGE_H, 81.6)`.

Note: the waypoint list feeds `JourneyTerrain` (it keeps the landscape ≥ 5 m below the route band). The terrain sorts points by Z, so the new on-ledge points are fine.

### G4-4 — More enemies: gallery deck and esplanade
File `scripts/environment/grand_journey_builder.gd`. Replace block:
```gdscript
		enemies.add_child(sg)
		root.add_child(enemies)
```
with:
```gdscript
		enemies.add_child(sg)
		root.add_child(enemies)
	# Gallery deck patrol (roamers: they never hold the gallery gate shut).
	var grg: Node3D = _roamer_group(root)
	_add_roamer(grg, "skeleton", "GallerySkeleton_A", Vector3(-2.4, y, 63.5), EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0, y, 60))
	_add_roamer(grg, "skeleton", "GallerySkeleton_B", Vector3(2.4, y, 66.5), EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0, y, 60))
```
**Uniqueness check:** this two-line block must occur exactly once (in `_build_stage_03_gallery`).
```powershell
(Select-String -Path scripts/environment/grand_journey_builder.gd -Pattern "enemies.add_child\(sg\)").Count
```
**Expected:** `1`.

Replace block:
```gdscript
	_add_roamer(rg, "brute", "EsplanadeBrute", Vector3(5.5, y, 118.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
```
with:
```gdscript
	_add_roamer(rg, "brute", "EsplanadeBrute", Vector3(5.5, y, 118.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "hexcaster", "EsplanadeHexcaster", Vector3(-3.0, y, 117.4), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
```

### G4-5 — Objective hints match the new layout
File `scripts/ui/objective_tracker.gd`. Replace block:
```gdscript
				"hint": "The bridge only exists in the Mirror — press Q and cross, then smash the cracked stone support with a Heavy (RMB).",
```
with:
```gdscript
				"hint": "The bridge only exists in the Mirror — press Q and cross, climb the broken blocks on the right to the high ledge, then smash the cracked support with a Heavy (RMB).",
```
Replace block:
```gdscript
			"hint": "Press Q to see the Mirror: the glowing stones over the gap turn solid. Cross, then press E at the glowing Mirror Switch.",
```
with:
```gdscript
			"hint": "Beat the gate guards, press Q so the glowing stones turn solid, cross, then press E at the Mirror Switch left of the gate.",
```

### G4-6 — MEMORY
Append to `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`:
```markdown
- **2026-11-18 (Gate stone, support ledge, more enemies)**: EntryMirrorSwitch moved left of the gate (-3.1, 0, 3.2), guardian plinths to x ±5.0; gate guards = 2 Shielded ×1.35 (`_enlarge_enemy`) + Grave Brute + Hexcaster; WeakStoneSupport on `SupportLedge` (deck +3.6 m) reached by ParkourStep_1..3 (+1/+2/+3 m), anchor switch behind it on the ledge, ledge blockers; ShieldedGuard_1 at z 83.2; +2 gallery skeletons, +1 esplanade hexcaster.
```
In `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md`, replace block:
```markdown
| `GalleryFloorSouth` / `GalleryFloorNorth` | 6 | (0, 65) / (0, 79) | 8 × 10 each | Aqueduct deck. **Gap z 70..74 is a pit** (spectral bridge `(0,6,72)` is Mirror-only until repaired) |
```
with:
```markdown
| `GalleryFloorSouth` / `GalleryFloorNorth` | 6 | (0, 65) / (0, 79) | 8 × 10 each | Aqueduct deck. **Gap z 70..74 is a pit** (spectral bridge `(0,6,72)` is Mirror-only until repaired). `SupportLedge` (x -2..2, z 78.8..82.4, top y 9.6) carries the WeakStoneSupport (z 80.2) and the BridgeAnchorSwitch (z 81.6); climb via ParkourStep_1/2/3 at (2.55,·,75.3) top 7.0, (2.55,·,77.0) top 8.0, (2.9,·,78.5) top 9.0 |
```
**If this exact line is not found** (the atlas wording differs), append the sentence above as a new bullet under section `### 6.1 Walkable floors` instead, and report it.

## E. Verification and failure handling

**G4-V1 — parse.**
```powershell
& $g --headless --path . --import --quit
foreach ($f in @("scripts/environment/grand_journey_builder.gd","scripts/ui/objective_tracker.gd")) { $o = & $g --headless --path . --check-only -s "res://$f" 2>&1 | Out-String; if ($o -match "SCRIPT ERROR|Parse Error") { "FAIL $f"; $o } else { "ok $f" } }
```
**Pass:** both `ok`.

**G4-V2 — boot smoke.** `& $g --headless --path . -s res://tests/boot_smoke.gd 2>&1 | Select-String "boot_smoke|SCRIPT ERROR"`.
- **Pass:** `[boot_smoke] OK`.
- **Enemy count:** the `enemies=` count is +6 vs before (`19` → `25`), assuming guide 05 isn't applied yet.

**G4-V3 — level props test (new, headless).** Create `tests/level_props_test.gd`:
```gdscript
extends SceneTree
## Checks guide 04 placements in the built level (headless).
var _results: Array[String] = []
var _main: Node = null

func _initialize() -> void:
	SquadAIConfig.force_offline()
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()

func _check(n: String, ok: bool, d: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", n, d]
	_results.append(line)
	print("[props] ", line)

func _run() -> void:
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	var lv: Node = _main.get_node("LevelRoot")
	var s1: Node3D = lv.get_node("Stage01_EntryVestibule") as Node3D
	var sw: Node3D = s1.get_node("EntryMirrorSwitch") as Node3D
	var gate: Node3D = s1.get_node("Gate01_EntryToHall") as Node3D
	var rel: Vector3 = sw.global_position - gate.global_position
	_check("gate_stone_beside_gate", absf(rel.x) >= 2.8 and absf(rel.z) < 2.5, str(rel))
	for n in ["GateWarden_W", "GateWarden_E", "GateBrute", "GateHexcaster"]:
		_check("guard_" + n, s1.get_node_or_null("Roamers/" + n) != null)
	var gw: Node3D = s1.get_node_or_null("Roamers/GateWarden_W") as Node3D
	_check("warden_enlarged", gw != null and (gw.get_node("VisualRoot") as Node3D).scale.x > 1.3)
	var s3: Node3D = lv.get_node("Stage03_CollapsedGallery") as Node3D
	var sup: Node3D = s3.get_node("WeakStoneSupport") as Node3D
	var ledge: Node3D = s3.get_node("SupportLedge") as Node3D
	var deck_y: float = (s3.get_node("GalleryFloorNorth") as Node3D).global_position.y + 0.25
	_check("support_high", sup.global_position.y - deck_y > 3.4, "%.2f above deck" % (sup.global_position.y - deck_y))
	_check("ledge_exists", ledge != null)
	for i in [1, 2, 3]:
		_check("parkour_step_%d" % i, s3.get_node_or_null("ParkourStep_%d" % i) != null)
	var anchor: Node3D = s3.get_node("BridgeAnchorSwitch") as Node3D
	_check("anchor_on_ledge", absf(anchor.global_position.y - sup.global_position.y) < 0.1 and anchor.global_position.z > sup.global_position.z)
	_check("gallery_extra_enemies", s3.get_node_or_null("Roamers/GallerySkeleton_A") != null and s3.get_node_or_null("Roamers/GallerySkeleton_B") != null)
	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[props] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
```
Run:
```powershell
& $g --headless --path . -s res://tests/level_props_test.gd 2>&1 | Select-String "\[props\]|SCRIPT ERROR"
```
**Pass:** `[props] SUMMARY 13 checks, 0 failed`.

**G4-V4 — climb check (windowed, visual).**
- **Setup:** run the game (F5), Start, open the console-free debug path. Quicker: run `tests/visual_check_shots.gd` from guide 01 if present.
- **Otherwise, manually:** go to the gallery, cross the bridge in the Mirror, and jump step 1 → 2 → 3 → ledge.
- **Pass:**
  - every jump is possible with a normal jump (no double-jump needed);
  - jumping sideways off the ledge lands on the deck, not in the gorge;
  - the anchor switch prompt doesn't appear until the support is smashed;
  - the gate stone is beside the gate and the two big shield guards are visibly larger than normal enemies.
- **Report:** what was observed.

**G4-V5 — regressions.**
```powershell
& $g --path . -s res://tests/squad_ai_windowed_test.gd -- --shots="$env:TEMP\pshots" 2>&1 | Select-String "FAIL|SUMMARY|SCRIPT ERROR"
& $g --headless --path . -s res://tests/restart_flow_test.gd 2>&1 | Select-String "restart_test"
Copy-Item "$env:TEMP\parallax_save_bk_g4\savegame.cfg" "$env:APPDATA\Godot\app_userdata\PARALLAX\savegame.cfg" -Force -ErrorAction SilentlyContinue
```
**Pass:** windowed `53 checks, 0 failed`; restart `=> PASS`.
- The windowed test fights at the forecourt (0, 0, -14) and spawns its own enemies. The new ENTRY gate guards at z -2.6 / -8.5 can join those fights.
- If a spacing/count check fails because of them, report it. Don't delete the guards; the fix belongs in the test (moving the test arena to the start terrace), and that needs approval first.

**Rollback:** `git checkout -- scripts/environment/grand_journey_builder.gd scripts/ui/objective_tracker.gd`, then delete `tests/level_props_test.gd`.

## F. Completion report contract
Report:
- applied step IDs;
- changed files;
- check results (with the `[props]` summary and the boot `enemies=` count);
- the V4 observations.

**Done means:** G4-1 … G4-6 are applied and V1–V3 and V5 pass.

**Author's validation:** the anchors were checked against the baseline source. The code has not been compiled or run by the author.
