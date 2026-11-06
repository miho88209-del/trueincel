extends Node3D
## Game world: environment, route sites, streaming, objectives, story, audio
## states, checkpoints, the awakening intro and the win / lose states.

const NOTES := {
	"engine": ["pinned beside the engine's ladder", "To whoever wakes up next —\n\nShe still has fire in her. Shovel coal into the firebox, wait for the steam needle to climb, let off the brake and open the regulator.\n\nGreyhaven is down the line, east. Tell them what happened to the 7:10 from Ashford.\n\nDon't stay off the train for long. If you see the tall one with the paper face, LOOK AT IT. It only moves when you look away.\n\nThe whistle hurts it.\n\n— M."],
	"carriage": ["passenger list, carriage two", "7:10 Ashford – Greyhaven. 23 aboard.\n\n9:40  stopped. Tree across the line.\n9:52  driver and fireman went out with the axe.\n10:05  the whistle stopped.\n\nPeople kept getting off to look for them. Nobody came back.\nI am the last one awake. I am going to try the engine myself.\n\n— M."],
	"shack": ["scratched into the wall planks", "It stood by the window all night.\nEvery time I blinked it was closer.\n\nI stared until morning. My eyes burned.\nIt was still there when the light came, just standing, like a coat on a hook.\n\nI'm going to run for the line."],
	"hut": ["a trapper's ledger", "Third tree down on the Ashford line this month. No wind. No rot.\nThe trunks are snapped clean at the bottom, like something wants the trains to stop.\n\nLeft my winter coal in the hut. If you need it, take it."],
	"wreck": ["on the back of a ticket", "This carriage never made it.\nSomebody wrote on every seat: DON'T LOOK BACK.\n\nBut you have to look back. That's the trick of it.\nIt can't move while you're watching."],
	"signalbox": ["signalman's log", "Line closed since the 3rd.\nSignals set to danger at every fallen tree.\n\nThe tall one comes to the box at night and stands under the lamp. It doesn't like the engines, I think. The noise of them.\n\nStove coal is in the corner. Greyhaven is a little over two kilometres on."],
	"notetree": ["notes tied to the branches", "i looked away\n\nit was smiling\n\nthe whistle hurts it\n\nkeep the fire lit\n\nit counts us\n\ndon't look back.   LOOK BACK.\n\ngreyhaven  greyhaven  greyhaven"],
	"barn": ["a letter tucked in a coal sack", "M. —\n\nI kept the coal dry for you, like I promised.\nIf I hear the whistle tonight I'll know you made it through.\nThe lamps at Greyhaven will be lit.\n\n— your sister, Ada"],
	"ruin": ["a prayer card", "Whoever finds this:\nthe thing in the woods is patient, not fast.\n\nWalk backwards if you must, but keep your eyes on it.\nIt hates the engine's scream."],
	"post": ["nailed to a telegraph pole", "DON'T LOOK AWAY\n\n(someone has added underneath, in pencil:)\nunless you're running"],
}

var train: Train
var player: Player
var hud: Hud
var creature: Creature
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var obstacles: Array = []
var pickups := {}          # id -> {node, kind, amount, pos}
var collected := {}
var notes_read := {}
var watchers: Array = []
var chunks := {}
var _building := false
var elapsed := 0.0
var darkness := 0.1
var cinematic := true
var ended := false
var started_once := false
var shoveled_once := false
var boarded_once := false
var _stranded_t := 0.0
var _stop_saved := {}
var _warned := {}
var _amb_cue_t := 10.0
var _status_t := 0.0
var _town_glows: Array = []
var _townsfolk: Array = []
var _signals: Array = []
var _whistle_hint := false
var _low_fire_t := 0.0
var _autotest: Node

func _ready() -> void:
	Track.init()
	Track.reset_sites()
	_setup_environment()
	_register_sites()
	train = Train.new()
	train.name = "Train"
	add_child(train)
	player = Player.new()
	player.world = self
	player.name = "Player"
	add_child(player)
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	train.setup(self)
	creature = Creature.new()
	add_child(creature)
	creature.setup(self)
	_build_sites()
	train.crashed.connect(_on_crash)
	train.impact.connect(_on_impact)
	train.whistled.connect(_on_whistle)
	train.started.connect(func() -> void:
		if not started_once:
			started_once = true
			hud.message("She's moving.", 2.5))
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	var restoring := Game.start_mode == "retry" and not Game.checkpoint.is_empty()
	if restoring:
		_restore(Game.checkpoint)
	else:
		var spawn := Track.side(-13.5, 6.5) + Vector3(0, 0.1, 0)
		player.teleport(spawn, _yaw_towards(spawn, train.cars["loco"].global_transform * Vector3(1.6, 1.0, 2.0)))
	await _initial_chunks()
	if restoring:
		_begin_from_checkpoint()
	if Game.autotest:
		_autotest = load("res://scripts/autotest.gd").new()
		add_child(_autotest)
		_autotest.run(self)
		return
	if not restoring:
		_intro()

func _yaw_towards(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)

