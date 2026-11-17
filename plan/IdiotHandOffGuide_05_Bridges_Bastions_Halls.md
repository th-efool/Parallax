# IdiotHandOffGuide 05 — Long winding bridges with bastions, 3× Hall of Echoes and clock-tower chamber

## A. Execution contract

**Outcome.** Four changes to the macro layout of "The Ascent":

1. **Longer bridges.** The four connectors become long winding bridges, each with two bastions that hold enemies:
   - Pilgrim's Causeway, terrace → gate forecourt: about 40 m → 179 m.
   - Sunlit Stair, gate → hall: 16 m → 81 m.
   - Windswept Rampart, hall → gallery: 16 m → 81 m.
   - Processional, chamber → esplanade: 16 m → 81 m.
2. **Hall of Echoes.** Grows from 20 × 20 m to 60 × 60 m. It gets 9 encounter enemies (was 4) and 3 roamers.
3. **Clock-tower chamber.** Grows from 12 × 12 m to 36 × 36 m and gets 8 roamers (was 3).
4. **Shared conversion.** Everything that used the old positions keeps working through one conversion class, `JourneyLayout`. That covers weather zones, music bands, objective targets, flora/fauna, set dressing, terrain, saves and tests.

**Root:** `C:\Users\TLSB\Documents\Parallax`. **Shell:** Windows PowerShell 5.1.

**Godot:** `E:\game making workshop\Godot\Godot_v4.7.2-stable_win64_console.exe`. Every command block below sets `$g` itself, because shell state does not persist between commands.

**Baseline:**
- branch `master`, HEAD `2f37a1b`;
- **guide 04 (`IdiotHandOffGuide_04_Gate_Support_Enemies.md`) applied first**;
- guides 01–03 may or may not be applied — this guide does not edit any line they edit.

**Readiness:** READY. That means the guide is fully specified. Nothing in it has been compiled or run (see F).

**Rules for the executor**
1. Close the Godot editor; it rewrites `main.tscn` / `project.godot` while open. Never kill `godot-ai.exe`.
2. Run G5-0 (baseline checks, save backup, the region-splice helper) before editing.
3. Apply steps G5-1 … G5-18 in order. Use the supplied code exactly; code blocks use **tab** indentation.
   - **Replace block:** the original block must match exactly once.
   - **Region splice** (for the five very long blocks): save the code block to the named file, then run the given `Set-Region` command. The helper refuses to run unless its anchors match exactly once and the region size is as expected.
4. If an anchor or replace block is missing or matches more than once, **stop that step and every later step in the same file**. Report the step ID, the path and the mismatch.
5. Partially applied before? Each step has a postcondition; verify it, skip steps already done, and resume at the first one not applied.
6. Run section E and report as in F. Do not commit or push; that needs the user's approval.

## B. Requirements and acceptance map

| ID | Observable behaviour | Steps | Checks |
|---|---|---|---|
| L1 | Each connector (between terrace/gate/hall/gallery/chamber/esplanade) is ≥ 4× its old walking length (actual 4.5×–5.1×) | G5-1, G5-5 | V3 `route_length_*` |
| L2 | Connectors are not straight: zig-zag through two bastions 16–34 m off the straight line | G5-1, G5-5 | V3 `route_not_straight_*` |
| L3 | ≥ 2 bastions per connector, each with 3 enemies, braziers, merlons and a ring parapet | G5-5 | V3 `route_bastions_*`, `route_enemies_*`, `bastion_ring_*` |
| L4 | Hall of Echoes is 3× in length and width (60 × 60 m) with 9 encounter enemies + 3 roamers | G5-5 | V3 `hall_3x`, `hall_more_enemies`, `hall_encounter_count_matches` |
| L5 | The other interior hall (clock-tower mechanism chamber) is 3× (36 × 36 m) with 8 roamers. The puzzle keeps its proven dimensions | G5-7 | V3 `chamber_3x`, `chamber_more_enemies` |
| L6 | Whole route walkable without holes. Bridge legs railed both sides. No gaps in bastion rings except the path openings | G5-4…G5-9 | V3 `route_walkable_*`, `route_railed_*`, `bastion_ring_*`; V5 manual walk |
| L7 | Systems that think in old positions follow the new layout: weather, music/room tone, footsteps, objective targets (arrow follows bastions), ambient flora/fauna, set dressing, terrain ridge, sky isles, occluders | G5-1, G5-2, G5-9…G5-13 | V3 `map_*`; V1 parse; V5 |
| L8 | New runs start on the moved terrace (z −136). Saves made before this guide still load at the right place (old coordinates converted) | G5-4, G5-14, G5-15 | V3 `spawn_on_terrace`; V4 restart test |
| L9 | Existing tests still pass with moved coordinates | G5-16 | V4 |

**Deliberately not changed:**
- The Mirror Colosseum. It is an open arena, not an interior hall, and the Warden fight is tuned to its 13 m sand ring.
- The Collapsed Gallery. It is a puzzle bridge with proven dimensions; it only moves north.

## C. File-change manifest

| Path | Operation | Step |
|---|---|---|
| `scripts/environment/journey_layout.gd` | create (`class_name JourneyLayout`) | G5-1 |
| `scripts/environment/grand_journey_builder.gd` | modify (build steps, dressing remap, anchors/waypoints, Stage 01/02/03/04/05, routes, scenery, occluders) | G5-2…G5-9 |
| `scripts/environment/journey_terrain.gd` | modify (world z bands, constants, gorge, arena skip) | G5-10 |
| `scripts/ambient/ambient_life_layout.gd` | modify (5 placement helpers convert positions) | G5-11 |
| `scripts/environment/weather_director.gd` | modify (1 line) | G5-12 |
| `scripts/core/audio_manager.gd` | modify (3 lines) | G5-12 |
| `scripts/ui/objective_tracker.gd` | modify (story thresholds, world targets, bridge guidance) | G5-13 |
| `scripts/core/leaderboard_store.gd` | modify (layout version, old-save conversion, hall enemy list) | G5-14 |
| `scenes/main/main.tscn` | modify (Player start z −56 → −136, one line) | G5-15 |
| `tests/squad_ai_windowed_test.gd`, `tests/feel_and_movement_test.gd` | modify (terrace / causeway coordinates) | G5-16 |
| `tests/layout_rework_test.gd` | create | G5-17 |
| `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md`, `MEMORY/02_CORE_SYSTEMS_AND_ARCHITECTURE.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` | modify | G5-18 |
| `%TEMP%\g5\*` | scratch files (splice helper + region texts), not part of the repo | G5-0, G5-3…G5-9 |

## D. Ordered implementation steps

### G5-0 — Baseline, save backup, splice helper

1. Check the baseline (working dir = repo root):
```powershell
git rev-parse --short HEAD
(Select-String -Path scripts/environment/grand_journey_builder.gd -Pattern "SupportLedge").Count
Test-Path scripts/environment/journey_layout.gd
```
   - **Expected:** first line `2f37a1b` (or a later commit that contains guide 04); then a number ≥ 1; then `False`.
   - If the second value is `0`, guide 04 is not applied: **stop** and report.
   - If the third is `True`, check G5-1's postcondition and continue from there.
2. Back up the save. Starting a run in the tests clears it.
```powershell
New-Item -ItemType Directory -Force "$env:TEMP\parallax_save_bk_g5" | Out-Null
Copy-Item "$env:APPDATA\Godot\app_userdata\PARALLAX\savegame.cfg" "$env:TEMP\parallax_save_bk_g5\savegame.cfg" -Force -ErrorAction SilentlyContinue
```
3. Create the folder `%TEMP%\g5` and the file `%TEMP%\g5\Set-Region.ps1` with exactly this content:
```powershell
function Set-Region {
  param(
    [Parameter(Mandatory)] [string]$File,
    [Parameter(Mandatory)] [string]$StartRx,
    [Parameter(Mandatory)] [string]$EndRx,
    [int]$Keep = 0,
    [int]$BlankAfter = 0,
    [Parameter(Mandatory)] [int]$MinLines,
    [Parameter(Mandatory)] [int]$MaxLines,
    [Parameter(Mandatory)] [string]$MustContain,
    [Parameter(Mandatory)] [string]$NewTextFile
  )
  # Replaces lines [first line matching StartRx .. (first line matching EndRx) - 1 - Keep] with the text file.
  $path = (Resolve-Path $File).Path
  $raw = [System.IO.File]::ReadAllText($path)
  $nl = "`n"
  if ($raw.Contains("`r`n")) { $nl = "`r`n" }
  $lines = $raw -split [regex]::Escape($nl)
  $s = @(); $t = @()
  for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -cmatch $StartRx) { $s += $i }
    if ($lines[$i] -cmatch $EndRx) { $t += $i }
  }
  if ($s.Count -ne 1 -or $t.Count -ne 1) { throw "STOP: anchor matches start=$($s.Count) end=$($t.Count) (need exactly 1 each) in $File" }
  $first = $s[0]
  $last = $t[0] - 1 - $Keep
  $n = $last - $first + 1
  if ($n -lt $MinLines -or $n -gt $MaxLines) { throw "STOP: region is $n lines (expected $MinLines..$MaxLines) in $File" }
  $region = $lines[$first..$last] -join "`n"
  if (-not $region.Contains($MustContain)) { throw "STOP: region does not contain '$MustContain' in $File" }
  $newRaw = [System.IO.File]::ReadAllText((Resolve-Path $NewTextFile).Path).Replace("`r`n", "`n").TrimEnd([char[]]@("`n"))
  $newLines = @($newRaw -split "`n")
  for ($b = 0; $b -lt $BlankAfter; $b++) { $newLines += "" }
  $before = @()
  if ($first -gt 0) { $before = $lines[0..($first - 1)] }
  $after = $lines[($last + 1)..($lines.Length - 1)]
  $out = @($before) + $newLines + @($after)
  [System.IO.File]::WriteAllText($path, ($out -join $nl), (New-Object System.Text.UTF8Encoding($false)))
  "ok $File : replaced $n lines with $($newLines.Count)"
}
```
**Postcondition:** `Test-Path "$env:TEMP\g5\Set-Region.ps1"` → `True`.

### G5-1 — Create `scripts/environment/journey_layout.gd`
The target must not exist (or must equal this content).
```gdscript
class_name JourneyLayout
extends RefCounted
## Macro layout of "The Ascent" after the 2026-11-18 rework (IdiotHandOffGuide 05).
##
## GrandJourneyBuilder was authored in STORY coordinates (the old compact layout, z -61 .. 202). The rework:
##  * moved the start terrace 80 m south (OFF_S1_TERRACE);
##  * replaced the four connectors (Pilgrim's Causeway, Sunlit Stair, Windswept Rampart, Processional) with long
##    winding bridges, two bastions each (ROUTES), built straight in WORLD coordinates by _build_routes();
##  * grew the Hall of Echoes 20 -> 60 m and the clock-tower chamber 12 -> 36 m (also built in WORLD coordinates);
##  * kept Stage 03 (gallery) and Stage 05 (esplanade, colosseum, summit) in story coordinates, shifting their
##    stage roots and decor zones by OFF_S3 / OFF_S5.
## Anything that still thinks in story coordinates converts here: to_world(), to_world_z(), story_z().

const VERSION: int = 2

const OFF_S1_TERRACE: float = -80.0
const OFF_S3: float = 104.0
const OFF_S5: float = 160.0

const HALL_CENTER := Vector3(0.0, 4.0, 86.0)
const HALL_HALF: float = 30.0
const CHAMBER_CENTER := Vector3(0.0, 6.0, 210.0)
const CHAMBER_HALF: float = 18.0

## [story z, world z] breakpoints; piecewise linear, slope 1 beyond both ends.
const ZMAP: Array = [
	[-50.5, -130.5], [-15.2, -15.2], [7.6, 7.6], [24.0, 56.0], [44.0, 116.0],
	[58.0, 162.0], [87.4, 191.4], [100.6, 228.6], [116.0, 276.0],
]
## Story z ranges whose old floors were replaced by the bridges: decor / flora authored there is dropped.
const DROPPED: Array = [[-50.5, -15.2], [7.9, 23.5], [44.5, 57.5], [100.7, 115.9]]
## Story z ranges of the two 3x rooms: x widens by SCALE_X there.
const SCALED: Array = [[24.0, 44.0], [87.4, 100.6]]
const SCALE_X: float = 3.0

const BRIDGE_WIDTH: float = 6.0
## Winding bridges in WORLD coordinates (feet heights), z-monotonic. Each node is either
##   [position, bastion_radius]                  - a bastion: round platform, ring parapet, garrison
##   [position, 0.0, edge_z, edge_half_width]    - first / last node: a floor edge at z = edge_z whose opening
##                                                 (|x| <= edge_half_width) is closed by join rails out to the bridge
const ROUTES: Array = [
	["R1_PilgrimCauseway", [[Vector3(0, 0, -131), 0.0, -131.0, 6.0], [Vector3(34, 0, -97), 8.0], [Vector3(-34, 0, -49), 8.0], [Vector3(0, 0, -15), 0.0, -15.0, 7.0]]],
	["R2_SunlitBridges", [[Vector3(0, 0, 8), 0.0, 8.0, 2.2], [Vector3(16, 1.1, 24), 8.0], [Vector3(-16, 2.9, 40), 8.0], [Vector3(0, 4, 56), 0.0, 55.5, 2.0]]],
	["R3_WindsweptRampart", [[Vector3(0, 4, 116), 0.0, 116.5, 2.0], [Vector3(16, 4.55, 132), 8.0], [Vector3(-16, 5.45, 148), 8.0], [Vector3(0, 6, 164), 0.0, 164.0, 3.95]]],
	["R5_Processional", [[Vector3(0, 6, 228), 0.0, 229.2, 2.0], [Vector3(16, 7.1, 244), 8.0], [Vector3(-16, 8.9, 260), 8.0], [Vector3(0, 10, 276), 0.0, 276.0, 9.0]]],
]


static func to_world_z(story: float) -> float:
	return _interp(story, 0, 1)


static func story_z(world: float) -> float:
	return _interp(world, 1, 0)


static func _interp(v: float, src: int, dst: int) -> float:
	var first: Array = ZMAP[0]
	if v <= float(first[src]):
		return float(first[dst]) + (v - float(first[src]))
	for i in range(ZMAP.size() - 1):
		var a: Array = ZMAP[i]
		var b: Array = ZMAP[i + 1]
		if v <= float(b[src]):
			var t: float = (v - float(a[src])) / maxf(0.0001, float(b[src]) - float(a[src]))
			return lerpf(float(a[dst]), float(b[dst]), t)
	var last: Array = ZMAP[ZMAP.size() - 1]
	return float(last[dst]) + (v - float(last[src]))


static func is_scaled(story_z_val: float) -> bool:
	for r in SCALED:
		if story_z_val >= float(r[0]) and story_z_val <= float(r[1]):
			return true
	return false


static func is_dropped(story_z_val: float) -> bool:
	for r in DROPPED:
		if story_z_val > float(r[0]) and story_z_val < float(r[1]):
			return true
	return false


