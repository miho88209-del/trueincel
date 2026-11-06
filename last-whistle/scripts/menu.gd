extends Node3D
## Main menu: a lamplit table in the night carriage, with handwritten paper buttons.

const WOOD_SHADER := """
shader_type spatial;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float plank = floor(lp.z * 5.0 + 0.5);
	float pr = fract(sin(plank * 12.9898) * 43758.5453);
	float grain = texture(noise_tex, vec2(lp.x * 0.12 + pr, lp.z * 3.0 + pr * 7.0)).r;
	float fine = texture(noise_tex, vec2(lp.x * 1.2 + pr * 3.0, lp.z * 26.0)).r;
	float f = fract(lp.z * 5.0 + 0.5);
	float seam = smoothstep(0.0, 0.035, f) * smoothstep(1.0, 0.965, f);
	vec3 c = vec3(0.17, 0.16, 0.15) * (0.65 + pr * 0.55) * (0.7 + grain * 0.6) * (0.88 + fine * 0.25);
	c *= mix(0.25, 1.0, seam);
	ALBEDO = c;
	ROUGHNESS = 0.62 - grain * 0.2;
	SPECULAR = 0.35;
}
"""

const PAPER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float flutter = 0.0;
uniform float seed = 0.0;
uniform float lift = 0.0;
uniform float tint = 0.0;
void vertex() {
	float ex = abs(UV.x * 2.0 - 1.0);
	float ey = abs(UV.y * 2.0 - 1.0);
	float edge = smoothstep(0.4, 1.0, max(ex, ey));
	VERTEX.y += (ex * ex * 0.004 + ey * 0.002) + edge * sin(TIME * 2.1 + seed + VERTEX.x * 9.0) * (0.0015 + flutter * 0.004 + lift * 0.004);
}
void fragment() {
	vec2 g = floor(UV * vec2(120.0, 150.0));
	float n = fract(sin(dot(g + seed, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 p = vec3(0.86, 0.85, 0.81) * (0.965 + n * 0.035);
	float ex = max(abs(UV.x * 2.0 - 1.0), abs(UV.y * 2.0 - 1.0));
	p *= 1.0 - smoothstep(0.85, 1.0, ex) * 0.12;
	ALBEDO = p + vec3(0.06, 0.04, 0.02) * tint;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
"""

var cam: Camera3D
var env: Environment
var lamp_light: OmniLight3D
var lamp_glow: StandardMaterial3D
var moon: DirectionalLight3D
var papers: Array = []       # {node, label, action, base_y, mat}
var hovered = null
var busy := false
var fade: ColorRect
var layer: CanvasLayer
var settings_open := false
var _t := 0.0
var _clack_t := 1.5
var _whistle_t := 12.0
var _jolt := 0.0

func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Props.fonts()
	_build_scene()
	_build_ui()
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	Sfx.stop_all_ambience(0.5)
	Sfx.music("music_menu", 3.0, -3.0)
	Sfx.ambience("amb_rain", -9.0, 3.0)
	Sfx.ambience("train_rumble", -17.0, 3.0)
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 2.0)
	if Game.autotest:
		var at = load("res://scripts/autotest.gd").new()
		add_child(at)
		at.run_menu(self)

func _apply_settings() -> void:
	Settings.configure_environment(env, 0.05)
	Settings.configure_light(lamp_light, true)
	Settings.configure_light(moon, true)

func _build_scene() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.06
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.9
	env.ssao_intensity = 1.2
	env.ssao_radius = 0.25
	env.adjustment_saturation = 0.72
	env.adjustment_contrast = 1.08
	env.volumetric_fog_albedo = Color(0.85, 0.85, 0.85)
	env.volumetric_fog_length = 6.0
	env.volumetric_fog_anisotropy = 0.4
	env.volumetric_fog_ambient_inject = 0.0
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.position = Vector3(0, 1.6, 1.0)
	add_child(cam)
	cam.look_at(Vector3(0, 0, -0.06), Vector3.UP)
	cam.current = true
	# table
	var table := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.0, 3.0)
	table.mesh = pm
	var sh := Shader.new()
	sh.code = WOOD_SHADER
	var wm := ShaderMaterial.new()
	wm.shader = sh
	wm.set_shader_parameter("noise_tex", Mats.noise_tex())
	table.material_override = wm
	add_child(table)
	# lamp (top-left), moonlight through a window frame (shadow bars)
	var lamp := Node3D.new()
	lamp.position = Vector3(-0.92, 0, -0.5)
	add_child(lamp)
	var mk := MK.new()
	mk.cyl("metal", Transform3D(), 0.13, 0.11, 0.05, 12, Color(0.35, 0.3, 0.22))
	mk.cyl("metal", Transform3D(Basis(), Vector3(0, 0.05, 0)), 0.09, 0.07, 0.12, 12, Color(0.4, 0.34, 0.24))
	mk.cyl("metal", Transform3D(Basis(), Vector3(0, 0.38, 0)), 0.06, 0.07, 0.04, 10, Color(0.3, 0.27, 0.2))
	mk.build(lamp, "Lamp", true)
	var chimney := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045; cm.bottom_radius = 0.075; cm.height = 0.22; cm.radial_segments = 14
	chimney.mesh = cm
	lamp_glow = Mats.emissive(Color(1.0, 0.68, 0.38), 3.0)
	lamp_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lamp_glow.albedo_color.a = 0.75
	chimney.material_override = lamp_glow
	chimney.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chimney.position = Vector3(0, 0.28, 0)
	lamp.add_child(chimney)
	lamp_light = OmniLight3D.new()
	lamp_light.light_color = Color(1.0, 0.72, 0.45)
	lamp_light.light_energy = 1.6
	lamp_light.omni_range = 3.2
	lamp_light.omni_attenuation = 1.3
	lamp_light.shadow_enabled = true
	lamp_light.shadow_blur = 1.5
	lamp_light.position = Vector3(0, 0.3, 0)
	lamp_light.light_volumetric_fog_energy = 0.5
	lamp.add_child(lamp_light)
	moon = DirectionalLight3D.new()
	moon.basis = Basis.looking_at(Vector3(-0.55, -1.0, -0.35).normalized(), Vector3.UP)
	moon.light_color = Color(0.75, 0.8, 0.95)
	moon.light_energy = 0.42
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 6.0
	moon.light_volumetric_fog_energy = 2.0
	add_child(moon)
	var bars := MK.new()
	for i in 4:
		bars.boxp("iron", Vector3(0.9 + i * 0.32, 1.1, 0.25 - i * 0.05), Vector3(0.05, 0.05, 2.5), Color.BLACK, 0.0)
	bars.boxp("iron", Vector3(1.3, 1.1, -0.1), Vector3(1.6, 0.05, 0.06), Color.BLACK)
	var bmi := bars.build(self, "WindowFrame", true)
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# papers
	_paper(Vector3(0.0, 0, 0.0), Vector2(0.34, 0.42), 0.04, "play", 150, "play", "the 7:10 to Greyhaven")
	_paper(Vector3(-0.53, 0, 0.15), Vector2(0.31, 0.23), 0.14, "settings", 100, "settings")
	_paper(Vector3(-0.17, 0, 0.44), Vector2(0.24, 0.17), -0.06, "exit", 100, "exit")
	_paper(Vector3(-0.03, 0, -0.39), Vector2(0.52, 0.13), 0.02, "THE LAST WHISTLE", 70, "", "", true)
	_paper(Vector3(-0.63, 0, -0.17), Vector2(0.2, 0.15), 0.42, "07:10", 80, "")
	_paper(Vector3(0.5, 0, -0.27), Vector2(0.27, 0.16), -0.3, "don't look away", 62, "")
	_paper(Vector3(0.56, 0, 0.17), Vector2(0.27, 0.3), 0.09, "the whistle\nkeeps it\nback", 64, "")
	_paper(Vector3(0.33, 0, 0.46), Vector2(0.22, 0.12), -0.18, "Greyhaven  4.7 km", 46, "")
	# mug with steam, pencil
	var mug := MK.new()
	mug.cyl("metal", Transform3D(Basis(), Vector3(0.86, 0, -0.08)), 0.06, 0.065, 0.13, 14, Color(0.5, 0.5, 0.5))
	mug.cyl("coal", Transform3D(Basis(), Vector3(0.86, 0.1, -0.08)), 0.055, 0.055, 0.02, 14, Color(0.06, 0.04, 0.03))
	mug.cyl_between("metal", Vector3(0.93, 0.03, -0.08), Vector3(0.95, 0.1, -0.08), 0.012, 0.012, 6, Color(0.5, 0.5, 0.5))
	mug.cyl_between("wood", Vector3(0.38, 0.006, 0.3), Vector3(0.62, 0.006, 0.2), 0.006, 0.006, 6, Color(0.35, 0.3, 0.24))
	mug.build(self, "MugPencil", true)
	_steam(Vector3(0.86, 0.13, -0.08))
	_dust()

func _paper(pos: Vector3, size: Vector2, yaw: float, text: String, font_size: int, action: String, sub := "", typed := false) -> void:
	var node := Node3D.new()
	node.position = pos + Vector3(0, 0.002 + papers.size() * 0.0004, 0)
	node.rotation.y = yaw
	add_child(node)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = PAPER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("seed", randf() * 10.0)
	mi.material_override = m
	node.add_child(mi)
	var col := Color(0.16, 0.15, 0.15) if action != "" else Color(0.3, 0.29, 0.28)
	var l := Props.label(text, font_size, col, not typed, 0.0012)
	l.rotation.x = -PI / 2
	l.position = Vector3(0, 0.009, -0.03 if sub != "" else 0.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.width = size.x / 0.0012 * 0.92
	node.add_child(l)
	if sub != "":
		var s := Props.label(sub, 40, Color(0.35, 0.33, 0.31), true, 0.0012)
		s.rotation.x = -PI / 2
		s.position = Vector3(0, 0.009, 0.11)
		node.add_child(s)
	if action != "":
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(size.x, 0.02, size.y)
		cs.shape = bs
		body.add_child(cs)
		body.set_meta("paper", papers.size())
		node.add_child(body)
	papers.append({"node": node, "label": l, "action": action, "base": node.position, "mat": m, "yaw": yaw, "col": col})

func _steam(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 3.5
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 0.04
	pm.initial_velocity_max = 0.09
	pm.gravity = Vector3(0.01, 0.02, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var sc := Curve.new(); sc.add_point(Vector2(0, 0.4)); sc.add_point(Vector2(1, 1.6))
	var sct := CurveTexture.new(); sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.2, Color(1, 1, 1, 0.12))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rg := Gradient.new(); rg.set_color(0, Color(1, 1, 1, 1)); rg.set_color(1, Color(1, 1, 1, 0))
	var rt := GradientTexture2D.new(); rt.gradient = rg; rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5); rt.fill_to = Vector2(0.5, 0.0)
	m.albedo_texture = rt
	q.material = m
	p.draw_pass_1 = q
	add_child(p)

func _dust() -> void:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.position = Vector3(-0.3, 0.45, -0.2)
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 2, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.4, 0.6)
	pm.gravity = Vector3(0.0, -0.004, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.02
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.05
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 0.7))
	g.add_point(0.8, Color(1, 1, 1, 0.7))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new(); gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.004, 0.004)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(1, 0.95, 0.85)
	m.emission_energy_multiplier = 1.5
	q.material = m
	p.draw_pass_1 = q
	add_child(p)

func _build_ui() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	var hint := Label.new()
	var ls := LabelSettings.new()
	ls.font = Props.font_type
	ls.font_size = 20
	ls.font_color = Color(0.55, 0.53, 0.5, 0.6)
	hint.label_settings = ls
	hint.text = "click a note"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -300; hint.offset_top = -60; hint.offset_right = -40; hint.offset_bottom = -30
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(hint)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)

func _process(dt: float) -> void:
	_t += dt
	# lamp flicker
	var f := 0.9 + 0.06 * sin(_t * 13.0) * sin(_t * 5.3) + 0.04 * sin(_t * 31.0)
	if randf() < dt * 0.25:
		f *= 0.7
	lamp_light.light_energy = 1.6 * f
	lamp_glow.emission_energy_multiplier = 3.0 * f
	# carriage rocking and rail joints
	_clack_t -= dt
	if _clack_t <= 0.0:
		_clack_t = randf_range(1.6, 2.4)
		_jolt = 1.0
		Sfx.play("rail_clack", -20.0, randf_range(0.85, 0.95))
	_jolt = maxf(0.0, _jolt - dt * 4.0)
	cam.position = Vector3(sin(_t * 0.35) * 0.012, 1.6 + _jolt * 0.002, 1.0 + sin(_t * 0.27) * 0.008)
	cam.look_at(Vector3(sin(_t * 0.21) * 0.01, 0, -0.06), Vector3(sin(_t * 0.6) * 0.008, 1, 0))
	_whistle_t -= dt
	if _whistle_t <= 0.0:
		_whistle_t = randf_range(28.0, 45.0)
		Sfx.play("whistle_distant", -12.0, randf_range(0.95, 1.02))
	# paper hover animation
	for i in papers.size():
		var p: Dictionary = papers[i]
		var on: bool = hovered == i and not busy and not settings_open
		var node: Node3D = p["node"]
		var target_y: float = p["base"].y + (0.035 if on else 0.0)
		node.position.y = lerpf(node.position.y, target_y, minf(1.0, dt * 10.0))
		node.rotation.y = lerp_angle(node.rotation.y, p["yaw"] + (0.04 if on else 0.0), minf(1.0, dt * 8.0))
		node.rotation.x = lerpf(node.rotation.x, 0.12 if on else 0.0, minf(1.0, dt * 8.0))
		(p["mat"] as ShaderMaterial).set_shader_parameter("lift", (node.position.y - p["base"].y) / 0.035)
		var lbl: Label3D = p["label"]
		lbl.modulate = lbl.modulate.lerp(Color(0.42, 0.1, 0.06) if on else p["col"], minf(1.0, dt * 10.0))

func _physics_process(_dt: float) -> void:
	if busy or settings_open:
		hovered = null
		return
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var to := from + cam.project_ray_normal(mp) * 5.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	var h = null
	if hit and hit.collider.has_meta("paper"):
		h = hit.collider.get_meta("paper")
	if h != hovered and h != null:
		Sfx.play("ui_hover", -8.0, randf_range(0.9, 1.1))
	hovered = h

func _unhandled_input(event: InputEvent) -> void:
	if busy or settings_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and hovered != null:
		activate(papers[hovered]["action"])
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]:
		activate("play")

func activate(action: String) -> void:
	match action:
		"play":
			busy = true
			Sfx.play("ui_click", -2.0)
			Sfx.stop_music(1.8)
			Sfx.stop_all_ambience(1.8)
			var tw := create_tween()
			tw.tween_property(fade, "color:a", 1.0, 1.8)
			tw.tween_interval(0.4)
			tw.tween_callback(Game.start_new)
		"settings":
			Sfx.play("ui_click", -2.0)
			settings_open = true
			var sp := SettingsPanel.new()
			sp.closed.connect(func() -> void: settings_open = false)
			layer.add_child(sp)
			layer.move_child(fade, layer.get_child_count() - 1)
		"exit":
			busy = true
			Sfx.play("ui_click", -2.0)
			var tw := create_tween()
			tw.tween_property(fade, "color:a", 1.0, 0.8)
			tw.tween_callback(Game.quit)
