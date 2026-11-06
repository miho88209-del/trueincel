class_name Creature
extends Node3D
## "The Stillman": a tall figure with a paper face. It only moves while you are
## not looking at it, never boards the train, hates the whistle, and after
## striking it withdraws into the fog for a while.

enum { DORMANT, WATCH, STALK }

var world: Node
var state := DORMANT
var exposure := 0.0
var cooldown := 0.0
var observed := false
var _seen_t := 0.0
var _visible_amt := 0.0
var _target_vis := 0.0
var _cue_t := 4.0
var _relocate_t := 0.0
var _whisper_t := 0.0
var _heart_t := 0.0
var _stalk_announced := false
var dist := 999.0
var _mat: StandardMaterial3D
var _face_mat: ShaderMaterial
var _head: Node3D
var _arms: Array = []
var _hitbox: Area3D
var _t := 0.0

static func build_model(parent: Node3D, mat: Material) -> Dictionary:
	var mk := MK.new()
	var c := Color(0.07, 0.07, 0.075)
	for s in [-1, 1]:
		mk.cyl_between("cloth", Vector3(s * 0.12, 0, 0), Vector3(s * 0.1, 1.35, 0), 0.06, 0.08, 5, c)
	mk.cyl_between("cloth", Vector3(0, 1.25, 0), Vector3(0, 2.25, 0.02), 0.17, 0.24, 6, c)
	mk.cyl_between("cloth", Vector3(0, 2.2, 0.02), Vector3(0, 2.38, 0), 0.24, 0.06, 6, c)
	# ragged coat hem
	for i in 8:
		var a := TAU * i / 8.0
		mk.tri("cloth", Vector3(cos(a) * 0.2, 1.4, sin(a) * 0.2), Vector3(cos(a + 0.4) * 0.2, 1.4, sin(a + 0.4) * 0.2), Vector3(cos(a + 0.2) * 0.26, 0.85 + (i % 3) * 0.12, sin(a + 0.2) * 0.26), c)
		mk.tri("cloth", Vector3(cos(a + 0.4) * 0.2, 1.4, sin(a + 0.4) * 0.2), Vector3(cos(a) * 0.2, 1.4, sin(a) * 0.2), Vector3(cos(a + 0.2) * 0.26, 0.85 + (i % 3) * 0.12, sin(a + 0.2) * 0.26), c)
	var body := MeshInstance3D.new()
	body.mesh = mk.commit()
	body.material_override = mat
	parent.add_child(body)
	var arms := []
	for s in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(s * 0.27, 2.2, 0)
		parent.add_child(pivot)
		var amk := MK.new()
		amk.cyl_between("cloth", Vector3.ZERO, Vector3(s * 0.08, -0.95, 0.05), 0.05, 0.04, 5, c)
		amk.cyl_between("cloth", Vector3(s * 0.08, -0.95, 0.05), Vector3(s * 0.05, -1.55, 0.12), 0.04, 0.025, 5, c)
		for f in 3:
			amk.cyl_between("cloth", Vector3(s * 0.05, -1.55, 0.12), Vector3(s * (0.03 + f * 0.02), -1.75, 0.1 + f * 0.04), 0.012, 0.004, 3, c)
		var ami := MeshInstance3D.new()
		ami.mesh = amk.commit()
		ami.material_override = mat
		pivot.add_child(ami)
		arms.append(pivot)
	var head := Node3D.new()
	head.position = Vector3(0, 2.38, 0)
	parent.add_child(head)
	var hmk := MK.new()
	hmk.blob("cloth", Transform3D(Basis.from_scale(Vector3(0.8, 1.25, 0.8)), Vector3(0, 0.2, 0)), 0.16, c, 0.1, 5, 4, 7)
	var hmi := MeshInstance3D.new()
	hmi.mesh = hmk.commit()
	hmi.material_override = mat
	head.add_child(hmi)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.24, 0.32)
	face.mesh = q
	var fm: ShaderMaterial = Props.note_face_material(true).duplicate()
	fm.set_shader_parameter("sway", 0.0)
	face.material_override = fm
	face.position = Vector3(0, 0.2, -0.13)
	face.rotation.y = PI
	head.add_child(face)
	return {"head": head, "arms": arms, "face": fm}