## Story-coordinate point -> world point (x widens x3 inside the two rebuilt rooms).
static func to_world(p: Vector3) -> Vector3:
	var x: float = p.x * SCALE_X if is_scaled(p.z) else p.x
	return Vector3(x, p.y, to_world_z(p.z))


## Moves story-coordinate decor (the Dress_* set-dressing zones) onto the world layout. Nodes in a bridge region
## are freed (they would float in the air); every other node moves with to_world(). An identity-transform node
## with children is a container (its children carry the story positions); an identity MultiMesh has its
## instances moved instead.
static func remap_subtree(n: Node) -> void:
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var c3: Node3D = c as Node3D
		if c3 is MultiMeshInstance3D and c3.transform.is_equal_approx(Transform3D.IDENTITY):
			_remap_multimesh(c3 as MultiMeshInstance3D)
		elif c3.transform.is_equal_approx(Transform3D.IDENTITY) and c3.get_child_count() > 0:
			remap_subtree(c3)
		elif is_dropped(c3.position.z):
			n.remove_child(c3)
			c3.queue_free()
		else:
			c3.position = to_world(c3.position)


static func _remap_multimesh(mmi: MultiMeshInstance3D) -> void:
	var mm: MultiMesh = mmi.multimesh
	if mm == null:
		return
	var kept: Array[Transform3D] = []
	for i in range(mm.instance_count):
		var xf: Transform3D = mm.get_instance_transform(i)
		if not is_dropped(xf.origin.z):
			xf.origin = to_world(xf.origin)
			kept.append(xf)
	mm.instance_count = 0
	mm.instance_count = kept.size()
	for i in range(kept.size()):
		mm.set_instance_transform(i, kept[i])


## Objective guidance on the bridges: the next bridge node north of the player (bastion centre or the far end)
## while the player is on a bridge, `fallback` elsewhere. Bridges are z-monotonic, so "ahead" = further north.
static func guide_target(world_pos: Vector3, fallback: Vector3) -> Vector3:
	for r in ROUTES:
		var nodes: Array = r[1]
		var z0: float = ((nodes[0] as Array)[0] as Vector3).z
		var z1: float = ((nodes[nodes.size() - 1] as Array)[0] as Vector3).z
		if world_pos.z < z0 - 6.0 or world_pos.z > z1:
			continue
		for nd in nodes:
			var p: Vector3 = (nd as Array)[0]
			if p.z > world_pos.z + 3.0:
				return p
		return fallback
	return fallback
```
**Postcondition:** the file exists and contains `class_name JourneyLayout` and `static func guide_target`.

### G5-2 — Builder: add the bridge build step and remap the set dressing
File `scripts/environment/grand_journey_builder.gd`. Replace block:
```gdscript
		["Raising the Execution Arena", func() -> void: add_child(_build_stage_05_arena())],
```
with:
```gdscript
		["Raising the Execution Arena", func() -> void: add_child(_build_stage_05_arena())],
		["Spanning the winding bridges", func() -> void: add_child(_build_routes())],
```
Replace block:
```gdscript
	if enable_set_dressing:
		(load("res://scripts/environment/journey_set_dressing.gd") as GDScript).new(self).call("build")
```
with:
```gdscript
	if enable_set_dressing:
		(load("res://scripts/environment/journey_set_dressing.gd") as GDScript).new(self).call("build")
		# The dressing is authored in story coordinates: move it onto the stretched layout (JourneyLayout).
		for dz in _decor.get_children():
			if String(dz.name).begins_with("Dress_"):
				JourneyLayout.remap_subtree(dz)
```
**Postcondition:** `add_child(_build_routes())` and `JourneyLayout.remap_subtree(dz)` each appear exactly once. `_build_routes` itself is defined later, in G5-5, so a parse check passes only after G5-5.

### G5-3 — Builder: key anchors and route waypoints in world coordinates (region splice)
Save this block as `%TEMP%\g5\anchors.gd.txt`:
```gdscript
func get_key_anchors() -> Dictionary:
	# World coordinates (JourneyLayout). Stage 03 / 05 content is story-built and shifted by OFF_S3 / OFF_S5.
	var s3 := Vector3(0, 0, JourneyLayout.OFF_S3)
	var s5 := Vector3(0, 0, JourneyLayout.OFF_S5)
	var hc: Vector3 = JourneyLayout.HALL_CENTER
	var cc: Vector3 = JourneyLayout.CHAMBER_CENTER
	return {
		"player_spawn": Vector3(0.0, 0.0, -56.0 + JourneyLayout.OFF_S1_TERRACE),
		"entry_gap_center": Vector3(0.0, 0.0, 1.0),
		"entry_switch": Vector3(-3.1, 0.0, 3.2),
		"hall_pillar": hc,
		"skeleton_1": hc + Vector3(-18.0, 0.0, -18.0),
		"skeleton_2": hc + Vector3(18.0, 0.0, -10.0),
		"phantom_1": hc + Vector3(-18.0, 0.0, 22.0),
		"phantom_2": hc + Vector3(18.0, 0.0, 24.0),
		"gallery_bridge_center": Vector3(0.0, Y_GALLERY, 72.0) + s3,
		"weak_stone_support": Vector3(0.0, Y_GALLERY + 3.6, 80.2) + s3,
		"bridge_anchor": Vector3(0.0, Y_GALLERY + 3.6, 81.6) + s3,
		"shielded_guard": Vector3(0.0, Y_GALLERY, 83.2) + s3,
		"mechanism_dais": cc + Vector3(-3.0, 1.35, -1.0),
		"mechanism_plate": cc,
		"arena_entry": Vector3(0.0, Y_ARENA, ARENA_CENTER.z - 13.5) + s5,
		"warden_spawn": Vector3(0.0, Y_ARENA, ARENA_CENTER.z - 1.0) + s5,
		"arena_exit": Vector3(0.0, Y_ARENA, ARENA_CENTER.z + 13.5) + s5,
		"summit": Vector3(0.0, Y_ARENA, ARENA_CENTER.z + 40.0) + s5,
	}


## Ordered critical-path waypoints (WORLD feet positions) with the realm required to stand there.
## Feeds JourneyTerrain (it keeps the landscape below this band). Bridges come from JourneyLayout.ROUTES.
func get_route_waypoints() -> Array:
	var bridges: Dictionary = {}
	for r in JourneyLayout.ROUTES:
		var pts: Array = []
		for nd in (r as Array)[1]:
			pts.append([(nd as Array)[0], 0])
		bridges[String((r as Array)[0])] = pts
	var out: Array = [[Vector3(0, 0, -56.0 + JourneyLayout.OFF_S1_TERRACE), 0]]
	out.append_array(bridges["R1_PilgrimCauseway"] as Array)
	out.append_array([[Vector3(0, 0, -10), 0], [Vector3(0, 0, -2), 0], [Vector3(0, 0, 1), 1], [Vector3(0, 0, 4), 1], [Vector3(0, 0, 6.5), 0]])
	out.append_array(bridges["R2_SunlitBridges"] as Array)
	var hc: Vector3 = JourneyLayout.HALL_CENTER
	out.append_array([[hc + Vector3(0, 0, -26), 0], [hc + Vector3(0, 0, -8), 0], [hc + Vector3(4, 0, 0), 0], [hc + Vector3(0, 0, 8), 0], [hc + Vector3(0, 0, 27), 0]])
	out.append_array(bridges["R3_WindsweptRampart"] as Array)
	var s3 := Vector3(0, 0, JourneyLayout.OFF_S3)
	for w in [[Vector3(0, Y_GALLERY, 65), 0], [Vector3(0, Y_GALLERY, 72), 1], [Vector3(0, Y_GALLERY, 76), 1],
			[Vector3(2.55, Y_GALLERY + 1.0, 75.3), 1], [Vector3(2.55, Y_GALLERY + 2.0, 77.0), 1], [Vector3(2.9, Y_GALLERY + 3.0, 78.5), 1],
			[Vector3(0, Y_GALLERY + 3.6, 79.2), 1], [Vector3(0, Y_GALLERY, 83.6), 0], [Vector3(0, Y_GALLERY, 86), 0]]:
		out.append([((w as Array)[0] as Vector3) + s3, (w as Array)[1]])
	var cc: Vector3 = JourneyLayout.CHAMBER_CENTER
	out.append_array([[cc + Vector3(0, 0, -14), 0], [cc + Vector3(0, 0, 14), 0]])
	out.append_array(bridges["R5_Processional"] as Array)
	var s5 := Vector3(0, 0, JourneyLayout.OFF_S5)
	for w in [[Vector3(0, Y_ARENA, 130), 0], [Vector3(0, Y_ARENA, 140), 0], [Vector3(2.6, Y_ARENA, 144), 0],
			[Vector3(6, Y_ARENA, 154), 0], [Vector3(2.6, Y_ARENA, 164), 0], [Vector3(0, Y_ARENA, 168), 0],
			[Vector3(0, Y_ARENA, 177), 0], [Vector3(0, Y_ARENA, 194), 0]]:
		out.append([((w as Array)[0] as Vector3) + s5, (w as Array)[1]])
	return out
```
Run:
```powershell
. "$env:TEMP\g5\Set-Region.ps1"; Set-Region -File scripts/environment/grand_journey_builder.gd -StartRx '^func get_key_anchors\(\) -> Dictionary:$' -EndRx '^# Materials$' -Keep 1 -BlankAfter 2 -MinLines 38 -MaxLines 52 -MustContain 'func get_route_waypoints() -> Array:' -NewTextFile "$env:TEMP\g5\anchors.gd.txt"
```
**Postcondition:**
- The command prints `ok ... replaced 4x lines with 6x`.
- The file contains `bridges["R5_Processional"]`.
- A line `# Materials` still follows a `# ====` banner line.

### G5-4 — Builder, Stage 01: terrace 80 m south, causeway replaced by bridge R1
**(a) Region splice.** Save this block as `%TEMP%\g5\prologue.gd.txt`:
```gdscript
	# --- Prologue: start terrace (moved 80 m south, 2026-11-18) and the gate forecourt. The Pilgrim's Causeway
	# between them is the winding bridge R1 with two bastions (_build_routes); its join rails close the terrace's
	# north edge (z -131) and the forecourt's south edge (z -15).
	var tz: float = -56.0 + JourneyLayout.OFF_S1_TERRACE
	_solid(root, "Prologue_StartTerrace", Vector3(0, -0.25, tz), Vector3(12, 0.5, 10), path_m)
	_solid(root, "Gate_Forecourt", Vector3(0, -0.25, -10), Vector3(14, 0.5, 10), floor_m)
	_parapet(root, "Rail_T0_S", Vector3(-6, 0, tz - 5.0), Vector3(6, 0, tz - 5.0), _m_wall())
	_parapet(root, "Rail_T0_W", Vector3(-6, 0, tz - 5.0), Vector3(-6, 0, tz + 5.0), _m_wall())
	_parapet(root, "Rail_T0_E", Vector3(6, 0, tz - 5.0), Vector3(6, 0, tz + 5.0), _m_wall())
	_parapet(root, "Rail_FC_W", Vector3(-7, 0, -15), Vector3(-7, 0, -5), _m_wall())
	_parapet(root, "Rail_FC_E", Vector3(7, 0, -15), Vector3(7, 0, -5), _m_wall())
```
Run:
```powershell
. "$env:TEMP\g5\Set-Region.ps1"; Set-Region -File scripts/environment/grand_journey_builder.gd -StartRx "^\t# --- Prologue: Pilgrim's Causeway" -EndRx '^\t# --- Gameplay core \(unchanged greybox coordinates\) ---$' -Keep 0 -BlankAfter 1 -MinLines 44 -MaxLines 46 -MustContain 'Rail_FC_SE' -NewTextFile "$env:TEMP\g5\prologue.gd.txt"
```
(In the double-quoted `-StartRx`, PowerShell leaves `\t` alone, so the regex receives `\t` = tab.)

**(b) Replace block:**
```gdscript
	root.add_child(_make_section_trigger("Trigger_Stage01_Entry", Vector3(0.0, 1.25, -56.0), Vector3(6.0, 2.5, 3.0),
		EncounterDirector.Section.ENTRY, Vector3(0.0, 0.0, -56.0), "", 0, NodePath(), false))
```
with:
```gdscript
	root.add_child(_make_section_trigger("Trigger_Stage01_Entry", Vector3(0.0, 1.25, -56.0 + JourneyLayout.OFF_S1_TERRACE), Vector3(6.0, 2.5, 3.0),
		EncounterDirector.Section.ENTRY, Vector3(0.0, 0.0, -56.0 + JourneyLayout.OFF_S1_TERRACE), "", 0, NodePath(), false))
```
**(c) Replace block** (terrace braziers + causeway / overlook decor):
```gdscript
	_brazier(g, Vector3(4.5, 0, -59.5))
	_brazier(g, Vector3(-4.5, 0, -59.5))
	# Prologue waystones and a toppled colossus on the overlook (looking out over the cloud sea).
	var fallen := CylinderMesh.new()
	fallen.top_radius = 0.9
	fallen.bottom_radius = 1.0
	fallen.height = 7.0
	fallen.radial_segments = 16
	# Toppled column lies along the west balustrade (clear of the causeway-to-causeway walking line).
	fallen.height = 4.4
	var fallen_basis: Basis = Basis(Vector3(1, 0, 0), PI * 0.5).rotated(Vector3.UP, 0.06)
	_mesh(g[0], "FallenColumn", fallen, _m_marble(), Transform3D(fallen_basis, Vector3(-10.3, 0.95, -31.75)))
	var fallen_col := _prop_collider(g[0], "FallenColumnCollider", Vector3(-10.3, 0.95, -31.75), _cyl_shape(0.98, 4.4))
	fallen_col.basis = fallen_basis
	_mesh(g[0], "OverlookObelisk", ProcMesh.column_mesh(0.45, 6.5, 12), _m_marble(), Transform3D(Basis.IDENTITY, Vector3(-10.5, 0, -35.5)))
	_prop_collider(g[0], "OverlookObeliskCollider", Vector3(-10.5, 3.25, -35.5), _cyl_shape(0.75, 6.5))
	for z in [-48.0, -40.0, -26.0, -19.0]:
		var x: float = lerpf(0.0, -7.0, clampf((z + 51.5) / 15.5, 0.0, 1.0)) if z < -30.0 else lerpf(-7.0, 0.0, clampf((z + 30.0) / 15.5, 0.0, 1.0))
		# Just outside the widened causeway's east rail (walkway half-width ~4.1 m on the x axis).
		_mesh(g[0], "Waystone", ProcMesh.column_mesh(0.25, 2.2, 8), _m_wall(), Transform3D(Basis.IDENTITY, Vector3(x + 4.9, 0, z)), true, 120.0)
	_crystal_cluster(g[2], Vector3(-3.5, 0.0, -35.4), 1.2, 11, true)
	_crystal_cluster(g[2], Vector3(5.0, 0.0, -57.0), 1.0, 12, true)
	g[1].add_child(_make_ambient_particles(Vector3(0, 3, -30), Vector3(10, 3, 30), false))
	g[2].add_child(_make_ambient_particles(Vector3(0, 3, -30), Vector3(10, 3, 30), true))
```
with:
```gdscript
	_brazier(g, Vector3(4.5, 0, -59.5 + JourneyLayout.OFF_S1_TERRACE))
	_brazier(g, Vector3(-4.5, 0, -59.5 + JourneyLayout.OFF_S1_TERRACE))
	_crystal_cluster(g[2], Vector3(5.0, 0.0, -57.0 + JourneyLayout.OFF_S1_TERRACE), 1.0, 12, true)
	g[1].add_child(_make_ambient_particles(Vector3(0, 3, -10), Vector3(10, 3, 6), false))
	g[2].add_child(_make_ambient_particles(Vector3(0, 3, -10), Vector3(10, 3, 6), true))
```
**(d) Replace block** (overlook roamers are gone; they now hold the R1 bastions):
```gdscript
	# Journey enemies (ENTRY): a two-skeleton teaching ambush on the overlook, and a Mirror phantom haunting
	# the gate forecourt that only reveals itself once the player first shifts to cross the stepping stones.
	var rg: Node3D = _roamer_group(root)
	_add_roamer(rg, "skeleton", "OverlookSkeleton_A", Vector3(-8.0, 0.0, -31.0), EncounterDirector.Section.ENTRY, Vector3(-7, 0, -40))
	_add_roamer(rg, "skeleton", "OverlookSkeleton_B", Vector3(-5.0, 0.0, -30.5), EncounterDirector.Section.ENTRY, Vector3(-7, 0, -40))
```
with:
```gdscript
	# Journey enemies (ENTRY): a Mirror phantom haunting the gate forecourt that only reveals itself once the
	# player first shifts to cross the stepping stones, plus the gate guards. The causeway ambushes now wait on
	# the two R1 bastions (_build_routes).
	var rg: Node3D = _roamer_group(root)
```
**(e) Delete these two lines** (replace them with nothing):
```gdscript
	# A Hollow Hexcaster hangs back up the path, teaching that some threats strike from range.
	_add_roamer(rg, "hexcaster", "OverlookHexcaster", Vector3(-4.3, 0.0, -24.0), EncounterDirector.Section.ENTRY, Vector3(-7, 0, -40))
```
**Postcondition:**
- The file has no `Prologue_CausewayA`, `OverlookSkeleton_A` or `OverlookHexcaster`.
- `Prologue_StartTerrace` appears once.
- `GateWarden_W` (from guide 04) is still present.

