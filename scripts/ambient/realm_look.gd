class_name RealmLook
extends RefCounted
## Makes imported fauna/flora read correctly in both realms.
## `apply(root, profile)` swaps every surface material under `root` for a managed duplicate (shared per
## original material + profile, so 200 trees cost one material). `FaunaDirector` calls `set_blend()`
## whenever the global `realm_mirror_blend` shader parameter moves (0 Reality .. 1 Mirror), so living
## things transition in lock-step with the level's own Reality -> Mirror shift.
##
## Profiles (Mirror look):
##   fur      — moonlit, desaturated cobalt fur with a cool rim and faint inner glow
##   feather  — like fur, a touch brighter
##   leaves   — cool teal-indigo foliage whose own texture glows softly (luminous canopy)
##   bark     — dark slate wood with a faint cobalt sheen
##   flower   — petals turn into bright cyan / violet light
##   grass    — blue-green blades with a faint glow
##   mushroom — strong bioluminescent glow
##   spectral — *always* the ghost look (Mirror-only spirit variants): uses mirror_spectral.gdshader

const SPECTRAL_SHADER_PATH: String = "res://assets/shaders/mirror_spectral.gdshader"

const PROFILES: Dictionary = {
	"fur":      {"tint": Color(0.42, 0.52, 0.85), "desat": 0.55, "glow": Color(0.25, 0.45, 1.0), "glow_e": 0.18, "rim": 0.55, "tex_glow": false},
	"feather":  {"tint": Color(0.55, 0.65, 0.95), "desat": 0.45, "glow": Color(0.35, 0.6, 1.0), "glow_e": 0.25, "rim": 0.6, "tex_glow": false},
	"leaves":   {"tint": Color(0.3, 0.55, 0.8), "desat": 0.45, "glow": Color(0.25, 0.8, 1.0), "glow_e": 0.35, "rim": 0.0, "tex_glow": true},
	"bark":     {"tint": Color(0.35, 0.38, 0.55), "desat": 0.6, "glow": Color(0.2, 0.4, 1.0), "glow_e": 0.08, "rim": 0.25, "tex_glow": false},
	"flower":   {"tint": Color(0.7, 0.75, 1.0), "desat": 0.2, "glow": Color(0.55, 0.75, 1.0), "glow_e": 1.6, "rim": 0.0, "tex_glow": true},
	"grass":    {"tint": Color(0.4, 0.7, 0.85), "desat": 0.3, "glow": Color(0.3, 0.9, 1.0), "glow_e": 0.3, "rim": 0.0, "tex_glow": true},
	"stone":    {"tint": Color(0.45, 0.5, 0.75), "desat": 0.6, "glow": Color(0.2, 0.45, 1.0), "glow_e": 0.06, "rim": 0.2, "tex_glow": false},
	"mushroom": {"tint": Color(0.6, 0.7, 1.0), "desat": 0.2, "glow": Color(0.4, 0.95, 1.0), "glow_e": 2.2, "rim": 0.0, "tex_glow": true},
}

static var _managed: Dictionary = {}   # key -> {"mat": StandardMaterial3D, "base": Dictionary, "profile": String}
static var _spectral: Dictionary = {}  # tint key -> ShaderMaterial
static var blend: float = 0.0


static func clear_caches() -> void:
	_managed.clear()
	_spectral.clear()


## Guess a profile from a material / mesh name when the caller passes "auto".
static func guess_profile(name_hint: String, fallback: String) -> String:
	var n: String = name_hint.to_lower()
	if n.contains("flower") or n.contains("petal") or n.contains("berry"):
		return "flower"
	if n.contains("mushroom"):
		return "mushroom"
	if n.contains("grass") or n.contains("clover"):
		return "grass"
	if n.contains("leaf") or n.contains("leaves") or n.contains("fern") or n.contains("pine") and not n.contains("bark"):
		return "leaves"
	if n.contains("bark") or n.contains("wood") or n.contains("trunk"):
		return "bark"
	return fallback


