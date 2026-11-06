class_name Train
extends Node3D
## The locomotive, tender and passenger carriage: geometry, controls, steam
## model, movement along the line, feedback and sounds.

signal started
signal stopped
signal crashed(speed: float)
signal impact(speed: float)
signal whistled

const CAR_OFFSETS := {"loco": 0.0, "tender": 8.6, "carriage": 19.3}
const FLOOR := 1.55
const FRONT := 6.0           # nose distance ahead of the loco centre
const COAL_PER_SHOVEL := 22.0
const TENDER_MAX := 14
const MAX_NOTCH := 4

var world: Node
var d := 0.0
var v := 0.0
var fire := 0.0
var pressure := 0.0
var throttle := 0
var brake := true
var brake_force := 1.0
var tender_coal := 6
var coal_burned := 0
var moving := false
var auto_brake_reason := ""
var whistle_cd := 0.0
var shovel_cd := 0.0
var _chuff_acc := 0.0
var _clack_acc := 0.0
var _creak_t := 6.0
var _wheel_angle := 0.0
var _hiss_burst := 0.0

var cars := {}               # name -> AnimatableBody3D
var wheels: Array = []       # [Node3D, radius]
var rods: Array = []         # [MeshInstance3D, base position]
var fire_light: OmniLight3D
var fire_mat: StandardMaterial3D
var fire_door: Node3D
var speed_needle: Node3D
var pressure_needle: Node3D
var regulator: Node3D
var brake_lever: Node3D
var whistle_handle: Node3D
var axe_prop: Node3D
var coal_pile: Node3D
var headlamp: SpotLight3D
var smoke: GPUParticles3D
var steam_burst: GPUParticles3D
var whistle_steam: GPUParticles3D
var carriage_lights: Array = []
var snd_rumble: AudioStreamPlayer3D
var snd_hiss: AudioStreamPlayer3D
var snd_fire: AudioStreamPlayer3D
var snd_cab: Node3D

func _init() -> void:
	process_physics_priority = -10

func setup(w: Node) -> void:
	world = w
	for n in CAR_OFFSETS:
		var body := AnimatableBody3D.new()
		body.name = n.capitalize()
		body.sync_to_physics = false
		body.collision_layer = 2
		body.collision_mask = 0
		body.set_meta("car", true)
		body.set_meta("surface", "metal" if n != "carriage" else "wood")
		add_child(body)
		cars[n] = body
	_build_loco(cars["loco"])
	_build_tender(cars["tender"])
	_build_carriage(cars["carriage"])
	_place_cars()
	for n in cars:
		cars[n].set_meta("prev", cars[n].global_transform)
		cars[n].reset_physics_interpolation()
	Settings.changed.connect(_apply_settings)
	_apply_settings()

func _apply_settings() -> void:
	if fire_light:
		Settings.configure_light(fire_light, true)
	if headlamp:
		headlamp.shadow_enabled = int(Settings.v["shadows"]) == 2
	for l in carriage_lights:
		Settings.configure_light(l, false)

# ------------------------------------------------------------------ geometry

func _wheel(parent: Node3D, pos: Vector3, r: float, spokes := true) -> Node3D:
	var key := "wheel%.2f" % r
	var mesh := Props.cached(key, func() -> Mesh:
		var mk := MK.new()
		var b := Basis(Vector3.FORWARD, PI / 2)
		mk.cyl("iron", Transform3D(b, Vector3(0.06, 0, 0)), r, r, 0.12, 14, Color(0.13, 0.13, 0.14))
		mk.cyl("metal", Transform3D(b, Vector3(0.075, 0, 0)), r * 0.28, r * 0.28, 0.15, 8, Color(0.3, 0.3, 0.3))
		if spokes:
			for i in 6:
				var a := TAU * i / 6.0
				mk.box("metal", Transform3D(Basis(Vector3.RIGHT, a), Vector3(-0.08, 0, 0)), Vector3(0.04, r * 1.7, 0.06), Color(0.24, 0.24, 0.25))
		mk.boxp("metal", Vector3(-0.1, r * 0.6, 0), Vector3(0.06, 0.08, 0.08), Color(0.5, 0.5, 0.5))
		return mk.commit())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if pos.x < 0:
		mi.rotation.y = PI
	parent.add_child(mi)
	wheels.append([mi, r])
	return mi

func _col(body: Node3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)

func _ladder(car: AnimatableBody3D, x: float, z: float, mk: MK) -> void:
	var s := signf(x)
	for rz: float in [-0.22, 0.22]:
		mk.boxp("metal", Vector3(x, (FLOOR - 0.35) * 0.5 + 0.1, z + rz), Vector3(0.05, FLOOR + 0.6, 0.05), Color(0.2, 0.2, 0.21))
	var y := -0.25
	while y < FLOOR:
		mk.boxp("metal", Vector3(x, y, z), Vector3(0.05, 0.04, 0.44), Color(0.3, 0.3, 0.3))
		y += 0.3
	# grab handles above the deck
	mk.boxp("metal", Vector3(x, FLOOR + 0.5, z - 0.3), Vector3(0.04, 1.0, 0.04), Color(0.35, 0.35, 0.35))
	var area := Area3D.new()
	area.collision_layer = 32
	area.collision_mask = 0
	area.monitoring = false
	area.position = Vector3(x + s * 0.25, 0.7, z)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.1, 3.4, 1.0)
	cs.shape = sh
	area.add_child(cs)
	area.set_meta("ladder", {"car": car, "bottom": Vector3(x + s * 0.36, -0.35, z), "top": Vector3(x + s * 0.36, FLOOR, z),
		"exit": Vector3(x - s * 0.55, FLOOR + 0.05, z), "out": Vector3(s, 0, 0)})
	car.add_child(area)
	Interactable.make(car, Vector3(x + s * 0.05, FLOOR - 0.3, z), Vector3(0.25, 1.4, 0.6),
		func() -> String: return "[E] Climb the ladder   (or walk into it holding W)",
		func(p) -> void: p.start_climb(area))

