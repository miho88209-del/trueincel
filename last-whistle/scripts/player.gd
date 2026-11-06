class_name Player
extends CharacterBody3D
## First-person controller: walking, riding the moving train, ladders,
## interaction, axe, lantern, health, footsteps and camera effects.

const WALK := 3.4
const SPRINT := 5.6
const ACCEL := 11.0
const GRAVITY := 14.0
const JUMP := 4.4
const EYE := 1.62
const MAX_CARRY := 9

var world: Node
var cam: Camera3D
var yaw := 0.0
var pitch := 0.0
var health := 100.0
var has_axe := false
var has_lantern := false
var lantern_on := false
var carried_coal := 0
var attached: Node3D = null
var _air_time := 0.0
var climbing := false
var _ladder: Dictionary = {}
var _climb_t := 0.0
var _dismount := -1.0
var control := true
var focus: Interactable = null
var _shake := 0.0
var _bob := 0.0
var _step_acc := 0.0
var _swing := -1.0
var _swing_hit := false
var _hurt_flash := 0.0
var cine_offset := Vector3.ZERO     # intro camera offsets
var cine_rot := Vector3.ZERO
var _sensor: Area3D
var axe_view: Node3D
var lantern_view: Node3D
var lantern_light: OmniLight3D
var shovel_view: Node3D
var _was_floor := true
var _fall_speed := 0.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	platform_floor_layers = 0
	platform_wall_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	_sensor = Area3D.new()
	_sensor.collision_layer = 0
	_sensor.collision_mask = 32
	var ss := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.35
	ss.shape = sph
	ss.position.y = 0.6
	_sensor.add_child(ss)
	add_child(_sensor)
	cam = Camera3D.new()
	cam.top_level = true
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.near = 0.05
	cam.far = 900.0
	cam.fov = float(Settings.v["fov"])
	add_child(cam)
	cam.current = true
	_build_viewmodels()
	Settings.changed.connect(func() -> void: cam.fov = float(Settings.v["fov"]))

func _build_viewmodels() -> void:
	axe_view = Node3D.new()
	cam.add_child(axe_view)
	var axe := MeshInstance3D.new()
	axe.mesh = Props.axe_mesh()
	axe.position = Vector3(0, -0.55, 0)
	axe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	axe_view.add_child(axe)
	axe_view.position = Vector3(0.36, -0.22, -0.55)
	axe_view.rotation = Vector3(0.25, -0.5, -0.15)
	axe_view.visible = false
	lantern_view = Node3D.new()
	cam.add_child(lantern_view)
	var lm := MeshInstance3D.new()
	lm.mesh = Props.lantern_mesh()
	lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern_view.add_child(lm)
	lantern_view.position = Vector3(-0.32, -0.42, -0.55)
	lantern_light = OmniLight3D.new()
	lantern_light.light_color = Color(1.0, 0.68, 0.38)
	lantern_light.light_energy = 1.3
	lantern_light.omni_range = 11.0
	lantern_light.omni_attenuation = 1.2
	lantern_light.light_volumetric_fog_energy = 0.3
	lantern_light.position = Vector3(0, 0.15, 0)
	lantern_view.add_child(lantern_light)
	lantern_view.visible = false
	shovel_view = Node3D.new()
	cam.add_child(shovel_view)
	var sm := MeshInstance3D.new()
	sm.mesh = Props.shovel_mesh()
	sm.rotation = Vector3(-1.2, 0, 0)
	shovel_view.add_child(sm)
	shovel_view.position = Vector3(0.1, -0.5, -0.4)
	shovel_view.visible = false

func teleport(p: Vector3, face_yaw: float) -> void:
	global_position = p
	velocity = Vector3.ZERO
	yaw = face_yaw
	pitch = 0.0
	climbing = false
	_dismount = -1.0
	reset_physics_interpolation()

func _unhandled_input(event: InputEvent) -> void:
	if not control or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		var s := Settings.mouse_sens()
		yaw -= m.relative.x * s
		pitch -= m.relative.y * s * (-1.0 if Settings.v["invert_y"] else 1.0)
		pitch = clampf(pitch, -1.45, 1.45)

func give_axe() -> void:
	has_axe = true
	axe_view.visible = true
	Sfx.play("pickup", 0.0, 0.8)
	world.hud.message("Axe taken. [Left Mouse] to swing.", 3.5)

func give_lantern() -> void:
	has_lantern = true
	lantern_on = true
	lantern_view.visible = true
	Sfx.play("pickup")
	world.hud.message("Storm lantern. [F] to cover or uncover it.", 3.5)

func add_shake(a: float) -> void:
	_shake = maxf(_shake, a)

func heal(n: float) -> void:
	health = minf(100.0, health + n)
	Sfx.play("heal")

func take_damage(n: float) -> void:
	if health <= 0.0:
		return
	health = maxf(0.0, health - n)
	_hurt_flash = 1.0
	add_shake(0.9)
	Sfx.play("hit", 2.0)
	world.hud.hurt()
	if health <= 0.0:
		world.on_player_died()

