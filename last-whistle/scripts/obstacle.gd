class_name Obstacle
extends Node3D
## A fallen tree across the line. Chop it with the axe until it splits and rolls clear.

signal cleared(id: String)

var id := ""
var d := 0.0
var hits_needed := 5
var hits := 0
var is_cleared := false
var _halves: Array = []
var _body: StaticBody3D
var _chips: GPUParticles3D
var _shake_t := 0.0

func setup(info: Dictionary) -> void:
	id = info["id"]
	d = info["d"]
	hits_needed = info["hits"]
	var base := Track.pos(d, 0.0)
	base.y = Track.BALLAST_Y
	global_transform = Transform3D(Basis.looking_at(Track.fwd(d), Vector3.UP), base)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var ang := rng.randf_range(-0.35, 0.35)
	var root := Node3D.new()
	root.rotation.y = ang
	add_child(root)
	# the trunk lies across the rails (local X), split point at x=0
	for side in [-1, 1]:
		var half := Node3D.new()
		half.position = Vector3(side * 0.02, 0.55, 0)
		root.add_child(half)
		var mk := MK.new()
		var length := 7.0 if side > 0 else 6.0
		mk.cyl("bark", Transform3D(Basis(Vector3.FORWARD, side * PI / 2), Vector3.ZERO), 0.48, 0.42 if side > 0 else 0.3, length, 9, Props.BARK)
		if side > 0:
			# root plate
			for i in 7:
				var a := TAU * i / 7.0
				mk.cyl_between("bark", Vector3(length - 0.3, 0, 0), Vector3(length + 0.4, sin(a) * 1.3, cos(a) * 1.3), 0.14, 0.03, 4, Props.BARK)
			mk.blob("stone", Transform3D(Basis.from_scale(Vector3(0.5, 1, 1)), Vector3(length, 0, 0)), 0.9, Color(0.16, 0.15, 0.13), 0.3, 3, 3, 7)
		else:
			# crown with dead branches
			for i in 9:
				var a := rng.randf() * TAU
				var start := Vector3(-rng.randf_range(2.5, 5.8), 0, 0)
				mk.cyl_between("bark", start, start + Vector3(-rng.randf_range(0.5, 1.8), sin(a) * rng.randf_range(0.8, 2.0), cos(a) * rng.randf_range(0.8, 2.0)), 0.1, 0.02, 4, Props.BARK)
			for i in 4:
				mk.blob("foliage", Transform3D(Basis.from_scale(Vector3(1, 0.6, 1)), Vector3(-rng.randf_range(4, 6.5), rng.randf_range(-0.3, 0.8), rng.randf_range(-1.5, 1.5))), rng.randf_range(0.8, 1.3), Props.CANOPY, 0.3, i, 3, 6)
		var mi := mk.build(half, "Half", true)
		_halves.append(half)
	# notch ring at the cut
	_body = StaticBody3D.new()
	_body.collision_layer = 1 | 16
	_body.set_meta("chop", self)
	_body.set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(10.0, 1.0, 1.0)
	cs.shape = bs
	cs.position = Vector3(0.5, 0.55, 0)
	_body.add_child(cs)
	root.add_child(_body)
	# stump beside the line
	var st := MK.new()
	st.cyl("bark", Transform3D(Basis(), Vector3(7.5, -0.4, 0.5)), 0.55, 0.45, 1.1, 8, Props.BARK)
	st.build(self, "Stump", true)
	_chips = GPUParticles3D.new()
	_chips.one_shot = true
	_chips.emitting = false
	_chips.amount = 24
	_chips.lifetime = 1.2
	_chips.explosiveness = 0.95
	_chips.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.angle_min = -180; pm.angle_max = 180
	_chips.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.02, 0.08)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.62, 0.56, 0.45)
	bm.material = cm
	_chips.draw_pass_1 = bm
	add_child(_chips)

func chop(at: Vector3) -> void:
	if is_cleared:
		return
	hits += 1
	_chips.global_position = at
	_chips.restart()
	_chips.emitting = true
	_shake_t = 0.25
	Sfx.play_at("axe_chop", at, 2.0, randf_range(0.9, 1.1), 40.0)
	if hits >= hits_needed:
		_split()

func progress() -> float:
	return float(hits) / hits_needed

func _split() -> void:
	is_cleared = true
	_body.collision_layer = 0
	Sfx.play_at("tree_crack", global_position + Vector3(0, 1, 0), 4.0, 1.0, 120.0)
	var tw := create_tween().set_parallel(true)
	for i in _halves.size():
		var h: Node3D = _halves[i]
		var side := -1.0 if i == 0 else 1.0
		tw.tween_property(h, "position", h.position + Vector3(side * 4.5, -0.25, 0.6), 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(h, "rotation", Vector3(side * 0.8, side * 0.35, 0), 1.6).set_trans(Tween.TRANS_QUAD)
	cleared.emit(id)

func _process(dt: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= dt
		for h in _halves:
			h.position.y = 0.55 + sin(_shake_t * 80.0) * 0.02 * _shake_t * 4.0

func set_cleared_instant() -> void:
	hits = hits_needed
	is_cleared = true
	_body.collision_layer = 0
	for i in _halves.size():
		var h: Node3D = _halves[i]
		var side := -1.0 if i == 0 else 1.0
		h.position += Vector3(side * 4.5, -0.25, 0.6)
		h.rotation = Vector3(side * 0.8, side * 0.35, 0)