# ------------------------------------------------------------------ environment

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.5, 0.52, 0.55)
	sky_mat.sky_horizon_color = Color(0.62, 0.63, 0.64)
	sky_mat.ground_horizon_color = Color(0.55, 0.56, 0.57)
	sky_mat.ground_bottom_color = Color(0.3, 0.3, 0.3)
	sky_mat.sun_angle_max = 0.0
	sky_mat.sky_cover_modulate = Color(1, 1, 1, 0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.6, 0.61, 0.63)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.92
	env.fog_aerial_perspective = 0.25
	env.fog_height = 1.2
	env.fog_height_density = 0.06
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(0.78, 0.78, 0.8)
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_anisotropy = 0.55
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(2, 1.0)
	env.set_glow_level(4, 0.6)
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.adjustment_saturation = 0.78
	env.adjustment_contrast = 1.07
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(0.35, -0.42, 1.0).normalized(), Vector3.UP)
	sun.light_color = Color(0.86, 0.88, 0.92)
	sun.light_energy = 1.0
	sun.shadow_blur = 1.6
	sun.light_angular_distance = 2.5
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)

func _apply_settings() -> void:
	Settings.configure_environment(env, 0.018)
	Settings.configure_light(sun, true)
	var dens := float(Settings.v["grass"])
	for c: Node in chunks.values():
		for g in 4:
			var n := c.get_node_or_null("Grass%d" % g)
			if n:
				(n as MultiMeshInstance3D).multimesh.visible_instance_count = int((n as MultiMeshInstance3D).multimesh.instance_count * clampf(dens / maxf(c.get_meta("grass", 1.0), 0.01), 0.0, 1.0)) if dens > 0.0 else 0

func _update_atmosphere(dt: float) -> void:
	var target := clampf(0.08 + 0.52 * clampf(train.d / 4700.0, 0.0, 1.0) + 0.32 * clampf(elapsed / 1500.0, 0.0, 1.0), 0.0, 0.9)
	darkness = move_toward(darkness, target, dt * 0.01)
	var n := darkness
	var o := Track.openness(-player.global_position.z)
	var fog_col := Color(0.6, 0.61, 0.63).lerp(Color(0.13, 0.14, 0.17), n)
	env.fog_light_color = fog_col
	env.fog_density = lerpf(0.0125, 0.0085, o) * lerpf(1.0, 0.85, n)
	sky_mat.sky_top_color = Color(0.5, 0.52, 0.55).lerp(Color(0.06, 0.065, 0.09), n)
	sky_mat.sky_horizon_color = fog_col
	sky_mat.ground_horizon_color = fog_col
	env.ambient_light_energy = lerpf(0.95, 0.55, n)
	env.volumetric_fog_albedo = Color(0.78, 0.78, 0.8).lerp(Color(0.35, 0.37, 0.42), n)
	sun.light_energy = lerpf(1.05, 0.28, n)
	sun.light_color = Color(0.88, 0.89, 0.92).lerp(Color(0.55, 0.62, 0.8), n)
	train.headlamp.light_energy = lerpf(2.5, 6.0, n)
	for g in _town_glows:
		var gm: StandardMaterial3D = g.material_override
		gm.albedo_color.a = clampf((train.d - 3500.0) / 700.0, 0.0, 1.0) * lerpf(0.35, 0.9, n)

# ------------------------------------------------------------------ route sites

func _site(d: float, off: float) -> Vector3:
	var p := Track.pos(d, 0.0) + Track.right(d) * off
	p.y = Track.height(p.x, p.z)
	return p

var _site_list: Array = []

func _register_sites() -> void:
	# [kind, d, offset, yaw-ish, clear radius]
	_site_list = [
		["camp", -14.0, 8.0, 0.4, 7.0],
		["shack", 872.0, 17.0, 0.0, 8.0],
		["hut", 935.0, -60.0, 0.6, 6.0],
		["cart", 1600.0, 6.2, 0.0, 4.0],
		["wreck", 2150.0, -10.5, 0.0, 10.0],
		["signalbox", 2240.0, 52.0, -0.4, 6.0],
		["notetree", 3305.0, 30.0, 0.0, 9.0],
		["barn", 3328.0, -23.0, 0.3, 8.0],
		["ruin", 3425.0, 78.0, 0.2, 7.0],
		["station", 4690.0, 10.0, 0.0, 26.0],
	]
	for s in _site_list:
		var p := _site(s[1], s[2])
		Track.add_site(p, s[4], s[0] != "notetree")
	# the town itself
	for i in 18:
		var rng := RandomNumberGenerator.new(); rng.seed = 600 + i
		var dd := rng.randf_range(4560.0, 4900.0)
		var off := rng.randf_range(22.0, 95.0) * (1.0 if i % 2 == 0 else -1.0)
		Track.add_site(_site(dd, off), 7.0)