func anim_shovel() -> void:
	shovel_view.visible = true
	axe_view.visible = false
	var tw := create_tween()
	shovel_view.position = Vector3(0.1, -0.5, -0.4)
	tw.tween_property(shovel_view, "position", Vector3(0.0, -0.35, -0.85), 0.3).set_trans(Tween.TRANS_BACK)
	tw.tween_property(shovel_view, "position", Vector3(0.1, -0.6, -0.4), 0.35)
	tw.tween_callback(func() -> void:
		shovel_view.visible = false
		axe_view.visible = has_axe)

func start_climb(area: Area3D) -> void:
	if climbing or not area.has_meta("ladder"):
		return
	_ladder = area.get_meta("ladder")
	var car: Node3D = _ladder["car"]
	var lp: Vector3 = car.global_transform.affine_inverse() * global_position
	var b: Vector3 = _ladder["bottom"]
	var t: Vector3 = _ladder["top"]
	if lp.y > t.y - 0.3:
		# standing on the deck: climb down from the top
		_climb_t = 1.0
	else:
		_climb_t = clampf((lp.y - b.y) / (t.y - b.y), 0.0, 1.0)
	climbing = true
	_dismount = -1.0
	attached = car
	velocity = Vector3.ZERO
	Sfx.play("ladder", -4.0)

func _physics_process(dt: float) -> void:
	# ride the train: apply the car's motion since last tick
	if attached and is_instance_valid(attached) and attached.has_meta("prev") and not climbing:
		var prev: Transform3D = attached.get_meta("prev")
		var delta_xf: Transform3D = attached.global_transform * prev.affine_inverse()
		global_position = delta_xf * global_position
		yaw += delta_xf.basis.get_euler().y
	if climbing:
		_climb(dt)
	else:
		_move(dt)
	_update_focus()
	if control:
		if Input.is_action_just_pressed("interact") and focus:
			focus.use(self)
		if Input.is_action_just_pressed("interact_alt") and focus:
			focus.alt(self)
		if Input.is_action_just_pressed("attack") and has_axe and _swing < 0.0 and not climbing:
			_swing = 0.0
			_swing_hit = false
			Sfx.play("axe_swing", -2.0, randf_range(0.9, 1.1))
		if Input.is_action_just_pressed("lantern") and has_lantern:
			lantern_on = not lantern_on
			Sfx.play("lever", -10.0, 1.6)
	_update_swing(dt)