### G5-5 — Builder, Stage 02: 60 × 60 hall + the winding-bridge builder (region splice)
Save this block as `%TEMP%\g5\stage02.gd.txt`:
```gdscript
func _build_stage_02_hall() -> Node3D:
	## Hall of Echoes, 3x the old room: a 60 x 60 floor at Y 4 centred on JourneyLayout.HALL_CENTER, built in
	## WORLD coordinates (2026-11-18). The Sunlit Stair and Windswept Rampart are now the winding bridges R2 / R3
	## (_build_routes). Gameplay node names are unchanged (save system + objective tracker look them up).
	var root := Node3D.new()
	root.name = "Stage02_HallOfEchoes"
	var g: Array[Node3D] = _zone("Zone02_Hall")
	var y: float = Y_HALL
	var c: Vector3 = JourneyLayout.HALL_CENTER
	var h: float = JourneyLayout.HALL_HALF
	var zs: float = c.z - h
	var zn: float = c.z + h

	var hall_floor := _solid(root, "HallFloor", Vector3(c.x, y - 0.25, c.z), Vector3(h * 2.0, 0.5, h * 2.0), _m_floor())
	var ring := ProcMesh.ring_sector_mesh(16.8, 19.8, 0.0, 0.03, 0.0, TAU, 96)
	_mesh(hall_floor, "MosaicRing", ring, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), false)
	var seal := _make_gate("Gate02a_HallSouthSeal", Vector3(0.0, y, zs), 1, "", true)
	_style_gate(seal)
	root.add_child(seal)
	_build_hall_walls(root, g, y)

	var pillar := _make_breakable_pillar("CrackedCentralPillar", Vector3(c.x, y, c.z), BreakableProp.PropKind.CRACKED_PILLAR, 1, 0.60, Vector3(0.0, 0.0, 2.5), 2.5)
	_restyle_pillar(pillar, 9.0, 0.7, Vector3(0, 0, 1))
	root.add_child(pillar)
	# A ring of eight great columns (r 17) breaks up the big floor: cover from the hexcasters, lanes to kite through.
	var col_mesh: ArrayMesh = ProcMesh.column_mesh(0.9, 12.0, 16)
	var cols: Array = []
	for i in range(8):
		var a: float = TAU * (float(i) + 0.5) / 8.0
		var cp := Vector3(c.x + sin(a) * 17.0, y, c.z + cos(a) * 17.0)
		cols.append(Transform3D(Basis.IDENTITY, cp))
		_prop_collider(root, "HallColumnCollider", cp + Vector3(0, 6.0, 0), _cyl_shape(1.2, 12.0))
	_multimesh(g[0], "HallColumns", col_mesh, _m_marble(), cols)

	# Encounter garrison: every one counts toward "hall_of_echoes"; the exit gate opens when all are down.
	var hall_specs: Array = [
		["skeleton", "SkeletonGuard_1", "hall_skel_1", Vector3(-18, 0, -18)],
		["skeleton", "SkeletonGuard_2", "hall_skel_2", Vector3(18, 0, -10)],
		["skeleton", "SkeletonGuard_3", "hall_skel_3", Vector3(-10, 0, 6)],
		["skeleton", "SkeletonGuard_4", "hall_skel_4", Vector3(12, 0, 12)],
		["skeleton", "SkeletonGuard_5", "hall_skel_5", Vector3(-20, 0, 18)],
		["skeleton", "SkeletonGuard_6", "hall_skel_6", Vector3(20, 0, 20)],
		["phantom", "PhantomTwin_1", "hall_phantom_1", Vector3(-18, 0, 22)],
		["phantom", "PhantomTwin_2", "hall_phantom_2", Vector3(18, 0, 24)],
		["phantom", "PhantomTwin_3", "hall_phantom_3", Vector3(0, 0, 16)],
	]
	var exit_gate := _make_gate("Gate02_HallToGallery", Vector3(0.0, y, zn), 1, "hall_of_echoes", false)
	_style_gate(exit_gate)
	root.add_child(exit_gate)
	root.add_child(_make_section_trigger("Trigger_Stage02_Hall", Vector3(0.0, y + 1.25, zs + 2.0), Vector3(5.0, 2.5, 1.5),
		EncounterDirector.Section.HALL_COMBAT, Vector3(0.0, y, zs + 1.6), "hall_of_echoes", hall_specs.size(), NodePath("../Gate02a_HallSouthSeal"), false))

	if spawn_enemies:
		var enemies := Node3D.new()
		enemies.name = "Enemies"
		for spec in hall_specs:
			var e: EnemyBase = null
			var tint := Color(0.82, 0.76, 0.65)
			if String(spec[0]) == "phantom":
				e = PhantomTwin.new()
				tint = Color(0.25, 0.78, 1.0, 0.85)
			else:
				e = SkeletonGuard.new()
				e.died.connect(_on_hall_skeleton_died)
			_configure_enemy_actor(e, String(spec[1]), String(spec[2]), c + (spec[3] as Vector3), tint)
			enemies.add_child(e)
		root.add_child(enemies)
	# Roamers (HALL section, never hold the gate): a Grave Brute before the exit, two Hexcasters on the flanks.
	var hrg: Node3D = _roamer_group(root)
	_add_roamer(hrg, "brute", "HallBrute", c + Vector3(0, 0, 24), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
	_add_roamer(hrg, "hexcaster", "HallHexcaster_W", c + Vector3(-24, 0, 0), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
	_add_roamer(hrg, "hexcaster", "HallHexcaster_E", c + Vector3(24, 0, 4), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))

	for p in [Vector3(-(h - 1.8), y, zs + 1.8), Vector3(h - 1.8, y, zs + 1.8), Vector3(-(h - 1.8), y, zn - 1.8), Vector3(h - 1.8, y, zn - 1.8),
			Vector3(-(h - 1.8), y, c.z), Vector3(h - 1.8, y, c.z)]:
		_brazier(g, p)
	for bx in [-15.0, -5.0, 5.0, 15.0]:
		_banner(g[1], Vector3(bx, y + 11.0, zn - 0.7), 180.0, 2.4, 8.0, false)
		_banner(g[2], Vector3(bx, y + 11.0, zn - 0.7), 180.0, 2.4, 8.0, true)
	# Crystals grow on the cliff just outside the arcades: seen through the grilles, never in the fighting space.
	_crystal_cluster(g[2], Vector3(-(h + 2.3), 3.4, c.z), 1.4, 21)
	_crystal_cluster(g[2], Vector3(h + 2.3, 3.4, c.z - 4.0), 1.2, 22)
	# Gate-arch piers flanking both gates protrude onto the landings: give them real collision.
	for sx in [-1.0, 1.0]:
		for gz in [zs - 0.7, zn + 0.7]:
			_prop_collider(root, "GateArchPier_%d" % int(sx), Vector3(sx * 2.6, y + 4.0, gz), _box_shape(Vector3(0.8, 8.0, 1.6)))
	g[1].add_child(_make_ambient_particles(Vector3(c.x, y + 3.5, c.z), Vector3(h - 3.0, 3.5, h - 3.0), false))
	g[2].add_child(_make_ambient_particles(Vector3(c.x, y + 3.5, c.z), Vector3(h - 3.0, 3.5, h - 3.0), true))
	return root


func _build_hall_walls(root: Node3D, g: Array[Node3D], y: float) -> void:
	var c: Vector3 = JourneyLayout.HALL_CENTER
	var h: float = JourneyLayout.HALL_HALF
	var zs: float = c.z - h
	var zn: float = c.z + h
	var wall_m: ShaderMaterial = _m_wall()
	# Collision: four sides, with 4 m openings for the south seal gate and north exit gate.
	_invisible_wall(root, "Wall_West", Vector3(-h - 0.25, y + 4.0, c.z), Vector3(0.5, 8.0, h * 2.0 + 0.5))
	_invisible_wall(root, "Wall_East", Vector3(h + 0.25, y + 4.0, c.z), Vector3(0.5, 8.0, h * 2.0 + 0.5))
	var seg_w: float = h - 2.0 + 0.2
	for sx in [-1.0, 1.0]:
		_invisible_wall(root, "Wall_South_%d" % int(sx), Vector3(sx * (2.0 + seg_w * 0.5), y + 4.0, zs - 0.25), Vector3(seg_w, 8.0, 0.5))
		_invisible_wall(root, "Wall_North_%d" % int(sx), Vector3(sx * (2.0 + seg_w * 0.5), y + 4.0, zn + 0.25), Vector3(seg_w, 8.0, 0.5))

	# Visual: two-storey arcades on all four sides (arch modules + grilles), corner towers, cornice.
	var mod_w: float = 4.0
	var arch_low: ArrayMesh = ProcMesh.arch_mesh(mod_w, 8.0, 2.6, 3.6, 1.4)
	var arch_up: ArrayMesh = ProcMesh.arch_mesh(mod_w, 5.0, 2.4, 2.4, 1.0)
	var grille: ArrayMesh = ProcMesh.portcullis_mesh(2.6, 4.6, 0.08, 0.32)
	var low_x: Array = []
	var up_x: Array = []
	var grille_x: Array = []
	# West/East sides: 4 m modules along Z (15 per 60 m side), facing inward.
	var n_mod: int = int(round(h * 2.0 / mod_w))
	for sx in [-1.0, 1.0]:
		for i in range(n_mod):
			var z: float = zs + mod_w * (float(i) + 0.5)
			var b := Basis(Vector3.UP, PI * 0.5)
			low_x.append(Transform3D(b, Vector3(sx * (h + 0.7), y, z)))
			up_x.append(Transform3D(b, Vector3(sx * (h + 0.9), y + 8.0, z)))
			grille_x.append(Transform3D(b, Vector3(sx * (h + 0.7), y, z)))
	# South/North sides: eight equal bays each side of the 6 m gate arch tile x 3 .. h exactly (no overlaps).
	var bays: int = 8
	var bay_w: float = (h - 3.0) / float(bays)
	var side_low: ArrayMesh = ProcMesh.arch_mesh(bay_w, 8.0, bay_w - 1.2, 3.6, 1.4)
	var side_up: ArrayMesh = ProcMesh.arch_mesh(bay_w, 5.0, bay_w - 1.4, 2.4, 1.0)
	var side_grille: ArrayMesh = ProcMesh.portcullis_mesh(bay_w - 1.2, 4.6, 0.08, 0.32)
	var gate_arch: ArrayMesh = ProcMesh.arch_mesh(6.0, 8.0, 4.4, 3.4, 1.6)
	var gate_up: ArrayMesh = ProcMesh.arch_mesh(6.0, 5.0, 3.4, 2.4, 1.0)
	var side_low_x: Array = []
	var side_up_x: Array = []
	var side_grille_x: Array = []
	for sz in [zs - 0.7, zn + 0.7]:
		for k in range(bays):
			var bx: float = 3.0 + bay_w * (float(k) + 0.5)
			for sx in [-1.0, 1.0]:
				side_low_x.append(Transform3D(Basis.IDENTITY, Vector3(sx * bx, y, sz)))
				side_up_x.append(Transform3D(Basis.IDENTITY, Vector3(sx * bx, y + 8.0, sz)))
				side_grille_x.append(Transform3D(Basis.IDENTITY, Vector3(sx * bx, y, sz)))
		_mesh(g[0], "GateArch", gate_arch, wall_m, Transform3D(Basis.IDENTITY, Vector3(0, y, sz)))
		_mesh(g[0], "GateArchUpper", gate_up, wall_m, Transform3D(Basis.IDENTITY, Vector3(0, y + 8.0, sz)))
	_multimesh(g[0], "HallArcadeLower", arch_low, wall_m, low_x)
	_multimesh(g[0], "HallArcadeUpper", arch_up, wall_m, up_x)
	_multimesh(g[0], "HallGrilles", grille, _m_iron(), grille_x)
	_multimesh(g[0], "HallArcadeLowerNS", side_low, wall_m, side_low_x)
	_multimesh(g[0], "HallArcadeUpperNS", side_up, wall_m, side_up_x)
	_multimesh(g[0], "HallGrillesNS", side_grille, _m_iron(), side_grille_x)
	# Corner towers
	var tower := BoxMesh.new()
	tower.size = Vector3(4.0, 24.0, 4.0)
	var towers: Array = []
	for cx in [-(h + 2.0), h + 2.0]:
		for cz in [zs - 2.0, zn + 2.0]:
			towers.append(Transform3D(Basis.IDENTITY, Vector3(cx, y + 6.0, cz)))
	_multimesh(g[0], "HallTowers", tower, wall_m, towers)
	var tower_cap := BoxMesh.new()
	tower_cap.size = Vector3(4.8, 0.8, 4.8)
	var caps: Array = []
	for t in towers:
		var tt: Transform3D = t
		caps.append(Transform3D(Basis.IDENTITY, tt.origin + Vector3(0, 12.4, 0)))
	_multimesh(g[0], "HallTowerCaps", tower_cap, _m_marble(), caps)
	# Cornice ring
	var cor := BoxMesh.new()
	cor.size = Vector3(1.6, 0.7, h * 2.0 + 4.0)
	_mesh(g[0], "CorniceW", cor, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(-(h + 0.9), y + 13.35, c.z)))
	_mesh(g[0], "CorniceE", cor, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(h + 0.9, y + 13.35, c.z)))
	# N/S runs sit 4 cm higher so the overlapping corner blocks never share a top/bottom plane.
	_mesh(g[0], "CorniceS", cor, _m_marble(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, y + 13.39, zs - 1.0)))
	_mesh(g[0], "CorniceN", cor, _m_marble(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, y + 13.39, zn + 1.0)))


# =====================================================================================================
# Winding bridges (2026-11-18): the four connectors as long zig-zag bridges with two bastions each.
# Geometry lives in JourneyLayout.ROUTES (world coordinates); garrisons below.
# =====================================================================================================

## Bastion garrisons per bridge: [bastion 1 kinds, bastion 2 kinds] (roamer kinds of _add_roamer).
const ROUTE_ENEMIES: Dictionary = {
	"R1_PilgrimCauseway": [["skeleton", "skeleton", "hexcaster"], ["skeleton", "shield", "hexcaster"]],
	"R2_SunlitBridges": [["phantom", "skeleton", "stalker"], ["skeleton", "skeleton", "hexcaster"]],
	"R3_WindsweptRampart": [["skeleton", "stalker", "hexcaster"], ["brute", "skeleton", "phantom"]],
	"R5_Processional": [["phantom", "skeleton", "hexcaster"], ["shield", "skeleton", "brute"]],
}


func _route_section(route_name: String) -> int:
	## The section that is current while the player walks this bridge (roamers wake only in their section).
	match route_name:
		"R3_WindsweptRampart":
			return EncounterDirector.Section.HALL_COMBAT
		"R5_Processional":
			return EncounterDirector.Section.MECHANISM_CHAMBER
		_:
			return EncounterDirector.Section.ENTRY


func _build_routes() -> Node3D:
	var all := Node3D.new()
	all.name = "Journey_Routes"
	var g: Array[Node3D] = _zone("Zone_Routes")
	var seed_i: int = 900
	for r in JourneyLayout.ROUTES:
		var rname: String = String((r as Array)[0])
		var nodes: Array = (r as Array)[1]
		var root := Node3D.new()
		root.name = rname
		all.add_child(root)
		var kinds: Array = ROUTE_ENEMIES.get(rname, [])
		var bi: int = 0
		for i in range(1, nodes.size() - 1):
			var nd: Array = nodes[i]
			if float(nd[1]) <= 0.0:
				continue
			var bk: Array = []
			if bi < kinds.size():
				bk = kinds[bi]
			var prev_p: Vector3 = (nodes[i - 1] as Array)[0]
			var next_p: Vector3 = (nodes[i + 1] as Array)[0]
			_build_bastion(root, g, "%s_Bastion%d" % [rname, bi + 1], nd[0] as Vector3, float(nd[1]), [prev_p, next_p], bk, _route_section(rname), seed_i)
			seed_i += 1
			bi += 1
		for i in range(nodes.size() - 1):
			_build_bridge_leg(root, g, "%s_Leg%d" % [rname, i + 1], nodes[i] as Array, nodes[i + 1] as Array)
	return all


func _build_bastion(root: Node3D, g: Array[Node3D], bname: String, c: Vector3, r: float, neighbours: Array, kinds: Array, section: int, seed_val: int) -> void:
	## Round fortified platform: walkable disc on a masonry drum and rock spur, ring parapet with openings exactly
	## where the bridge legs arrive, merlons, two braziers on the far side, and a garrison of roamers.
	var off: float = JourneyLayout.BRIDGE_WIDTH * 0.5 + 0.2
	var rr: float = r - 0.2
	var body := StaticBody3D.new()
	body.name = bname
	body.position = Vector3(c.x, c.y - 0.25, c.z)
	body.collision_layer = LAYER_WORLD_SHARED
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _cyl_shape(r, 0.5)
	body.add_child(cs)
	var deck := CylinderMesh.new()
	deck.top_radius = r
	deck.bottom_radius = r
	deck.height = 0.5
	deck.radial_segments = 40
	deck.rings = 1
	_mesh(body, "Deck", deck, _m_floor(), Transform3D.IDENTITY, true, 0.0, false)
	root.add_child(body)
	var drum := CylinderMesh.new()
	drum.top_radius = r + 0.3
	drum.bottom_radius = r + 1.4
	drum.height = 8.0
	drum.radial_segments = 32
	drum.rings = 1
	_mesh(g[0], "BastionDrum", drum, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(c.x, c.y - 0.52 - 4.0, c.z)))
	var rk: MeshInstance3D = _rock(_scenery, "BastionRock", Vector3(c.x, c.y - 8.6, c.z), Vector3(r * 2.0 + 5.0, 60.0, r * 2.0 + 5.0), seed_val, _m_rock(), 0.72, 0.24, 14, false, true)
	rk.remove_meta("gj_batch")
	# Ring parapet: arcs between the openings. Each opening spans +-asin(off / rr) around a leg direction, so the
	# leg's side rails end exactly on the arc ends (no gap to fall through).
	var opens: Array[float] = []
	for nb in neighbours:
		var d: Vector3 = (nb as Vector3) - c
		opens.append(atan2(d.x, d.z))
	opens.sort()
	var beta: float = asin(clampf(off / rr, 0.0, 1.0))
	var arcs: Array = []
	for i in range(opens.size()):
		var a0: float = opens[i] + beta
		var a1: float = opens[(i + 1) % opens.size()] - beta
		if i == opens.size() - 1:
			a1 += TAU
		if a1 - a0 > 0.05:
			arcs.append([a0, a1])
	var merlon := BoxMesh.new()
	merlon.size = Vector3(0.9, 1.0, 0.55)
	var merlons: Array = []
	var seg: int = 0
	var far_arc: Array = [0.0, 0.0]
	for arc in arcs:
		var a0: float = float(arc[0])
		var a1: float = float(arc[1])
		if a1 - a0 > float(far_arc[1]) - float(far_arc[0]):
			far_arc = [a0, a1]
		var n: int = maxi(1, ceili((a1 - a0) / 0.26))
		for k in range(n):
			var t0: float = lerpf(a0, a1, float(k) / float(n))
			var t1: float = lerpf(a0, a1, float(k + 1) / float(n))
			var p0 := Vector3(c.x + sin(t0) * rr, c.y, c.z + cos(t0) * rr)
			var p1 := Vector3(c.x + sin(t1) * rr, c.y, c.z + cos(t1) * rr)
			_parapet(root, "%s_Ring%d" % [bname, seg], p0, p1, _m_wall())
			seg += 1
		var nm: int = int((a1 - a0) * rr / 2.4)
		for k in range(nm):
			var am: float = lerpf(a0, a1, (float(k) + 0.5) / float(nm))
			merlons.append(Transform3D(Basis(Vector3.UP, am), Vector3(c.x + sin(am) * rr, c.y + 1.75, c.z + cos(am) * rr)))
	if not merlons.is_empty():
		_multimesh(g[0], "BastionMerlons", merlon, _m_wall(), merlons)
	# Braziers on the far (outer) side of the bend, garrison spread around the centre facing the way in.
	var m: float = (float(far_arc[0]) + float(far_arc[1])) * 0.5
	for s in [-0.42, 0.42]:
		_brazier(g, Vector3(c.x + sin(m + s) * (rr - 1.3), c.y, c.z + cos(m + s) * (rr - 1.3)))
	var face: Vector3 = neighbours[0] as Vector3
	var spots: Array = [m, m + 2.2, m - 2.2]
	for ei in range(kinds.size()):
		var a: float = float(spots[ei % spots.size()])
		var ep := Vector3(c.x + sin(a) * 3.4, c.y, c.z + cos(a) * 3.4)
		var kind: String = String(kinds[ei])
		_add_roamer(_roamer_group(root), kind, "%s_%s%d" % [bname, kind.capitalize(), ei + 1], ep, section, face)


func _build_bridge_leg(root: Node3D, g: Array[Node3D], lname: String, na: Array, nb: Array) -> void:
	## One straight span between two bridge nodes: sloped deck between the bastion edges (or from a floor edge,
	## with a flat apron tucked into that floor so the angled end leaves no hole), side parapets, join rails along
	## a floor edge, and masonry piers under long spans.
	var a: Vector3 = na[0]
	var b: Vector3 = nb[0]
	var ra: float = float(na[1])
	var rb: float = float(nb[1])
	var w: float = JourneyLayout.BRIDGE_WIDTH
	var off: float = w * 0.5 + 0.2
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var u: Vector3 = flat.normalized()
	var nrm := Vector3(u.z, 0.0, -u.x)
	var tan_th: float = absf(u.x) / maxf(absf(u.z), 0.05)
	var a_deck: Vector3 = a + u * (ra - 0.4) if ra > 0.0 else a
	var b_deck: Vector3 = b - u * (rb - 0.4) if rb > 0.0 else b
	if ra <= 0.0:
		_ramp(root, lname + "_ApronA", a - u * (w * 0.5 * tan_th + 0.6), a, w, _m_path())
	if rb <= 0.0:
		_ramp(root, lname + "_ApronB", b, b + u * (w * 0.5 * tan_th + 0.6), w, _m_path())
	_ramp(root, lname, a_deck, b_deck, w, _m_path())
	# Side parapets: from the bastion ring (or the floor edge line) to the next ring / edge.
	for s in [-1.0, 1.0]:
		var p0: Vector3
		var p1: Vector3
		if ra > 0.0:
			p0 = a + u * sqrt(maxf(0.0, (ra - 0.2) * (ra - 0.2) - off * off)) + nrm * (s * off)
		else:
			p0 = _line_at_z(a, b, s * off, float(na[2]))
		if rb > 0.0:
			p1 = b - u * sqrt(maxf(0.0, (rb - 0.2) * (rb - 0.2) - off * off)) + nrm * (s * off)
		else:
			p1 = _line_at_z(a, b, s * off, float(nb[2]))
		p0.y = a.y
		p1.y = b.y
		_parapet(root, "%s_Rail%s" % [lname, "R" if s > 0.0 else "L"], p0, p1, _m_wall())
	# Join rails along a floor edge (z = edge_z, edge opening |x| <= edge_half_width) out to the bridge rails.
	for e in [[na, ra, a], [nb, rb, b]]:
		if float(e[1]) > 0.0:
			continue
		var nd: Array = e[0]
		var ez: float = float(nd[2])
		var hw: float = float(nd[3])
		var ey: float = (e[2] as Vector3).y
		var xl: float = _line_at_z(a, b, -off, ez).x
		var xr: float = _line_at_z(a, b, off, ez).x
		var lo: float = minf(xl, xr)
		var hi: float = maxf(xl, xr)
		if absf(lo + hw) > 0.05:
			_parapet(root, lname + "_JoinW", Vector3(-hw, ey, ez), Vector3(lo, ey, ez), _m_wall())
		if absf(hi - hw) > 0.05:
			_parapet(root, lname + "_JoinE", Vector3(hw, ey, ez), Vector3(hi, ey, ez), _m_wall())
	# Masonry piers under long spans (visual only; the kill plane still catches falls).
	var piers: int = int(flat.length() / 16.0)
	for k in range(piers):
		var pp: Vector3 = a_deck.lerp(b_deck, (float(k) + 1.0) / float(piers + 1))
		var pier := BoxMesh.new()
		pier.size = Vector3(w * 0.55, 30.0, 2.2)
		_mesh(g[0], "BridgePier", pier, _m_wall(), Transform3D(Basis(Vector3.UP, atan2(u.x, u.z)), Vector3(pp.x, pp.y - 0.62 - 15.0, pp.z)))
```
Run:
```powershell
. "$env:TEMP\g5\Set-Region.ps1"; Set-Region -File scripts/environment/grand_journey_builder.gd -StartRx '^func _build_stage_02_hall\(\) -> Node3D:$' -EndRx '^# Stage 03 .*Aqueduct Gallery' -Keep 1 -BlankAfter 2 -MinLines 190 -MaxLines 205 -MustContain 'func _build_hall_walls' -NewTextFile "$env:TEMP\g5\stage02.gd.txt"
```
**Postcondition:**
- The file contains `func _build_routes() -> Node3D:` and `HallHexcaster_E`.
- It has no `SunlitStair_Ramp` and no `Rampart_CurtainWall`.