func _build_sites() -> void:
	for s in _site_list:
		var kind: String = s[0]
		var d: float = s[1]
		var off: float = s[2]
		var p := _site(d, off)
		var basis := Basis.looking_at(Track.fwd(d), Vector3.UP).rotated(Vector3.UP, s[3] + (PI / 2 if off > 0 else -PI / 2))
		var node: Node3D
		match kind:
			"camp":
				node = Node3D.new()
				node.add_child(Props.campfire_dead())
				for i in 3:
					var sc := Props.suitcase(i)
					sc.position = Vector3(1.5 + i * 0.6, 0, -1.2 + i * 0.9)
					sc.rotation.y = i * 1.3
					node.add_child(sc)
				var cr := Props.crate(5, 0.7)
				cr.position = Vector3(-1.4, 0, 0.6)
				node.add_child(cr)
				_add_to_world(node, p, basis)
				_pickup("lantern0", "lantern", 1, node.to_global(Vector3(-1.4, 0.72, 0.6)))
				_pickup("coal_camp", "coal", 2, node.to_global(Vector3(1.2, 0.0, 1.4)))
			"shack":
				node = Props.shack(11)
				_add_to_world(node, p, basis)
				_pickup("coal_shack", "coal", 3, node.to_global(Vector3(1.6, 0.72, -1.3)))
				_pickup("bandage_shack", "bandage", 1, node.to_global(Vector3(-1.5, 0.84, -1.2)))
				_note("shack", node.to_global(Vector3(-1.0, 0.84, -1.3)))
				_lantern_light(node, Vector3(-1.1, 1.9, -1.0), 0.6)
			"hut":
				node = Props.hut(12)
				_add_to_world(node, p, basis)
				_pickup("coal_hut", "coal", 4, node.to_global(Vector3(0.8, 0.12, -0.8)))
				_note("hut", node.to_global(Vector3(-0.9, 0.12, -0.9)))
			"cart":
				node = Props.coal_cart(13)
				_add_to_world(node, p, basis)
				_pickup("coal_cart", "coal", 2, node.to_global(Vector3(1.4, 0.0, 0.9)))
				var post := Node3D.new()
				var mk := MK.new()
				mk.boxp("wood", Vector3(0, 1.0, 0), Vector3(0.1, 2.0, 0.1), Props.WOOD_D, 0.0, true)
				mk.build(post, "Post", true)
				_add_to_world(post, node.to_global(Vector3(-1.6, 0, 1.4)), basis)
				_lantern_light(post, Vector3(0.15, 1.75, 0), 1.0)
			"wreck":
				node = Props.wrecked_carriage(14)
				_add_to_world(node, p, Basis.looking_at(Track.fwd(d), Vector3.UP).rotated(Vector3.UP, 0.08))
				_pickup("coal_wreck", "coal", 3, node.to_global(Vector3(2.6, 0.0, 4.6)))
				_pickup("bandage_wreck", "bandage", 1, node.to_global(Vector3(2.4, 0.0, -3.2)))
				_note("wreck", node.to_global(Vector3(2.2, 0.0, 1.0)))
			"signalbox":
				node = Props.signal_box(15)
				_add_to_world(node, p, basis)
				_pickup("coal_box", "coal", 4, node.to_global(Vector3(1.6, 0.12, 0.9)))
				_pickup("medkit_box", "medkit", 1, node.to_global(Vector3(-1.6, 0.12, 0.9)))
				_note("signalbox", node.to_global(Vector3(0.0, 0.52, -0.8)))
				_lantern_light(node, Vector3(0, 2.4, 0), 0.8)
			"notetree":
				node = Props.note_tree()
				_add_to_world(node, p, Basis())
				_note("notetree", node.to_global(Vector3(0.0, 1.3, 0.7)), false, Vector3(1.4, 1.8, 1.4))
				_pickup("coal_tree", "coal", 2, node.to_global(Vector3(-2.2, 0.0, 1.8)))
				for i in 4:
					var sc := Props.suitcase(20 + i)
					sc.position = Vector3(-2.6 + i * 0.4, 0, 2.6 - i * 0.3)
					sc.rotation.y = i * 0.9
					node.add_child(sc)
			"barn":
				node = Props.barn(16)
				_add_to_world(node, p, basis)
				_pickup("coal_barn", "coal", 3, node.to_global(Vector3(-2.3, 0.92, -1.8)))
				_note("barn", node.to_global(Vector3(-2.6, 0.72, 0.2)))
			"ruin":
				node = Props.ruin(17)
				_add_to_world(node, p, basis)
				_pickup("coal_ruin", "coal", 4, node.to_global(Vector3(1.2, 0.1, -1.0)))
				_pickup("bandage_ruin", "bandage", 1, node.to_global(Vector3(-1.5, 0.1, -1.2)))
				_note("ruin", node.to_global(Vector3(-0.2, 0.1, 0.5)))
			"station":
				_build_station()
	# notes nailed to poles in the dead wood
	_note("post", Track.side(2620.0, -5.5, 1.4), false)
	for dd: float in [2480.0, 2700.0, 2860.0, 3010.0]:
		var n := MeshInstance3D.new()
		n.mesh = Props.note_mesh()
		var pp := Track.side(dd, -5.55, 1.5)
		_add_to_world(n, pp, Basis(Vector3.RIGHT, PI / 2).rotated(Vector3.UP, atan2(-Track.right(dd).x, -Track.right(dd).z)))
	# signs
	for sg in [[2000.0 - 300.0, "GREYHAVEN  3 km"], [3680.0, "GREYHAVEN  1 km"], [4450.0, "GREYHAVEN"]]:
		var sp := Props.sign_post(sg[1])
		_add_to_world(sp, Track.side(sg[0], 4.2), Basis.looking_at(-Track.fwd(sg[0]), Vector3.UP))
	# signals
	for sd in Track.SIGNALS:
		var sig := Props.signal_post(sd[2])
		_add_to_world(sig, Track.side(sd[0], sd[1]), Basis.looking_at(Track.fwd(sd[0]), Vector3.UP).rotated(Vector3.UP, PI))
		_signals.append(sig)
	# obstacles
	for info in Track.OBSTACLES:
		var ob := Obstacle.new()
		add_child(ob)
		ob.setup(info)
		ob.cleared.connect(_on_obstacle_cleared)
		obstacles.append(ob)
	# the engine note, carriage note and first-aid kit live on the train
	var loco: Node3D = train.cars["loco"]
	var np := MeshInstance3D.new()
	np.mesh = Props.note_mesh()
	np.position = Vector3(1.47, Train.FLOOR - 0.25, 3.75)
	np.rotation = Vector3(0, 0, -PI / 2)
	loco.add_child(np)
	Interactable.make(loco, Vector3(1.55, Train.FLOOR - 0.25, 3.75), Vector3(0.25, 0.4, 0.35), func() -> String: return "[E] Read the note", func(_p) -> void: read_note("engine"))
	var car: Node3D = train.cars["carriage"]
	var cn := MeshInstance3D.new()
	cn.mesh = Props.note_mesh()
	cn.position = Vector3(0.85, Train.FLOOR + 0.79, 4.9)
	cn.rotation.y = 0.3
	car.add_child(cn)
	Interactable.make(car, Vector3(0.85, Train.FLOOR + 0.85, 4.9), Vector3(0.5, 0.25, 0.5), func() -> String: return "[E] Read the passenger list", func(_p) -> void: read_note("carriage"))
	var kit := MeshInstance3D.new()
	kit.mesh = Props.medkit_mesh()
	kit.position = Vector3(1.1, Train.FLOOR + 0.78, 5.1)
	car.add_child(kit)
	Interactable.make(car, Vector3(1.1, Train.FLOOR + 0.9, 5.1), Vector3(0.5, 0.3, 0.4),
		func() -> String: return "[E] Use the first-aid tin" if kit.visible and player.health < 100.0 else ("First-aid tin (you're unhurt)" if kit.visible else ""),
		func(_p) -> void:
			if kit.visible and player.health < 100.0:
				kit.visible = false
				collected["kit_carriage"] = true
				player.heal(70.0)
				hud.message("You patch yourself up.", 2.5))
	kit.set_meta("id", "kit_carriage")
	pickups["kit_carriage"] = {"node": kit, "kind": "kit", "amount": 0, "pos": Vector3.ZERO}
	# travel glimpses
	for w in [[300.0, -30.0], [1350.0, 36.0], [2560.0, -42.0], [2950.0, 24.0], [4020.0, -58.0]]:
		_watcher(w[0], w[1])

