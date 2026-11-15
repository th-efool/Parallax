class_name ScoreManager
extends Node
## Autoloaded as `RunState`.
## Tracks live score, checkpoint banked score, combo multiplier (x1/x2/x3 with 4.0s decay),
## elapsed run timer, per-encounter No-Hit flags, Time Bonus, and S/A/B/C Rank calculation.

signal score_changed(new_score: int, delta: int, event_type: String)
signal combo_changed(multiplier: int, hits: int, time_remaining: float)
signal no_hit_awarded(encounter_id: String, bonus_points: int)
signal run_timer_updated(elapsed_sec: float)
signal run_finalized(summary: Dictionary)

const POINTS_ENEMY_KILL: int = 100
const POINTS_MIRROR_KILL: int = 200
const POINTS_ENVIRONMENTAL_KILL: int = 250
const POINTS_NO_HIT_ENCOUNTER: int = 500
const POINTS_WARDEN_DEFEAT: int = 1000
const MAX_TIME_BONUS: int = 1000
const COMBO_DECAY_SECONDS: float = 4.0

const ELIGIBLE_NO_HIT_ENCOUNTERS: PackedStringArray = [
	"hall_of_echoes",
	"shielded_guard",
	"the_warden",
]

var score: int = 0
var banked_score: int = 0
var combo_hits: int = 0
var combo_timer: float = 0.0
var max_combo_multiplier_reached: int = 1
var elapsed_seconds: float = 0.0
var timer_running: bool = false

var current_active_encounter: String = ""
var encounter_damaged: Dictionary = {}
var encounter_no_hit_awarded: Dictionary = {}
var awarded_event_ids: Dictionary = {}
var _banked_event_ids: Dictionary = {}
var warden_defeat_awarded: bool = false


func _process(delta: float) -> void:
	if timer_running:
		elapsed_seconds += delta
		run_timer_updated.emit(elapsed_seconds)

	if combo_hits > 0 and combo_timer > 0.0:
		combo_timer = maxf(0.0, combo_timer - delta)
		if combo_timer <= 0.0:
			combo_hits = 0
			combo_changed.emit(1, 0, 0.0)


func start_new_run() -> void:
	score = 0
	banked_score = 0
	combo_hits = 0
	combo_timer = 0.0
	max_combo_multiplier_reached = 1
	elapsed_seconds = 0.0
	timer_running = true
	current_active_encounter = ""
	encounter_damaged.clear()
	encounter_no_hit_awarded.clear()
	awarded_event_ids.clear()
	_banked_event_ids.clear()
	warden_defeat_awarded = false
	score_changed.emit(score, 0, "reset")
	combo_changed.emit(1, 0, 0.0)


func pause_timer() -> void:
	timer_running = false


func resume_timer() -> void:
	timer_running = true


func get_combo_multiplier() -> int:
	if combo_hits >= 6:
		return 3
	if combo_hits >= 3:
		return 2
	return 1


func register_hit() -> int:
	combo_hits += 1
	combo_timer = COMBO_DECAY_SECONDS
	var mult: int = get_combo_multiplier()
	if mult > max_combo_multiplier_reached:
		max_combo_multiplier_reached = mult
	combo_changed.emit(mult, combo_hits, combo_timer)
	return mult


func on_player_damaged(encounter_id: String = "") -> void:
	combo_hits = 0
	combo_timer = 0.0
	combo_changed.emit(1, 0, 0.0)

	var target_enc: String = encounter_id if not encounter_id.is_empty() else current_active_encounter
	if not target_enc.is_empty():
		encounter_damaged[target_enc] = true


func add_score_event(type: String, eligible_for_combo: bool = true, unique_id: String = "") -> int:
	if not unique_id.is_empty():
		if bool(awarded_event_ids.get(unique_id, false)):
			return 0
		awarded_event_ids[unique_id] = true

	var base_points: int = _get_base_points(type)
	if base_points <= 0:
		return 0

	var mult: int = get_combo_multiplier() if eligible_for_combo else 1
	var awarded: int = base_points * mult
	score += awarded
	score_changed.emit(score, awarded, type)
	return awarded


func record_enemy_kill(enemy_unique_id: String, in_mirror_realm: bool = false, is_environmental: bool = false) -> int:
	var total_awarded: int = 0
	total_awarded += add_score_event("enemy_kill", true, enemy_unique_id + ":kill")
	if in_mirror_realm:
		total_awarded += add_score_event("mirror_kill", true, enemy_unique_id + ":mirror")
	if is_environmental:
		total_awarded += add_score_event("environmental_kill", true, enemy_unique_id + ":env")
	return total_awarded


func begin_encounter(encounter_id: String) -> void:
	if encounter_id.is_empty():
		return
	current_active_encounter = encounter_id
	encounter_damaged[encounter_id] = false


func end_encounter(encounter_id: String) -> int:
	var target_id: String = encounter_id if not encounter_id.is_empty() else current_active_encounter
	if current_active_encounter == target_id:
		current_active_encounter = ""

	if not ELIGIBLE_NO_HIT_ENCOUNTERS.has(target_id):
		return 0
	if bool(encounter_no_hit_awarded.get(target_id, false)):
		return 0
	if bool(encounter_damaged.get(target_id, false)):
		return 0

	encounter_no_hit_awarded[target_id] = true
	var bonus: int = add_score_event("no_hit_encounter", false, "no_hit:" + target_id)
	if bonus > 0:
		no_hit_awarded.emit(target_id, bonus)
	return bonus


func bank_section_score() -> void:
	banked_score = score
	_banked_event_ids = awarded_event_ids.duplicate()


func revert_to_banked_score() -> void:
	score = banked_score
	combo_hits = 0
	combo_timer = 0.0
	awarded_event_ids = _banked_event_ids.duplicate()
	score_changed.emit(score, 0, "checkpoint_revert")
	combo_changed.emit(1, 0, 0.0)


func calculate_time_bonus(time_sec: float = -1.0) -> int:
	var t: float = elapsed_seconds if time_sec < 0.0 else time_sec
	return maxi(0, MAX_TIME_BONUS - int(t))


func calculate_rank(total_score: int) -> String:
	if total_score >= 5000:
		return "S"
	if total_score >= 4000:
		return "A"
	if total_score >= 3000:
		return "B"
	return "C"


func finalize_run(award_warden_bonus: bool = true) -> Dictionary:
	timer_running = false
	var warden_bonus: int = 0
	if award_warden_bonus and not warden_defeat_awarded:
		warden_defeat_awarded = true
		warden_bonus = add_score_event("warden_defeat", false, "warden_defeat_once")

	var time_bonus: int = calculate_time_bonus(elapsed_seconds)
	if time_bonus > 0:
		score += time_bonus
		score_changed.emit(score, time_bonus, "time_bonus")

	banked_score = score
	_banked_event_ids = awarded_event_ids.duplicate()
	var final_rank: String = calculate_rank(score)
	var summary: Dictionary = {
		"score": score,
		"time_sec": elapsed_seconds,
		"time_bonus": time_bonus,
		"warden_bonus": warden_bonus,
		"rank": final_rank,
		"max_combo": max_combo_multiplier_reached,
	}
	run_finalized.emit(summary)
	return summary


func _get_base_points(type: String) -> int:
	match type:
		"enemy_kill":
			return POINTS_ENEMY_KILL
		"mirror_kill":
			return POINTS_MIRROR_KILL
		"environmental_kill":
			return POINTS_ENVIRONMENTAL_KILL
		"no_hit_encounter":
			return POINTS_NO_HIT_ENCOUNTER
		"warden_defeat":
			return POINTS_WARDEN_DEFEAT
	return 0
