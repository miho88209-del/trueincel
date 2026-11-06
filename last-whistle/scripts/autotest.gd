extends Node
## Automated playthrough used for verification (run with `-- --autotest`).
## Drives the real game systems, prints PASS/FAIL lines and saves screenshots.

var w
var shots := ""
var fails := 0
var passes := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	shots = OS.get_environment("LW_SHOTS")
	if shots == "":
		shots = OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(shots)

func say(s: String) -> void:
	print("[AUTOTEST] ", s)

func check(name: String, cond: bool, extra := "") -> void:
	if cond:
		passes += 1
	else:
		fails += 1
	say(("PASS  " if cond else "FAIL  ") + name + ("  (" + extra + ")" if extra != "" else ""))

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots + "/" + name + ".png")
	say("shot " + name)

func wait(t: float) -> void:
	await get_tree().create_timer(t, true, true, false).timeout

func wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()

func finish() -> void:
	say("SUMMARY pass=%d fail=%d" % [passes, fails])
	Engine.time_scale = 1.0
	get_tree().quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ menu

func _fast() -> void:
	# llvmpipe is slow: keep the automated run light, raise quality only for key shots
	Settings.set_val("quality", "Low")
	Settings.set_val("grass", 0.5)
	Settings.set_val("render_scale", 0.6)

func _pretty() -> void:
	Settings.set_val("quality", "High")
	Settings.set_val("render_scale", 0.8)

func pshot(name: String) -> void:
	_pretty()
	await wait(0.4)
	await shot(name)
	_fast()

func run_menu(m) -> void:
	if Game.autotest_args.get("mode", "") == "tour":
		await wait(1.0)
		Game.start_new()
		return
	await wait(3.0)
	await shot("01_menu")
	m.hovered = 0
	await wait(0.8)
	await shot("02_menu_hover_play")
	m.activate("settings")
	await wait(1.0)
	var panel: SettingsPanel = null
	for c in m.layer.get_children():
		if c is SettingsPanel:
			panel = c
	check("settings panel opens", panel != null)
	await shot("03_settings")
	Settings.set_val("quality", "Low")
	check("Low preset disables shadows/volumetrics", int(Settings.v["shadows"]) == 0 and not Settings.v["volumetric"] and float(Settings.v["render_scale"]) < 0.8)
	check("Low preset applied to viewport", is_equal_approx(get_viewport().scaling_3d_scale, 0.75))
	Settings.set_val("music", 0.35)
	Settings.save_settings()
	var cfg := ConfigFile.new()
	check("settings persisted to disk", cfg.load(Settings.PATH) == OK and cfg.get_value("settings", "quality") == "Low" and is_equal_approx(cfg.get_value("settings", "music"), 0.35))
	await wait(0.5)
	await shot("04_menu_low_quality")
	Settings.set_val("quality", "High")
	Settings.set_val("music", 0.7)
	if panel:
		panel.close()
	await wait(0.3)
	check("settings closes", not m.settings_open)
	_fast()
	m.activate("play")

# ------------------------------------------------------------------ world

