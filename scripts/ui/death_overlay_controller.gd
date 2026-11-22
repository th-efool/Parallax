class_name DeathOverlayController
extends Control
## Cinematic death & checkpoint respawn overlay:
## On player death: fades screen to solid black while showing "YOU DIED", holds briefly,
## performs the checkpoint respawn while the screen is black, then fades back in.

signal death_fade_started()
signal death_fade_completed()

enum Phase {
	IDLE = 0,
	FADE_IN = 1,
	HOLD = 2,
	FADE_OUT = 3,
}

@export var fade_in_duration: float = 0.70
@export var hold_duration: float = 1.60
@export var fade_duration: float = 0.65
@export var build_default_ui_if_empty: bool = true
@export var fade_rect_path: NodePath

var is_fading: bool = false
var fade_alpha: float = 0.0
var _phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0
var _respawn_callback: Callable = Callable()
var _banner_box: Control = null


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
	rect.color = Color(0.0, 0.0, 0.0, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.enforce_full_rect(rect)
	add_child(rect)
	fade_rect_path = get_path_to(rect)

	var center := CenterContainer.new()
	center.name = "DeathCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.enforce_full_rect(center)
	add_child(center)

	var box := VBoxContainer.new()
	box.name = "DeathBannerBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_banner_box = box

	var lbl := Label.new()
	lbl.name = "DeathBannerLabel"
	lbl.text = "YOU DIED"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.style_title(lbl, 76, Color(0.88, 0.16, 0.14, 1.0))
	box.add_child(lbl)

	var sub := Label.new()
	sub.name = "DeathFlavorLabel"
	sub.text = "The mirror remembers."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.style_flavor(sub, 24, Color(0.78, 0.70, 0.66, 0.92))
	box.add_child(sub)


func bind_player(player: Node) -> void:
	if player != null and player.has_signal("player_died"):
		if not player.is_connected("player_died", _on_player_died):
			player.connect("player_died", _on_player_died)


func play_death_sequence(on_black_respawn: Callable) -> void:
	if _phase == Phase.FADE_IN or _phase == Phase.HOLD:
		return
	_respawn_callback = on_black_respawn
	_phase = Phase.FADE_IN
	_phase_timer = 0.0
	is_fading = true
	fade_alpha = 0.0
	visible = true
	_sync_visual(0.0)
	death_fade_started.emit()


func trigger_death_fade() -> void:
	# Quick fade-out only (used for Pause Menu "Restart Section").
	_respawn_callback = Callable()
	_phase = Phase.FADE_OUT
	_phase_timer = maxf(0.05, fade_duration)
	is_fading = true
	fade_alpha = 1.0
	visible = true
	_sync_visual(0.0)
	death_fade_started.emit()


func _process(delta: float) -> void:
	if not is_fading or _phase == Phase.IDLE:
		return
	# Use real wall-clock delta so hitstop/slowmo never stalls the death screen.
	var dt: float = delta / maxf(0.05, Engine.time_scale) if Engine.time_scale > 0.0 else delta
	dt = minf(dt, 0.1)

	match _phase:
		Phase.FADE_IN:
			_phase_timer += dt
			var dur: float = maxf(0.05, fade_in_duration)
			fade_alpha = clampf(_phase_timer / dur, 0.0, 1.0)
			var text_a: float = clampf((_phase_timer - dur * 0.2) / maxf(0.05, dur * 0.8), 0.0, 1.0)
			_sync_visual(text_a)
			if _phase_timer >= dur:
				_phase = Phase.HOLD
				_phase_timer = 0.0
				fade_alpha = 1.0
				_sync_visual(1.0)
		Phase.HOLD:
			_phase_timer += dt
			fade_alpha = 1.0
			_sync_visual(1.0)
			if _phase_timer >= maxf(0.1, hold_duration):
				# Respawn behind the solid black screen so there is zero visual pop.
				var cb: Callable = _respawn_callback
				_respawn_callback = Callable()
				if cb.is_valid():
					cb.call()
				_phase = Phase.FADE_OUT
				_phase_timer = maxf(0.05, fade_duration)
		Phase.FADE_OUT:
			_phase_timer = maxf(0.0, _phase_timer - dt)
			var dur_out: float = maxf(0.05, fade_duration)
			fade_alpha = clampf(_phase_timer / dur_out, 0.0, 1.0)
			var text_out: float = clampf((fade_alpha - 0.35) / 0.65, 0.0, 1.0)
			_sync_visual(text_out)
			if _phase_timer <= 0.0:
				_phase = Phase.IDLE
				is_fading = false
				fade_alpha = 0.0
				visible = false
				_sync_visual(0.0)
				death_fade_completed.emit()


func _on_player_died() -> void:
	# If PlayerController._on_death() already started play_death_sequence(), do nothing.
	if _phase == Phase.IDLE:
		play_death_sequence(Callable())


func _on_player_respawned(_sec_id: int, _xform: Transform3D) -> void:
	if not is_fading:
		trigger_death_fade()


func _sync_visual(text_alpha: float = -1.0) -> void:
	modulate.a = 1.0
	if not fade_rect_path.is_empty():
		var rect: CanvasItem = get_node_or_null(fade_rect_path) as CanvasItem
		if rect != null:
			rect.modulate.a = fade_alpha
	if _banner_box != null:
		_banner_box.modulate.a = fade_alpha if text_alpha < 0.0 else text_alpha