func _build_loco(body: AnimatableBody3D) -> void:
	var mk := MK.new()
	var black := Color(0.1, 0.1, 0.105)
	var dark := Color(0.15, 0.15, 0.16)
	var brass := Color(0.55, 0.45, 0.28)
	# frame and running boards
	mk.boxp("iron", Vector3(0, 0.95, -0.2), Vector3(2.0, 0.35, 11.4), black)
	mk.boxp("metal", Vector3(0, 1.22, -2.0), Vector3(2.9, 0.06, 7.2), dark)
	for s: float in [-1, 1]:
		mk.boxp("metal", Vector3(s * 1.45, 1.1, -2.0), Vector3(0.05, 0.2, 7.2), Color(0.3, 0.3, 0.3))
	# boiler
	var bz := Basis(Vector3.RIGHT, -PI / 2)
	mk.cyl("metal", Transform3D(bz, Vector3(0, 2.15, 1.5)), 0.86, 0.86, 5.9, 14, Color(0.12, 0.12, 0.13))
	for bz_i: float in [0.8, -1.0, -2.8]:
		mk.cyl("metal", Transform3D(bz, Vector3(0, 2.15, bz_i)), 0.88, 0.88, 0.08, 14, brass)
	mk.cyl("iron", Transform3D(bz, Vector3(0, 2.15, -4.4)), 0.9, 0.9, 0.95, 14, black)
	mk.cyl("iron", Transform3D(bz, Vector3(0, 2.15, -5.35)), 0.6, 0.55, 0.06, 12, Color(0.18, 0.18, 0.19))
	mk.cyl("iron", Transform3D(Basis(), Vector3(0, 2.9, -4.8)), 0.24, 0.32, 1.15, 10, black)
	mk.cyl("iron", Transform3D(Basis(), Vector3(0, 4.0, -4.8)), 0.36, 0.36, 0.12, 10, black)
	mk.cyl("metal", Transform3D(Basis(), Vector3(0, 2.9, -2.2)), 0.38, 0.32, 0.45, 10, brass)
	mk.blob("metal", Transform3D(Basis.from_scale(Vector3(1, 0.5, 1)), Vector3(0, 3.35, -2.2)), 0.32, brass, 0.0, 1, 3, 10)
	mk.cyl("metal", Transform3D(Basis(), Vector3(0, 2.9, -0.4)), 0.3, 0.26, 0.35, 10, dark)
	mk.cyl("metal", Transform3D(Basis(), Vector3(0.3, 2.95, 0.9)), 0.06, 0.05, 0.4, 6, brass)  # whistle
	# smoke deflector-ish plates, buffers, cowcatcher
	mk.boxp("iron", Vector3(0, 1.0, -5.75), Vector3(2.6, 0.35, 0.2), Color(0.35, 0.12, 0.1))
	for s: float in [-0.8, 0.8]:
		mk.cyl("iron", Transform3D(bz, Vector3(s, 1.0, -5.8)), 0.12, 0.12, 0.35, 8, Color(0.4, 0.4, 0.4))
	for i in 7:
		var x := -0.9 + i * 0.3
		mk.box("iron", Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(x, 0.55, -6.05)), Vector3(0.08, 0.06, 0.95), black)
	# cylinders
	for s: float in [-1, 1]:
		mk.cyl("iron", Transform3D(bz, Vector3(s * 1.12, 0.95, -3.4)), 0.3, 0.3, 1.2, 10, dark)
	# headlamp
	mk.boxp("iron", Vector3(0, 2.95, -5.45), Vector3(0.45, 0.45, 0.4), black)
	mk.boxp("lamp_white", Vector3(0, 2.95, -5.66), Vector3(0.3, 0.3, 0.02), Color.WHITE)
	# cab
	var cz := 3.65
	mk.boxp("metal", Vector3(0, FLOOR - 0.05, cz + 0.2), Vector3(2.9, 0.1, 4.7), Color(0.2, 0.2, 0.2))
	# backhead with spectacle windows either side of the boiler
	mk.boxp("iron", Vector3(0, FLOOR + 1.15, 1.5), Vector3(1.2, 2.35, 0.1), black)
	for s in [-1, 1]:
		mk.boxp("iron", Vector3(s * 1.0, FLOOR + 0.62, 1.5), Vector3(0.8, 1.24, 0.1), black)
		mk.boxp("iron", Vector3(s * 1.0, FLOOR + 2.21, 1.5), Vector3(0.8, 0.22, 0.1), black)
		mk.boxp("iron", Vector3(s * 1.36, FLOOR + 1.7, 1.5), Vector3(0.08, 1.0, 0.1), black)
		mk.boxp("metal", Vector3(s * 0.98, FLOOR + 1.25, 1.52), Vector3(0.74, 0.03, 0.06), Color(0.5, 0.45, 0.3))
	for s: float in [-1, 1]:
		mk.boxp("iron", Vector3(s * 1.4, FLOOR + 0.55, 2.8), Vector3(0.08, 1.1, 2.6), black)
		mk.boxp("iron", Vector3(s * 1.4, FLOOR + 2.1, 2.8), Vector3(0.08, 0.5, 2.6), black)
		for pz: float in [1.55, 2.8, 4.08]:
			mk.boxp("iron", Vector3(s * 1.4, FLOOR + 1.2, pz), Vector3(0.1, 2.4, 0.1), black)
		mk.boxp("iron", Vector3(s * 1.4, FLOOR + 1.2, 5.45), Vector3(0.1, 2.4, 0.1), black)
		mk.boxp("metal", Vector3(s * 1.36, FLOOR + 1.0, 4.75), Vector3(0.04, 0.04, 1.2), Color(0.4, 0.4, 0.4))  # grab rail
	mk.boxp("iron", Vector3(0, FLOOR + 2.42, cz), Vector3(3.1, 0.08, 4.5), black)
	mk.boxp("iron", Vector3(0, FLOOR + 2.5, cz), Vector3(2.0, 0.08, 4.3), Color(0.08, 0.08, 0.09))
	# cab details: gauges back plates, pipes, shelf, shovel
	mk.cyl("metal", Transform3D(bz.rotated(Vector3.UP, PI), Vector3(-0.45, FLOOR + 1.55, 1.56)), 0.17, 0.17, 0.05, 12, brass)
	mk.cyl("metal", Transform3D(bz.rotated(Vector3.UP, PI), Vector3(0.45, FLOOR + 1.55, 1.56)), 0.17, 0.17, 0.05, 12, brass)
	mk.cyl("metal", Transform3D(bz.rotated(Vector3.UP, PI), Vector3(0, FLOOR + 0.65, 1.56)), 0.42, 0.42, 0.05, 12, Color(0.2, 0.2, 0.2))
	mk.cyl_between("metal", Vector3(-1.2, FLOOR + 2.2, 1.6), Vector3(1.2, FLOOR + 2.2, 1.6), 0.04, 0.04, 6, brass)
	mk.cyl_between("metal", Vector3(0.95, FLOOR + 0.2, 1.6), Vector3(0.95, FLOOR + 2.2, 1.6), 0.035, 0.035, 6, brass)
	mk.boxp("wood", Vector3(-1.1, FLOOR + 0.45, 2.3), Vector3(0.5, 0.06, 0.8), Color(0.3, 0.27, 0.22))   # driver seat
	mk.boxp("wood", Vector3(1.1, FLOOR + 0.45, 2.3), Vector3(0.5, 0.06, 0.8), Color(0.3, 0.27, 0.22))
	_ladder(body, 1.45, 4.75, mk)
	_ladder(body, -1.45, 4.75, mk)
	mk.build(body, "Loco", true)
	# colliders
	_col(body, Vector3(0, FLOOR - 0.06, cz + 0.2), Vector3(2.9, 0.12, 4.7))       # cab floor + fall plate
	_col(body, Vector3(0, FLOOR + 1.15, 1.45), Vector3(2.8, 2.4, 0.2))
	for s: float in [-1, 1]:
		_col(body, Vector3(s * 1.42, FLOOR + 1.2, 2.8), Vector3(0.12, 2.4, 2.6))
		_col(body, Vector3(s * 1.42, FLOOR + 1.2, 5.45), Vector3(0.12, 2.4, 0.12))
	_col(body, Vector3(0, FLOOR + 2.45, cz), Vector3(3.0, 0.1, 4.5))
	_col(body, Vector3(0, 2.15, -1.8), Vector3(1.8, 1.8, 7.0))   # boiler
	_col(body, Vector3(0, 0.9, -0.2), Vector3(2.4, 0.9, 11.4))   # frame
	_col(body, Vector3(0, 1.22, -2.0), Vector3(2.9, 0.1, 7.2))
	# wheels and rods
	for s: float in [-1.0, 1.0]:
		for z: float in [-2.2, -0.6, 1.0]:
			_wheel(body, Vector3(s * 1.02, 0.75, z), 0.75)
		for z: float in [-4.7, -3.9]:
			_wheel(body, Vector3(s * 0.95, 0.42, z), 0.42, false)
		var rod := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.06, 0.1, 3.4)
		bm.material = Mats.get_mat("metal")
		rod.mesh = bm
		rod.position = Vector3(s * 1.15, 0.75, -0.6)
		body.add_child(rod)
		rods.append([rod, rod.position])
	# firebox door, glow, fire light
	fire_mat = Mats.emissive(Color(1.0, 0.42, 0.1), 0.5)
	var glow := MeshInstance3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(0.55, 0.42)
	glow.mesh = qm
	glow.material_override = fire_mat
	glow.position = Vector3(0, FLOOR + 0.65, 1.585)
	body.add_child(glow)
	fire_door = Node3D.new()
	fire_door.position = Vector3(-0.3, FLOOR + 0.65, 1.62)
	body.add_child(fire_door)
	var door_mk := MK.new()
	door_mk.boxp("iron", Vector3(0.3, 0, 0.0), Vector3(0.6, 0.48, 0.04), Color(0.14, 0.14, 0.15))
	door_mk.boxp("metal", Vector3(0.52, 0, 0.04), Vector3(0.05, 0.05, 0.08), Color(0.5, 0.45, 0.3))
	door_mk.build(fire_door, "Door", false)
	var slits := MeshInstance3D.new()
	var sq := QuadMesh.new(); sq.size = Vector2(0.4, 0.05)
	slits.mesh = sq
	slits.material_override = fire_mat
	slits.position = Vector3(0.3, -0.1, 0.025)
	fire_door.add_child(slits)
	fire_light = Props.omni(Color(1.0, 0.52, 0.22), 0.6, 7.5, true)
	fire_light.position = Vector3(0, FLOOR + 0.8, 2.1)
	fire_light.distance_fade_enabled = false
	body.add_child(fire_light)
	var cab_lamp := Props.omni(Color(1.0, 0.7, 0.4), 0.5, 4.0)
	cab_lamp.position = Vector3(0.9, FLOOR + 2.0, 4.6)
	body.add_child(cab_lamp)
	var cl := MeshInstance3D.new()
	cl.mesh = Props.lantern_mesh()
	cl.position = Vector3(0.9, FLOOR + 1.95, 4.6)
	body.add_child(cl)
	# gauges
	speed_needle = _needle(body, Vector3(0.45, FLOOR + 1.55, 1.6))
	pressure_needle = _needle(body, Vector3(-0.45, FLOOR + 1.55, 1.6))
	var lbl1 := Props.label("SPEED", 28, Color(0.75, 0.7, 0.6), false, 0.0025)
	lbl1.position = Vector3(0.45, FLOOR + 1.3, 1.6)
	body.add_child(lbl1)
	var lbl2 := Props.label("STEAM", 28, Color(0.75, 0.7, 0.6), false, 0.0025)
	lbl2.position = Vector3(-0.45, FLOOR + 1.3, 1.6)
	body.add_child(lbl2)
	# regulator
	regulator = Node3D.new()
	regulator.position = Vector3(0.62, FLOOR + 1.05, 1.62)
	body.add_child(regulator)
	var rmk := MK.new()
	rmk.cyl("metal", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.02)), 0.06, 0.06, 0.1, 8, Color(0.5, 0.45, 0.3))
	rmk.boxp("metal", Vector3(0, -0.22, 0.08), Vector3(0.05, 0.45, 0.04), Color(0.45, 0.45, 0.45))
	rmk.boxp("wood", Vector3(0, -0.45, 0.12), Vector3(0.07, 0.12, 0.12), Color(0.35, 0.12, 0.1))
	rmk.build(regulator, "Reg", false)
	var reg_lbl := Props.label("REGULATOR", 24, Color(0.75, 0.7, 0.6), false, 0.0022)
	reg_lbl.position = Vector3(0.62, FLOOR + 1.2, 1.6)
	body.add_child(reg_lbl)
	Interactable.make(body, Vector3(0.62, FLOOR + 0.85, 1.75), Vector3(0.4, 0.6, 0.3), _regulator_prompt, func(_p) -> void: set_notch(throttle + 1), func(_p) -> void: set_notch(throttle - 1))
	# brake lever (left wall)
	brake_lever = Node3D.new()
	brake_lever.position = Vector3(-1.3, FLOOR + 0.6, 2.6)
	body.add_child(brake_lever)
	var bmk := MK.new()
	bmk.boxp("metal", Vector3(0, 0.3, 0), Vector3(0.05, 0.6, 0.05), Color(0.45, 0.45, 0.45))
	bmk.boxp("wood", Vector3(0, 0.62, 0), Vector3(0.1, 0.1, 0.14), Color(0.35, 0.12, 0.1))
	bmk.build(brake_lever, "Brake", false)
	var brk_lbl := Props.label("BRAKE", 26, Color(0.75, 0.7, 0.6), false, 0.0025)
	brk_lbl.position = Vector3(-1.34, FLOOR + 1.0, 2.6)
	brk_lbl.rotation.y = PI / 2
	body.add_child(brk_lbl)
	Interactable.make(body, Vector3(-1.2, FLOOR + 1.0, 2.6), Vector3(0.35, 0.7, 0.5), _brake_prompt, func(_p) -> void: toggle_brake())
	# whistle pull
	whistle_handle = Node3D.new()
	whistle_handle.position = Vector3(0.25, FLOOR + 1.85, 2.05)
	body.add_child(whistle_handle)
	var wmk := MK.new()
	wmk.cyl("plain", Transform3D(), 0.008, 0.008, 0.55, 3, Color(0.2, 0.2, 0.2), false)
	wmk.boxp("wood", Vector3(0, -0.02, 0), Vector3(0.16, 0.04, 0.04), Color(0.4, 0.33, 0.25))
	wmk.build(whistle_handle, "Pull", false)
	Interactable.make(body, Vector3(0.25, FLOOR + 1.85, 2.05), Vector3(0.35, 0.35, 0.35), _whistle_prompt, func(_p) -> void: blow_whistle())
	# firebox
	Interactable.make(body, Vector3(0, FLOOR + 0.65, 1.75), Vector3(0.75, 0.6, 0.3), _firebox_prompt, func(p) -> void: shovel(p))
	# axe on the left wall
	axe_prop = MeshInstance3D.new()
	(axe_prop as MeshInstance3D).mesh = Props.axe_mesh()
	axe_prop.position = Vector3(-1.33, FLOOR + 0.9, 3.7)
	axe_prop.rotation = Vector3(0.3, PI / 2, 0)
	body.add_child(axe_prop)
	Interactable.make(body, Vector3(-1.2, FLOOR + 1.2, 3.75), Vector3(0.35, 0.8, 0.5),
		func() -> String: return "[E] Take the axe" if axe_prop.visible else "",
		func(p) -> void:
			if axe_prop.visible:
				axe_prop.visible = false
				p.give_axe())
	var shov := MeshInstance3D.new()
	shov.mesh = Props.shovel_mesh()
	shov.position = Vector3(1.15, FLOOR + 0.25, 1.75)
	shov.rotation = Vector3(-0.2, 0, 0.25)
	body.add_child(shov)
	# headlamp
	headlamp = SpotLight3D.new()
	headlamp.position = Vector3(0, 2.95, -5.7)
	headlamp.light_color = Color(1.0, 0.86, 0.66)
	headlamp.light_energy = 5.0
	headlamp.spot_range = 75.0
	headlamp.spot_angle = 24.0
	headlamp.spot_attenuation = 0.7
	headlamp.light_volumetric_fog_energy = 1.5
	headlamp.rotation.x = -0.05
	body.add_child(headlamp)
	# smoke from the chimney, steam bursts
	smoke = _particles(body, Vector3(0, 4.15, -4.8), 70, 6.0, Color(0.3, 0.3, 0.31, 0.6), 2.8, Vector3(0, 0.7, 0), 1.2)
	steam_burst = _particles(body, Vector3(0, 0.9, -3.6), 40, 1.6, Color(0.85, 0.85, 0.86, 0.5), 3.0, Vector3(0, 0.3, 0), 0.8)
	(steam_burst.process_material as ParticleProcessMaterial).direction = Vector3(1, 0.2, 0)
	(steam_burst.process_material as ParticleProcessMaterial).spread = 180.0
	steam_burst.emitting = false
	steam_burst.one_shot = true
	steam_burst.explosiveness = 0.7
	whistle_steam = _particles(body, Vector3(0.3, 3.4, 0.9), 30, 1.4, Color(0.9, 0.9, 0.9, 0.55), 2.2, Vector3(0, 1.0, 0), 0.5)
	whistle_steam.emitting = false
	# sounds
	snd_rumble = Sfx.loop_3d("train_rumble", body, Vector3(0, 0.5, 2.0), 90.0)
	snd_hiss = Sfx.loop_3d("steam_hiss", body, Vector3(0, 1.0, -2.0), 40.0)
	snd_fire = Sfx.loop_3d("furnace_fire", body, Vector3(0, FLOOR + 0.6, 1.8), 14.0)
	snd_cab = Node3D.new()
	snd_cab.position = Vector3(0, FLOOR + 1.5, 2.5)
	body.add_child(snd_cab)