func _add_to_world(node: Node3D, pos: Vector3, basis: Basis) -> void:
	add_child(node)
	node.global_transform = Transform3D(basis, pos)

func _lantern_light(parent: Node3D, pos: Vector3, energy: float) -> void:
	var lm := MeshInstance3D.new()
	lm.mesh = Props.lantern_mesh()
	lm.position = pos - Vector3(0, 0.2, 0)
	parent.add_child(lm)
	var l := Props.omni(Color(1.0, 0.62, 0.32), energy, 7.0)
	l.position = pos
	parent.add_child(l)

func _pickup(id: String, kind: String, amount: int, pos: Vector3) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = pos
	var mi := MeshInstance3D.new()
	match kind:
		"coal": mi.mesh = Props.coal_sack_mesh()
		"bandage": mi.mesh = Props.bandage_mesh()
		"medkit": mi.mesh = Props.medkit_mesh()
		"lantern": mi.mesh = Props.lantern_mesh()
	node.add_child(mi)
	var size := Vector3(0.8, 0.9, 0.8) if kind == "coal" else Vector3(0.5, 0.5, 0.5)
	Interactable.make(node, Vector3(0, size.y * 0.5, 0), size, func() -> String:
		match kind:
			"coal": return "[E] Pick up a sack of coal (%d)" % amount if player.carried_coal + amount <= Player.MAX_CARRY else "You can't carry any more coal"
			"bandage": return "[E] Take the bandages"
			"medkit": return "[E] Take the first-aid kit"
			"lantern": return "[E] Take the storm lantern"
		return "", func(_p) -> void: _collect(id))
	pickups[id] = {"node": node, "kind": kind, "amount": amount, "pos": pos}

func _collect(id: String) -> void:
	var pk: Dictionary = pickups[id]
	match pk["kind"]:
		"coal":
			if player.carried_coal + pk["amount"] > Player.MAX_CARRY:
				return
			player.carried_coal += pk["amount"]
			Sfx.play("coal_pickup")
			hud.message("Coal +%d. Carry it back and tip it into the tender." % pk["amount"], 3.0)
		"bandage":
			player.heal(35.0)
			hud.message("Bandages. You feel steadier.", 2.5)
		"medkit":
			player.heal(80.0)
			hud.message("First-aid kit.", 2.5)
		"lantern":
			player.give_lantern()
	collected[id] = true
	pk["node"].queue_free()

func _note(id: String, pos: Vector3, show_mesh := true, size := Vector3(0.5, 0.4, 0.5)) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = pos
	if show_mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = Props.note_mesh()
		mi.position.y = 0.01
		mi.rotation.y = randf() * TAU
		node.add_child(mi)
	Interactable.make(node, Vector3(0, 0.1, 0), size, func() -> String: return "[E] Read", func(_p) -> void: read_note(id))

