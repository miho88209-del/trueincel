extends Node
## Persistent player settings (user://settings.cfg). Scenes listen to `changed`
## and re-apply environment / light settings through the helpers below.

signal changed

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]
const SHADOW_NAMES := ["Off", "Low", "High"]
const AA_NAMES := ["Off", "FXAA", "MSAA 2x", "MSAA 4x"]
const VIEW_NAMES := ["Near", "Normal", "Far"]
const MODE_NAMES := ["Windowed", "Fullscreen"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]

const PRESETS := {
	"Low": {"shadows": 0, "post_fx": false, "volumetric": false, "ssao": false, "render_scale": 0.75, "grass": 0.35, "view": 0, "aa": 1},
	"Medium": {"shadows": 1, "post_fx": true, "volumetric": false, "ssao": false, "render_scale": 0.9, "grass": 0.6, "view": 1, "aa": 1},
	"High": {"shadows": 2, "post_fx": true, "volumetric": true, "ssao": true, "render_scale": 1.0, "grass": 0.85, "view": 1, "aa": 1},
	"Ultra": {"shadows": 2, "post_fx": true, "volumetric": true, "ssao": true, "render_scale": 1.0, "grass": 1.0, "view": 2, "aa": 3},
}

var v := {
	"quality": "High",
	"shadows": 2, "post_fx": true, "volumetric": true, "ssao": true,
	"render_scale": 1.0, "grass": 0.85, "view": 1, "aa": 1,
	"window_mode": 1, "resolution": 3, "vsync": true,
	"master": 0.85, "music": 0.7, "sfx": 0.9, "ambience": 0.8,
	"sensitivity": 0.22, "fov": 75.0, "invert_y": false,
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_display()
	apply_viewport()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in v.keys():
		if cfg.has_section_key("settings", k):
			var val = cfg.get_value("settings", k)
			if typeof(val) == typeof(v[k]) or (typeof(v[k]) == TYPE_FLOAT and typeof(val) == TYPE_INT):
				v[k] = val

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in v.keys():
		cfg.set_value("settings", k, v[k])
	cfg.save(PATH)

func get_val(key: String):
	return v[key]

## Changes one value. Graphics keys switch the preset label to "Custom" unless they match a preset.
func set_val(key: String, value) -> void:
	v[key] = value
	if key == "quality" and PRESETS.has(value):
		for pk in PRESETS[value]:
			v[pk] = PRESETS[value][pk]
	elif PRESETS["Low"].has(key):
		v["quality"] = _matching_preset()
	if key in ["window_mode", "resolution", "vsync"]:
		apply_display()
	apply_viewport()
	changed.emit()

func _matching_preset() -> String:
	for name in PRESETS:
		var ok := true
		for pk in PRESETS[name]:
			if not is_equal_approx(float(PRESETS[name][pk]), float(v[pk])):
				ok = false
				break
		if ok:
			return name
	return "Custom"

func reset_defaults() -> void:
	v["quality"] = "High"
	for pk in PRESETS["High"]:
		v[pk] = PRESETS["High"][pk]
	v["master"] = 0.85; v["music"] = 0.7; v["sfx"] = 0.9; v["ambience"] = 0.8
	v["sensitivity"] = 0.22; v["fov"] = 75.0; v["invert_y"] = false
	v["vsync"] = true
	apply_display()
	apply_viewport()
	changed.emit()

func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v["vsync"] else DisplayServer.VSYNC_DISABLED)
	if int(v["window_mode"]) == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var res: Vector2i = RESOLUTIONS[clampi(int(v["resolution"]), 0, RESOLUTIONS.size() - 1)]
		var screen := DisplayServer.screen_get_size()
		res = Vector2i(mini(res.x, screen.x), mini(res.y, screen.y))
		DisplayServer.window_set_size(res)
		DisplayServer.window_set_position(DisplayServer.screen_get_position() + (screen - res) / 2)

func apply_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(v["render_scale"]) < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(v["render_scale"])
	var aa := int(v["aa"])
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][aa]
	var sh := int(v["shadows"])
	RenderingServer.directional_shadow_atlas_set_size(4096 if sh == 2 else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if sh == 2 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if sh == 2 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	vp.positional_shadow_atlas_size = 4096 if sh == 2 else 2048

## Applies post-processing choices to an Environment built by a scene.
func configure_environment(env: Environment, volumetric_density: float = 0.0) -> void:
	var post: bool = v["post_fx"]
	env.glow_enabled = post
	env.ssao_enabled = bool(v["ssao"]) and post
	env.adjustment_enabled = post
	env.volumetric_fog_enabled = bool(v["volumetric"]) and volumetric_density > 0.0
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = volumetric_density

func configure_light(light: Light3D, important: bool = true) -> void:
	var sh := int(v["shadows"])
	light.shadow_enabled = sh > 0 and (important or sh == 2)
	if light is DirectionalLight3D:
		var dl := light as DirectionalLight3D
		dl.directional_shadow_max_distance = 60.0 if sh == 1 else 110.0
		dl.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sh == 1 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS

func view_ahead() -> float:
	return [220.0, 300.0, 400.0][int(v["view"])]

func mouse_sens() -> float:
	return float(v["sensitivity"]) * 0.01