func _needle(body: Node3D, pos: Vector3) -> Node3D:
	var face := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.15; cm.bottom_radius = 0.15; cm.height = 0.01; cm.radial_segments = 16
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.85, 0.82, 0.74); fm.roughness = 0.6
	cm.material = fm
	face.mesh = cm
	face.rotation.x = PI / 2
	face.position = pos + Vector3(0, 0, 0.01)
	body.add_child(face)
	var pivot := Node3D.new()
	pivot.position = pos + Vector3(0, 0, 0.025)
	body.add_child(pivot)
	var n := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.012, 0.12, 0.005)
	var nm := StandardMaterial3D.new(); nm.albedo_color = Color(0.5, 0.06, 0.05)
	bm.material = nm
	n.mesh = bm
	n.position = Vector3(0, 0.05, 0)
	pivot.add_child(n)
	for i in 9:
		var t := MeshInstance3D.new()
		var tb := BoxMesh.new(); tb.size = Vector3(0.006, 0.025, 0.004)
		var tm := StandardMaterial3D.new(); tm.albedo_color = Color(0.1, 0.1, 0.1)
		tb.material = tm
		t.mesh = tb
		var a := deg_to_rad(-120.0 + i * 30.0)
		t.position = pos + Vector3(sin(a) * 0.125, cos(a) * 0.125, 0.018)
		t.rotation.z = -a
		body.add_child(t)
	return pivot