func run(world) -> void:
	w = world
	var p: Player = w.player
	var t: Train = w.train
	if Game.autotest_args.get("phase", "") == "retry":
		await _run_retry()
		return
	if Game.autotest_args.get("mode", "") == "tour":
		await _run_tour()
		return
	Engine.time_scale = 1.0
	say("fps %d" % Engine.get_frames_per_second())
	w._intro()
	await wait(3.0)
	await shot("05_intro_black")
	var woke := await wait_until(func() -> bool: return not w.cinematic, 40.0)
	check("awakening intro completes and gives control", woke and p.control)
	await wait(1.0)
	await pshot("06_awake_beside_engine")
	check("first objective points at the note", w.hud._obj_text.contains("note"), w.hud._obj_text)
	w.read_note("engine")
	await wait(0.6)
	await shot("07_note")
	check("note pauses the game", get_tree().paused)
	w.hud.close_note()
	# ladder
	var loco: Node3D = t.cars["loco"]
	var bottom := loco.global_transform * Vector3(1.45 + 0.75, 0.0, 4.75)
	bottom.y = Track.height(bottom.x, bottom.z) + 0.4
	var lad_target := loco.global_transform * Vector3(0.0, 0.0, 4.75)
	p.teleport(bottom, w._yaw_towards(bottom, Vector3(lad_target.x, bottom.y, lad_target.z)))
	await wait(0.5)
	await pshot("08_ladder")
	Input.action_press("move_forward")
	var climbed := await wait_until(func() -> bool: return t.is_in_cab(p.global_position), 10.0)
	Input.action_release("move_forward")
	check("climbs the ladder into the cab", climbed)
	await wait(0.5)
	# firing up
	p.teleport(t.cab_point(), w._yaw_towards(t.cab_point(), loco.global_position))
	p.attached = loco
	p.pitch = -0.35
	await wait(0.3)
	check("objective asks for coal", w.hud._obj_text.to_lower().contains("coal"), w.hud._obj_text)
	var coal0 := t.tender_coal
	for i in 3:
		t.shovel(p)
		await wait(1.3)
	check("shovelling uses tender coal and feeds the fire", t.tender_coal == coal0 - 3 and t.fire > 50.0, "fire=%.1f tender=%d" % [t.fire, t.tender_coal])
	await shot("09_firebox")
	Engine.time_scale = 4.0
	var press := await wait_until(func() -> bool: return t.pressure > 0.6, 40.0)
	Engine.time_scale = 1.0
	check("steam pressure builds", press, "p=%.2f" % t.pressure)
	t.toggle_brake()
	t.set_notch(4)
	var moving := await wait_until(func() -> bool: return t.v > 4.0, 25.0)
	check("train starts and accelerates", moving, "v=%.1f" % t.v)
	p.pitch = -0.05
	p.yaw = w._yaw_towards(p.global_position, loco.global_transform * Vector3(0, 2, -30))
	var rel0: Vector3 = loco.global_transform.affine_inverse() * p.global_position
	await wait(2.0)
	var rel1: Vector3 = loco.global_transform.affine_inverse() * p.global_position
	check("player rides the moving train", rel0.distance_to(rel1) < 0.3, "drift=%.2f v=%.1f" % [rel0.distance_to(rel1), t.v])
	await pshot("10_cab_moving")
	# walk back into the carriage while moving
	var car: Node3D = t.cars["carriage"]
	p.teleport(car.global_transform * Vector3(0, Train.FLOOR + 0.05, 3.0), 0.0)
	p.yaw = w._yaw_towards(p.global_position, car.global_transform * Vector3(0, Train.FLOOR, -5.0))
	p.attached = car
	await wait(0.5)
	say("carriage: attached=%s floor=%s brake=%s pos=%s" % [p.attached.name if p.attached else "null", p.is_on_floor(), t.brake, str(car.global_transform.affine_inverse() * p.global_position)])
	await wait(1.0)
	var crel: Vector3 = car.global_transform.affine_inverse() * p.global_position
	check("player stands inside the moving carriage", absf(crel.x) < 1.4 and absf(crel.z) < 7.0 and crel.y > 1.2, str(crel))
	await pshot("11_carriage_interior")
	# jump ahead along the line towards the first fallen tree
	p.teleport(t.cab_point(), 0.0)
	p.attached = loco
	check("dead-man brake did not trip with the player aboard", not t.brake)
	t.brake = false
	t.set_notch(3)
	t.d = 640.0
	t.v = 14.0
	await wait(0.2)
	p.yaw = w._yaw_towards(p.global_position, loco.global_transform * Vector3(0, 2, -30))
	var ob: Obstacle = w.obstacles[0]
	var near := await wait_until(func() -> bool: return ob.d - (t.d + Train.FRONT) < 110.0, 30.0)
	check("first obstacle warning reached", near and w._warned.has(ob.id))
	await pshot("12_tree_ahead")
	t.toggle_brake()
	t.set_notch(0)
	var stopped := await wait_until(func() -> bool: return not t.moving, 20.0)
	check("train brakes to a stop before the tree", stopped and not w.ended and t.d + Train.FRONT <= ob.d, "gap=%.1f" % (ob.d - t.d - Train.FRONT))
	await wait(0.5)
	check("checkpoint saved at the stop", not Game.checkpoint.is_empty() and absf(Game.checkpoint["train"]["d"] - t.d) < 1.0)
	check("objective asks for the axe", w.hud._obj_text.to_lower().contains("axe"), w.hud._obj_text)
	# axe
	t.axe_prop.visible = false
	p.give_axe()
	var stand := Track.pos(ob.d - 2.1, Track.BALLAST_Y + 0.05)
	p.teleport(stand, w._yaw_towards(stand, Track.pos(ob.d + 5.0, 0)))
	p.attached = null
	p.pitch = -0.42
	await wait(0.6)
	await pshot("13_axe_at_tree")
	for i in ob.hits_needed + 2:
		Input.action_press("attack")
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release("attack")
		await wait(0.75)
		if ob.is_cleared:
			break
	check("axe chops through the fallen tree", ob.is_cleared, "hits=%d/%d" % [ob.hits, ob.hits_needed])
	await wait(2.0)
	await pshot("14_tree_cleared")
	check("line unblocked", w.block_d(t.d) > ob.d + 1.0)
	# the forest threat
	p.teleport(Track.side(ob.d - 30.0, 7.0, 0.3), 0.0)
	Engine.time_scale = 3.0
	var watch := await wait_until(func() -> bool: return w.creature.state != Creature.DORMANT and w.creature.visible, 40.0)
	check("creature begins watching while the player is exposed", watch)
	var stalk := await wait_until(func() -> bool: return w.creature.state == Creature.STALK and w.creature.visible, 40.0)
	Engine.time_scale = 1.0
	check("creature starts stalking", stalk)
	if stalk:
		var c: Creature = w.creature
		p.yaw = w._yaw_towards(p.global_position, c.global_position)
		p.pitch = 0.05
		await wait(1.0)
		await pshot("15_creature_seen")
		var cp0 := c.global_position
		await wait(1.5)
		check("creature freezes while observed", c.observed and c.global_position.distance_to(cp0) < 0.05, "obs=%s moved=%.2f" % [c.observed, c.global_position.distance_to(cp0)])
		p.yaw += PI
		var d0 := c.global_position.distance_to(p.global_position)
		await wait(2.0)
		var d1 := c.global_position.distance_to(p.global_position)
		check("creature approaches when unobserved", d1 < d0 - 2.0, "%.1f -> %.1f" % [d0, d1])
		var h0 := p.health
		var struck := await wait_until(func() -> bool: return p.health < h0, 25.0)
		check("creature strikes when it reaches the player", struck and p.health > 0.0, "hp=%.0f" % p.health)
		await wait(0.4)
		await shot("16_struck")
	# coal
	w._collect("coal_shack")
	check("coal sack picked up", p.carried_coal == 3)
	var before := t.tender_coal
	t.deposit(p)
	check("coal tipped into tender", t.tender_coal == before + 3 and p.carried_coal == 0)
	w._collect("bandage_shack")
	check("bandages heal", p.health > 70.0, "hp=%.0f" % p.health)
	# whistle
	p.teleport(t.cab_point(), 0.0)
	p.attached = loco
	w.creature.exposure = 30.0
	t.blow_whistle()
	await wait(0.2)
	check("whistle drives the creature off", w.creature.state == Creature.DORMANT and w.creature.cooldown > 10.0)
	# run to the end of the line
	for o in w.obstacles:
		if not o.is_cleared:
			o.set_cleared_instant()
	t.fire = 80.0
	t.pressure = 1.0
	t.d = 4300.0
	t.v = 13.0
	t.brake = false
	t.set_notch(2)
	w.darkness = 0.78
	await wait(0.3)
	p.yaw = w._yaw_towards(p.global_position, loco.global_transform * Vector3(0, 2, -30))
	var lights := await wait_until(func() -> bool: return t.d > 4480.0, 40.0)
	await pshot("17_greyhaven_lights")
	t.set_notch(1)
	var arrived := await wait_until(func() -> bool: return w.ended, 60.0)
	check("arrival at Greyhaven triggers the ending", arrived and lights and t.d > Track.STATION_ZONE, "d=%.0f" % t.d)
	p.yaw = w._yaw_towards(p.global_position, Track.side(4690.0, 8.0, 1.5))
	p.pitch = 0.0
	await wait(4.0)
	await pshot("18_arrival")
	var panel := await wait_until(func() -> bool: return w.hud.end_panel != null, 15.0)
	await wait(2.5)
	check("victory screen shown", panel)
	await shot("19_victory")
	# retry from the last checkpoint in a fresh world
	Game.autotest_args["phase"] = "retry"
	Game.autotest_args["expect_d"] = Game.checkpoint["train"]["d"]
	say("passes so far %d, fails %d" % [passes, fails])
	Game.autotest_args["passes"] = passes
	Game.autotest_args["fails"] = fails
	Game.retry()

