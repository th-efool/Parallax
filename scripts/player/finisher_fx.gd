extends RefCounted
## VFX + audio for the critical-hit window and the five finishers
## (Rend / Sunder / Phantom Step / Mirror Break / Execution).
## Everything is spawned under GoreFX's host and frees itself; no per-frame cost when idle.

const GoreFXScript := preload("res://scripts/core/gore_fx.gd")
const GameFeelScript := preload("res://scripts/core/game_feel.gd")

const GOLD := Color(1.0, 0.82, 0.38)
const REND_COL := Color(1.0, 0.72, 0.30)
const SUNDER_COL := Color(1.0, 0.38, 0.16)
const PHANTOM_COL := Color(0.35, 0.85, 1.0)
const MIRROR_COL := Color(0.55, 0.95, 1.0)
const AMBER := Color(1.0, 0.7, 0.3)
const EXEC_COL := Color(0.95, 0.15, 0.2)


static func _add_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat


static func _play(cue: String, db: float = 0.0) -> void:
	if AudioManager.instance != null:
		AudioManager.instance.play_sfx(cue, db)


## Critical hit landed: golden starburst + ring on the target, glint sound.
static func critical_flash(pc: Node3D, target: Node3D) -> void:
	var at: Vector3 = (target.global_position if is_instance_valid(target) else pc.global_position) + Vector3.UP * 1.1
	GoreFXScript.sparks(pc, at, Vector3.UP, GOLD, 40)
	GoreFXScript.flash_light(pc, at, GOLD, 9.0, 0.5, 6.0)
	GoreFXScript.shockwave_ring(pc, at - Vector3.UP * 1.0, 1.8, Color(GOLD.r, GOLD.g, GOLD.b, 0.9), 0.5, 0.08)
	_starburst(pc, at, GOLD, 1.6, 0.45)
	GameFeelScript.play_sound(pc, "chime", at, 2.0, 1.25)
	_play("ui_confirm", -2.0)


## Four crossing light blades that flare and fade (crit "glint").
static func _starburst(ctx: Node3D, at: Vector3, color: Color, size: float, dur: float) -> void:
	var host: Node = GoreFXScript.host_for(ctx)
	if host == null:
		return
	var root := Node3D.new()
	host.add_child(root)
	root.global_position = at
	var mat := _add_mat(color)
	for i in 4:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(size * (1.0 if i % 2 == 0 else 0.6), 0.06)
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation = Vector3(0.0, 0.0, PI * 0.25 * float(i))
		root.add_child(mi)
	# Face the camera once (cheap billboard).
	var cam: Camera3D = ctx.get_viewport().get_camera_3d() if ctx.get_viewport() != null else null
	if cam != null:
		root.look_at(cam.global_position, Vector3.UP)
	root.scale = Vector3(0.2, 0.2, 0.2)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE * 1.4, dur * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(root, "rotation:z", root.rotation.z + 0.6, dur)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur * 0.65)
	tw.tween_callback(root.queue_free)


## Rend: each tick draws a flat crescent of light across the player's front at a new angle.
static func rend_slash(pc: Node3D, tick: int) -> void:
	var host: Node = GoreFXScript.host_for(pc)
	if host == null:
		return
	var fwd: Vector3 = pc.call("get_facing_direction") if pc.has_method("get_facing_direction") else -pc.global_transform.basis.z
	var center: Vector3 = pc.global_position + Vector3.UP * 1.0 + fwd * 1.2
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	mi.mesh = torus
	var col: Color = REND_COL.lerp(Color(1, 1, 1), 0.15 * float(tick % 2))
	var mat := _add_mat(Color(col.r, col.g, col.b, 0.95))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	mi.global_position = center
	mi.look_at(center + fwd, Vector3.UP)
	var rolls: Array[float] = [0.45, -0.55, 1.25, -0.15]
	mi.rotate_object_local(Vector3.FORWARD, rolls[tick % rolls.size()])
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.scale = Vector3(0.6, 0.02, 0.6)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.9, 0.02, 1.9), 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.22).set_delay(0.06)
	tw.chain().tween_callback(mi.queue_free)
	GoreFXScript.sparks(pc, center, fwd, REND_COL, 14)
	GameFeelScript.play_sound(pc, "whoosh_light", center, -2.0, 1.15 + 0.08 * float(tick))