func read_note(id: String) -> void:
	notes_read[id] = true
	hud.show_note(NOTES[id][0], NOTES[id][1])

func _watcher(d: float, off: float) -> void:
	var w := Node3D.new()
	add_child(w)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.albedo_color = Color(1, 1, 1, 0)
	Creature.build_model(w, mat)
	w.global_position = _site(d, off)
	w.visible = false
	watchers.append({"node": w, "d": d, "mat": mat, "seen": 0.0, "done": false})

func _build_station() -> void:
	var d0 := 4632.0
	var d1 := 4736.0
	var mk := MK.new()
	var dd := d0
	while dd < d1:
		var e := minf(dd + 8.0, d1)
		var mid := (dd + e) * 0.5
		var c := Track.pos(mid, 0.0) + Track.right(mid) * 5.2
		var b := Basis.looking_at(Track.fwd(mid), Vector3.UP)
		mk.box("stone", Transform3D(b, c + Vector3(0, 0.55, 0)), Vector3(3.8, 1.1, e - dd + 0.05), Color(0.38, 0.38, 0.37), true)
		mk.box("stone", Transform3D(b, Track.pos(mid, 1.12) + Track.right(mid) * 3.45), Vector3(0.3, 0.04, e - dd + 0.05), Color(0.6, 0.6, 0.58))
		dd = e
	# ramp at the far end
	var rp := Track.pos(d1 + 3.0, 0.0) + Track.right(d1) * 5.2
	mk.box("stone", Transform3D(Basis.looking_at(Track.fwd(d1), Vector3.UP).rotated(Track.right(d1), -0.17), rp + Vector3(0, 0.3, 0)), Vector3(3.8, 0.2, 7.0), Color(0.35, 0.35, 0.34), true)
	mk.build(self, "Platform", true, 1, {"surface": "gravel"})
	var house := Props.town_house(77, true)
	_add_to_world(house, _site(4688.0, 12.5) + Vector3(0, 0.0, 0), Basis.looking_at(Track.fwd(4688.0), Vector3.UP).rotated(Vector3.UP, PI / 2))
	var sign := Props.sign_post("GREYHAVEN")
	_add_to_world(sign, Track.pos(4672.0, 1.1) + Track.right(4672.0) * 6.6, Basis.looking_at(Track.right(4672.0), Vector3.UP))
	for i in 7:
		var ld := d0 + 6.0 + i * 15.0
		var lp := Props.lamp_post(i % 2 == 0)
		_add_to_world(lp, Track.pos(ld, 1.1) + Track.right(ld) * 6.6, Basis())
	var bell := Node3D.new()
	var bmk := MK.new()
	bmk.boxp("wood", Vector3(0, 1.4, 0), Vector3(0.12, 2.8, 0.12), Props.WOOD_D)
	bmk.boxp("wood", Vector3(0.3, 2.8, 0), Vector3(0.7, 0.1, 0.1), Props.WOOD_D)
	bmk.cyl("metal", Transform3D(Basis(), Vector3(0.55, 2.35, 0)), 0.22, 0.1, 0.4, 10, Color(0.5, 0.42, 0.28))
	bmk.build(bell, "Bell", true)
	_add_to_world(bell, Track.pos(4700.0, 1.1) + Track.right(4700.0) * 6.4, Basis())
	var buf := Props.buffer_stop()
	_add_to_world(buf, Track.pos(Track.END_D + 0.6, Track.RAIL_Y - 0.3), Basis.looking_at(-Track.fwd(Track.END_D), Vector3.UP))
	for i in 5:
		var tp := Props.townsperson(40 + i)
		var td := 4664.0 + i * 7.0
		_add_to_world(tp, Track.pos(td, 1.1) + Track.right(td) * (5.2 + (i % 2) * 1.2), Basis(Vector3.UP, atan2(Track.right(td).x, Track.right(td).z)))
		_townsfolk.append(tp)
	# town houses
	for i in 18:
		var rng := RandomNumberGenerator.new(); rng.seed = 600 + i
		var hd := rng.randf_range(4560.0, 4900.0)
		var off := rng.randf_range(22.0, 95.0) * (1.0 if i % 2 == 0 else -1.0)
		var h := Props.town_house(600 + i, rng.randf() < 0.8)
		_add_to_world(h, _site(hd, off), Basis(Vector3.UP, rng.randf() * TAU))
	var ch := Props.church()
	_add_to_world(ch, _site(4800.0, -48.0), Basis(Vector3.UP, 0.3))
	# distant glows visible through the fog long before arrival
	for i in 9:
		var gd := 4600.0 + i * 30.0
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(14, 10)
		g.mesh = q
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		gm.disable_fog = true
		gm.no_depth_test = false
		var rg := Gradient.new()
		rg.set_color(0, Color(1.0, 0.62, 0.3, 0.8))
		rg.set_color(1, Color(1.0, 0.5, 0.2, 0.0))
		var rt := GradientTexture2D.new()
		rt.gradient = rg
		rt.fill = GradientTexture2D.FILL_RADIAL
		rt.fill_from = Vector2(0.5, 0.5)
		rt.fill_to = Vector2(0.5, 0.0)
		gm.albedo_texture = rt
		gm.albedo_color = Color(1, 1, 1, 0)
		g.material_override = gm
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add_to_world(g, _site(gd, (i % 3 - 1) * 35.0) + Vector3(0, 5.0, 0), Basis())
		_town_glows.append(g)