func _run_retry() -> void:
	passes = Game.autotest_args.get("passes", 0)
	fails = Game.autotest_args.get("fails", 0)
	var p: Player = w.player
	var t: Train = w.train
	await wait(1.0)
	check("retry restores the last stop", absf(t.d - float(Game.autotest_args["expect_d"])) < 1.0 and t.is_in_cab(p.global_position), "d=%.1f" % t.d)
	await shot("20_retry_cab")
	p.teleport(Track.side(t.d, 5.0, 0.2), 0.0)
	p.attached = null
	await wait(0.3)
	p.take_damage(200.0)
	var dead := await wait_until(func() -> bool: return w.hud.end_panel != null, 10.0)
	await wait(2.5)
	check("death shows the defeat screen", dead and w.ended)
	await shot("21_death")
	finish()

# ------------------------------------------------------------------ visual tour

func _chunks_ready() -> bool:
	var r: Vector2i = w._wanted_range()
	for i in range(r.x, r.y + 1):
		if not w.chunks.has(i) or not w.chunks[i].built:
			return false
	return true

func _goto(train_d: float, cam_pos: Vector3, look_at: Vector3, dark: float, name: String) -> void:
	var p: Player = w.player
	var t: Train = w.train
	t.d = train_d
	t.v = 0.0
	t._place_cars()
	p.attached = null
	p.teleport(cam_pos, w._yaw_towards(cam_pos, look_at))
	var flat := Vector2(look_at.x - cam_pos.x, look_at.z - cam_pos.z).length()
	p.pitch = atan2(look_at.y - (cam_pos.y + Player.EYE), flat)
	w.darkness = dark
	w.cinematic = true
	await wait_until(_chunks_ready, 120.0)
	await wait(1.5)
	p.teleport(cam_pos, w._yaw_towards(cam_pos, look_at))
	p.pitch = atan2(look_at.y - (cam_pos.y + Player.EYE), flat)
	await wait(0.5)
	await shot(name)