func _particles(parent: Node3D, pos: Vector3, amount: int, life: float, col: Color, size: float, grav: Vector3, vel: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = vel * 1.5
	pm.initial_velocity_max = vel * 3.0
	pm.gravity = grav
	pm.damping_min = 0.8
	pm.damping_max = 1.6
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new(); sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r * 1.2, col.g * 1.2, col.b * 1.2, 0.0))
	g.add_point(0.15, col)
	var gt := GradientTexture1D.new(); gt.gradient = g
	pm.color_ramp = gt
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_receive_shadows = true
	var rg := Gradient.new()
	rg.set_color(0, Color(1, 1, 1, 1))
	rg.set_color(1, Color(1, 1, 1, 0))
	var rt := GradientTexture2D.new()
	rt.gradient = rg
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5)
	rt.fill_to = Vector2(0.5, 0.0)
	rt.width = 64; rt.height = 64
	m.albedo_texture = rt
	qm.material = m
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p

func _build_tender(body: AnimatableBody3D) -> void:
	var mk := MK.new()
	var black := Color(0.1, 0.1, 0.105)
	mk.boxp("iron", Vector3(0, 0.95, 0), Vector3(2.0, 0.35, 5.0), black)
	mk.boxp("metal", Vector3(0, FLOOR - 0.05, 0), Vector3(2.9, 0.1, 5.0), Color(0.2, 0.2, 0.2))
	for s: float in [-1, 1]:
		mk.boxp("iron", Vector3(s * 1.42, FLOOR + 0.5, 0), Vector3(0.08, 1.0, 5.0), black)
		mk.boxp("metal", Vector3(s * 1.42, FLOOR + 1.02, 0), Vector3(0.12, 0.06, 5.0), Color(0.3, 0.3, 0.3))
	# coal bunker in the middle, walkways either side
	mk.boxp("iron", Vector3(0, FLOOR + 0.45, 0.95), Vector3(1.24, 0.9, 0.08), black)
	for s: float in [-1, 1]:
		mk.boxp("iron", Vector3(s * 0.62, FLOOR + 0.45, -0.6), Vector3(0.08, 0.9, 3.1), black)
	mk.boxp("iron", Vector3(0, FLOOR + 0.18, -2.1), Vector3(1.24, 0.36, 0.08), black)
	mk.boxp("iron", Vector3(0, FLOOR + 0.6, 1.75), Vector3(1.24, 1.2, 1.5), Color(0.13, 0.13, 0.14))  # water tank
	for s: float in [-1, 1]:
		mk.boxp("metal", Vector3(s * 0.9, FLOOR + 1.6, 2.45), Vector3(0.05, 0.8, 0.05), Color(0.3, 0.3, 0.3))
	mk.boxp("metal", Vector3(0, FLOOR + 1.95, 2.45), Vector3(1.85, 0.05, 0.05), Color(0.3, 0.3, 0.3))
	mk.build(body, "Tender", true)
	_col(body, Vector3(0, FLOOR - 0.06, 0), Vector3(2.9, 0.12, 5.0))
	_col(body, Vector3(0, 0.9, 0), Vector3(2.2, 0.9, 5.0))
	for s: float in [-1, 1]:
		_col(body, Vector3(s * 1.42, FLOOR + 0.55, 0), Vector3(0.12, 1.1, 5.0))
	_col(body, Vector3(0, FLOOR + 0.45, -0.6), Vector3(1.28, 0.9, 3.1))
	# water tank is a step the player walks around on the sides; leave walkway x>0.75
	_col(body, Vector3(0, FLOOR + 0.6, 1.75), Vector3(1.28, 1.2, 1.5))
	for s: float in [-1.0, 1.0]:
		for z: float in [-1.4, 1.4]:
			_wheel(body, Vector3(s * 0.95, 0.45, z), 0.45, false)
	coal_pile = Node3D.new()
	coal_pile.position = Vector3(0, FLOOR, -0.6)
	body.add_child(coal_pile)
	var pile := MeshInstance3D.new()
	pile.mesh = Props.coal_pile_mesh()
	pile.scale = Vector3(1.15, 1.0, 2.8)
	coal_pile.add_child(pile)
	Interactable.make(body, Vector3(0, FLOOR + 0.6, -2.1), Vector3(1.3, 0.8, 0.4), _bunker_prompt, func(p) -> void: deposit(p))
	Interactable.make(body, Vector3(0, FLOOR + 1.0, -0.6), Vector3(1.3, 0.4, 3.0), _bunker_prompt, func(p) -> void: deposit(p))
	var lbl := Props.label("COAL", 40, Color(0.7, 0.68, 0.62), false, 0.004)
	lbl.position = Vector3(0, FLOOR + 0.25, -2.16)
	lbl.rotation.y = 0.0
	body.add_child(lbl)