### G5-6 — Builder, Stage 03: shift the gallery by `OFF_S3`
Replace block:
```gdscript
	var g: Array[Node3D] = _zone("Zone03_Gallery")
```
with:
```gdscript
	var g: Array[Node3D] = _zone("Zone03_Gallery")
	# Story-coordinate stage: the stage root and its decor zone are shifted onto the stretched layout.
	root.position.z = JourneyLayout.OFF_S3
	(g[0].get_parent() as Node3D).position.z = JourneyLayout.OFF_S3
```
Replace block:
```gdscript
		EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0.0, y, 61.5), "shielded_guard", 1, NodePath(), false))
```
with:
```gdscript
		EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0.0, y, 61.5 + JourneyLayout.OFF_S3), "shielded_guard", 1, NodePath(), false))
```
Replace block:
```gdscript
	_rock(_scenery, "GorgeWallWest", Vector3(-36.0, y + 12.0, 76.0), Vector3(26.0, 84.0, 28.0), 301, _m_rock(), 1.0, 0.2, 14)
	_rock(_scenery, "GorgeWallEast", Vector3(36.0, y + 20.0, 72.0), Vector3(26.0, 92.0, 34.0), 302, _m_rock(), 1.0, 0.2, 14)
```
with:
```gdscript
	_rock(_scenery, "GorgeWallWest", Vector3(-36.0, y + 12.0, 76.0 + JourneyLayout.OFF_S3), Vector3(26.0, 84.0, 28.0), 301, _m_rock(), 1.0, 0.2, 14)
	_rock(_scenery, "GorgeWallEast", Vector3(36.0, y + 20.0, 72.0 + JourneyLayout.OFF_S3), Vector3(26.0, 92.0, 34.0), 302, _m_rock(), 1.0, 0.2, 14)
```
**Postcondition:** `JourneyLayout.OFF_S3` appears exactly 5 times in the file (2 header + 1 trigger + 2 gorge walls). The G5-3 anchors use `JourneyLayout.OFF_S3` 2 more times, so the total count is **7**.