static func apply(root: Node, fallback_profile: String) -> void:
	for mi in _meshes(root):
		var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for s in range(count):
			var orig: Material = mi.get_active_material(s)
			if not (orig is StandardMaterial3D):
				continue
			var profile: String = fallback_profile
			if fallback_profile == "auto" or fallback_profile == "leaves":
				profile = guess_profile(String(orig.resource_name) + " " + String(mi.name), "leaves" if fallback_profile == "auto" else fallback_profile)
			mi.set_surface_override_material(s, _managed_for(orig as StandardMaterial3D, profile))


## Ghost look for Mirror-only spirit variants (whole model).
static func apply_spectral(root: Node, tint: Color = Color(0.2, 0.75, 1.0)) -> void:
	var key: String = tint.to_html()
	var sm: ShaderMaterial = _spectral.get(key, null) as ShaderMaterial
	if sm == null and ResourceLoader.exists(SPECTRAL_SHADER_PATH):
		sm = ShaderMaterial.new()
		sm.shader = load(SPECTRAL_SHADER_PATH) as Shader
		sm.set_shader_parameter("rim_color", Color(tint.r, tint.g, tint.b, 1.0))
		sm.set_shader_parameter("base_tint", Color(tint.r * 0.25, tint.g * 0.35, tint.b * 0.55, 0.62))
		_spectral[key] = sm
	if sm == null:
		return
	for mi in _meshes(root):
		mi.material_override = sm


static func _managed_for(orig: StandardMaterial3D, profile: String) -> StandardMaterial3D:
	var key: String = "%d_%s" % [orig.get_instance_id(), profile]
	if _managed.has(key):
		return _managed[key]["mat"] as StandardMaterial3D
	var m: StandardMaterial3D = orig.duplicate() as StandardMaterial3D
	var base: Dictionary = {
		"albedo": orig.albedo_color,
		"emission_enabled": orig.emission_enabled,
		"emission": orig.emission,
		"energy": orig.emission_energy_multiplier,
		"emission_texture": orig.emission_texture,
		"rim_enabled": orig.rim_enabled,
	}
	m.emission_enabled = true
	if bool(PROFILES[profile]["tex_glow"]) and orig.albedo_texture != null and orig.emission_texture == null:
		m.emission_texture = orig.albedo_texture
	_managed[key] = {"mat": m, "base": base, "profile": profile}
	_apply_one(_managed[key], blend)
	return m


static func set_blend(b: float) -> void:
	b = clampf(b, 0.0, 1.0)
	if absf(b - blend) < 0.002 and b != 0.0 and b != 1.0:
		return
	blend = b
	for k in _managed.keys():
		_apply_one(_managed[k], b)


static func _apply_one(entry: Dictionary, b: float) -> void:
	var m: StandardMaterial3D = entry["mat"] as StandardMaterial3D
	if m == null:
		return
	var base: Dictionary = entry["base"]
	var p: Dictionary = PROFILES[String(entry["profile"])]
	var a: Color = base["albedo"]
	var lum: float = a.r * 0.299 + a.g * 0.587 + a.b * 0.114
	var desat := Color(lum, lum, lum, a.a).lerp(a, 1.0 - float(p["desat"]))
	var tint: Color = p["tint"]
	var mirror_albedo := Color(desat.r * tint.r * 1.3, desat.g * tint.g * 1.3, desat.b * tint.b * 1.3, a.a)
	m.albedo_color = a.lerp(mirror_albedo, b)
	# Emission: original emission in Reality, profile glow in Mirror.
	var base_e: float = float(base["energy"]) if bool(base["emission_enabled"]) else 0.0
	var base_c: Color = base["emission"] if bool(base["emission_enabled"]) else Color.BLACK
	var glow: Color = p["glow"]
	m.emission = base_c.lerp(glow, b)
	m.emission_energy_multiplier = lerpf(base_e, float(p["glow_e"]), b)
	if not bool(base["emission_enabled"]) and b <= 0.001:
		m.emission_energy_multiplier = 0.0
	var rim: float = float(p["rim"])
	m.rim_enabled = bool(base["rim_enabled"]) or (rim > 0.0 and b > 0.01)
	m.rim = rim * b
	m.rim_tint = 0.85


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.append(n as MeshInstance3D)
		for c in n.get_children():
			stack.append(c)
	return out
