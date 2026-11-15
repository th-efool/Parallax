class_name DeathOverlayController
extends Control
## Non-blocking death & checkpoint respawn fade overlay (GDD Section 9.2):
## Triggers a brief fade when `PlayerController.player_died` or `EncounterDirector.player_respawned` fires,
## automatically decaying back to transparent with zero confirmation clicks required.

signal death_fade_started()
signal death_fade_completed()

@export var fade_duration: float = 0.65
@export var build_default_ui_if_empty: bool = true
@export var fade_rect_path: NodePath

var is_fading: bool = false
var fade_alpha: float = 0.0
var _fade_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("death_overlay")
	MenuStyle.enforce_full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if build_default_ui_if_empty and get_child_count() == 0:
		_build_default_ui()
	if EncounterDirector.instance != null:
		if not EncounterDirector.instance.player_respawned.is_connected(_on_player_respawned):
			EncounterDirector.instance.player_respawned.connect(_on_player_respawned)


func _build_default_ui() -> void:
	var rect := ColorRect.new()
	rect.name = "FadeRect"
	rect.color = Color(0.11, 0.015, 0.02, 0.88)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.enforce_full_rect(rect)
	add_child(rect)
	fade_rect_path = get_path_to(rect)

	var center := CenterContainer.new()
	center.name = "DeathCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.enforce_full_rect(center)
	add_child(center)

	var lbl := Label.new()
	lbl.name = "DeathBannerLabel"
	lbl.text = "SHATTERED — RETURNING TO CHECKPOINT"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.style_title(lbl, 30, Color(0.95, 0.36, 0.30, 1.0))
	center.add_child(lbl)


func bind_player(player: Node) -> void:
	if player != null and player.has_signal("player_died"):
		if not player.is_connected("player_died", _on_player_died):
			player.connect("player_died", _on_player_died)


func _process(delta: float) -> void:
	if not is_fading:
		return
	_fade_timer = maxf(0.0, _fade_timer - delta)
	var dur: float = maxf(0.05, fade_duration)
	fade_alpha = clampf(_fade_timer / dur, 0.0, 1.0)
	_sync_visual()
	if _fade_timer <= 0.0:
		is_fading = false
		fade_alpha = 0.0
		visible = false
		_sync_visual()
		death_fade_completed.emit()


func trigger_death_fade() -> void:
	is_fading = true
	_fade_timer = maxf(0.05, fade_duration)
	fade_alpha = 1.0
	visible = true
	_sync_visual()
	death_fade_started.emit()


func _on_player_died() -> void:
	trigger_death_fade()


func _on_player_respawned(_sec_id: int, _xform: Transform3D) -> void:
	if not is_fading:
		trigger_death_fade()


func _sync_visual() -> void:
	modulate.a = fade_alpha
	if not fade_rect_path.is_empty():
		var rect: CanvasItem = get_node_or_null(fade_rect_path) as CanvasItem
		if rect != null:
			rect.modulate.a = fade_alpha