### G5-7 — Builder, Stage 04: 36 × 36 clock-tower chamber (region splice)
Save this block as `%TEMP%\g5\stage04.gd.txt`:
```gdscript
func _build_stage_04_mechanism() -> Node3D:
	## Clock-Tower Mechanism Chamber, 3x the old room: a 36 x 36 floor at Y 6 centred on
	## JourneyLayout.CHAMBER_CENTER, built in WORLD coordinates (2026-11-18). The puzzle (dais, weight, plate)
	## keeps its proven dimensions at the centre; the room, clockwork, tower and garrison grew around it.
	var root := Node3D.new()
	root.name = "Stage04_MechanismChamber"
	var g: Array[Node3D] = _zone("Zone04_Tower")
	var y: float = Y_GALLERY
	var cz: float = JourneyLayout.CHAMBER_CENTER.z
	var h: float = JourneyLayout.CHAMBER_HALF
	var wall_h: float = 24.0
	var span: float = h * 2.0 + 3.0

	_solid(root, "ChamberFloor", Vector3(0.0, y - 0.25, cz), Vector3(h * 2.0, 0.5, h * 2.0), _m_floor())
	_solid(root, "RaisedImpactDais", Vector3(-3.0, y + 0.675, cz - 1.0), Vector3(2.5, 1.35, 2.5), _m_marble())
	# Walls (visible, tall) with 4 m openings south & north.
	_solid(root, "Wall_West", Vector3(-h - 0.75, y + wall_h * 0.5, cz), Vector3(1.5, wall_h, h * 2.0 + 1.5), _m_wall())
	_solid(root, "Wall_East", Vector3(h + 0.75, y + wall_h * 0.5, cz), Vector3(1.5, wall_h, h * 2.0 + 1.5), _m_wall())
	var seg_w: float = h - 2.0
	for sx in [-1.0, 1.0]:
		# Segments butt exactly against the side walls' inner faces (x = +-h): no overlapping corners.
		_solid(root, "Wall_South_%d" % int(sx), Vector3(sx * (2.0 + seg_w * 0.5), y + wall_h * 0.5, cz - h - 0.6), Vector3(seg_w, wall_h, 1.2), _m_wall())
		_solid(root, "Wall_North_%d" % int(sx), Vector3(sx * (2.0 + seg_w * 0.5), y + wall_h * 0.5, cz + h + 0.6), Vector3(seg_w, wall_h, 1.2), _m_wall())
	var lintel := BoxMesh.new()
	lintel.size = Vector3(4.0, wall_h - 4.0, 1.2)
	_mesh(g[0], "LintelSouth", lintel, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + 4.0 + (wall_h - 4.0) * 0.5, cz - h - 0.6)))
	_mesh(g[0], "LintelNorth", lintel, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + 4.0 + (wall_h - 4.0) * 0.5, cz + h + 0.6)))
	# Ceiling with a 4 x 4 oculus at the top of the walls.
	var ceil_y: float = y + wall_h + 0.5
	var ceil_piece := BoxMesh.new()
	ceil_piece.size = Vector3(span, 1.0, h - 0.5)
	_mesh(g[0], "CeilingS", ceil_piece, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, ceil_y, cz - 2.0 - (h - 0.5) * 0.5)))
	_mesh(g[0], "CeilingN", ceil_piece, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, ceil_y, cz + 2.0 + (h - 0.5) * 0.5)))
	var ceil_side := BoxMesh.new()
	ceil_side.size = Vector3(h - 0.5, 1.0, 4.0)
	_mesh(g[0], "CeilingW", ceil_side, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(-2.0 - (h - 0.5) * 0.5, ceil_y, cz)))
	_mesh(g[0], "CeilingE", ceil_side, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(2.0 + (h - 0.5) * 0.5, ceil_y, cz)))
	# Tower exterior rising above: spire block + pyramid roof.
	var spire := BoxMesh.new()
	spire.size = Vector3(span, 14.0, span)
	_mesh(g[0], "TowerUpper", spire, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + wall_h + 8.0, cz)))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = span * 0.7
	roof.height = 24.0
	roof.radial_segments = 4
	roof.rings = 1
	_mesh(g[0], "TowerRoof", roof, _m_bronze(), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, y + wall_h + 27.0, cz)))

	var gate := _make_gate("Gate04_MechanismToArena", Vector3(0.0, y, cz + h), 3, "", false)
	_style_gate(gate)
	root.add_child(gate)
	root.add_child(_make_section_trigger("Trigger_Stage04_Mechanism", Vector3(0.0, y + 1.25, cz - h + 1.5), Vector3(4.5, 2.5, 1.5),
		EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0.0, y, cz - h + 1.5), "", 0, NodePath(), false))

	var puzzle := MechanismPuzzle.new()
	puzzle.name = "ChamberMechanismPuzzle"
	puzzle.position = Vector3(0.0, y, cz)
	puzzle.linked_gate_path = NodePath("../Gate04_MechanismToArena")
	puzzle.weight_node_path = NodePath("SuspendedWeight")
	puzzle.plate_node_path = NodePath("PressurePlate")
	var weight := Node3D.new()
	weight.name = "SuspendedWeight"
	weight.position = Vector3(0.0, 2.5, 0.0)
	weight.add_child(_make_mesh_box("WeightMesh", Vector3(1.2, 1.2, 1.2), Color(0.20, 0.72, 1.0, 0.85)))
	var chain := BoxMesh.new()
	chain.size = Vector3(0.08, 14.0, 0.08)
	for cx in [-0.45, 0.45]:
		_mesh(weight, "Chain", chain, _m_crystal(), Transform3D(Basis.IDENTITY, Vector3(cx, 7.6, 0)), false)
	var hurt := Hurtbox3D.new()
	hurt.name = "Hurtbox3D"
	hurt.owner_actor_path = NodePath("../..")
	hurt.is_enemy_hurtbox = false
	hurt.collision_layer = LAYER_INTERACTABLE | LAYER_HITBOX
	hurt.collision_mask = LAYER_HITBOX
	var hcol := CollisionShape3D.new()
	var hs := BoxShape3D.new()
	hs.size = Vector3(1.4, 1.4, 1.4)
	hcol.shape = hs
	hurt.add_child(hcol)
	weight.add_child(hurt)
	puzzle.add_child(weight)
	var plate := Node3D.new()
	plate.name = "PressurePlate"
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 0.95
	plate_mesh.bottom_radius = 1.05
	plate_mesh.height = 0.14
	plate_mesh.radial_segments = 24
	# Recessed plate: top sits 3 cm proud of the floor (was 14 cm, which feet clipped through).
	_mesh(plate, "PlateMesh", plate_mesh, _m_bronze(), Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0)), true, 0.0, false)
	puzzle.add_child(plate)
	root.add_child(puzzle)

	# Clockwork: bronze gears turning on both side walls. [side, height (old y-6 datum), z offset, radius,
	# turns per 40 s, inset]. Meshing pairs sit on different depth planes (0.4 m apart) and clear the pilasters.
	for spec in [[-1.0, 12.0, -0.7, 3.4, 1.0, 0.0], [-1.0, 15.5, 2.2, 2.2, -1.6, 0.4], [1.0, 11.0, 1.2, 3.0, -1.0, 0.0], [1.0, 15.0, -2.4, 2.0, 1.4, 0.4],
			[-1.0, 14.0, 10.5, 4.0, 0.7, 0.0], [-1.0, 18.5, 10.5, 2.6, -1.2, 0.4], [1.0, 13.0, -10.5, 4.0, -0.8, 0.0], [1.0, 18.0, -10.5, 2.8, 1.1, 0.4]]:
		var gear: ArrayMesh = ProcMesh.gear_mesh(float(spec[3]), 0.35, int(float(spec[3]) * 6.0), 0.35)
		var gpos := Vector3(float(spec[0]) * (h - 0.05 - float(spec[5])), y + float(spec[1]) - 6.0, cz + float(spec[2]))
		var gm := _mesh(g[0], "Gear", gear, _m_bronze(), Transform3D(Basis(Vector3.UP, PI * 0.5), gpos), true, 0.0, false)
		var tw := gm.create_tween().set_loops()
		tw.tween_property(gm, "rotation:x", TAU * signf(float(spec[4])), 40.0 / absf(float(spec[4]))).as_relative()
		_anim_tweens.append(tw)
	# Pilasters
	var pil := BoxMesh.new()
	pil.size = Vector3(0.4, wall_h - 1.0, 0.9)
	var pils: Array = []
	for sx in [-1.0, 1.0]:
		for dz in [-16.0, -5.5, 5.5, 16.0]:
			var pp := Vector3(sx * (h - 0.2), y + (wall_h - 1.0) * 0.5, cz + dz)
			pils.append(Transform3D(Basis.IDENTITY, pp))
			_prop_collider(root, "PilasterCollider", pp, _box_shape(Vector3(0.4, wall_h - 1.0, 0.9)))
	_multimesh(g[0], "Pilasters", pil, _m_marble(), pils)
	_brazier(g, Vector3(-(h - 1.4), y, cz + h - 1.0))
	_brazier(g, Vector3(h - 1.4, y, cz + h - 1.0))
	_brazier(g, Vector3(-(h - 1.4), y, cz - h + 1.4))
	_crystal_cluster(g[2], Vector3(h - 1.4, y, cz - h + 1.4), 1.0, 41, true)
	g[1].add_child(_make_ambient_particles(Vector3(0, y + 6, cz), Vector3(h - 0.5, 6, h - 0.5), false))
	g[2].add_child(_make_ambient_particles(Vector3(0, y + 6, cz), Vector3(h - 0.5, 6, h - 0.5), true))
	# Tower garrison (MECHANISM section): skeletons and a brute hold the floor, a hexcaster and a stalker work
	# the flanks, and a phantom harries the player in the Mirror while they line up the landing slam.
	var rg: Node3D = _roamer_group(root)
	var door := Vector3(0, y, cz - h)
	_add_roamer(rg, "skeleton", "TowerSkeleton_A", Vector3(10.0, y, cz + 10.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_B", Vector3(-12.0, y, cz + 9.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "phantom", "TowerPhantom", Vector3(11.0, y, cz - 6.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_C", Vector3(-10.0, y, cz - 10.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_D", Vector3(6.0, y, cz + 14.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "brute", "TowerBrute", Vector3(0.0, y, cz + 12.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "hexcaster", "TowerHexcaster", Vector3(-14.0, y, cz + 2.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "stalker", "TowerStalker", Vector3(14.0, y, cz + 3.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	return root
```
Run:
```powershell
. "$env:TEMP\g5\Set-Region.ps1"; Set-Region -File scripts/environment/grand_journey_builder.gd -StartRx '^func _build_stage_04_mechanism\(\) -> Node3D:$' -EndRx '^# Stage 05 .*Mirror Colosseum' -Keep 1 -BlankAfter 2 -MinLines 110 -MaxLines 125 -MustContain 'ChamberMechanismPuzzle' -NewTextFile "$env:TEMP\g5\stage04.gd.txt"
```
**Postcondition:** the file contains `TowerStalker` and `var wall_h: float = 24.0`.

### G5-8 — Builder, Stage 05: shift by `OFF_S5`, processional replaced by bridge R5
Replace block:
```gdscript
	var g: Array[Node3D] = _zone("Zone05_Colosseum")
```
with:
```gdscript
	var g: Array[Node3D] = _zone("Zone05_Colosseum")
	# Story-coordinate stage: the stage root and its decor zone are shifted onto the stretched layout.
	root.position.z = JourneyLayout.OFF_S5
	(g[0].get_parent() as Node3D).position.z = JourneyLayout.OFF_S5
```
Replace block:
```gdscript
	# --- Processional: corridor Z 100..102, stair Z 102..116 (Y 6 -> 10), esplanade Z 116..120 ---
	_solid(root, "Corridor04_Floor", Vector3(0.0, y0 - 0.25, 101.0), Vector3(4.0, 0.5, 2.0), _m_floor())
	_parapet(root, "Corridor04_W", Vector3(-2.2, y0, 100.6), Vector3(-2.2, y0, 102.0), _m_wall())
	_parapet(root, "Corridor04_E", Vector3(2.2, y0, 100.6), Vector3(2.2, y0, 102.0), _m_wall())
	var p_run: float = 14.0 / 22.0
	_ramp(root, "Processional_Ramp", Vector3(0, y0, 102.0 - p_run * 0.5), Vector3(0, y, 116.0 - p_run * 0.5), 12.0, null, false)
	_solid(root, "Processional_TopStep", Vector3(0, y - 0.25, 116.0 - p_run * 0.5), Vector3(12.0, 0.5, p_run), null, LAYER_WORLD_SHARED, Vector3.ZERO, false)
	_mesh(g[0], "Processional_Steps", ProcMesh.steps_mesh(12.0, y - y0, 14.0, 22), _m_floor(), Transform3D(Basis.IDENTITY, Vector3(0, y0, 102.0)))
	_solid(root, "Processional_Esplanade", Vector3(0.0, y - 0.25, 118.0), Vector3(18.0, 0.5, 4.0), _m_floor())
	_parapet(root, "Rail_Proc_W", Vector3(-6.2, y0, 101.8), Vector3(-6.2, y, 116.0), _m_wall())
	_parapet(root, "Rail_Proc_E", Vector3(6.2, y0, 101.8), Vector3(6.2, y, 116.0), _m_wall())
	_parapet(root, "Rail_Esp_W", Vector3(-9.0, y, 116.0), Vector3(-9.0, y, 120.0), _m_wall())
	_parapet(root, "Rail_Esp_E", Vector3(9.0, y, 116.0), Vector3(9.0, y, 120.0), _m_wall())
	_parapet(root, "Rail_Esp_SW", Vector3(-9.0, y, 116.0), Vector3(-6.2, y, 116.0), _m_wall())
	_parapet(root, "Rail_Esp_SE", Vector3(9.0, y, 116.0), Vector3(6.2, y, 116.0), _m_wall())
	# Colossal statues on stepped plinths flanking the stair, facing the path.
	for sx in [-1.0, 1.0]:
		for z in [105.5, 112.5]:
			var top: float = y0 + (z - 102.0) / 14.0 * (y - y0) + 2.0
			_solid(root, "StatuePlinth", Vector3(sx * 8.6, top - 7.0, z), Vector3(3.2, 14.0, 3.2), _m_marble())
			_sword_monument(g[0], Vector3(sx * 8.6, top, z), 90.0, 13.0)
```
with:
```gdscript
	# --- Esplanade Z 116..120 (story). The Processional is now the winding bridge R5 (_build_routes), which
	# arrives at the esplanade's south edge; its join rails close that edge out to x +-9.
	_solid(root, "Processional_Esplanade", Vector3(0.0, y - 0.25, 118.0), Vector3(18.0, 0.5, 4.0), _m_floor())
	_parapet(root, "Rail_Esp_W", Vector3(-9.0, y, 116.0), Vector3(-9.0, y, 120.0), _m_wall())
	_parapet(root, "Rail_Esp_E", Vector3(9.0, y, 116.0), Vector3(9.0, y, 120.0), _m_wall())
```
**Delete this line** (the stair phantom now lives on an R5 bastion):
```gdscript
	_add_roamer(rg, "phantom", "StairPhantom", Vector3(3.0, 8.3, 110.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 102))
```
Replace block:
```gdscript
		EncounterDirector.Section.EXECUTION_ARENA, Vector3(0.0, y, c.z - 11.5), "the_warden", 1, NodePath("../Gate04b_ArenaSouthSeal"), false))
```
with:
```gdscript
		EncounterDirector.Section.EXECUTION_ARENA, Vector3(0.0, y, c.z - 11.5 + JourneyLayout.OFF_S5), "the_warden", 1, NodePath("../Gate04b_ArenaSouthSeal"), false))
```
Replace block:
```gdscript
		EncounterDirector.Section.COMPLETE, Vector3(0.0, y, sz0 + 3.0), "", 0, NodePath(), true))
```
with:
```gdscript
		EncounterDirector.Section.COMPLETE, Vector3(0.0, y, sz0 + 3.0 + JourneyLayout.OFF_S5), "", 0, NodePath(), true))
```
**Postcondition:**
- The file has no `Processional_Ramp`, no `StairPhantom` and no `Rail_Esp_SW`.
- `EsplanadeHexcaster` (from guide 04) is still present.
- `OFF_S5` appears in Stage 05 four times: 2 header + 2 triggers.