func setup(w: Node) -> void:
	world = w
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 1.0
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_mat.albedo_color = Color(1, 1, 1, 0)
	var parts := build_model(self, _mat)
	_head = parts["head"]
	_arms = parts["arms"]
	_face_mat = parts["face"]
	_hitbox = Area3D.new()
	_hitbox.collision_layer = 16
	_hitbox.collision_mask = 0
	_hitbox.monitoring = false
	_hitbox.set_meta("creature", self)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 2.5
	cs.shape = cap
	cs.position.y = 1.3
	_hitbox.add_child(cs)
	add_child(_hitbox)
	visible = false

func is_hunting() -> bool:
	return state == STALK and visible

func _player() -> Node3D:
	return world.player

func tick(dt: float, exposed: bool, darkness: float) -> void:
	_t += dt
	var p: Player = world.player
	cooldown = maxf(0.0, cooldown - dt)
	var k := lerpf(1.0, 0.6, darkness)
	if exposed:
		exposure += dt
	else:
		exposure = maxf(0.0, exposure - dt * 3.0)
	dist = global_position.distance_to(p.global_position) if visible else 999.0
	observed = visible and _is_observed(p)
	# state transitions
	if not exposed or cooldown > 0.0:
		state = DORMANT
		if visible and _target_vis > 0.0 and not observed:
			_vanish(false)
	elif state == DORMANT and exposure > 9.0 * k:
		state = WATCH
		_spawn(p, 38.0, 48.0, false)
	elif state == WATCH and exposure > 24.0 * k:
		state = STALK
		if not _stalk_announced or randf() < 0.5:
			_stalk_announced = true
			Sfx.duck_ambience(-28.0, 0.8)
			get_tree().create_timer(6.0).timeout.connect(func() -> void: Sfx.duck_ambience(0.0, 3.0))
			world.hud.message("The woods have gone quiet.", 3.0)
		if not visible or not observed:
			_spawn(p, 26.0, 32.0, true)
	match state:
		WATCH: _watch(dt, p)
		STALK: _stalk(dt, p, darkness)
	# fade and animate
	_visible_amt = move_toward(_visible_amt, _target_vis, dt * 1.6)
	_mat.albedo_color.a = _visible_amt
	visible = _visible_amt > 0.01
	_face_mat.set_shader_parameter("sway", 0.0)
	if visible:
		var to := p.global_position - global_position
		to.y = 0
		if to.length() > 0.1:
			var target_yaw := atan2(-to.x, -to.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, dt * (1.0 if observed else 6.0)))
		_head.rotation.z = lerpf(_head.rotation.z, 0.45 if observed else 0.08 * sin(_t * 0.7), dt * (0.4 if observed else 2.0))
		for i in _arms.size():
			_arms[i].rotation.x = sin(_t * 0.9 + i) * 0.05

func _watch(dt: float, p: Player) -> void:
	_cue_t -= dt
	if _cue_t <= 0.0:
		_cue_t = randf_range(5.0, 9.0)
		var pos := global_position if visible else p.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(20, 35)
		if randf() < 0.55:
			Sfx.play_at(Sfx.variant("branch_snap", 3), pos + Vector3(0, 0.5, 0), 0.0, randf_range(0.85, 1.1), 90.0)
		else:
			Sfx.play_at("far_steps", pos, -2.0, randf_range(0.9, 1.05), 90.0)
	if visible and observed:
		_seen_t += dt
		if _seen_t > 1.2:
			_vanish(false)
			_relocate_t = randf_range(4.0, 8.0)
	elif not visible:
		_relocate_t -= dt
		if _relocate_t <= 0.0:
			_spawn(p, 34.0, 46.0, false)

