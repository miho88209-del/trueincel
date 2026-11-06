class_name Mats
extends RefCounted
## Shared materials (vertex-coloured PBR with triplanar noise detail) and shaders.

static var _cache := {}
static var _noise_tex: NoiseTexture2D
static var _fine_tex: NoiseTexture2D
static var _detail_tex: NoiseTexture2D

## Low-contrast variant used as albedo detail so surfaces read as weathered, not camouflaged.
static func detail_tex() -> NoiseTexture2D:
	if _detail_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 5
		n.frequency = 0.03
		n.fractal_octaves = 4
		var g := Gradient.new()
		g.set_color(0, Color(0.74, 0.74, 0.74))
		g.set_color(1, Color(1.0, 1.0, 1.0))
		_detail_tex = NoiseTexture2D.new()
		_detail_tex.width = 256
		_detail_tex.height = 256
		_detail_tex.seamless = true
		_detail_tex.noise = n
		_detail_tex.color_ramp = g
		_detail_tex.generate_mipmaps = true
	return _detail_tex

static func noise_tex() -> NoiseTexture2D:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 7
		n.frequency = 0.02
		n.fractal_octaves = 4
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 256
		_noise_tex.height = 256
		_noise_tex.seamless = true
		_noise_tex.noise = n
		_noise_tex.generate_mipmaps = true
	return _noise_tex

static func fine_tex() -> NoiseTexture2D:
	if _fine_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 3
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.08
		_fine_tex = NoiseTexture2D.new()
		_fine_tex.width = 256
		_fine_tex.height = 256
		_fine_tex.seamless = true
		_fine_tex.noise = n
		_fine_tex.generate_mipmaps = true
	return _fine_tex

static func _std(rough: float, metal := 0.0, detail := true, scale := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	if detail:
		m.albedo_texture = detail_tex()
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
	return m

static func _emit(col: Color, energy: float, fogless := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.vertex_color_use_as_albedo = false
	m.disable_fog = fogless
	return m

static func get_mat(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	var m: Material
	match key:
		"wood": m = _std(0.88, 0.0, true, 0.6)
		"metal": m = _std(0.5, 0.65, true, 0.8)
		"iron": m = _std(0.62, 0.45, true, 1.2)
		"rust": m = _std(0.8, 0.3, true, 0.4)
		"bark": m = _std(0.95, 0.0, true, 1.5)
		"foliage":
			var f := _std(1.0, 0.0, true, 0.35)
			f.backlight_enabled = true
			f.backlight = Color(0.1, 0.1, 0.1)
			m = f
		"stone": m = _std(0.92, 0.0, true, 0.5)
		"coal":
			var c := _std(0.35, 0.2, true, 2.0)
			m = c
		"cloth": m = _std(1.0, 0.0, true, 1.0)
		"paper":
			var p := _std(0.75, 0.0, false)
			p.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = p
		"plain": m = _std(0.8, 0.0, false)
		"glow": m = _emit(Color(1.0, 0.66, 0.32), 3.0)
		"glow_far": m = _emit(Color(1.0, 0.62, 0.3), 6.0, true)
		"window": m = _emit(Color(1.0, 0.6, 0.28), 1.6)
		"lamp_red": m = _emit(Color(1.0, 0.12, 0.06), 5.0)
		"lamp_green": m = _emit(Color(0.3, 1.0, 0.45), 4.0)
		"lamp_white": m = _emit(Color(1.0, 0.92, 0.78), 5.0)
		"fire": m = _emit(Color(1.0, 0.45, 0.12), 4.0)
		"ink":
			var k := _std(0.9, 0.0, false)
			m = k
		"ground": m = _shader_mat(GROUND_SHADER)
		"grass": m = _shader_mat(GRASS_SHADER)
		"ballast": m = _std(0.95, 0.0, true, 3.0)
		_:
			m = _std(0.9)
	_cache[key] = m
	return m

static func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("fine_tex", fine_tex())
	return m

## Separate instance so callers can animate emission energy (lamps, firebox, windows).
static func emissive(col: Color, energy: float, fogless := false) -> StandardMaterial3D:
	return _emit(col, energy, fogless)

const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D fine_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 grass_col : source_color = vec3(0.47, 0.48, 0.45);
uniform vec3 dry_col : source_color = vec3(0.56, 0.55, 0.50);
uniform vec3 dirt_col : source_color = vec3(0.22, 0.215, 0.20);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n1 = texture(noise_tex, wpos.xz * 0.004).r;
	float n2 = texture(noise_tex, wpos.xz * 0.03).r;
	float n3 = texture(fine_tex, wpos.xz * 0.35).r;
	float n4 = texture(noise_tex, wpos.xz * 0.6).r;
	vec3 c = mix(grass_col, dry_col, smoothstep(0.4, 0.7, n1));
	c = mix(dirt_col, c, smoothstep(0.28, 0.5, n2 + (n4 - 0.5) * 0.25));
	c *= 0.82 + 0.3 * n3;
	c = mix(c, COLOR.rgb, COLOR.a);
	ALBEDO = c;
	ROUGHNESS = 0.96;
	SPECULAR = 0.2;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D fine_tex : repeat_enable, filter_linear_mipmap;
uniform float wind = 1.0;
varying float hgt;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	hgt = clamp(VERTEX.y / 0.7, 0.0, 1.0);
	float gust = texture(noise_tex, wp.xz * 0.01 + vec2(TIME * 0.03, TIME * 0.02)).r;
	float sway = sin(TIME * 1.6 + wp.x * 0.35 + wp.z * 0.21) * 0.06 + (gust - 0.5) * 0.25;
	VERTEX.x += sway * hgt * hgt * wind;
	VERTEX.z += sway * 0.6 * hgt * hgt * wind;
}
void fragment() {
	vec3 c = COLOR.rgb * mix(0.45, 1.05, hgt);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.15);
}
"""
