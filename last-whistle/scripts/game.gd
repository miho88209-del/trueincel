extends Node
## Scene flow, input map and the checkpoint used for "retry from last stop".

const WORLD := "res://scenes/world.tscn"
const MENU := "res://scenes/menu.tscn"

var start_mode := "new"      # "new" | "retry"
var checkpoint := {}
var autotest := false
var autotest_args := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest"):
			autotest = true
			var parts := a.split("=")
			autotest_args["mode"] = parts[1] if parts.size() > 1 else "full"

func _setup_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("sprint", [KEY_SHIFT])
	_key("jump", [KEY_SPACE])
	_key("interact", [KEY_E])
	_key("interact_alt", [KEY_Q])
	_key("lantern", [KEY_F])
	_key("pause", [KEY_ESCAPE])
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)

func _key(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func start_new() -> void:
	start_mode = "new"
	checkpoint = {}
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD)

func retry() -> void:
	start_mode = "retry" if not checkpoint.is_empty() else "new"
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD)

func goto_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.muffle(false)
	get_tree().change_scene_to_file(MENU)

func quit() -> void:
	Settings.save_settings()
	get_tree().quit()