func _build_carriage(body: AnimatableBody3D) -> void:
	var mk := MK.new()
	var wall := Color(0.2, 0.19, 0.18)
	var trim := Color(0.33, 0.3, 0.26)
	var L := 11.6
	mk.boxp("iron", Vector3(0, 0.95, 0), Vector3(2.0, 0.35, 14.0), Color(0.1, 0.1, 0.1))
	mk.boxp("wood", Vector3(0, FLOOR - 0.05, 0), Vector3(2.9, 0.1, 14.0), Color(0.25, 0.22, 0.19))
	mk.boxp("metal", Vector3(0, FLOOR - 0.05, -7.65), Vector3(1.2, 0.08, 1.4), Color(0.25, 0.25, 0.25))  # gangway plate
	# side walls with five windows
	var nwin := 5
	var seg := L / nwin
	for s: float in [-1, 1]:
		var x := s * 1.45
		mk.boxp("wood", Vector3(x, FLOOR + 0.45, 0), Vector3(0.08, 0.9, L), wall)
		mk.boxp("wood", Vector3(x, FLOOR + 2.05, 0), Vector3(0.08, 0.5, L), wall)
		mk.boxp("wood", Vector3(x * 1.01, FLOOR + 0.92, 0), Vector3(0.06, 0.05, L), trim)
		for i in nwin + 1:
			mk.boxp("wood", Vector3(x, FLOOR + 1.35, -L / 2 + i * seg), Vector3(0.1, 1.0, 0.35), wall)
	# end walls with doorways
	for e: float in [-1, 1]:
		var z := e * L / 2
		mk.boxp("wood", Vector3(-0.95, FLOOR + 1.15, z), Vector3(1.0, 2.3, 0.08), wall)
		mk.boxp("wood", Vector3(0.95, FLOOR + 1.15, z), Vector3(1.0, 2.3, 0.08), wall)
		mk.boxp("wood", Vector3(0, FLOOR + 2.18, z), Vector3(0.9, 0.25, 0.08), wall)
		# platform railings
		for s: float in [-1, 1]:
			mk.boxp("metal", Vector3(s * 1.4, FLOOR + 0.5, z + e * 0.65), Vector3(0.05, 1.0, 0.05), Color(0.3, 0.3, 0.3))
			mk.boxp("metal", Vector3(s * 1.4, FLOOR + 1.0, z + e * 0.35), Vector3(0.05, 0.05, 0.6), Color(0.3, 0.3, 0.3))
		if e > 0:
			mk.boxp("metal", Vector3(0, FLOOR + 1.0, 7.0), Vector3(2.8, 0.05, 0.05), Color(0.3, 0.3, 0.3))
			mk.boxp("metal", Vector3(0, FLOOR + 0.5, 7.0), Vector3(2.8, 0.05, 0.05), Color(0.3, 0.3, 0.3))
	# roof
	mk.boxp("iron", Vector3(0, FLOOR + 2.35, 0), Vector3(3.0, 0.1, 14.0), Color(0.12, 0.12, 0.13))
	mk.boxp("iron", Vector3(0, FLOOR + 2.5, 0), Vector3(2.0, 0.2, 13.6), Color(0.14, 0.14, 0.15))
	for s: float in [-1, 1]:
		mk.box("iron", Transform3D(Basis(Vector3.FORWARD, s * 0.35), Vector3(s * 1.2, FLOOR + 2.42, 0)), Vector3(0.7, 0.08, 13.8), Color(0.12, 0.12, 0.13))
	# benches facing each other
	var bz := -L / 2 + 1.0
	var k := 0
	while bz < L / 2 - 1.6:
		for s: float in [-1, 1]:
			var face := 1 if k % 2 == 0 else -1
			mk.boxp("wood", Vector3(s * 0.95, FLOOR + 0.42, bz), Vector3(0.9, 0.1, 0.55), Color(0.32, 0.27, 0.22))
			mk.boxp("wood", Vector3(s * 0.95, FLOOR + 0.2, bz), Vector3(0.85, 0.4, 0.45), Color(0.2, 0.18, 0.16))
			mk.boxp("wood", Vector3(s * 0.95, FLOOR + 0.8, bz - face * 0.3), Vector3(0.9, 0.75, 0.08), Color(0.28, 0.24, 0.2))
			_col(body, Vector3(s * 0.95, FLOOR + 0.4, bz), Vector3(0.9, 0.8, 0.65))
		bz += 1.65
		k += 1
	# luggage racks
	for s: float in [-1, 1]:
		mk.boxp("metal", Vector3(s * 1.15, FLOOR + 1.95, 0), Vector3(0.45, 0.03, L - 0.4), Color(0.3, 0.28, 0.25))
	# table at rear end
	mk.boxp("wood", Vector3(0.9, FLOOR + 0.75, 4.95), Vector3(0.9, 0.06, 0.7), Color(0.33, 0.28, 0.22))
	mk.boxp("wood", Vector3(0.9, FLOOR + 0.37, 4.95), Vector3(0.1, 0.75, 0.1), Color(0.2, 0.18, 0.16))
	_col(body, Vector3(0.9, FLOOR + 0.4, 4.95), Vector3(0.9, 0.8, 0.7))
	mk.build(body, "Carriage", true)
	# glass
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.75, 0.5, 0.08)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.6, 0.3)
	glass.emission_energy_multiplier = 0.7
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.1
	for s: float in [-1, 1]:
		for i in nwin:
			var g := MeshInstance3D.new()
			var q := QuadMesh.new(); q.size = Vector2(seg - 0.35, 1.0)
			g.mesh = q
			g.material_override = glass
			g.position = Vector3(s * 1.45, FLOOR + 1.35, -L / 2 + (i + 0.5) * seg)
			g.rotation.y = PI / 2
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(g)
	# lamps inside
	for z: float in [-3.0, 2.0]:
		var lm := MeshInstance3D.new()
		lm.mesh = Props.lantern_mesh()
		lm.position = Vector3(0, FLOOR + 1.9, z)
		body.add_child(lm)
		var l := Props.omni(Color(1.0, 0.66, 0.36), 1.1, 6.5)
		l.position = Vector3(0, FLOOR + 1.9, z)
		body.add_child(l)
		carriage_lights.append(l)
	var tail := MeshInstance3D.new()
	var tm := SphereMesh.new(); tm.radius = 0.09; tm.height = 0.18
	tail.mesh = tm
	tail.material_override = Mats.get_mat("lamp_red")
	tail.position = Vector3(1.2, FLOOR + 0.3, 7.1)
	body.add_child(tail)
	# colliders
	_col(body, Vector3(0, FLOOR - 0.06, 0), Vector3(2.9, 0.12, 14.0))
	_col(body, Vector3(0, FLOOR - 0.06, -7.65), Vector3(1.2, 0.12, 1.4))
	_col(body, Vector3(0, 0.9, 0), Vector3(2.2, 0.9, 14.0))
	for s: float in [-1, 1]:
		_col(body, Vector3(s * 1.46, FLOOR + 1.2, 0), Vector3(0.12, 2.4, L))
	for e: float in [-1, 1]:
		var z := e * L / 2
		_col(body, Vector3(-0.95, FLOOR + 1.15, z), Vector3(1.0, 2.3, 0.12))
		_col(body, Vector3(0.95, FLOOR + 1.15, z), Vector3(1.0, 2.3, 0.12))
		# platform side rails leave the ladder gap at the outer end
		for s: float in [-1, 1]:
			_col(body, Vector3(s * 1.42, FLOOR + 0.55, z + e * 0.35), Vector3(0.08, 1.1, 0.6))
	_col(body, Vector3(0, FLOOR + 0.55, 7.02), Vector3(2.8, 1.1, 0.08))
	_col(body, Vector3(0, FLOOR + 2.4, 0), Vector3(3.0, 0.12, 14.0))
	var mk2 := MK.new()
	_ladder(body, 1.45, 6.45, mk2)
	_ladder(body, -1.45, 6.45, mk2)
	mk2.build(body, "Ladders", true)
	for s: float in [-1.0, 1.0]:
		for z: float in [-5.6, -4.4, 4.4, 5.6]:
			_wheel(body, Vector3(s * 0.95, 0.45, z), 0.45, false)