## Per-finisher strike frame payoff.
static func on_strike(pc: Node3D, fin_name: String) -> void:
	var fwd: Vector3 = pc.call("get_facing_direction") if pc.has_method("get_facing_direction") else Vector3.FORWARD
	match fin_name:
		"fin_sunder":
			var at: Vector3 = pc.global_position + fwd * 1.4
			_light_pillar(pc, at, SUNDER_COL, 7.0, 0.55)
			GoreFXScript.shockwave_ring(pc, at, 5.0, Color(SUNDER_COL.r, SUNDER_COL.g, SUNDER_COL.b, 0.95), 0.5, 0.4)
			GoreFXScript.shockwave_ring(pc, at, 2.6, Color(1, 0.95, 0.8, 0.9), 0.28, 0.25)
			GoreFXScript.dust_puff(pc, at, 2.2, 34, Color(0.6, 0.52, 0.44, 0.7), 4.0)
			GoreFXScript.flash_light(pc, at + Vector3.UP, SUNDER_COL, 8.0, 0.45, 10.0)
			for i in 8:
				var ang: float = TAU * float(i) / 8.0
				GoreFXScript.ground_crack(pc, at, Vector3(cos(ang), 0.0, sin(ang)), 3.6, SUNDER_COL)
			GameFeelScript.play_sound(pc, "land_heavy", at, 4.0, 0.7)
			GameFeelScript.play_sound(pc, "thud", at, 2.0, 0.6)
			_play("glass_shatter", -4.0)
		"fin_phantom":
			var at2: Vector3 = pc.global_position + Vector3.UP * 1.0 + fwd * 1.0
			_starburst(pc, at2, PHANTOM_COL, 2.2, 0.4)
			GoreFXScript.sparks(pc, at2, fwd, PHANTOM_COL, 46)
			GoreFXScript.flash_light(pc, at2, PHANTOM_COL, 10.0, 0.4, 8.0)
			GameFeelScript.play_sound(pc, "slash_flesh", at2, 3.0, 0.8)
		"fin_rend":
			GoreFXScript.flash_light(pc, pc.global_position + Vector3.UP + fwd, REND_COL, 6.0, 0.6, 6.0)
		"fin_mirror_break":
			var c: Vector3 = pc.global_position
			GoreFXScript.shockwave_ring(pc, c, 4.5, Color(MIRROR_COL.r, MIRROR_COL.g, MIRROR_COL.b, 0.9), 0.45, 0.3)
			GoreFXScript.shockwave_ring(pc, c, 3.0, Color(AMBER.r, AMBER.g, AMBER.b, 0.85), 0.35, 0.2)
			GoreFXScript.flash_light(pc, c + Vector3.UP * 1.2, MIRROR_COL, 9.0, 0.5, 9.0)
			_shard_burst(pc, c + Vector3.UP * 1.1, 22, 5.5)
			_play("glass_shatter", 0.0)
			_play("mirror_whisper", -4.0)
		"fin_execution":
			var at3: Vector3 = pc.global_position + fwd * 1.3
			_light_pillar(pc, at3, EXEC_COL, 9.0, 0.6)
			GoreFXScript.shockwave_ring(pc, at3, 3.6, Color(EXEC_COL.r, EXEC_COL.g, EXEC_COL.b, 0.95), 0.4, 0.35)
			GoreFXScript.dust_puff(pc, at3, 1.8, 30, Color(0.4, 0.32, 0.3, 0.7), 4.5)
			GoreFXScript.flash_light(pc, at3 + Vector3.UP, EXEC_COL, 9.0, 0.45, 9.0)
			for i in 6:
				var ang2: float = TAU * float(i) / 6.0 + 0.3
				GoreFXScript.ground_crack(pc, at3, Vector3(cos(ang2), 0.0, sin(ang2)), 3.0, EXEC_COL)
			GameFeelScript.play_sound(pc, "land_heavy", at3, 5.0, 0.6)
			GameFeelScript.play_sound(pc, "slash_flesh", at3, 4.0, 0.7)


