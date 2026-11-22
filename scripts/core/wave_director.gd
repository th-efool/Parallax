class_name WaveDirector
extends Node3D
## Runs a room's garrison as consecutive waves (Hall of Echoes, Clock-Tower chamber).
## Wave 1 fights normally; later waves are held (EnemyBase.is_wave_held: hidden, inert, untargetable) and pour in
## with a burst once every enemy of the current wave is down. A section reset (player death) rewinds to wave 1.
## Set `waves` before the node enters the tree: Array of Array of NodePath (relative to this node).

const CombatVFXScript := preload("res://scripts/core/combat_vfx.gd")

signal wave_started(index: int, total: int)
signal waves_cleared()

@export var section_id: int = 1
@export var next_wave_delay: float = 2.0

var waves: Array = []
var current_wave: int = 0
var finished: bool = false
var _delay: float = -1.0
var _poll: float = 0.0


func _ready() -> void:
	add_to_group("wave_director")
	if EncounterDirector.instance != null and not EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset):
		EncounterDirector.instance.section_reset_requested.connect(_on_section_reset)
	_restart.call_deferred()


func get_total() -> int:
	return waves.size()


## 1-based wave number for display; 0 when idle/finished.
func get_display_wave() -> int:
	return 0 if finished or waves.is_empty() else current_wave + 1


## True during the brief pause after one wave is cleared and before the next wave spawns.
func is_waiting_for_next_wave() -> bool:
	return not finished and _delay >= 0.0


## Alive, active (non-held) enemies belonging to the currently active wave.
func get_current_wave_alive() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	if finished or _delay >= 0.0:
		return out
	for e in _enemies(current_wave):
		if is_instance_valid(e) and not e.is_dead and not e.is_wave_held:
			out.append(e)
	return out


func _enemies(i: int) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	if i < 0 or i >= waves.size():
		return out
	for p in waves[i]:
		var e: EnemyBase = get_node_or_null(p as NodePath) as EnemyBase
		if e != null:
			out.append(e)
	return out


func _restart() -> void:
	current_wave = 0
	finished = waves.is_empty()
	_delay = -1.0
	for i in range(waves.size()):
		for e in _enemies(i):
			e.set_wave_held(i > 0)


func _wave_down(i: int) -> bool:
	for e in _enemies(i):
		if not e.is_dead:
			return false
	return true


func _process(delta: float) -> void:
	if finished:
		return
	if _delay >= 0.0:
		_delay -= delta
		if _delay < 0.0:
			_release(current_wave)
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.25
	if not _wave_down(current_wave):
		return
	if current_wave >= waves.size() - 1:
		finished = true
		waves_cleared.emit()
		return
	current_wave += 1
	_delay = next_wave_delay


func _release(i: int) -> void:
	var host: Node = get_parent() if get_parent() != null else self
	for e in _enemies(i):
		if e.is_dead:
			continue
		e.set_wave_held(false)
		CombatVFXScript.spawn_impact_burst(host, e.global_position + Vector3(0, 1.0, 0), true, true, 1.6)
	if AudioManager.instance != null:
		AudioManager.instance.play_sfx("ui_confirm", -2.0)
	wave_started.emit(i + 1, waves.size())


func _on_section_reset(sec: int) -> void:
	if sec == section_id:
		# After the enemies' own reset (same signal), hold the later waves again.
		_restart.call_deferred()