# ------------------------------------------------------------------ controls

func _regulator_prompt() -> String:
	return "Regulator %d/%d   [E] Open   [Q] Close" % [throttle, MAX_NOTCH]

func _brake_prompt() -> String:
	return "[E] Release the brake" if brake else "[E] Apply the brake"

func _whistle_prompt() -> String:
	return "[E] Pull the whistle" if pressure > 0.15 else "Whistle (needs steam pressure)"

func _firebox_prompt() -> String:
	if tender_coal <= 0:
		return "Firebox — the tender is empty. Find coal."
	if fire > 92.0:
		return "Firebox — the fire is roaring"
	return "[E] Shovel coal into the firebox   (%d left)" % tender_coal

func _bunker_prompt() -> String:
	if world and world.player and world.player.carried_coal > 0:
		return "[E] Tip %d coal into the tender" % world.player.carried_coal
	return "Coal bunker — %d shovelfuls left" % tender_coal

func set_notch(n: int) -> void:
	var nn := clampi(n, 0, MAX_NOTCH)
	if nn == throttle:
		return
	throttle = nn
	Sfx.play_at("lever", Vector3.ZERO, -4.0, randf_range(0.9, 1.1), 20.0, snd_cab)
	if throttle > 0 and pressure < 0.2:
		world.hud.message("Not enough steam. Feed the fire and wait for pressure.", 3.0)
	elif throttle > 0 and brake:
		world.hud.message("The brake is still on.", 2.5)