func _stalk(dt: float, p: Player, darkness: float) -> void:
	if not visible and _target_vis <= 0.0:
		_relocate_t -= dt
		if _relocate_t <= 0.0:
			_spawn(p, 24.0, 30.0, true)
		return
	var to := p.global_position - global_position
	to.y = 0
	var dd := to.length()
	if not observed:
		var speed := 2.7 + darkness * 1.3
		if dd > 3.0:
			global_position += to.normalized() * minf(speed * dt, dd)
		else:
			global_position += to.normalized() * minf(speed * 0.7 * dt, dd)
		global_position.y = Track.height(global_position.x, global_position.z)
		if dd < 1.5:
			_strike(p)
	else:
		_seen_t += dt
		_heart_t -= dt
		if dd < 12.0 and _heart_t <= 0.0:
			_heart_t = lerpf(0.55, 1.1, dd / 12.0)
			Sfx.play("heartbeat", lerpf(0.0, -10.0, dd / 12.0))
	_whisper_t -= dt
	if dd < 16.0 and _whisper_t <= 0.0:
		_whisper_t = randf_range(3.0, 5.5)
		Sfx.play_at(Sfx.variant("whisper", 3), global_position + Vector3(0, 2.2, 0), lerpf(2.0, -8.0, dd / 16.0), 1.0, 30.0)
	_cue_t -= dt
	if dd > 14.0 and _cue_t <= 0.0:
		_cue_t = randf_range(4.0, 7.0)
		Sfx.play_at(Sfx.variant("step_grass", 4), global_position, 4.0, 0.7, 50.0)

func _strike(p: Player) -> void:
	p.take_damage(34.0)
	world.hud.message("Don't look away.", 3.0)
	_vanish(true)
	cooldown = 16.0
	exposure = 12.0
	state = DORMANT

func scare() -> void:
	if state == DORMANT and not visible:
		exposure = 0.0
		cooldown = maxf(cooldown, 20.0)
		return
	Sfx.play_at(Sfx.variant("whisper", 3), global_position + Vector3(0, 2, 0), 2.0, 0.6, 80.0)
	_vanish(false)
	state = DORMANT
	exposure = 0.0
	cooldown = 35.0

func struck() -> void:
	if not visible:
		return
	Sfx.play_at("sting", global_position + Vector3(0, 2, 0), -4.0, 1.2, 60.0)
	_vanish(false)
	state = DORMANT
	exposure = 6.0
	cooldown = 22.0

func _vanish(_fast: bool) -> void:
	_target_vis = 0.0
	_seen_t = 0.0
	if _fast:
		_visible_amt = 0.0

func _spawn(p: Player, rmin: float, rmax: float, behind: bool) -> void:
	var cam := p.cam
	var fwd := -cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var best := Vector3.ZERO
	var found := false
	for i in 14:
		var a := randf() * TAU
		if behind:
			a = atan2(-fwd.x, -fwd.z) + PI + randf_range(-1.1, 1.1)
		var dir := Vector3(-sin(a), 0, -cos(a))
		var pos := p.global_position + dir * randf_range(rmin, rmax)
		if Track.dist_to_track(pos.x, pos.z) < 4.0:
			continue
		pos.y = Track.height(pos.x, pos.z)
		if dir.dot(fwd) > 0.2:
			continue
		best = pos
		found = true
		break
	if not found:
		best = p.global_position - fwd * rmax
		best.y = Track.height(best.x, best.z)
	global_position = best
	_target_vis = 1.0
	_visible_amt = 0.0
	_seen_t = 0.0
	visible = true
	reset_physics_interpolation()

func _is_observed(p: Player) -> bool:
	return _is_observed_point(p, global_position)

func _is_observed_point(p: Player, base: Vector3) -> bool:
	var cam := p.cam
	var space := get_world_3d().direct_space_state
	for h in [2.3, 1.4]:
		var target := base + Vector3(0, h, 0)
		var to := target - cam.global_position
		var dd := to.length()
		if dd > 85.0:
			return false
		var ang := cos(deg_to_rad(cam.fov * 0.62))
		if (-cam.global_basis.z).dot(to / dd) < ang:
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, target, 1 | 2)
		q.exclude = [p.get_rid()]
		if space.intersect_ray(q).is_empty():
			return true
	return false