# ------------------------------------------------------------------ streaming

func _wanted_range() -> Vector2i:
	var pd := -player.global_position.z
	var a := int(floor((pd - 110.0) / Track.CHUNK))
	var b := int(floor((pd + Settings.view_ahead()) / Track.CHUNK))
	return Vector2i(maxi(a, -3), mini(b, int((Track.END_D + 240.0) / Track.CHUNK)))

func _initial_chunks() -> void:
	var r := _wanted_range()
	for i in range(r.x, r.y + 1):
		await _make_chunk(i)

func _make_chunk(i: int) -> void:
	var c := Chunk.new()
	add_child(c)
	chunks[i] = c
	c.set_meta("grass", float(Settings.v["grass"]))
	await c.build(i, float(Settings.v["grass"]))

func _stream() -> void:
	if _building:
		return
	var r := _wanted_range()
	for i in chunks.keys():
		if i < r.x - 1 or i > r.y + 1:
			chunks[i].queue_free()
			chunks.erase(i)
	# build nearest missing chunk first (ahead of the train has priority)
	for i in range(r.x, r.y + 1):
		if not chunks.has(i):
			_building = true
			await _make_chunk(i)
			_building = false
			return

# ------------------------------------------------------------------ main loop

func block_d(_d: float) -> float:
	for ob in obstacles:
		if not ob.is_cleared and ob.d - 0.55 > _d:
			return ob.d - 0.55
	return INF

func next_obstacle() -> Obstacle:
	for ob in obstacles:
		if not ob.is_cleared and ob.d > train.d:
			return ob
	return null

func on_train() -> bool:
	return player.attached != null or player.climbing

func _physics_process(dt: float) -> void:
	if player == null:
		return
	if not cinematic and not ended:
		elapsed += dt
	_stream()
	_update_atmosphere(dt)
	var exposed := not on_train() and train.v < 0.6 and not ended and not cinematic and train.d < 4300.0
	creature.tick(dt, exposed, darkness)
	_update_watchers(dt)
	if cinematic:
		return
	if not ended:
		_game_logic(dt)
	_update_audio_state()
	_status_t -= dt
	if _status_t <= 0.0:
		_status_t = 0.1
		var ob := next_obstacle()
		var near_ob := ob != null and player.global_position.distance_to(ob.global_position) < 9.0 and player.has_axe
		hud.update_status({
			"dist_km": maxf(0.0, (Track.STATION_D - train.d) / 1000.0),
			"kmh": int(round(train.v * 3.6)),
			"notch": train.throttle,
			"brake": train.brake,
			"coal": train.tender_coal,
			"fire": train.fire,
			"carried": player.carried_coal,
			"health": player.health,
			"show_train": on_train() or train.moving,
			"chop": ob.progress() if near_ob else -1.0,
		})
		hud.set_prompt(player.focus.prompt() if player.focus else "")

func _game_logic(dt: float) -> void:
	if not boarded_once and on_train():
		boarded_once = true
	if train.fire > 0.0:
		shoveled_once = true
	hud.set_objective(_objective())
	# warnings
	var ob := next_obstacle()
	if ob and train.v > 1.5:
		var gap := ob.d - (train.d + Train.FRONT)
		if gap < 190.0 and not _warned.has(ob.id):
			_warned[ob.id] = true
			hud.message("Something lies across the track ahead — brake!", 4.0)
			Sfx.play("sting", -14.0)
	if train.moving and train.fire < 12.0 and train.throttle > 0:
		_low_fire_t -= dt
		if _low_fire_t <= 0.0:
			_low_fire_t = 12.0
			hud.message("The fire is dying. Shovel more coal." if train.tender_coal > 0 else "The tender is empty. She'll coast to a stop.", 3.0)
	# checkpoint when halted before an obstacle
	if ob and not train.moving and ob.d - train.d < 280.0 and not _stop_saved.has(ob.id):
		_stop_saved[ob.id] = true
		save_checkpoint()
	# arrival
	if train.d > Track.STATION_ZONE and not train.moving:
		_victory()
		return
	# stranded?
	if not train.moving and train.fire <= 0.0 and train.tender_coal <= 0 and player.carried_coal <= 0 and not _coal_nearby():
		_stranded_t += dt
		if _stranded_t > 8.0:
			_defeat("stranded")
	else:
		_stranded_t = 0.0
	# ambient horror cues while exposed
	_amb_cue_t -= dt
	if _amb_cue_t <= 0.0:
		_amb_cue_t = randf_range(14.0, 30.0)
		if not on_train() and creature.state == Creature.DORMANT and train.d < 4300.0:
			var a := randf() * TAU
			Sfx.play_at(Sfx.variant("branch_snap", 3), player.global_position + Vector3(cos(a), 0.3, sin(a)) * randf_range(18, 30), -6.0, randf_range(0.8, 1.1), 60.0)
		elif train.moving and darkness > 0.4 and randf() < 0.35:
			Sfx.play(Sfx.variant("whisper", 3), -18.0)