func toggle_brake() -> void:
	brake = not brake
	Sfx.play_at("lever", Vector3.ZERO, -2.0, 0.8, 20.0, snd_cab)
	if brake and v > 1.5:
		Sfx.play_at("brake", Vector3(0, -1.0, 0), 0.0, 1.0, 60.0, snd_cab)

func shovel(p) -> void:
	if shovel_cd > 0.0 or tender_coal <= 0 or fire > 92.0:
		return
	shovel_cd = 1.1
	tender_coal -= 1
	coal_burned += 1
	Sfx.play_at("shovel", Vector3.ZERO, 0.0, randf_range(0.95, 1.05), 15.0, snd_cab)
	Sfx.play_at("furnace_door", Vector3(0, -0.9, -0.8), -6.0, 1.0, 15.0, snd_cab)
	if p and p.has_method("anim_shovel"):
		p.anim_shovel()
	var tw := create_tween()
	tw.tween_property(fire_door, "rotation:y", -1.7, 0.25)
	tw.tween_callback(func() -> void:
		fire = minf(100.0, fire + COAL_PER_SHOVEL)
		fire_light.light_energy += 2.0)
	tw.tween_interval(0.35)
	tw.tween_property(fire_door, "rotation:y", 0.0, 0.3)
	_update_coal_pile()

func deposit(p) -> void:
	if p.carried_coal <= 0:
		return
	var room := TENDER_MAX - tender_coal
	var n := mini(room, p.carried_coal)
	if n <= 0:
		world.hud.message("The tender is full.", 2.0)
		return
	tender_coal += n
	p.carried_coal -= n
	Sfx.play("coal_pickup", 0.0, 0.85)
	world.hud.message("+%d coal in the tender" % n, 2.0)
	_update_coal_pile()

func _update_coal_pile() -> void:
	var t := clampf(float(tender_coal) / TENDER_MAX, 0.0, 1.0)
	coal_pile.scale = Vector3(1, maxf(0.05, t * 1.6), 1)
	coal_pile.visible = tender_coal > 0

func blow_whistle() -> void:
	if whistle_cd > 0.0 or pressure < 0.15:
		return
	whistle_cd = 3.0
	pressure = maxf(0.0, pressure - 0.04)
	Sfx.play_at("whistle", Vector3(0.3, 3.4, 0.9), 4.0, 1.0, 400.0, cars["loco"])
	whistle_steam.restart()
	whistle_steam.emitting = true
	var tw := create_tween()
	tw.tween_property(whistle_handle, "position:y", FLOOR + 1.72, 0.12)
	tw.tween_interval(1.6)
	tw.tween_property(whistle_handle, "position:y", FLOOR + 1.85, 0.3)
	tw.tween_callback(func() -> void: whistle_steam.emitting = false)
	whistled.emit()

# ------------------------------------------------------------------ simulation

func _place_cars() -> void:
	for n in cars:
		var body: AnimatableBody3D = cars[n]
		body.global_transform = Track.xform(d - CAR_OFFSETS[n])

func _physics_process(dt: float) -> void:
	for n in cars:
		cars[n].set_meta("prev", cars[n].global_transform)
	shovel_cd = maxf(0.0, shovel_cd - dt)
	whistle_cd = maxf(0.0, whistle_cd - dt)
	var T := float(throttle) / MAX_NOTCH
	# steam
	var target := clampf(fire / 35.0, 0.0, 1.0)
	pressure = move_toward(pressure, target, dt * (0.09 if target > pressure else 0.05))
	if fire > 0.0:
		var burn := 0.05 + (0.25 * T + 1.5 * T * T) * maxf(pressure, 0.3)
		fire = maxf(0.0, fire - burn * dt)
	# forces
	var power := T * pressure * 1.15
	brake_force = move_toward(brake_force, 1.0 if brake else 0.0, dt * 2.0)
	var a := power - (0.02 * v + 0.0022 * v * v) - 0.03 - brake_force * 2.8
	# dead-man: stop if nobody is aboard
	var p = world.player if world else null
	if p and v > 0.5 and p.attached == null and not p.climbing:
		if p.global_position.distance_to(cars["loco"].global_position) > 14.0:
			if not brake:
				brake = true
				throttle = 0
				world.hud.message("Nobody at the controls. The brake engages.", 3.0)
	# approach to Greyhaven buffers
	if d > Track.END_D - 110.0 and v > 2.0:
		a = minf(a, -2.2)
		if auto_brake_reason == "":
			auto_brake_reason = "station"
	v = maxf(0.0, v + a * dt)
	var was_moving := moving
	var nd := d + v * dt
	# obstacles
	var block: float = world.block_d(d) if world else INF
	if nd + FRONT > block:
		var hit_v := v
		nd = block - FRONT
		v = 0.0
		if hit_v > 9.0:
			crashed.emit(hit_v)
		elif hit_v > 0.5:
			impact.emit(hit_v)
	nd = minf(nd, Track.END_D - FRONT - 0.5)
	if nd >= Track.END_D - FRONT - 0.5:
		v = 0.0
	var dd := nd - d
	d = nd
	_place_cars()
	moving = v > 0.15
	if moving and not was_moving:
		started.emit()
		Sfx.play_at("engine_start", Vector3(0, 1.0, -3.0), -2.0, 1.0, 120.0, cars["loco"])
		steam_burst.restart()
		steam_burst.emitting = true
		if world and world.player:
			world.player.add_shake(0.25)
	elif was_moving and not moving:
		stopped.emit()
		_hiss_burst = 1.0
		if world and world.player and world.player.attached != null:
			world.player.add_shake(0.35)
	if brake_force > 0.3 and v > 2.5 and randf() < dt * 0.6:
		Sfx.play_at("brake", Vector3(0, 0.3, 0), -4.0, randf_range(0.9, 1.1), 70.0, cars["tender"])
	_animate(dt, dd, T)