func _move(dt: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if control else Vector2.ZERO
	var basis := Basis(Vector3.UP, yaw)
	var wish := basis * Vector3(input.x, 0, input.y)
	var speed := SPRINT if Input.is_action_pressed("sprint") else WALK
	if carried_coal > 0:
		speed *= 0.82
	var hv := Vector3(velocity.x, 0, velocity.z)
	var acc := ACCEL if is_on_floor() else ACCEL * 0.25
	hv = hv.move_toward(wish * speed, acc * speed * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		if control and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
		else:
			velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * dt
	_fall_speed = -velocity.y
	move_and_slide()
	# what are we standing on?
	if is_on_floor():
		_air_time = 0.0
		var fc := _floor_collider()
		attached = fc if fc and fc.has_meta("car") else null
		if not _was_floor and _fall_speed > 4.0:
			Sfx.play("land", -4.0)
			add_shake(0.15)
	else:
		_air_time += dt
		if _air_time > 0.8:
			attached = null
	_was_floor = is_on_floor()
	# walk into a ladder holding forward
	if control and input.y < -0.5:
		for a in _sensor.get_overlapping_areas():
			if a.has_meta("ladder"):
				var out: Vector3 = (a.get_meta("ladder")["car"] as Node3D).global_transform.basis * a.get_meta("ladder")["out"]
				var look := -(basis.z)
				if look.dot(-out) > 0.35:
					start_climb(a)
					break
	# footsteps
	if is_on_floor() and hv.length() > 0.5:
		_step_acc += hv.length() * dt
		_bob += hv.length() * dt * 2.2
		var stride := 0.95 if speed > WALK else 0.75
		if _step_acc > stride:
			_step_acc = 0.0
			_footstep()
	else:
		_bob = lerpf(_bob, round(_bob / PI) * PI, dt * 4.0)

func _floor_collider() -> Node:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y > 0.6:
			return c.get_collider() as Node
	return null

func _footstep() -> void:
	var surf := "grass"
	var fc := _floor_collider()
	if fc and fc.has_meta("surface"):
		surf = fc.get_meta("surface")
	if surf == "terrain":
		surf = "gravel" if Track.dist_to_track(global_position.x, global_position.z) < 2.8 else "grass"
	match surf:
		"wood": Sfx.play(Sfx.variant("step_wood", 4), -6.0, randf_range(0.9, 1.1))
		"metal": Sfx.play(Sfx.variant("step_metal", 3), -7.0, randf_range(0.9, 1.1))
		"gravel": Sfx.play(Sfx.variant("step_gravel", 3), -6.0, randf_range(0.9, 1.1))
		_: Sfx.play(Sfx.variant("step_grass", 4), -5.0, randf_range(0.9, 1.1))

func _climb(dt: float) -> void:
	var car: Node3D = _ladder["car"]
	if not is_instance_valid(car):
		climbing = false
		return
	var xf := car.global_transform
	var b: Vector3 = _ladder["bottom"]
	var t: Vector3 = _ladder["top"]
	var ex: Vector3 = _ladder["exit"]
	attached = car
	velocity = Vector3.ZERO
	if _dismount >= 0.0:
		_dismount += dt / 0.4
		var s := clampf(_dismount, 0.0, 1.0)
		var p := t.lerp(ex, s)
		p.y = t.y + sin(s * PI) * 0.15 + 0.05
		global_position = xf * p
		if _dismount >= 1.0:
			climbing = false
			_dismount = -1.0
			global_position = xf * ex
		return
	var up := 0.0
	if control:
		up = -Input.get_vector("move_left", "move_right", "move_forward", "move_back").y
	var prev_t := _climb_t
	_climb_t = clampf(_climb_t + up * 2.4 * dt / (t.y - b.y), 0.0, 1.0)
	if int(prev_t * 6.0) != int(_climb_t * 6.0):
		Sfx.play("ladder", -6.0, randf_range(0.9, 1.1))
	global_position = xf * b.lerp(t, _climb_t)
	_bob += absf(up) * dt * 3.0
	if _climb_t >= 1.0 and up > 0.0:
		_dismount = 0.0
	elif _climb_t <= 0.0 and up < 0.0:
		climbing = false
		var out: Vector3 = xf.basis * _ladder["out"]
		global_position += out * 0.15
	elif control and Input.is_action_just_pressed("jump"):
		climbing = false
		velocity = (xf.basis * _ladder["out"]) * 2.5 + Vector3.UP * 1.5

func _update_focus() -> void:
	focus = null
	if not control:
		return
	var from := cam.global_position
	var to := from - cam.global_basis.z * 2.7
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | Interactable.LAYER)
	q.collide_with_areas = true
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider is Interactable:
		var it := hit.collider as Interactable
		if it.prompt() != "":
			focus = it

func _update_swing(dt: float) -> void:
	if _swing < 0.0:
		return
	_swing += dt
	var T := 0.55
	var k := _swing / T
	# wind up, strike, recover
	var a: float
	if k < 0.3:
		a = lerpf(0.0, -1.0, k / 0.3)
	elif k < 0.45:
		a = lerpf(-1.0, 1.1, (k - 0.3) / 0.15)
	else:
		a = lerpf(1.1, 0.0, (k - 0.45) / 0.55)
	axe_view.rotation = Vector3(0.25 - a * 0.9, -0.5 + a * 0.25, -0.15 - a * 0.3)
	axe_view.position = Vector3(0.36 - a * 0.12, -0.22 + a * 0.05, -0.55 - maxf(a, 0.0) * 0.2)
	if k >= 0.42 and not _swing_hit:
		_swing_hit = true
		_axe_hit()
	if _swing >= T:
		_swing = -1.0

func _axe_hit() -> void:
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.6, 1 | 2 | 16)
	q.exclude = [get_rid()]
	q.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		var c: Object = hit.collider
		if c.has_meta("chop"):
			c.get_meta("chop").chop(hit.position)
			add_shake(0.2)
		elif c.has_meta("creature"):
			c.get_meta("creature").struck()
		else:
			Sfx.play_at("axe_chop", hit.position, -8.0, 1.4, 20.0)

func _process(dt: float) -> void:
	_shake = maxf(0.0, _shake - dt * 1.6)
	_hurt_flash = maxf(0.0, _hurt_flash - dt)
	var base := get_global_transform_interpolated().origin
	var bob_y := sin(_bob * 2.0) * 0.035 if not climbing else sin(_bob * 2.0) * 0.02
	var bob_x := cos(_bob) * 0.025
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.06
	var basis := Basis.from_euler(Vector3(pitch + cine_rot.x, yaw + cine_rot.y, cine_rot.z))
	cam.global_basis = basis
	cam.global_position = base + Vector3(0, EYE, 0) + basis * Vector3(bob_x, bob_y, 0) + sh + cine_offset
	# viewmodel sway
	if lantern_view:
		lantern_view.visible = has_lantern
		lantern_light.visible = lantern_on
		lantern_light.light_energy = (1.25 + sin(Time.get_ticks_msec() * 0.011) * 0.06) if lantern_on else 0.0
		lantern_view.position = Vector3(-0.32, -0.42 + bob_y * 0.6, -0.55)
	if axe_view and _swing < 0.0 and has_axe:
		axe_view.position = Vector3(0.36 + bob_x * 0.5, -0.22 + bob_y * 0.8, -0.55)