func _coal_nearby() -> bool:
	var lp := train.loco_pos()
	for id in pickups:
		var pk: Dictionary = pickups[id]
		if pk["kind"] == "coal" and not collected.has(id):
			if Vector2(pk["pos"].x - lp.x, pk["pos"].z - lp.z).length() < 170.0:
				return true
	return false

func _objective() -> String:
	if not notes_read.has("engine") and not boarded_once:
		return "Read the note pinned beside the engine's ladder."
	if not boarded_once:
		return "Climb the ladder into the engine's cab."
	if not started_once:
		if not shoveled_once:
			return "Shovel coal from the tender into the firebox  [E]."
		if train.pressure < 0.25:
			return "Wait for the steam needle (left gauge) to climb. Another shovelful helps."
		if train.brake:
			return "Release the brake (lever on the left wall)."
		return "Open the regulator to get moving."
	var ob := next_obstacle()
	if ob and ob.d - train.d < 280.0 and not train.moving:
		if not player.has_axe:
			return "A tree blocks the line. Take the axe from the cab wall."
		var s := "Clear the fallen tree with the axe  [Left Mouse]."
		if train.tender_coal < 6:
			s += "\nCoal is low — search the buildings nearby."
		return s
	if not on_train() and train.d > 100.0:
		if player.carried_coal > 0:
			return "Carry the coal back and tip it into the tender."
		return "Get back aboard the train."
	if train.d > 4300.0:
		return "Bring the train into Greyhaven station. Brake at the platform."
	if train.tender_coal == 0 and train.fire < 20.0:
		return "Out of coal. Stop near buildings and search for more."
	return "Follow the line to Greyhaven."

func _update_audio_state() -> void:
	if ended:
		return
	if creature.is_hunting():
		Sfx.music("music_danger", 2.0, -2.0)
	elif train.moving:
		Sfx.music("music_travel", 4.0, -6.0)
	else:
		Sfx.music("music_stop", 4.0, -6.0)
	var off := not on_train()
	Sfx.ambience("amb_wind", lerpf(-10.0, -4.0, Track.openness(train.d)), 2.0)
	Sfx.ambience("amb_forest", -6.0 if off and not train.moving else -18.0, 3.0)

func _update_watchers(dt: float) -> void:
	for w in watchers:
		if w["done"]:
			continue
		var node: Node3D = w["node"]
		var mat: StandardMaterial3D = w["mat"]
		var active: bool = train.d > w["d"] - 170.0 and train.d < w["d"] + 15.0 and train.moving
		var target := 1.0 if active and w["seen"] < 1.6 else 0.0
		mat.albedo_color.a = move_toward(mat.albedo_color.a, target, dt * (0.8 if target > 0.0 else 1.5))
		node.visible = mat.albedo_color.a > 0.01
		if node.visible:
			var to := train.loco_pos() - node.global_position
			node.rotation.y = atan2(-to.x, -to.z)
			if creature._is_observed_point(player, node.global_position):
				if w["seen"] == 0.0:
					Sfx.play("sting", -16.0)
				w["seen"] += dt
		if train.d > w["d"] + 40.0 and not node.visible:
			w["done"] = true

# ------------------------------------------------------------------ events

func _on_whistle() -> void:
	creature.scare()
	if not _whistle_hint:
		_whistle_hint = true
		hud.message("The whistle screams through the trees.", 2.5)

func _on_impact(speed: float) -> void:
	player.add_shake(1.0)
	Sfx.play("crash", -10.0)
	if on_train() and speed > 4.0:
		player.take_damage(8.0)
	hud.message("The engine slams into the fallen tree.", 3.0)

func _on_crash(_speed: float) -> void:
	Sfx.play("crash", 2.0)
	player.add_shake(1.5)
	_defeat("derail")

func _on_obstacle_cleared(id: String) -> void:
	hud.message("The line is clear. Back to the engine.", 3.5)
	save_checkpoint()

func on_player_died() -> void:
	_defeat("dead")

func _stats() -> String:
	var t := int(elapsed)
	return "distance travelled  %.1f km   ·   time  %d:%02d   ·   coal burned  %d   ·   notes found  %d / %d" % [
		maxf(0.0, train.d) / 1000.0, t / 60, t % 60, train.coal_burned, notes_read.size(), NOTES.size()]