## Mirror Break tick: a ring of glass shards bursting outward, alternating cyan (Mirror) / amber (Reality).
static func mirror_shards(pc: Node3D, tick: int) -> void:
	var c: Vector3 = pc.global_position + Vector3.UP * (0.8 + 0.25 * float(tick))
	_shard_burst(pc, c, 12, 4.0 + float(tick))
	GoreFXScript.shockwave_ring(pc, pc.global_position, 3.2 + 0.4 * float(tick), Color(MIRROR_COL.r, MIRROR_COL.g, MIRROR_COL.b, 0.7), 0.3, 0.12)
	GameFeelScript.play_sound(pc, "whoosh_heavy", c, -3.0, 1.0 + 0.12 * float(tick))


## Execution kill: crimson starburst + blood-red light on the executed enemy.
static func execution_kill(pc: Node3D, target: Node3D) -> void:
	var at: Vector3 = target.global_position + Vector3.UP * 1.0
	_starburst(pc, at, EXEC_COL, 2.6, 0.5)
	GoreFXScript.sparks(pc, at, Vector3.UP, EXEC_COL, 40)
	GoreFXScript.flash_light(pc, at, EXEC_COL, 12.0, 0.5, 8.0)
	_play("glass_shatter", -2.0)


## Thin additive glass shards flung outward and spinning, fading out. Cheap: plain quads + tweens.
static func _shard_burst(ctx: Node3D, at: Vector3, count: int, dist: float) -> void:
	var host: Node = GoreFXScript.host_for(ctx)
	if host == null:
		return
	for i in count:
		var col: Color = MIRROR_COL if i % 2 == 0 else AMBER
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(randf_range(0.08, 0.18), randf_range(0.3, 0.6))
		mi.mesh = q
		var mat := _add_mat(Color(col.r, col.g, col.b, 0.9))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(mi)
		mi.global_position = at
		var ang: float = TAU * float(i) / float(count) + randf_range(-0.15, 0.15)
		var dir := Vector3(cos(ang), randf_range(-0.15, 0.45), sin(ang)).normalized()
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var dur: float = randf_range(0.35, 0.6)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", at + dir * dist * randf_range(0.7, 1.0), dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "rotation", mi.rotation + Vector3(randf_range(3, 8), randf_range(3, 8), 0), dur)
		tw.tween_property(mat, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)


## Phantom Step: a cyan streak + shard burst from where the player was to where they reappear.
static func phantom_blink(pc: Node3D, from: Vector3, to: Vector3) -> void:
	var host: Node = GoreFXScript.host_for(pc)
	if host == null:
		return
	var rig: Node = pc.get_node_or_null("PlayerFeelRig")
	if rig != null and rig.has_method("_spawn_ghost"):
		rig.call("_spawn_ghost", Color(PHANTOM_COL.r, PHANTOM_COL.g, PHANTOM_COL.b, 0.7))
	var mid: Vector3 = (from + to) * 0.5 + Vector3.UP * 1.0
	var length: float = from.distance_to(to)
	if length > 0.1:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.12, length)
		mi.mesh = box
		var mat := _add_mat(Color(PHANTOM_COL.r, PHANTOM_COL.g, PHANTOM_COL.b, 0.9))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(mi)
		mi.global_position = mid
		mi.look_at(to + Vector3.UP * 1.0, Vector3.UP)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "scale", Vector3(4.0, 0.2, 1.0), 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
		tw.chain().tween_callback(mi.queue_free)
	GoreFXScript.sparks(pc, from + Vector3.UP, (to - from), PHANTOM_COL, 30)
	GoreFXScript.shockwave_ring(pc, from, 1.6, Color(PHANTOM_COL.r, PHANTOM_COL.g, PHANTOM_COL.b, 0.8), 0.3, 0.1)
	GoreFXScript.shockwave_ring(pc, to, 1.6, Color(PHANTOM_COL.r, PHANTOM_COL.g, PHANTOM_COL.b, 0.8), 0.3, 0.1)
	_play("mirror_whisper", -2.0)
	GameFeelScript.play_sound(pc, "whoosh_heavy", mid, -1.0, 1.3)


## Tall additive column of light (Sunder impact).
static func _light_pillar(ctx: Node3D, at: Vector3, color: Color, height: float, dur: float) -> void:
	var host: Node = GoreFXScript.host_for(ctx)
	if host == null:
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.55
	cyl.height = height
	cyl.radial_segments = 16
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.mesh = cyl
	var mat := _add_mat(Color(color.r, color.g, color.b, 0.4))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	mi.global_position = at + Vector3.UP * height * 0.5
	mi.scale = Vector3(0.3, 1.0, 0.3)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.1, 1.1, 1.1), dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)