### G5-9 — Builder: world scenery and occluders in world coordinates
Replace block:
```gdscript
	var massifs: Array = [
		# [center_top, size, seed]
		[Vector3(0, -0.6, -56), Vector3(17, 70, 15), 1],
		[Vector3(-3.5, -0.6, -44), Vector3(9, 60, 15), 2],
		[Vector3(-7, -0.6, -33), Vector3(13, 66, 11), 3],
		[Vector3(-3.5, -0.6, -22), Vector3(9, 60, 15), 4],
		# Stage 01 is split around the stepping-stone gap (Z -0.5..2.5) so the chasm stays a real drop.
		[Vector3(0, -0.6, -10.5), Vector3(26, 74, 16), 5],
		[Vector3(0, -0.6, 5.6), Vector3(26, 74, 3.0), 13],
		[Vector3(0, -0.6, 15), Vector3(16, 70, 16), 6],
		[Vector3(0, 3.4, 35), Vector3(28, 80, 26), 14],
		[Vector3(0, 3.4, 52), Vector3(24, 80, 18), 7],
		[Vector3(0, 5.4, 61), Vector3(14, 70, 6), 8],
		[Vector3(0, 5.4, 92), Vector3(22, 84, 26), 9],
		[Vector3(0, 5.4, 112), Vector3(28, 84, 24), 10],
		[Vector3(0, 9.4, 157), Vector3(76, 96, 70), 11],
		[Vector3(0, 9.4, 194), Vector3(26, 90, 20), 12],
	]
```
with:
```gdscript
	var massifs: Array = [
		# [center_top, size, seed] in WORLD coordinates (JourneyLayout). The bridges span open air between them;
		# every bridge bastion stands on its own rock spur (_build_bastion).
		[Vector3(0, -0.6, -136), Vector3(17, 70, 15), 1],
		# Stage 01 is split around the stepping-stone gap (Z -0.5..2.5) so the chasm stays a real drop.
		[Vector3(0, -0.6, -10.5), Vector3(26, 74, 16), 5],
		[Vector3(0, -0.6, 5.6), Vector3(26, 74, 3.0), 13],
		[Vector3(0, 3.4, 86), Vector3(70, 80, 66), 14],
		[Vector3(0, 5.4, 165), Vector3(14, 70, 6), 8],
		[Vector3(0, 5.4, 210), Vector3(42, 84, 42), 9],
		[Vector3(0, 9.4, 278), Vector3(20, 84, 8), 10],
		[Vector3(0, 9.4, 317), Vector3(76, 96, 70), 11],
		[Vector3(0, 9.4, 354), Vector3(26, 90, 20), 12],
	]
```
Replace block:
```gdscript
		var pos := Vector3(sin(ang) * rng.randf_range(45.0, 90.0), rng.randf_range(18.0, 55.0), 120.0 + cos(ang) * rng.randf_range(50.0, 95.0))
```
with:
```gdscript
		var pos := Vector3(sin(ang) * rng.randf_range(45.0, 90.0), rng.randf_range(18.0, 55.0), 120.0 + JourneyLayout.OFF_S5 + cos(ang) * rng.randf_range(50.0, 95.0))
```
Replace block:
```gdscript
	var kz := _make_pit_kill_zone("PitKillZone_World", Vector3(0.0, -25.0, 70.0), Vector3(700.0, 19.0, 700.0))
```
with:
```gdscript
	var kz := _make_pit_kill_zone("PitKillZone_World", Vector3(0.0, -25.0, 113.0), Vector3(700.0, 19.0, 700.0))
```
**Occluders, region splice.** Save this block as `%TEMP%\g5\occluders.gd.txt`:
```gdscript
func _build_occluders() -> void:
	var occ := Node3D.new()
	occ.name = "Occluders"
	add_child(occ)
	# Gatehouse piers (facade x +-2.3..+-11, z 4.5..7.5, y 0..15).
	for sx in [-1.0, 1.0]:
		_occluder(occ, "GatehousePier", Vector3(sx * 6.65, 7.3, 6.0), Vector3(8.3, 14.2, 2.6))
	# Hall corner towers (world, JourneyLayout.HALL_CENTER).
	var hc: Vector3 = JourneyLayout.HALL_CENTER
	var hh: float = JourneyLayout.HALL_HALF
	for cx in [-(hh + 2.0), hh + 2.0]:
		for cz in [hc.z - hh - 2.0, hc.z + hh + 2.0]:
			_occluder(occ, "HallTower", Vector3(cx, Y_HALL + 6.0, cz), Vector3(3.6, 23.4, 3.6))
	# Clock tower: four walls + upper block (world, JourneyLayout.CHAMBER_CENTER).
	var ty: float = Y_GALLERY
	var cc: Vector3 = JourneyLayout.CHAMBER_CENTER
	var ch: float = JourneyLayout.CHAMBER_HALF
	_occluder(occ, "TowerWallW", Vector3(-ch - 0.75, ty + 12.0, cc.z), Vector3(1.2, 23.4, ch * 2.0 + 1.0))
	_occluder(occ, "TowerWallE", Vector3(ch + 0.75, ty + 12.0, cc.z), Vector3(1.2, 23.4, ch * 2.0 + 1.0))
	for sx in [-1.0, 1.0]:
		_occluder(occ, "TowerWallS", Vector3(sx * (2.0 + (ch - 2.0) * 0.5), ty + 12.0, cc.z - ch - 0.6), Vector3(ch - 2.4, 23.4, 0.9))
		_occluder(occ, "TowerWallN", Vector3(sx * (2.0 + (ch - 2.0) * 0.5), ty + 12.0, cc.z + ch + 0.6), Vector3(ch - 2.4, 23.4, 0.9))
	_occluder(occ, "TowerUpper", Vector3(0, ty + 32.0, cc.z), Vector3(ch * 2.0 + 2.4, 13.4, ch * 2.0 + 2.4))
	# Colosseum: portal-tower piers beside both tunnels, and the solid facade podium ring (as chords).
	var c: Vector3 = ARENA_CENTER + Vector3(0, 0, JourneyLayout.OFF_S5)
	for dz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			_occluder(occ, "PortalPier", c + Vector3(sx * 4.75, 12.5, dz * 22.4), Vector3(3.1, 24.6, 17.4))
	for i in range(24):
		var a: float = TAU * (float(i) + 0.5) / 24.0
		if absf(sin(a)) < 0.3:
			continue
		var dir := Vector3(sin(a), 0, cos(a))
		var chord: float = 2.0 * 31.2 * sin(PI / 24.0) * 0.92
		_occluder(occ, "FacadePodium", c + dir * 31.85 + Vector3(0, -6.0, 0), Vector3(chord, 19.0, 0.9), a)
	# Rock massif cores (well inside the noisy hulls), world coordinates.
	for mdef in [[Vector3(0, -12, -10.5), Vector3(16, 20, 10)], [Vector3(0, -8, 86), Vector3(44, 20, 40)], [Vector3(0, -6, 210), Vector3(26, 20, 26)],
			[Vector3(0, -6, 317), Vector3(50, 24, 46)], [Vector3(0, -6, 354), Vector3(16, 20, 12)]]:
		_occluder(occ, "MassifCore", mdef[0], mdef[1])
```
Run:
```powershell
. "$env:TEMP\g5\Set-Region.ps1"; Set-Region -File scripts/environment/grand_journey_builder.gd -StartRx '^func _build_occluders\(\) -> void:$' -EndRx '^# Atmosphere: sky' -Keep 1 -BlankAfter 2 -MinLines 34 -MaxLines 44 -MustContain 'MassifCore' -NewTextFile "$env:TEMP\g5\occluders.gd.txt"
```
**Postcondition:**
- The file has no `"CurtainWall"`.
- It contains `Vector3(0, 9.4, 354)` and `PitKillZone_World", Vector3(0.0, -25.0, 113.0)`.

### G5-10 — Terrain follows the world layout
File `scripts/environment/journey_terrain.gd`. Replace block:
```gdscript
const Z_MIN: float = -64.0
const Z_MAX: float = 203.0
const ROUTE_CENTER := Vector2(0.0, 70.0)
```
with:
```gdscript
## World z extent of the route (JourneyLayout, 2026-11-18 rework: terrace z -141 .. summit z 362).
const Z_MIN: float = -144.0
const Z_MAX: float = 370.0
const ROUTE_CENTER := Vector2(0.0, 113.0)
```
Replace block:
```gdscript
func _half_width(z: float) -> float:
	var hw: float = 9.5
	if z > -38.0 and z < -28.0:
		hw = 7.0   # west overlook
	if z > -16.0 and z < 9.0:
		hw = 13.0  # forecourt + gatehouse (piers to x +-11)
	if z > 20.0 and z < 49.0:
		hw = 15.0  # hall + corner towers
	if z > 86.0 and z < 102.0:
		hw = 10.0  # clock tower
	if z > 102.0 and z < 121.0:
		hw = 15.0  # processional stair + esplanade
	if z > 121.0 and z < 188.0:
		hw = 38.0  # colosseum facade + portal towers
	if z >= 188.0:
		hw = 13.0
	return hw
```
with:
```gdscript
func _half_width(z: float) -> float:
	# World z bands (JourneyLayout). The band centre follows the waypoints, so on the winding bridges it swings
	# with the deck; 14 m covers the deck plus a bastion and its drum.
	var hw: float = 9.5
	if z > -144.0 and z < -130.0:
		hw = 9.0   # start terrace
	if z >= -130.0 and z < -15.0:
		hw = 14.0  # R1 causeway bridges + bastions
	if z > -16.0 and z < 9.0:
		hw = 13.0  # forecourt + gatehouse (piers to x +-11)
	if z >= 9.0 and z < 54.0:
		hw = 14.0  # R2 bridges + bastions
	if z >= 54.0 and z < 120.0:
		hw = 36.0  # 60 m hall + corner towers
	if z >= 120.0 and z < 161.0:
		hw = 14.0  # R3 rampart bridges
	if z >= 189.0 and z < 230.0:
		hw = 22.0  # 36 m clock tower
	if z >= 230.0 and z < 276.0:
		hw = 14.0  # R5 processional bridges
	if z >= 276.0 and z < 281.0:
		hw = 15.0  # esplanade
	if z >= 281.0 and z < 348.0:
		hw = 38.0  # colosseum facade + portal towers
	if z >= 348.0:
		hw = 13.0
	return hw
```
Replace block:
```gdscript
		if p.z > 141.0 and p.z < 167.0:
```
with:
```gdscript
		if p.z > 301.0 and p.z < 327.0:
```
Replace block:
```gdscript
	# Dry gorge under the aqueduct (z ~74): arches stand in it; descends outward to the valley.
	var gorge: float = -38.0 - 0.14 * d + maxf(absf(z - 74.0 - 4.0 * sin(x * 0.03)) - 8.0, 0.0) * 1.35
```
with:
```gdscript
	# Dry gorge under the aqueduct (world z ~178): arches stand in it; descends outward to the valley.
	var gorge: float = -38.0 - 0.14 * d + maxf(absf(z - 178.0 - 4.0 * sin(x * 0.03)) - 8.0, 0.0) * 1.35
```
**Postcondition:** the file contains `const Z_MAX: float = 370.0` and `z - 178.0`.

### G5-11 — Ambient life follows the world layout
File `scripts/ambient/ambient_life_layout.gd`. All placements in this file are authored in story coordinates. The five helpers convert them, and drop spots that lay on the old connectors. Replace block:
```gdscript
func _habitat(parent: Node3D, n: String, pos: Vector3, species: int, count: int, radius: float, mode: int, home_scale: float) -> Node3D:
	var h: Node3D = HABITAT.new() as Node3D
```
with:
```gdscript
func _habitat(parent: Node3D, n: String, pos: Vector3, species: int, count: int, radius: float, mode: int, home_scale: float) -> Node3D:
	if JourneyLayout.is_dropped(pos.z):
		return null   # story spot replaced by a winding bridge (JourneyLayout)
	var h: Node3D = HABITAT.new() as Node3D
```
Replace block (one tab of indentation):
```gdscript
	h.global_position = pos
```
with:
```gdscript
	h.global_position = JourneyLayout.to_world(pos)
```

Replace block:
```gdscript
func _veg(parent: Node3D, n: String, pos: Vector3, kind: int, mix: Array, count: int, radius: float, spacing: float) -> Node3D:
	var v: Node3D = VEG_PATCH.new() as Node3D
```
with:
```gdscript
func _veg(parent: Node3D, n: String, pos: Vector3, kind: int, mix: Array, count: int, radius: float, spacing: float) -> Node3D:
	if JourneyLayout.is_dropped(pos.z):
		return null
	var v: Node3D = VEG_PATCH.new() as Node3D
```
Replace block:
```gdscript
	v.global_position = pos
```
with:
```gdscript
	v.global_position = JourneyLayout.to_world(pos)
```

Replace block:
```gdscript
func _flora(parent: Node3D, n: String, pos: Vector3, kind: int, count: int, radius: float, spacing: float) -> Node3D:
	var f: Node3D = FLORA_PATCH.new() as Node3D
```
with:
```gdscript
func _flora(parent: Node3D, n: String, pos: Vector3, kind: int, count: int, radius: float, spacing: float) -> Node3D:
	if JourneyLayout.is_dropped(pos.z):
		return null
	var f: Node3D = FLORA_PATCH.new() as Node3D
```
Replace block:
```gdscript
	f.global_position = pos
```
with:
```gdscript
	f.global_position = JourneyLayout.to_world(pos)
```

Replace block:
```gdscript
func _ivy(parent: Node3D, pos: Vector3, yaw: float, w: float, h: float, hanging: bool) -> Node3D:
	var iv: Node3D = IVY.new() as Node3D
```
with:
```gdscript
func _ivy(parent: Node3D, pos: Vector3, yaw: float, w: float, h: float, hanging: bool) -> Node3D:
	if JourneyLayout.is_dropped(pos.z):
		return null
	var iv: Node3D = IVY.new() as Node3D
```
Replace block:
```gdscript
	iv.global_position = pos
```
with:
```gdscript
	iv.global_position = JourneyLayout.to_world(pos)
```

Replace block:
```gdscript
func _marker(parent: Node3D, group: String, pos: Vector3) -> void:
	var m := Marker3D.new()
```
with:
```gdscript
func _marker(parent: Node3D, group: String, pos: Vector3) -> void:
	if JourneyLayout.is_dropped(pos.z):
		return
	var m := Marker3D.new()
```
Replace block:
```gdscript
	m.global_position = pos
```
with:
```gdscript
	m.global_position = JourneyLayout.to_world(pos)
```

**Postconditions:**
- `JourneyLayout.to_world(pos)` occurs exactly 5 times in this file.
- `body.global_position = pos` (cliff garden `_solid`) is unchanged; the garden is off (`build_garden = false`).

