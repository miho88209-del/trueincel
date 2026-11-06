class_name Interactable
extends Area3D
## Something the player can aim at and use with E (and optionally Q).
## prompt_fn() -> String ("" hides the prompt), use_fn(player), alt_fn(player).

const LAYER := 8

var prompt_fn: Callable
var use_fn: Callable
var alt_fn: Callable
var highlight_target: GeometryInstance3D

static func make(parent: Node3D, pos: Vector3, size: Vector3, prompt: Callable, use: Callable, alt: Callable = Callable()) -> Interactable:
	var it := Interactable.new()
	it.collision_layer = LAYER
	it.collision_mask = 0
	it.monitoring = false
	it.monitorable = true
	it.prompt_fn = prompt
	it.use_fn = use
	it.alt_fn = alt
	it.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	it.add_child(cs)
	parent.add_child(it)
	return it

func prompt() -> String:
	if prompt_fn.is_valid():
		return prompt_fn.call()
	return ""

func use(player) -> void:
	if use_fn.is_valid():
		use_fn.call(player)

func alt(player) -> void:
	if alt_fn.is_valid():
		alt_fn.call(player)