func _defeat(kind: String) -> void:
	if ended:
		return
	ended = true
	player.control = false
	Sfx.stop_music(1.0)
	Sfx.duck_ambience(-20.0, 1.0)
	var title := ""
	var sub := ""
	match kind:
		"dead":
			title = "You looked away."
			sub = "The fog closed in. Somewhere down the line the engine kept hissing for a while, and then it didn't."
			var tw := create_tween()
			tw.tween_property(player, "cine_rot", Vector3(0.6, 0.0, 1.2), 1.4).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(player, "cine_offset", Vector3(0, -1.3, 0), 1.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			Sfx.muffle(true, 400.0)
		"derail":
			title = "Derailed."
			sub = "The engine hit the fallen tree at speed and left the rails. Greyhaven never heard the whistle."
		"stranded":
			title = "Stranded."
			sub = "The fire went out and the fog came close. Something between the trees stopped pretending to be a tree."
	Sfx.play("sting", -4.0)
	await get_tree().create_timer(2.2).timeout
	hud.show_end(kind, title, sub, _stats())

func _victory() -> void:
	ended = true
	cinematic = false
	Sfx.music("music_ending", 3.0, -3.0)
	Sfx.stop_all_ambience(4.0)
	Sfx.ambience("amb_wind", -16.0, 4.0)
	hud.set_objective("")
	creature._vanish(true)
	creature.state = Creature.DORMANT
	for i in 3:
		get_tree().create_timer(1.0 + i * 3.2).timeout.connect(func() -> void: Sfx.play_at("bell", _site(4700.0, 6.4) + Vector3(0, 2.5, 0), 2.0, 1.0, 200.0))
	for tp in _townsfolk:
		var target: Vector3 = tp.global_position + (train.loco_pos() - tp.global_position).normalized() * 1.2
		target.y = tp.global_position.y
		var tw := create_tween()
		tw.tween_interval(randf_range(1.0, 3.0))
		tw.tween_property(tp, "global_position", target, 3.0)
	hud.show_subtitle("Greyhaven.", 1.5, 3.0, 1.5)
	await get_tree().create_timer(9.0).timeout
	var sub := "The bell of Greyhaven rang until dawn. You told them about the 7:10, the notes in the trees, and the tall thing that waits for you to blink. They believed you — the trees around Greyhaven had started falling too."
	if notes_read.has("barn"):
		sub += "\n\nA woman on the platform asked about M. You gave her the letter."
	player.control = false
	hud.show_end("win", "Survivor", sub, _stats())

# ------------------------------------------------------------------ checkpoints

func save_checkpoint() -> void:
	var cleared := []
	for ob in obstacles:
		if ob.is_cleared:
			cleared.append(ob.id)
	Game.checkpoint = {
		"train": train.state(),
		"axe": player.has_axe,
		"lantern": player.has_lantern,
		"health": maxf(player.health, 70.0),
		"carried": player.carried_coal,
		"collected": collected.duplicate(),
		"notes": notes_read.duplicate(),
		"cleared": cleared,
		"elapsed": elapsed,
		"darkness": darkness,
		"flags": [boarded_once, started_once, shoveled_once],
	}

func _restore(cp: Dictionary) -> void:
	train.restore(cp["train"])
	for id in cp["collected"]:
		if pickups.has(id):
			collected[id] = true
			if id == "kit_carriage":
				pickups[id]["node"].visible = false
			else:
				pickups[id]["node"].queue_free()
	notes_read = cp["notes"].duplicate()
	for ob in obstacles:
		if ob.id in cp["cleared"]:
			ob.set_cleared_instant()
		_stop_saved[ob.id] = ob.d < train.d + 300.0
		_warned[ob.id] = _stop_saved[ob.id]
	elapsed = cp["elapsed"]
	darkness = cp["darkness"]
	boarded_once = cp["flags"][0]
	started_once = cp["flags"][1]
	shoveled_once = cp["flags"][2]
	player.health = cp["health"]
	player.carried_coal = cp["carried"]
	if cp["axe"]:
		player.has_axe = true
		player.axe_view.visible = true
	if cp["lantern"]:
		player.has_lantern = true
		player.lantern_on = true
	var cab := train.cab_point()
	player.teleport(cab, _yaw_towards(cab, train.loco_pos() + Track.fwd(train.d) * 30.0))
	player.attached = train.cars["loco"]

func _begin_from_checkpoint() -> void:
	cinematic = false
	hud.fade.color.a = 1.0
	hud.fade_to(0.0, 1.5)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.message("Back at the controls.", 2.5)

# ------------------------------------------------------------------ intro

func _intro() -> void:
	cinematic = true
	player.control = false
	hud.fade.color.a = 1.0
	player.cine_offset = Vector3(0, -1.38, 0)
	player.cine_rot = Vector3(1.15, 0.3, 0.55)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.muffle(true, 280.0)
	Sfx.ambience("amb_wind", -10.0, 6.0)
	Sfx.ambience("amb_forest", -12.0, 6.0)
	Sfx.play("wake_muffled", 0.0)
	await get_tree().create_timer(1.0).timeout
	Sfx.play("heartbeat", -4.0)
	await hud.show_subtitle("cold.", 1.2, 1.6, 1.0).finished
	Sfx.play("breath", -4.0)
	Sfx.play("heartbeat", -6.0)
	await hud.show_subtitle("the whistle stopped.", 1.2, 1.8, 1.0).finished
	Sfx.play("whistle_distant", -8.0)
	await hud.show_subtitle("where did everyone go?", 1.2, 1.8, 1.2).finished
	var tw := create_tween().set_parallel(true)
	tw.tween_property(hud.fade, "color:a", 0.0, 3.5).set_trans(Tween.TRANS_SINE)
	tw.tween_method(Sfx.set_muffle_cutoff, 280.0, 18000.0, 5.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(player, "cine_rot", Vector3(0.35, 0.15, 0.25), 3.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(player, "cine_offset", Vector3(0, -1.25, 0), 3.5)
	await tw.finished
	Sfx.play("breath", -6.0)
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(player, "cine_rot", Vector3.ZERO, 2.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw2.tween_property(player, "cine_offset", Vector3.ZERO, 2.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw2.finished
	Sfx.muffle(false)
	cinematic = false
	player.control = true
	save_checkpoint()
	hud.message("Somewhere on the Ashford line. Greyhaven lies %.1f km ahead." % ((Track.STATION_D - train.d) / 1000.0), 5.0)