func _run_tour() -> void:
	Settings.set_val("quality", "High")
	Settings.set_val("render_scale", 0.85)
	var p: Player = w.player
	var t: Train = w.train
	p.control = false
	w.hud.fade.color.a = 0.0
	w.hud.root.visible = false
	var sh: Vector3 = w._site(872.0, 17.0)
	await _goto(880.0, w._site(860.0, 2.5) + Vector3(0, 0.3, 0), sh + Vector3(0, 1.5, 0), 0.3, "t1_shack_stop")
	var ob: Obstacle = w.obstacles[0]
	await _goto(880.0, Track.side(905.0, 9.0, 0.2), Track.pos(890.0, 1.5), 0.35, "t2_tree_and_train")
	var nt: Vector3 = w._site(3305.0, 30.0)
	await _goto(3330.0, nt + Vector3(-9.0, 0.2, 7.0), nt + Vector3(0, 3.5, 0), 0.55, "t3_note_tree")
	var wr: Vector3 = w._site(2150.0, -10.5)
	await _goto(2160.0, Track.side(2135.0, -1.5, 0.3), wr + Vector3(0, 1.2, 0), 0.45, "t4_wreck")
	await _goto(640.0, Track.side(600.0, 1.0, 0.3), Track.side(700.0, -3.4, 4.0), 0.5, "t5_red_signal")
	# creature glimpse between the trees
	var cpos := Track.side(1200.0, 18.0)
	await _goto(1150.0, Track.side(1185.0, 3.0, 0.2), cpos + Vector3(0, 1.8, 0), 0.45, "t6_pre_creature")
	var c: Creature = w.creature
	c.global_position = cpos
	c._target_vis = 1.0
	c._visible_amt = 1.0
	c.visible = true
	c._mat.albedo_color.a = 1.0
	c.rotation.y = w._yaw_towards(cpos, p.global_position)
	await wait(0.3)
	await shot("t6_creature")
	c._vanish(true)
	c.visible = false
	# train in motion at dusk, seen from the trackside
	t.d = 1700.0
	t.fire = 90.0
	t.pressure = 1.0
	t.brake = false
	t.brake_force = 0.0
	t.set_notch(4)
	t.v = 9.0
	w.darkness = 0.62
	p.teleport(Track.side(1745.0, 7.5, 0.2), w._yaw_towards(Track.side(1745.0, 7.5), Track.pos(1700.0, 2.0)))
	await wait_until(_chunks_ready, 120.0)
	t.d = 1700.0
	await wait(2.5)
	p.yaw = w._yaw_towards(p.global_position, t.loco_pos() + Vector3(0, 2, 0))
	await shot("t7_train_moving_dusk")
	t.set_notch(0)
	t.v = 0.0
	# Greyhaven at night
	await _goto(4690.0, Track.side(4640.0, 6.0, 1.15), Track.side(4700.0, 3.0, 2.0), 0.85, "t8_greyhaven_night")
	await _goto(4600.0, Track.pos(4420.0, 3.0), Track.pos(4700.0, 4.0), 0.85, "t9_town_lights_far")
	await _goto(2000.0, Track.side(2030.0, -8.0, 0.2), Track.pos(2000.0, 2.0) + Track.fwd(2000.0) * -10.0, 0.88, "t10_carriage_night")
	finish()