### G5-12 — Weather and audio read story z
File `scripts/environment/weather_director.gd`. Replace block:
```gdscript
	var target_name: String = forced_profile if forced_profile != "" else get_profile_for(probe.z)
```
with:
```gdscript
	var target_name: String = forced_profile if forced_profile != "" else get_profile_for(JourneyLayout.story_z(probe.z))
```
File `scripts/core/audio_manager.gd`. Replace block:
```gdscript
	if pc.global_position.z < -40.0:
```
with:
```gdscript
	if JourneyLayout.story_z(pc.global_position.z) < -40.0:
```
Replace block:
```gdscript
	var z: float = pc.global_position.z if pc != null else -60.0
```
with:
```gdscript
	var z: float = JourneyLayout.story_z(pc.global_position.z) if pc != null else -60.0
```
Replace block:
```gdscript
		var z: float = pc.global_position.z
		# Enclosed hall / tower interior band.
```
with:
```gdscript
		var z: float = JourneyLayout.story_z(pc.global_position.z)
		# Enclosed hall / tower interior band (story z).
```
**Postcondition:** `JourneyLayout.story_z` appears once in `weather_director.gd` and 3 times in `audio_manager.gd`.

### G5-13 — Objective tracker: story thresholds, world targets, the arrow follows the bastions
File `scripts/ui/objective_tracker.gd`. Replace block:
```gdscript
	var pz: float = player.global_position.z
```
with:
```gdscript
	# Thresholds below are story z (the old compact layout); targets convert with JourneyLayout.
	var pz: float = JourneyLayout.story_z(player.global_position.z)
```
Replace block:
```gdscript
			return {"title": "Follow the Pilgrim's Causeway to the gate", "hint": "Head north along the stone causeway.", "target": Vector3(0, 0, -9)}
```
with:
```gdscript
			return {"title": "Follow the Pilgrim's Causeway to the gate", "hint": "Cross the winding causeway past both bastions to the gate.", "target": JourneyLayout.guide_target(player.global_position, Vector3(0, 0, -9))}
```
Replace block:
```gdscript
			return {"title": "Climb the Sunlit Stair to the Hall of Echoes", "hint": "Go up the wide stair north of the gate.", "target": Vector3(0, 4, 26)}
```
with:
```gdscript
			return {"title": "Cross the Sunlit Bridges to the Hall of Echoes", "hint": "Through the gate and over the bridges, past both bastions, to the hall.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 4, 26)))}
```
Replace block:
```gdscript
		return {"title": "Climb the Windswept Rampart", "hint": "Through the opened gate and up the ramp to the gallery.", "target": Vector3(0, 6, 62)}
```
with:
```gdscript
		return {"title": "Cross the Windswept Rampart", "hint": "Through the opened gate and over the rampart bridges, past both bastions, to the gallery.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 6, 62)))}
```
Replace block:
```gdscript
			"target": sw3.global_position if sw3 != null else Vector3(0, 6, 79)}
```
with:
```gdscript
			"target": sw3.global_position if sw3 != null else JourneyLayout.to_world(Vector3(0, 6, 79))}
```
Replace block:
```gdscript
			return {"title": "Enter the Clock-Tower Mechanism Chamber", "hint": "North through the gallery gate.", "target": Vector3(0, 6, 90)}
```
with:
```gdscript
			return {"title": "Enter the Clock-Tower Mechanism Chamber", "hint": "North through the gallery gate.", "target": JourneyLayout.to_world(Vector3(0, 6, 90))}
```
Replace block:
```gdscript
			return {"title": "Climb the Processional Stair to the Colosseum", "hint": "The Warden waits at the top.", "target": Vector3(0, 10, 140.5)}
```
with:
```gdscript
			return {"title": "Cross the Processional to the Colosseum", "hint": "Over the bridges and past both bastions. The Warden waits at the top.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 10, 140.5)))}
```
Replace block:
```gdscript
	return {"title": "Walk into the light", "hint": "Leave through the north gate to the summit.", "target": Vector3(0, 10, 194)}
```
with:
```gdscript
	return {"title": "Walk into the light", "hint": "Leave through the north gate to the summit.", "target": JourneyLayout.to_world(Vector3(0, 10, 194))}
```
**Postcondition:** `JourneyLayout.` appears 12 times in the file: 1 `story_z`, 4 `guide_target`, 6 `to_world`, and 1 in the new comment line.

### G5-14 — Saves: layout version, old saves converted, all hall enemies restored
File `scripts/core/leaderboard_store.gd`.

The loader (`_load_savegame_from_disk`) reads only keys that exist in `get_default_save_data()`. So the version key must get a default. That default is `1`: a file without the key is an old-layout save. Replace block:
```gdscript
		"player_health": 100,
		"world_flags": {
```
with:
```gdscript
		"player_health": 100,
		"layout_version": 1,   # JourneyLayout.VERSION of the save; files without the key are the old layout
		"world_flags": {
```
Replace block:
```gdscript
	var snapshot: Dictionary = {
		"has_active_run": true,
	}
```
with:
```gdscript
	var snapshot: Dictionary = {
		"has_active_run": true,
		"layout_version": JourneyLayout.VERSION,
	}
```
Replace block:
```gdscript
	var saved_pos: Vector3 = _save_data.get("checkpoint_position", Vector3(0.0, 0.0, -3.0))
```
with:
```gdscript
	var saved_pos: Vector3 = _save_data.get("checkpoint_position", Vector3(0.0, 0.0, -3.0))
	# Saves written before the 2026-11-18 layout rework hold old (story) coordinates: carry them over.
	if int(_save_data.get("layout_version", 1)) < JourneyLayout.VERSION:
		saved_pos = JourneyLayout.to_world(saved_pos)
```
Replace block:
```gdscript
					for ename in ["SkeletonGuard_1", "SkeletonGuard_2", "PhantomTwin_1", "PhantomTwin_2"]:
						var en: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/Enemies/" + ename)
						if en != null:
```
with:
```gdscript
					var hall_enemies: Array = []
					var hall_group: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/Enemies")
					if hall_group != null:
						hall_enemies = hall_group.get_children()
					for en in hall_enemies:
						if en != null:
```
**Postcondition:** in this file:
- `JourneyLayout.VERSION` appears twice;
- `"layout_version"` appears 3 times;
- `"SkeletonGuard_1"` appears 0 times.

### G5-15 — New-run start position
File `scenes/main/main.tscn`. Replace the line **directly under** `[node name="Player" parent="." instance=ExtResource("7_player")]`:
```
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, -56)
```
with:
```
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, -136)
```
Edit only this one line (text edit, never with the editor open).

**Postcondition:** `git diff --stat scenes/main/main.tscn` shows `1 file changed, 1 insertion(+), 1 deletion(-)`.

### G5-16 — Existing tests use the moved terrace / causeway
File `tests/squad_ai_windowed_test.gd`. Replace block:
```gdscript
	_teleport_player(Vector3(0, 0, -59))
```
with:
```gdscript
	_teleport_player(Vector3(0, 0, -139))   # start terrace (moved 80 m south, JourneyLayout)
```
Replace block:
```gdscript
	# Walk the taunter well away from the enemy's home (leash 22 m) across the forecourt / causeway.
	taunter.global_position = Vector3(-3.5, 0, -40.0)
	_teleport_player(Vector3(-3.5, 0, -36.0))   # stay near him so his catch-up teleport never fires
	if taunter.current != null:
		taunter.current.args["spot"] = Vector3(-3.5, 0, -40.0)
		taunter.current.data["spot"] = Vector3(-3.5, 0, -40.0)
```
with:
```gdscript
	# Walk the taunter well away from the enemy's home (leash 22 m) out along the R1 causeway bridge (last leg,
	# 45 % of the way from the forecourt edge to bastion 2).
	var fixation_spot_r1 := Vector3(-15.3, 0, -30.3)
	taunter.global_position = fixation_spot_r1
	_teleport_player(Vector3(-11.9, 0, -26.9))   # stay near him so his catch-up teleport never fires
	if taunter.current != null:
		taunter.current.args["spot"] = fixation_spot_r1
		taunter.current.data["spot"] = fixation_spot_r1
```
File `tests/feel_and_movement_test.gd`. Replace block:
```gdscript
	_player.global_position = Vector3(0, 0, -58)
```
with:
```gdscript
	_player.global_position = Vector3(0, 0, -138)   # start terrace (moved 80 m south, JourneyLayout)
```
**Postcondition:** neither file contains `-59)`, `-58)` or `-40.0)`.

### G5-17 — New test `tests/layout_rework_test.gd`
Create (must not exist):
```gdscript
extends SceneTree
## Guide 05 checks (headless): JourneyLayout math; the four winding bridges (length vs the old connectors, bends,
## bastions, garrisons, walkable centre line, rails, bastion rings); the 3x hall and chamber and their garrisons;
## stage offsets; the moved start terrace.
var _results: Array[String] = []
var _main: Node = null

const OLD_LENGTH: Dictionary = {"R1_PilgrimCauseway": 40.0, "R2_SunlitBridges": 16.0, "R3_WindsweptRampart": 16.0, "R5_Processional": 16.0}
const FLOOR_MASK: int = 4 | 8 | 16   # World_Shared | World_Reality | World_Mirror
const WALL_MASK: int = 4 | 128       # World_Shared | Player_Blocker


func _initialize() -> void:
	SquadAIConfig.force_offline()
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()


func _check(n: String, ok: bool, d: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", n, d]
	_results.append(line)
	print("[layout] ", line)


func _dist_to_line_xz(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	if ab.length() < 0.001:
		return ap.length()
	return absf(ab.x * ap.y - ab.y * ap.x) / ab.length()


func _run() -> void:
	# --- Pure math ---
	_check("map_terrace", is_equal_approx(JourneyLayout.to_world_z(-56.0), -136.0))
	_check("map_hall_south", is_equal_approx(JourneyLayout.to_world_z(24.0), 56.0))
	var hw: Vector3 = JourneyLayout.to_world(Vector3(10, 4, 34))
	_check("map_hall_scaled", is_equal_approx(hw.x, 30.0) and is_equal_approx(hw.z, 86.0), str(hw))
	_check("map_gallery", is_equal_approx(JourneyLayout.to_world_z(72.0), 176.0))
	_check("map_arena", is_equal_approx(JourneyLayout.to_world_z(154.0), 314.0))
	var rt_ok: bool = true
	for z in [-60.0, -30.0, 0.0, 15.0, 30.0, 50.0, 70.0, 95.0, 110.0, 160.0]:
		if absf(JourneyLayout.story_z(JourneyLayout.to_world_z(z)) - z) > 0.001:
			rt_ok = false
	_check("map_round_trip", rt_ok)
	_check("map_dropped", JourneyLayout.is_dropped(-30.0) and JourneyLayout.is_dropped(15.0) and not JourneyLayout.is_dropped(-56.0) and not JourneyLayout.is_dropped(34.0))

	# --- Build the level like a real run ---
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	for _i in range(3):
		await physics_frame
	var lv: Node3D = _main.get_node("LevelRoot") as Node3D
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	var off: float = JourneyLayout.BRIDGE_WIDTH * 0.5 + 0.2

	# --- Bridges ---
	for r in JourneyLayout.ROUTES:
		var rname: String = String((r as Array)[0])
		var nodes: Array = (r as Array)[1]
		var rr: Node3D = lv.get_node_or_null("Journey_Routes/" + rname) as Node3D
		_check("route_exists_" + rname, rr != null)
		if rr == null:
			continue
		var p_first: Vector3 = (nodes[0] as Array)[0]
		var p_last: Vector3 = (nodes[nodes.size() - 1] as Array)[0]
		var poly: float = 0.0
		var max_dev: float = 0.0
		var bastions: int = 0
		for i in range(nodes.size()):
			var p: Vector3 = (nodes[i] as Array)[0]
			if i > 0:
				poly += p.distance_to((nodes[i - 1] as Array)[0])
			max_dev = maxf(max_dev, _dist_to_line_xz(p, p_first, p_last))
			if float((nodes[i] as Array)[1]) > 0.0:
				bastions += 1
		var old_len: float = float(OLD_LENGTH[rname])
		_check("route_length_" + rname, poly >= 4.0 * old_len, "%.0f m vs old %.0f m (x%.1f)" % [poly, old_len, poly / old_len])
		_check("route_not_straight_" + rname, max_dev >= 10.0, "bastions %.1f m off the straight line" % max_dev)
		_check("route_bastions_" + rname, bastions >= 2, "%d" % bastions)
		var rg: Node = rr.get_node_or_null("Roamers")
		var n_en: int = rg.get_child_count() if rg != null else 0
		_check("route_enemies_" + rname, n_en >= 2 * bastions, "%d enemies" % n_en)
		# Walkable: floor under the centre line every <= 1.5 m, plus 1 m into the floors at both ends.
		var probes: Array[Vector3] = []
		for i in range(nodes.size() - 1):
			var a: Vector3 = (nodes[i] as Array)[0]
			var b: Vector3 = (nodes[i + 1] as Array)[0]
			var steps: int = int(a.distance_to(b) / 1.5) + 1
			for k in range(steps + 1):
				probes.append(a.lerp(b, float(k) / float(steps)))
		var p_second: Vector3 = (nodes[1] as Array)[0]
		var p_before_last: Vector3 = (nodes[nodes.size() - 2] as Array)[0]
		probes.append(p_first - Vector3(p_second.x - p_first.x, 0, p_second.z - p_first.z).normalized())
		probes.append(p_last + Vector3(p_last.x - p_before_last.x, 0, p_last.z - p_before_last.z).normalized())
		var holes: int = 0
		for p in probes:
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.2, 0), p + Vector3(0, -1.2, 0), FLOOR_MASK))
			if hit.is_empty():
				holes += 1
				print("[layout]   no floor at ", p)
		_check("route_walkable_" + rname, holes == 0, "%d of %d centre-line probes without floor" % [holes, probes.size()])
		# Railed: from each leg's midpoint a sideways ray must meet a rail within 4 m on both sides.
		var unrailed: int = 0
		for i in range(nodes.size() - 1):
			var a2: Vector3 = (nodes[i] as Array)[0]
			var b2: Vector3 = (nodes[i + 1] as Array)[0]
			var mid: Vector3 = a2.lerp(b2, 0.5) + Vector3(0, 1.0, 0)
			var u: Vector3 = Vector3(b2.x - a2.x, 0, b2.z - a2.z).normalized()
			var nrm := Vector3(u.z, 0, -u.x)
			for s in [-1.0, 1.0]:
				var hit2: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(mid, mid + nrm * s * 6.0, WALL_MASK))
				if hit2.is_empty() or (hit2["position"] as Vector3).distance_to(mid) > off + 0.8:
					unrailed += 1
		_check("route_railed_" + rname, unrailed == 0, "%d leg sides without a rail" % unrailed)
		# Bastion rings: closed except where the legs arrive.
		for i in range(1, nodes.size() - 1):
			var nd: Array = nodes[i]
			if float(nd[1]) <= 0.0:
				continue
			var c: Vector3 = nd[0]
			var rr2: float = float(nd[1]) - 0.2
			var beta: float = asin(off / rr2)
			var opens: Array[float] = []
			for j in [i - 1, i + 1]:
				var q: Vector3 = (nodes[j] as Array)[0]
				opens.append(atan2(q.x - c.x, q.z - c.z))
			var gaps: int = 0
			for k in range(24):
				var ang: float = TAU * float(k) / 24.0
				var near_open: bool = false
				for o in opens:
					if absf(wrapf(ang - o, -PI, PI)) < beta + 0.12:
						near_open = true
				if near_open:
					continue
				var from: Vector3 = c + Vector3(0, 1.0, 0)
				var hit3: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(sin(ang), 0, cos(ang)) * (rr2 + 1.0), WALL_MASK))
				if hit3.is_empty():
					gaps += 1
			_check("bastion_ring_%s_%d" % [rname, i], gaps == 0, "%d open directions" % gaps)

	# --- 3x hall and chamber ---
	var s2: Node3D = lv.get_node("Stage02_HallOfEchoes") as Node3D
	var hsize: Vector3 = (((s2.get_node("HallFloor") as Node3D).get_child(0) as CollisionShape3D).shape as BoxShape3D).size
	_check("hall_3x", hsize.x >= 59.0 and hsize.z >= 59.0, str(hsize))
	var hall_en: Node = s2.get_node("Enemies")
	_check("hall_more_enemies", hall_en.get_child_count() >= 8, "%d encounter enemies (was 4)" % hall_en.get_child_count())
	_check("hall_encounter_count_matches", int(s2.get_node("Trigger_Stage02_Hall").get("encounter_enemy_count")) == hall_en.get_child_count())
	_check("hall_roamers", s2.get_node_or_null("Roamers") != null and s2.get_node("Roamers").get_child_count() >= 3)
	var s4: Node3D = lv.get_node("Stage04_MechanismChamber") as Node3D
	var csize: Vector3 = (((s4.get_node("ChamberFloor") as Node3D).get_child(0) as CollisionShape3D).shape as BoxShape3D).size
	_check("chamber_3x", csize.x >= 35.9 and csize.z >= 35.9, str(csize))
	var tr: Node = s4.get_node_or_null("Roamers")
	_check("chamber_more_enemies", tr != null and tr.get_child_count() >= 7, "%d (was 3)" % (tr.get_child_count() if tr != null else 0))
	var puz: Node3D = s4.get_node("ChamberMechanismPuzzle") as Node3D
	_check("puzzle_centred", puz.global_position.distance_to(JourneyLayout.CHAMBER_CENTER) < 0.01)

	# --- Story stages shifted, checkpoints in world space, spawn on the moved terrace ---
	_check("gallery_offset", is_equal_approx((lv.get_node("Stage03_CollapsedGallery") as Node3D).position.z, JourneyLayout.OFF_S3))
	_check("arena_offset", is_equal_approx((lv.get_node("Stage05_ExecutionArena") as Node3D).position.z, JourneyLayout.OFF_S5))
	var gt: Node = lv.get_node("Stage03_CollapsedGallery/Trigger_Stage03_Gallery")
	_check("gallery_checkpoint_world", absf((gt.get("checkpoint_spawn_position") as Vector3).z - (61.5 + JourneyLayout.OFF_S3)) < 0.01)
	var pl: Node3D = _main.get_node("Player") as Node3D
	_check("spawn_on_terrace", absf(pl.global_position.z + 136.0) < 2.0, str(pl.global_position))

	var fails: int = _results.filter(func(r2: String) -> bool: return r2.begins_with("FAIL")).size()
	print("[layout] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
```
**Postcondition:** the file exists.