func _animate(dt: float, dd: float, T: float) -> void:
	_wheel_angle += dd / 0.75
	for w in wheels:
		w[0].rotation.x = -_wheel_angle * 0.75 / w[1] * (1.0 if w[0].position.x > 0 else -1.0)
	for r in rods:
		var base: Vector3 = r[1]
		r[0].position = base + Vector3(0, cos(_wheel_angle) * 0.32, sin(_wheel_angle) * 0.32)
	# chuffs, two per wheel revolution
	if T > 0.0 and pressure > 0.1 and v > 0.05:
		_chuff_acc += dd
		var per := TAU * 0.75 / 4.0
		if _chuff_acc > per:
			_chuff_acc = fmod(_chuff_acc, per)
			var vol := lerpf(-1.0, -9.0, clampf(v / 18.0, 0.0, 1.0)) + linear_to_db(clampf(T * pressure + 0.25, 0.1, 1.0))
			Sfx.play_at("chuff", Vector3(0, 4.0, -4.8), vol, randf_range(0.92, 1.05) + v * 0.01, 140.0, cars["loco"])
	_clack_acc += dd
	if _clack_acc > 12.5:
		_clack_acc -= 12.5
		Sfx.play_at("rail_clack", Vector3(0, 0.3, 0), lerpf(-14.0, -3.0, clampf(v / 15.0, 0.0, 1.0)), randf_range(0.95, 1.05), 50.0, cars["tender"])
	_creak_t -= dt
	if _creak_t < 0.0:
		_creak_t = randf_range(7.0, 16.0)
		if v > 1.0 or randf() < 0.3:
			Sfx.play_at(Sfx.variant("creak", 2), Vector3(0, 2.0, 0), -10.0, randf_range(0.9, 1.1), 30.0, cars["carriage"])
	# loops
	if snd_rumble:
		var sp := clampf(v / 17.0, 0.0, 1.0)
		snd_rumble.volume_db = linear_to_db(sp * 0.9 + 0.0001) + 2.0
		snd_rumble.pitch_scale = 0.7 + sp * 0.5
		_hiss_burst = maxf(0.0, _hiss_burst - dt * 0.4)
		snd_hiss.volume_db = linear_to_db(clampf(pressure * 0.35 + _hiss_burst * 0.6 + (0.3 if pressure > 0.97 and not moving else 0.0), 0.0001, 1.0)) - 4.0
		snd_fire.volume_db = linear_to_db(clampf(fire / 100.0, 0.0001, 1.0)) + 2.0
	# fire light, needles, levers
	var flick := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.023) * sin(Time.get_ticks_msec() * 0.0071)
	var target_e := (0.25 + fire / 100.0 * 2.2) * flick
	fire_light.light_energy = lerpf(fire_light.light_energy, target_e, minf(1.0, dt * 4.0))
	fire_mat.emission_energy_multiplier = 0.3 + fire / 100.0 * 4.5 * flick
	speed_needle.rotation.z = -deg_to_rad(-120.0 + clampf(v / 20.0, 0.0, 1.0) * 240.0)
	pressure_needle.rotation.z = -deg_to_rad(-120.0 + pressure * 240.0)
	regulator.rotation.z = lerp_angle(regulator.rotation.z, -deg_to_rad(-35.0 + T * 70.0), minf(1.0, dt * 8.0))
	brake_lever.rotation.x = lerp_angle(brake_lever.rotation.x, 0.6 if brake else -0.5, minf(1.0, dt * 8.0))
	smoke.amount_ratio = clampf(0.12 + T * pressure * 0.88 + (0.15 if fire > 0.0 else -0.1), 0.0, 1.0)
	smoke.emitting = fire > 0.0 or pressure > 0.05

func is_in_cab(p: Vector3) -> bool:
	var lp: Vector3 = cars["loco"].global_transform.affine_inverse() * p
	return absf(lp.x) < 1.45 and lp.z > 1.5 and lp.z < 6.1 and lp.y > FLOOR - 0.4 and lp.y < FLOOR + 2.4

func loco_pos() -> Vector3:
	return cars["loco"].global_position

func cab_point() -> Vector3:
	return cars["loco"].global_transform * Vector3(0.3, FLOOR + 0.05, 3.8)

func state() -> Dictionary:
	return {"d": d, "fire": fire, "pressure": pressure, "tender": tender_coal, "burned": coal_burned,
		"axe": not axe_prop.visible}

func restore(s: Dictionary) -> void:
	d = s.get("d", 0.0)
	fire = s.get("fire", 0.0)
	pressure = s.get("pressure", 0.0)
	tender_coal = s.get("tender", 6)
	coal_burned = s.get("burned", 0)
	axe_prop.visible = not s.get("axe", false)
	v = 0.0
	throttle = 0
	brake = true
	brake_force = 1.0
	_place_cars()
	for n in cars:
		cars[n].set_meta("prev", cars[n].global_transform)
		cars[n].reset_physics_interpolation()
	_update_coal_pile()
