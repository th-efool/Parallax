class_name InteractSwitch
extends Area3D
## Contextual `E: Interact` switch used for:
## - Stage 01 Mirror Switch (opens Gate 1 in both realms)
## - Stage 03 Bridge Anchor Switch (permanently repairs the Collapsed Gallery Reality bridge)
## Automatically formats its prompt text using the live `interact` keybinding from `LeaderboardStore`.

enum SwitchRole {
	GATE_OPENER = 0,
	BRIDGE_ANCHOR = 1,
	BOTH = 2,
}

signal switch_activated(switch_node: InteractSwitch)
signal prompt_changed(show_prompt: bool, prompt_text: String)

@export var switch_role: SwitchRole = SwitchRole.GATE_OPENER
@export var required_realm: int = 1 # 1 = MIRROR, 0 = REALITY, -1 = ANY
@export var linked_gate_path: NodePath
@export var linked_platform_path: NodePath
@export var blocking_prop_path: NodePath
@export var prompt_text: String = "E: Interact"

var is_activated: bool = false
var _player_inside: bool = false


func _exit_tree() -> void:
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_signal("controls_rebound"):
		if store.is_connected("controls_rebound", _on_controls_rebound):
			store.disconnect("controls_rebound", _on_controls_rebound)


func _ready() -> void:
	add_to_group("interactable_switch")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	var store: Node = _get_leaderboard_store()
	if store != null and store.has_signal("controls_rebound"):
		if not store.is_connected("controls_rebound", _on_controls_rebound):
			store.connect("controls_rebound", _on_controls_rebound)


func get_action_verb() -> String:
	var idx: int = prompt_text.find(":")
	if idx >= 0 and idx + 1 < prompt_text.length():
		return prompt_text.substr(idx + 1).strip_edges()
	return prompt_text if not prompt_text.is_empty() else "Interact"


func get_formatted_prompt_text() -> String:
	var key_label: String = "E"
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("get_action_display_label"):
		key_label = String(store.call("get_action_display_label", "interact"))
	return "%s: %s" % [key_label, get_action_verb()]


func can_interact() -> bool:
	if is_activated:
		return false

	if not blocking_prop_path.is_empty():
		var blocker: BreakableProp = get_node_or_null(blocking_prop_path) as BreakableProp
		if blocker != null and blocker.current_state != BreakableProp.PropState.BROKEN:
			return false

	if required_realm >= 0 and RealmManager.instance != null and not RealmManager.instance.is_merged:
		if int(RealmManager.instance.current_realm) != required_realm:
			return false

	return true


func interact() -> bool:
	if not can_interact():
		return false

	is_activated = true
	if switch_role == SwitchRole.BRIDGE_ANCHOR or switch_role == SwitchRole.BOTH:
		var platform: Node = get_node_or_null(linked_platform_path)
		if platform != null and platform.has_method("repair_for_reality"):
			platform.call("repair_for_reality")

	if switch_role == SwitchRole.GATE_OPENER or switch_role == SwitchRole.BOTH:
		var gate: Node = get_node_or_null(linked_gate_path)
		if gate != null and gate.has_method("unlock_and_open"):
			gate.call("unlock_and_open")

	prompt_changed.emit(false, "")
	switch_activated.emit(self)
	return true


func _on_body_entered(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_player_inside = true
		if body.has_method("register_nearby_interactable"):
			body.call("register_nearby_interactable", self)
		if can_interact():
			prompt_changed.emit(true, get_formatted_prompt_text())


func _on_body_exited(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_player_inside = false
		if body.has_method("unregister_nearby_interactable"):
			body.call("unregister_nearby_interactable", self)
		prompt_changed.emit(false, "")


func _on_controls_rebound(_action_name: String, _display_label: String, _all_bindings: Dictionary) -> void:
	if _player_inside and can_interact():
		prompt_changed.emit(true, get_formatted_prompt_text())


func _get_leaderboard_store() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("LeaderboardStore")
	return null