### G5-18 — MEMORY
1. In `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md`, **insert before** the line that starts with `## 6. MAP ATLAS FOR AGENTS`:
```markdown
## 2.y LAYOUT REWORK 2026-11-18 — world coordinates (supersedes positions past the start terrace in §2 and §6)
Single source of truth: `scripts/environment/journey_layout.gd` (`JourneyLayout`). The builders still contain
story-coordinate code (the old compact layout); `JourneyLayout.to_world()` / `story_z()` convert.

| Piece | World placement |
|---|---|
| Start terrace (player spawn, `main.tscn` Player z −136) | 12 × 10 at (0, 0, −136); story z < −50.5 shifted by `OFF_S1_TERRACE` −80 |
| R1 Pilgrim's Causeway bridge (ENTRY) | (0,0,−131) → bastion (34,0,−97) → bastion (−34,0,−49) → forecourt (0,0,−15); 179 m |
| Forecourt + gate + stepping stones | unchanged (z −15 … 8) |
| R2 Sunlit bridges (ENTRY) | (0,0,8) → (16,1.1,24) → (−16,2.9,40) → hall gate (0,4,56); 81 m |
| Hall of Echoes | 60 × 60 floor, centre (0, 4, 86); gates z 56 / 116; 9 encounter enemies + 3 roamers; 8 cover columns r 17 |
| R3 Windswept Rampart bridges (HALL) | (0,4,116) → (16,4.55,132) → (−16,5.45,148) → gallery (0,6,164); 81 m |
| Collapsed Gallery (Stage 03) | story code, root offset `OFF_S3` +104 (deck z 162 … 192) |
| Clock-tower chamber | 36 × 36 floor, centre (0, 6, 210), walls 24 m; puzzle unchanged at the centre; 8 roamers |
| R5 Processional bridges (MECHANISM) | (0,6,228) → (16,7.1,244) → (−16,8.9,260) → esplanade (0,10,276); 81 m |
| Esplanade, Colosseum, Summit (Stage 05) | story code, root offset `OFF_S5` +160 (arena centre z 314, summit z 346 … 362) |

- Bridges: deck 6 m wide, parapets both sides, piers under spans > 16 m.
- Bastions: r 8 m disc on a drum and rock spur, ring parapet with openings only where legs arrive, merlons, 2 braziers, 3 roamers each.
- Set dressing (Dress_* zones) and AmbientLife: remapped by `JourneyLayout`; spots on the old connectors are dropped.
- Weather zones, music bands, footsteps and objective thresholds: read `story_z()`.
- Saves: carry `layout_version` 2; older checkpoints are converted with `to_world()`.
```
2. Append to the end of `MEMORY/02_CORE_SYSTEMS_AND_ARCHITECTURE.md`:
```markdown

### JourneyLayout (2026-11-18)
`JourneyLayout` (`scripts/environment/journey_layout.gd`, static) owns the macro layout of The Ascent:
- `ROUTES`: winding bridges in world coordinates;
- stage offsets `OFF_S1_TERRACE` / `OFF_S3` / `OFF_S5`;
- `HALL_CENTER` / `CHAMBER_CENTER`;
- `to_world()`, `to_world_z()` and `story_z()` for story-coordinate code;
- `guide_target()` for the objective arrow.

Never hard-code world z thresholds; compare `story_z()` values instead.
```
3. Append to the end of `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`:
```markdown
- **2026-11-18 (Long bridges, bastions, 3× halls)**: connectors are now winding bridges with 2 bastions (3 enemies each), 4.5–5.1× longer (R1 179 m, R2/R3/R5 81 m); Hall of Echoes 60 × 60 (9 encounter + 3 roamers), clock-tower chamber 36 × 36 (8 roamers); terrace moved to z −136; gallery +104, arena/summit +160; `JourneyLayout` converts story ↔ world for weather/audio/objectives/flora/dressing/terrain/saves; test `tests/layout_rework_test.gd`.
```

## E. Verification and failure handling

Before V2–V5, back up the save (G5-0 step 2). After each run that starts a game, restore it:
```powershell
Copy-Item "$env:TEMP\parallax_save_bk_g5\savegame.cfg" "$env:APPDATA\Godot\app_userdata\PARALLAX\savegame.cfg" -Force -ErrorAction SilentlyContinue
```

**G5-V1 — import + parse every touched script** (proves the code compiles; covers L7).
```powershell
$g = "E:\game making workshop\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $g --headless --path . --import --quit
foreach ($f in @("scripts/environment/journey_layout.gd","scripts/environment/grand_journey_builder.gd","scripts/environment/journey_terrain.gd","scripts/ambient/ambient_life_layout.gd","scripts/environment/weather_director.gd","scripts/core/audio_manager.gd","scripts/ui/objective_tracker.gd","scripts/core/leaderboard_store.gd","tests/layout_rework_test.gd")) { $o = & $g --headless --path . --check-only -s "res://$f" 2>&1 | Out-String; if ($o -match "SCRIPT ERROR|Parse Error") { "FAIL $f"; $o } else { "ok $f" } }
```
**Pass:** every line is `ok`. **On FAIL:** report the file and the first error line verbatim. Do not improvise fixes beyond an obvious typo you introduced while copying (compare against the guide text).

**G5-V2 — boot smoke.**
```powershell
$g = "E:\game making workshop\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $g --headless --path . -s res://tests/boot_smoke.gd 2>&1 | Select-String "boot_smoke|SCRIPT ERROR"
```
- **Pass:** `[boot_smoke] OK`.
- **Enemy count:** with guides 02–04 applied, `enemies=` should be **56** (25 before this guide: +24 bastion garrisons, +5 hall encounter, +3 hall roamers, +5 chamber, −6 removed connector roamers).
- If boot_smoke is OK but the count differs, report the number; it is not a failure by itself.

**G5-V3 — layout test** (L1–L6, L8):
```powershell
$g = "E:\game making workshop\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $g --headless --path . -s res://tests/layout_rework_test.gd 2>&1 | Select-String "\[layout\]|SCRIPT ERROR"
```
- **Pass:** `[layout] SUMMARY 54 checks, 0 failed`. The 54 checks are 7 math, 4 bridges × 7, 8 bastion rings, 7 hall/chamber and 4 offset/spawn checks.
- Expected route details: R1 `179 m vs old 40 m (x4.5)`; R2/R3/R5 `81 m vs old 16 m (x5.1)`.
- **If `route_walkable_*` fails:** the test prints each `no floor at (x, y, z)`. Report those lines and do not move geometry yourself.
- **If `route_railed_*` / `bastion_ring_*` fails:** report it. These are fall-risk holes.

**G5-V4 — regressions** (L9). Run each, restoring the save afterwards:
```powershell
$g = "E:\game making workshop\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $g --headless --path . -s res://tests/restart_flow_test.gd 2>&1 | Select-String "restart_test"
& $g --path . -s res://tests/squad_ai_windowed_test.gd -- --shots="$env:TEMP\pshots" 2>&1 | Select-String "FAIL|SUMMARY|SCRIPT ERROR"
& $g --path . -s res://tests/feel_and_movement_test.gd -- --shots="$env:TEMP\pshots" 2>&1 | Select-String "FAIL|SUMMARY|SCRIPT ERROR"
Copy-Item "$env:TEMP\parallax_save_bk_g5\savegame.cfg" "$env:APPDATA\Godot\app_userdata\PARALLAX\savegame.cfg" -Force -ErrorAction SilentlyContinue
```
**Pass:**
- restart `=> PASS`;
- windowed `0 failed` (53 checks unless earlier guides changed the count);
- feel `0 failed` (13 checks). The camera-sightline check was already borderline before this guide; if it alone fails, report it as pre-existing.

**Known risk:** `taunted_enemy_chases_past_leash`. The taunted enemy walks from the forecourt onto the R1 bridge. If it snags on the forecourt's join rail, the check fails with a distance under 22 m. Report the printed distances and keep the test change; adjusting it needs approval.

**G5-V5 — manual walk** (L6/L7, needs the user or a windowed session). Run the game (F5 with the editor, or `& $g --path .`), press Start, then:
1. On the terrace the objective arrow points at R1 bastion 1, then bastion 2, then the gate.
2. Walk every bridge: no invisible walls on the deck, no gaps at bastion rings or where bridges meet floors, slopes walkable without jumping, enemies on every bastion.
3. The hall is visibly 3× bigger with columns; clearing all 9 encounter enemies opens the north gate.
4. The chamber is 3× bigger; the dais + weight + plate puzzle still works.
5. Weather changes at the hall exit (storm) and at the chamber (tempest) as before.
6. Ivy/grass hug the new hall walls and nothing floats in mid-air where the old stair/rampart were.

**Report:**
- what was seen, and any spot with floating props or holes (give the player position from the debug overlay, or describe it);
- **frame rate** on the terrace and in the hall. The level now has about 56 enemies and 16 more brazier lights. Enemies only wake in their section and lights fade beyond 45–60 m, but a drop over ~20 % compared with before this guide is worth reporting.

**Rollback** (this guide's changes only; earlier guides stay):
```powershell
git checkout -- scripts/environment/grand_journey_builder.gd scripts/environment/journey_terrain.gd scripts/ambient/ambient_life_layout.gd scripts/environment/weather_director.gd scripts/core/audio_manager.gd scripts/ui/objective_tracker.gd scripts/core/leaderboard_store.gd scenes/main/main.tscn tests/squad_ai_windowed_test.gd tests/feel_and_movement_test.gd
Remove-Item scripts/environment/journey_layout.gd, tests/layout_rework_test.gd -ErrorAction SilentlyContinue
```
**Warning:** `git checkout` also reverts guide 01–04 edits in those files if they are uncommitted. **If earlier guides are applied but not committed, do not run the rollback.** Report instead, and ask the user.

## F. Completion report contract
Report:
- step IDs applied (G5-0 … G5-18) and any skipped, with the reason;
- changed and created files;
- results of V1–V4 (the `ok` lines, boot `enemies=` count, `[layout] SUMMARY` line plus any FAIL lines, restart/windowed/feel summaries);
- the V5 observations, or "V5 not run";
- blockers (step, path, mismatch text).

The task is complete only when V1–V4 pass, or every failure is reported with its output.

**Author's validation (separate from execution):**
- **Read against source.** Every replace-block original and every splice anchor was copied from the source at HEAD `2f37a1b` and from the guide 04 text, and the region sizes were counted from those reads:
  - anchors 44 lines after guide 04;
  - prologue 45;
  - Stage 02 197;
  - Stage 04 117;
  - occluders 39.
- **Geometry by hand.**
  - Every bastion's two leg directions are ≥ 99° apart, so the ring openings (±24.2°) never overlap.
  - Every floor-edge join stays inside its edge's width or is closed by join rails.
  - Bridge slopes are ≤ 9 %.
  - Bastion discs clear the gatehouse, hall towers, chamber tower and each other.
- **Actually run by the author:**
  - **Replace blocks:** a script matched all 49 replace/delete originals in this guide against the current source; each matched exactly once.
  - **Splice anchors (dry run):** all five matched exactly once. Regions were 41 / 45 / 197 / 117 / 39 lines before guide 04.
  - **`journey_layout.gd` (G5-1):** parsed with Godot 4.7.2 `--check-only` in a scratch project, then exercised.
    - `to_world_z`: −56 → −136, 24 → 56, 72 → 176, 154 → 314.
    - `to_world(10,4,34)` → (30, 4, 86); `story_z` round trip exact.
    - `guide_target` returns the next bridge node.
- **Not run:** the builder, terrain, ambient, UI, save and test code in G5-2…G5-17 has not been compiled or executed by the author. Correctness is established only by section E.
