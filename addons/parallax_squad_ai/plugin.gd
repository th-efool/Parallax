@tool
extends EditorPlugin
## Editor side of the PARALLAX Squad AI plugin: registers the runtime node types so they can be added from
## the "Create Node" dialog, and ensures microphone input is enabled (required for Whisper push-to-talk).
## The runtime itself needs no autoload: `SquadComms` is created by the shared HUD.


func _enter_tree() -> void:
	add_custom_type("OpenAIClient", "Node", preload("res://addons/parallax_squad_ai/openai_client.gd"), null)
	add_custom_type("SquadComms", "Node", preload("res://addons/parallax_squad_ai/squad_comms.gd"), null)
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		ProjectSettings.set_setting("audio/driver/enable_input", true)
		ProjectSettings.save()


func _exit_tree() -> void:
	remove_custom_type("OpenAIClient")
	remove_custom_type("SquadComms")
