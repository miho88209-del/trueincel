class_name Props
extends RefCounted
## Procedural low-poly models. Meshes are cached; structures return Node3D trees
## with MeshInstance3D + StaticBody3D colliders.

const BARK := Color(0.115, 0.11, 0.105)
const CANOPY := Color(0.085, 0.09, 0.085)
const PINE := Color(0.075, 0.088, 0.08)
const PALE := Color(0.5, 0.49, 0.46)
const WOOD := Color(0.31, 0.29, 0.26)
const WOOD_D := Color(0.17, 0.16, 0.15)
const RUST := Color(0.36, 0.25, 0.19)
const IRON := Color(0.11, 0.11, 0.12)
const STONE := Color(0.36, 0.36, 0.35)
const PAPER := Color(0.86, 0.85, 0.8)

static var _mesh_cache := {}
static var font_hand: Font
static var font_type: Font

static func fonts() -> void:
	if font_hand == null:
		font_hand = load("res://fonts/Caveat.ttf")
		font_type = load("res://fonts/SpecialElite-Regular.ttf")

static func cached(key: String, builder: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = builder.call()
	return _mesh_cache[key]

static func _shade(c: Color, rng: RandomNumberGenerator, amt := 0.08) -> Color:
	var f := 1.0 + rng.randf_range(-amt, amt)
	return Color(c.r * f, c.g * f, c.b * f)

# ---------------------------------------------------------------- vegetation

static func tree_broad(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var mk := MK.new()
	var h := rng.randf_range(3.2, 4.6)
	var lean := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
	var top := Vector3(0, h, 0) + lean
	mk.cyl_between("bark", Vector3(0, -0.3, 0), Vector3(0, h * 0.5, 0) + lean * 0.3, 0.32, 0.24, 6, BARK)
	mk.cyl_between("bark", Vector3(0, h * 0.5, 0) + lean * 0.3, top, 0.24, 0.16, 6, BARK)
	var crown := top + Vector3(0, 1.4, 0)
	for i in rng.randi_range(3, 4):
		var a := TAU * i / 4.0 + rng.randf_range(-0.4, 0.4)
		var tip := crown + Vector3(cos(a) * rng.randf_range(1.6, 2.6), rng.randf_range(-0.3, 1.0), sin(a) * rng.randf_range(1.6, 2.6))
		mk.cyl_between("bark", top - Vector3(0, 0.4, 0), tip, 0.13, 0.05, 5, BARK)
	for i in rng.randi_range(7, 10):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.4, 2.7)
		var c := crown + Vector3(cos(a) * r, rng.randf_range(-0.4, 1.3), sin(a) * r)
		var s := rng.randf_range(1.3, 2.1)
		var xf := Transform3D(Basis.from_scale(Vector3(s, s * 0.62, s)).rotated(Vector3.UP, rng.randf() * TAU), c)
		mk.blob("foliage", xf, 1.0, _shade(CANOPY, rng), 0.3, seed * 31 + i, 3, 6)
	return mk.commit()

static func tree_pine(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var mk := MK.new()
	var h := rng.randf_range(9.0, 13.0)
	mk.cyl("bark", Transform3D(Basis(), Vector3(0, -0.3, 0)), 0.26, 0.08, h, 6, BARK)
	var layers := rng.randi_range(5, 7)
	for i in layers:
		var t := float(i) / layers
		var y := lerpf(1.8, h - 2.0, t)
		var r := lerpf(2.7, 0.7, t) * rng.randf_range(0.85, 1.1)
		var off := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(0, y, 0) + off)
		mk.cyl("foliage", xf, r, 0.0, lerpf(2.6, 2.0, t), 7, _shade(PINE, rng))
	return mk.commit()

static func _branch(mk: MK, rng: RandomNumberGenerator, a: Vector3, dir: Vector3, length: float, r: float, depth: int, col: Color, tips: Array) -> void:
	var b := a + dir * length
	mk.cyl_between("bark", a, b, r, r * 0.62, 5 if depth > 1 else 4, col, depth == 0)
	if depth <= 0:
		tips.append(b)
		return
	var n := rng.randi_range(2, 3)
	for i in n:
		var nd := (dir + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.05, 0.6), rng.randf_range(-0.9, 0.9))).normalized()
		_branch(mk, rng, b, nd, length * rng.randf_range(0.55, 0.75), r * 0.6, depth - 1, col, tips)

static func tree_bare(seed: int, scale := 1.0, col := BARK, tips: Array = []) -> ArrayMesh:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var mk := MK.new()
	var h := rng.randf_range(3.5, 5.0) * scale
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 1, rng.randf_range(-0.25, 0.25)).normalized()
	mk.cyl_between("bark", Vector3(0, -0.4, 0), lean * h, 0.34 * scale, 0.2 * scale, 6, col)
	for i in rng.randi_range(3, 4):
		var d := (lean + Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 0.9), rng.randf_range(-1, 1))).normalized()
		_branch(mk, rng, lean * h * rng.randf_range(0.7, 1.0), d, 2.2 * scale, 0.17 * scale, 2, col, tips)
	return mk.commit()

static func tree_snag(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var mk := MK.new()
	var h := rng.randf_range(6.0, 9.0)
	mk.cyl("bark", Transform3D(Basis(), Vector3(0, -0.3, 0)), 0.2, 0.1, h, 6, PALE)
	for i in rng.randi_range(2, 4):
		var y := rng.randf_range(h * 0.4, h * 0.9)
		var a := rng.randf() * TAU
		mk.cyl_between("bark", Vector3(0, y, 0), Vector3(cos(a) * 1.3, y + 0.8, sin(a) * 1.3), 0.06, 0.02, 4, PALE)
	return mk.commit()

static func grass_tuft(seed: int, tall := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := rng.randi_range(6, 9) if not tall else rng.randi_range(4, 6)
	for i in blades:
		var a := TAU * i / blades + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var h := rng.randf_range(0.3, 0.62) * (1.6 if tall else 1.0)
		var lean := rng.randf_range(0.15, 0.45)
		var w := rng.randf_range(0.035, 0.06)
		var side := dir.cross(Vector3.UP).normalized() * w
		var base := dir * 0.04
		var tip := dir * (lean * h + 0.05) + Vector3(0, h, 0)
		var g := rng.randf_range(0.55, 0.7)
		var col := Color(g, g * 1.0, g * 0.93)
		var n := (side).cross(tip - base).normalized()
		for p in [base - side, tip, base + side]:
			st.set_color(col)
			st.set_normal((n + Vector3.UP * 0.8).normalized())
			st.add_vertex(p)
	var m := st.commit()
	m.surface_set_material(0, Mats.get_mat("grass"))
	return m

static func leaf_patch(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var mk := MK.new()
	var c := Vector3(0, 0.03, 0)
	var n := 9
	var pts := []
	for i in n:
		var a := TAU * i / n
		var r := rng.randf_range(0.25, 0.6)
		pts.append(Vector3(cos(a) * r, 0.03 + rng.randf_range(0, 0.05), sin(a) * r))
	for i in n:
		mk.tri("foliage", c, pts[(i + 1) % n], pts[i], Color(0.07, 0.075, 0.07))
	return mk.commit()

static func rock(seed: int) -> ArrayMesh:
	var mk := MK.new()
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	mk.blob("stone", Transform3D(Basis.from_scale(Vector3(1, 0.55, 0.8)), Vector3(0, 0.1, 0)), rng.randf_range(0.35, 0.8), _shade(STONE, rng, 0.15), 0.35, seed, 3, 6)
	return mk.commit()

# ---------------------------------------------------------------- helpers

static func label(text: String, size := 64, col := Color(0.1, 0.09, 0.08), hand := true, px := 0.004) -> Label3D:
	fonts()
	var l := Label3D.new()
	l.text = text
	l.font = font_hand if hand else font_type
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func omni(col: Color, energy: float, rng_m: float, shadows := false) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = col
	o.light_energy = energy
	o.omni_range = rng_m
	o.omni_attenuation = 1.4
	o.shadow_enabled = shadows
	o.distance_fade_enabled = true
	o.distance_fade_begin = 70.0
	o.distance_fade_length = 30.0
	o.light_volumetric_fog_energy = 0.6
	return o

# ---------------------------------------------------------------- structures

## Plank wall along local X from x0 to x1 at z, with optional gaps [[a,b,ytop]].
static func _plank_wall(mk: MK, rng: RandomNumberGenerator, x0: float, x1: float, z: float, h0: float, h1: float, gaps: Array, along_z := false, collide := true) -> void:
	var w := 0.24
	var x := x0
	while x < x1 - 0.01:
		var cx := x + w * 0.5
		var t := (cx - x0) / maxf(x1 - x0, 0.01)
		var hh := lerpf(h0, h1, t) * rng.randf_range(0.97, 1.0)
		var bottom := 0.0
		var skip := false
		for g in gaps:
			if cx > g[0] and cx < g[1]:
				if g[2] <= 0.0:
					skip = true
				else:
					hh = minf(hh, g[2])
		if rng.randf() < 0.06:
			hh *= rng.randf_range(0.4, 0.8)   # broken plank
		if not skip:
			var ph := hh - bottom
			var col := _shade(WOOD, rng, 0.18) if rng.randf() > 0.15 else WOOD_D
			var pos := Vector3(cx, bottom + ph * 0.5, z)
			var size := Vector3(w * 0.92, ph, 0.06)
			if along_z:
				pos = Vector3(z, bottom + ph * 0.5, cx)
				size = Vector3(0.06, ph, w * 0.92)
			mk.boxp("wood", pos, size, col)
		x += w
	if collide:
		# coarse colliders per wall segment between gaps
		var segs := [[x0, x1]]
		for g in gaps:
			if g[2] > 0.0:
				continue
			var nsegs := []
			for s in segs:
				if g[0] > s[0] and g[1] < s[1]:
					nsegs.append([s[0], g[0]]); nsegs.append([g[1], s[1]])
				else:
					nsegs.append(s)
			segs = nsegs
		for s in segs:
			var len: float = s[1] - s[0]
			var cxs: float = (s[0] + s[1]) * 0.5
			var hh := maxf(h0, h1)
			if along_z:
				mk.cols.append([Transform3D(Basis(), Vector3(z, hh * 0.5, cxs)), Vector3(0.12, hh, len)])
			else:
				mk.cols.append([Transform3D(Basis(), Vector3(cxs, hh * 0.5, z)), Vector3(len, hh, 0.12)])

static func _corrugated_roof(mk: MK, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, holes := 0.1) -> void:
	# sheets run from z0 (height y0) to z1 (height y1)
	var w := 0.16
	var x := x0
	var i := 0
	var dz := z1 - z0
	var dy := y1 - y0
	var len := sqrt(dz * dz + dy * dy)
	var ang := atan2(dy, dz)
	while x < x1:
		if rng.randf() > holes:
			var col := _shade(RUST, rng, 0.2) * (1.0 if i % 2 == 0 else 0.8)
			col.a = 1.0
			var b := Basis(Vector3.RIGHT, -ang)
			var c := Vector3(x + w * 0.5, (y0 + y1) * 0.5 + (0.03 if i % 2 == 0 else 0.0), (z0 + z1) * 0.5)
			mk.box("rust", Transform3D(b, c), Vector3(w, 0.025, len * rng.randf_range(0.9, 1.0)), col)
		x += w
		i += 1

static func shack(seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var root := Node3D.new()
	var mk := MK.new()
	var W := 5.0; var D := 4.0
	mk.boxp("wood", Vector3(0, 0.06, 0), Vector3(W, 0.12, D), WOOD_D, 0.0, true)
	# front wall (+z) with door, back wall with window, sides
	_plank_wall(mk, rng, -W / 2, W / 2, D / 2, 2.6, 2.6, [[-0.5, 0.5, 0.0], [1.2, 2.0, 1.0]])
	_plank_wall(mk, rng, -W / 2, W / 2, -D / 2, 2.0, 2.0, [[-1.0, 0.2, 1.0]])
	_plank_wall(mk, rng, -D / 2, D / 2, -W / 2, 2.0, 2.6, [[0.2, 1.1, 0.0]], true)
	_plank_wall(mk, rng, -D / 2, D / 2, W / 2, 2.0, 2.6, [[-0.8, 0.4, 1.0]], true)
	for cx in [-W / 2, W / 2]:
		for cz in [-D / 2, D / 2]:
			mk.boxp("wood", Vector3(cx, 1.3, cz), Vector3(0.14, 2.7, 0.14), WOOD_D)
	_corrugated_roof(mk, rng, -W / 2 - 0.3, W / 2 + 0.3, -D / 2 - 0.4, D / 2 + 0.5, 2.05, 2.7, 0.12)
	# table and shelf inside
	mk.boxp("wood", Vector3(-1.3, 0.8, -1.2), Vector3(1.3, 0.06, 0.8), WOOD, 0.0, true)
	for lx: float in [-1.85, -0.75]:
		for lz: float in [-1.5, -0.9]:
			mk.boxp("wood", Vector3(lx, 0.4, lz), Vector3(0.06, 0.8, 0.06), WOOD_D)
	mk.boxp("wood", Vector3(1.6, 0.35, -1.3), Vector3(0.9, 0.7, 0.7), _shade(WOOD, rng), 0.3, true)
	mk.build(root, "Shack", true, 1, {"surface": "wood"})
	return root

static func hut(seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var root := Node3D.new()
	var mk := MK.new()
	var W := 3.6; var D := 3.2
	mk.boxp("wood", Vector3(0, 0.06, 0), Vector3(W, 0.12, D), WOOD_D, 0.0, true)
	# log walls
	for i in 8:
		var y := 0.15 + i * 0.27
		var col := _shade(WOOD_D, rng, 0.2)
		if i < 7:
			mk.boxp("bark", Vector3(-W / 2, y, 0), Vector3(0.26, 0.26, D + 0.3), col)
			mk.boxp("bark", Vector3(W / 2, y, 0), Vector3(0.26, 0.26, D + 0.3), col)
		mk.boxp("bark", Vector3(0, y, -D / 2), Vector3(W + 0.3, 0.26, 0.26), col)
		# front wall with doorway
		if i >= 7 or true:
			mk.boxp("bark", Vector3(-1.15, y, D / 2), Vector3(1.3, 0.26, 0.26), col)
			mk.boxp("bark", Vector3(1.15, y, D / 2), Vector3(1.3, 0.26, 0.26), col)
	mk.cols.append([Transform3D(Basis(), Vector3(-W / 2, 1.1, 0)), Vector3(0.3, 2.2, D)])
	mk.cols.append([Transform3D(Basis(), Vector3(W / 2, 1.1, 0)), Vector3(0.3, 2.2, D)])
	mk.cols.append([Transform3D(Basis(), Vector3(0, 1.1, -D / 2)), Vector3(W, 2.2, 0.3)])
	mk.cols.append([Transform3D(Basis(), Vector3(-1.15, 1.1, D / 2)), Vector3(1.3, 2.2, 0.3)])
	mk.cols.append([Transform3D(Basis(), Vector3(1.15, 1.1, D / 2)), Vector3(1.3, 2.2, 0.3)])
	# gable roof
	for s: float in [-1, 1]:
		var b := Basis(Vector3.FORWARD, s * 0.6)
		mk.box("wood", Transform3D(b, Vector3(s * W * 0.26, 2.55, 0)), Vector3(W * 0.62, 0.1, D + 0.8), _shade(WOOD_D, rng))
	mk.build(root, "Hut", true, 1, {"surface": "wood"})
	return root

static func barn(seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var root := Node3D.new()
	var mk := MK.new()
	var W := 7.0; var D := 6.0
	mk.boxp("wood", Vector3(0, 0.06, 0), Vector3(W, 0.12, D), WOOD_D, 0.0, true)
	_plank_wall(mk, rng, -W / 2, W / 2, -D / 2, 3.4, 3.4, [])
	_plank_wall(mk, rng, -W / 2, W / 2, D / 2, 3.4, 3.4, [[-1.4, 1.4, 0.0]])
	_plank_wall(mk, rng, -D / 2, D / 2, -W / 2, 3.4, 3.4, [[1.0, 2.2, 1.2]], true)
	_plank_wall(mk, rng, -D / 2, D / 2, W / 2, 3.4, 2.0, [], true)
	for s: float in [-1, 1]:
		var b := Basis(Vector3.FORWARD, s * 0.55)
		for k in 6:
			if s == 1 and k > 2:
				continue  # collapsed part of the roof
			var z := -D / 2 + (k + 0.5) * D / 6
			mk.box("rust", Transform3D(b, Vector3(s * W * 0.24, 4.15, z)), Vector3(W * 0.58, 0.05, D / 6 - 0.04), _shade(RUST, rng, 0.2))
	mk.box("wood", Transform3D(Basis(Vector3.FORWARD, 0.3), Vector3(2.4, 0.9, 1.0)), Vector3(3.0, 0.12, 0.25), WOOD_D)
	mk.boxp("wood", Vector3(-2.3, 0.45, -1.8), Vector3(1.2, 0.9, 1.0), WOOD, 0.1, true)
	mk.boxp("wood", Vector3(-2.6, 0.35, 0.2), Vector3(0.8, 0.7, 0.8), WOOD, -0.3, true)
	mk.build(root, "Barn", true, 1, {"surface": "wood"})
	return root

static func ruin(seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var root := Node3D.new()
	var mk := MK.new()
	var W := 6.0; var D := 5.0
	for side in 4:
		var length := W if side < 2 else D
		var n := int(length / 0.5)
		for i in n:
			var t := (i + 0.5) / n - 0.5
			var hh := rng.randf_range(0.8, 3.2) if not (side == 0 and absf(t) < 0.15) else 0.0
			if hh <= 0.0:
				continue
			var p := Vector3(t * length, hh * 0.5, (D / 2 if side == 0 else -D / 2)) if side < 2 else Vector3((W / 2 if side == 2 else -W / 2), hh * 0.5, t * length)
			var size := Vector3(0.5, hh, 0.45) if side < 2 else Vector3(0.45, hh, 0.5)
			mk.boxp("stone", p, size, _shade(STONE, rng, 0.15), 0.0, true)
	mk.boxp("stone", Vector3(0, 0.05, 0), Vector3(W, 0.1, D), Color(0.25, 0.25, 0.24), 0.0, true)
	for i in 5:
		mk.blob("stone", Transform3D(Basis(), Vector3(rng.randf_range(-2.5, 2.5), 0.15, rng.randf_range(-2, 2))), rng.randf_range(0.2, 0.4), STONE, 0.3, seed + i, 2, 5)
	mk.build(root, "Ruin", true, 1, {"surface": "gravel"})
	return root

static func signal_box(seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var root := Node3D.new()
	var mk := MK.new()
	var W := 4.4; var D := 3.4
	mk.boxp("stone", Vector3(0, 0.06, 0), Vector3(W, 0.12, D), Color(0.22, 0.22, 0.21), 0.0, true)
	# low brick base then big windows
	for zf in [-D / 2, D / 2]:
		if zf > 0:
			mk.boxp("stone", Vector3(-1.4, 0.55, zf), Vector3(1.6, 1.1, 0.25), STONE, 0.0, true)
			mk.boxp("stone", Vector3(1.4, 0.55, zf), Vector3(1.6, 1.1, 0.25), STONE, 0.0, true)
			mk.boxp("wood", Vector3(0, 2.55, zf), Vector3(W, 0.5, 0.2), WOOD)
		else:
			mk.boxp("stone", Vector3(0, 0.55, zf), Vector3(W, 1.1, 0.25), STONE, 0.0, true)
	for xf in [-W / 2, W / 2]:
		mk.boxp("stone", Vector3(xf, 0.55, 0), Vector3(0.25, 1.1, D), STONE, 0.0, true)
	for cx in [-W / 2, -W / 6, W / 6, W / 2]:
		for cz in [-D / 2, D / 2]:
			mk.boxp("wood", Vector3(cx, 1.75, cz), Vector3(0.1, 1.3, 0.1), WOOD_D)
	mk.cols.append([Transform3D(Basis(), Vector3(0, 1.8, -D / 2)), Vector3(W, 1.4, 0.2)])
	mk.cols.append([Transform3D(Basis(), Vector3(-W / 2, 1.8, 0)), Vector3(0.2, 1.4, D)])
	mk.cols.append([Transform3D(Basis(), Vector3(W / 2, 1.8, 0)), Vector3(0.2, 1.4, D)])
	mk.boxp("wood", Vector3(0, 1.15, -D / 2 + 0.08), Vector3(W, 0.08, 0.2), WOOD_D)
	for s: float in [-1, 1]:
		mk.box("wood", Transform3D(Basis(Vector3.RIGHT, s * 0.45), Vector3(0, 3.1, s * D * 0.25)), Vector3(W + 0.6, 0.08, D * 0.6), WOOD_D)
	# lever frame
	for i in 6:
		mk.box("metal", Transform3D(Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)), Vector3(-1.5 + i * 0.6, 0.7, -0.8)), Vector3(0.06, 1.2, 0.06), Color(0.3, 0.12, 0.1) if i % 2 == 0 else IRON)
	mk.boxp("wood", Vector3(0, 0.25, -0.8), Vector3(3.8, 0.5, 0.4), WOOD_D, 0.0, true)
	mk.build(root, "SignalBox", true, 1, {"surface": "wood"})
	return root

static func wrecked_carriage(seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var root := Node3D.new()
	var body := Node3D.new()
	body.rotation = Vector3(0, 0.12, 1.15)
	body.position = Vector3(0, 1.2, 0)
	root.add_child(body)
	var mk := MK.new()
	var L := 13.0
	mk.boxp("wood", Vector3(0, 0, 0), Vector3(2.8, 0.15, L), WOOD_D)
	mk.boxp("wood", Vector3(0, 2.4, 0), Vector3(2.9, 0.15, L), Color(0.2, 0.2, 0.2))
	for s: float in [-1, 1]:
		var z := -L / 2
		while z < L / 2:
			mk.boxp("wood", Vector3(s * 1.4, 1.2, z + 0.35), Vector3(0.1, 2.4, 0.18), _shade(WOOD, rng, 0.2))
			mk.boxp("wood", Vector3(s * 1.4, 0.45, z + 0.8), Vector3(0.08, 0.9, 0.9), _shade(WOOD, rng, 0.2))
			mk.boxp("wood", Vector3(s * 1.4, 2.15, z + 0.8), Vector3(0.08, 0.35, 0.9), _shade(WOOD, rng, 0.2))
			z += 1.3
	for i in 6:
		mk.boxp("wood", Vector3(rng.randf_range(-0.8, 0.8), 0.45, -5.0 + i * 2.0), Vector3(1.0, 0.5, 0.5), WOOD_D, rng.randf_range(-0.3, 0.3))
	mk.build(body, "Wreck", true)
	# bogie lying nearby, debris
	var mk2 := MK.new()
	for i in 2:
		mk2.cyl("iron", Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(3.6, 0.45, -2.0 + i * 1.8)), 0.45, 0.45, 0.12, 10, IRON)
	mk2.boxp("iron", Vector3(3.6, 0.3, -1.1), Vector3(0.3, 0.2, 2.6), IRON)
	for i in 7:
		mk2.boxp("wood", Vector3(rng.randf_range(-4, 5), 0.05, rng.randf_range(-7, 7)), Vector3(rng.randf_range(0.6, 1.6), 0.06, 0.2), _shade(WOOD, rng, 0.2), rng.randf() * TAU)
	mk2.cols.append([Transform3D(Basis(Vector3(0, 0, 1), 1.15).rotated(Vector3.UP, 0.12), Vector3(0, 1.3, 0)), Vector3(2.9, 2.6, 13.0)])
	mk2.build(root, "Debris", true, 1, {"surface": "wood"})
	return root

static func coal_cart(seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var root := Node3D.new()
	var mk := MK.new()
	var tilt := Basis(Vector3.FORWARD, 0.5)
	mk.box("iron", Transform3D(tilt, Vector3(0, 0.6, 0)), Vector3(1.4, 0.8, 1.0), Color(0.16, 0.15, 0.15), true)
	for i in 4:
		mk.cyl("iron", Transform3D(Basis(Vector3.FORWARD, PI / 2 + 0.5), Vector3(-0.6 + (i % 2) * 1.0, 0.25 + (i % 2) * 0.5, -0.5 + (i / 2) * 1.0)), 0.22, 0.22, 0.08, 8, IRON)
	for i in 14:
		mk.blob("coal", Transform3D(Basis(), Vector3(rng.randf_range(0.5, 1.8), 0.08, rng.randf_range(-0.8, 0.8))), rng.randf_range(0.08, 0.16), Color(0.05, 0.05, 0.055), 0.4, seed + i, 2, 5)
	mk.build(root, "Cart", true, 1, {"surface": "gravel"})
	return root

static func signal_post(red: bool) -> Node3D:
	var root := Node3D.new()
	var mk := MK.new()
	mk.cyl("iron", Transform3D(), 0.09, 0.07, 5.2, 6, IRON)
	mk.boxp("iron", Vector3(0, 0.15, 0), Vector3(0.5, 0.3, 0.5), IRON, 0.0, true)
	mk.boxp("iron", Vector3(0, 4.3, 0.05), Vector3(0.34, 0.75, 0.3), IRON)
	mk.box("wood", Transform3D(Basis(Vector3.FORWARD, 0.0 if red else 0.7), Vector3(0.75, 4.9, 0.0)), Vector3(1.3, 0.2, 0.05), Color(0.55, 0.54, 0.5) if red else Color(0.4, 0.4, 0.38))
	for i in 9:
		mk.boxp("iron", Vector3(0, 0.5 + i * 0.42, 0.14), Vector3(0.3, 0.03, 0.03), IRON)
	mk.build(root, "Signal", true)
	var lens := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.11; sm.height = 0.22; sm.radial_segments = 10; sm.rings = 5
	lens.mesh = sm
	lens.material_override = Mats.get_mat("lamp_red" if red else "lamp_green")
	lens.position = Vector3(0, 4.45, 0.22)
	root.add_child(lens)
	var l := omni(Color(1, 0.2, 0.1) if red else Color(0.4, 1.0, 0.5), 1.4, 9.0)
	l.position = Vector3(0, 4.45, 0.5)
	root.add_child(l)
	return root

static func telegraph_pole(seed: int) -> Mesh:
	return cached("pole%d" % seed, func() -> Mesh:
		var mk := MK.new()
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		mk.cyl("wood", Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.04, 0.04)), Vector3(0, -0.4, 0)), 0.13, 0.1, 7.4, 6, WOOD_D)
		mk.boxp("wood", Vector3(0, 6.6, 0), Vector3(1.6, 0.1, 0.1), WOOD_D)
		for x: float in [-0.65, -0.2, 0.2, 0.65]:
			mk.cyl("plain", Transform3D(Basis(), Vector3(x, 6.65, 0)), 0.03, 0.03, 0.12, 4, Color(0.6, 0.6, 0.58))
		return mk.commit())

static func fence_segment() -> Mesh:
	return cached("fence", func() -> Mesh:
		var mk := MK.new()
		var rng := RandomNumberGenerator.new(); rng.seed = 5
		mk.boxp("wood", Vector3(0, 0.6, 0), Vector3(0.12, 1.3, 0.12), WOOD_D)
		mk.box("wood", Transform3D(Basis(Vector3.FORWARD, 0.04), Vector3(1.5, 0.95, 0)), Vector3(3.0, 0.1, 0.05), _shade(WOOD, rng))
		mk.box("wood", Transform3D(Basis(Vector3.FORWARD, -0.03), Vector3(1.5, 0.45, 0)), Vector3(3.0, 0.1, 0.05), _shade(WOOD, rng))
		return mk.commit())

static func sign_post(text: String) -> Node3D:
	var root := Node3D.new()
	var mk := MK.new()
	mk.boxp("wood", Vector3(0, 1.1, 0), Vector3(0.12, 2.2, 0.12), WOOD_D, 0.0, true)
	mk.boxp("wood", Vector3(0, 2.0, 0.08), Vector3(1.9, 0.55, 0.05), Color(0.5, 0.48, 0.44))
	mk.build(root, "Sign", true)
	var l := label(text, 72, Color(0.08, 0.07, 0.06), false, 0.0055)
	l.position = Vector3(0, 2.0, 0.112)
	l.width = 330
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(l)
	return root

static func buffer_stop() -> Node3D:
	var root := Node3D.new()
	var mk := MK.new()
	mk.boxp("wood", Vector3(0, 0.9, 0), Vector3(2.4, 0.4, 0.35), Color(0.35, 0.12, 0.1), 0.0, true)
	for s: float in [-0.75, 0.75]:
		mk.box("iron", Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(s, 0.6, -0.6)), Vector3(0.15, 0.15, 1.7), IRON)
		mk.cyl("iron", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(s, 0.9, 0.2)), 0.12, 0.12, 0.3, 8, Color(0.5, 0.5, 0.5))
	mk.build(root, "Buffer", true)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.12; sm.height = 0.24
	lamp.mesh = sm
	lamp.material_override = Mats.get_mat("lamp_red")
	lamp.position = Vector3(0, 1.3, 0.1)
	root.add_child(lamp)
	return root

static func campfire_dead() -> Node3D:
	var root := Node3D.new()
	var mk := MK.new()
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	for i in 9:
		var a := TAU * i / 9
		mk.blob("stone", Transform3D(Basis(), Vector3(cos(a) * 0.55, 0.05, sin(a) * 0.55)), 0.14, STONE, 0.3, i, 2, 5)
	for i in 5:
		var a := rng.randf() * TAU
		mk.box("bark", Transform3D(Basis(Vector3.UP, a).rotated(Vector3(cos(a), 0, sin(a)), 0.3), Vector3(0, 0.12, 0)), Vector3(0.08, 0.08, 0.8), Color(0.05, 0.05, 0.05))
	mk.build(root, "Fire", true)
	return root

static func suitcase(seed: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var mk := MK.new()
	var col := _shade(Color(0.28, 0.24, 0.2), rng, 0.25)
	mk.boxp("cloth", Vector3(0, 0.12, 0), Vector3(0.7, 0.22, 0.45), col)
	mk.boxp("iron", Vector3(0, 0.25, -0.02), Vector3(0.18, 0.04, 0.04), IRON)
	mk.build(root, "Case", true)
	return root

static func crate(seed: int, s := 0.8) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var mk := MK.new()
	mk.boxp("wood", Vector3(0, s / 2, 0), Vector3(s, s, s), _shade(WOOD, rng, 0.15), 0.0, true)
	for e: float in [-1, 1]:
		mk.boxp("wood", Vector3(e * s / 2, s / 2, 0), Vector3(0.04, s, s * 1.01), WOOD_D)
	mk.build(root, "Crate", true, 1, {"surface": "wood"})
	return root

# ---------------------------------------------------------------- items

static func coal_sack_mesh() -> Mesh:
	return cached("sack", func() -> Mesh:
		var mk := MK.new()
		mk.blob("cloth", Transform3D(Basis.from_scale(Vector3(1, 1.15, 0.85)), Vector3(0, 0.34, 0)), 0.32, Color(0.36, 0.32, 0.26), 0.15, 3, 4, 8)
		for i in 7:
			mk.blob("coal", Transform3D(Basis(), Vector3(randf_range(-0.12, 0.12), 0.68, randf_range(-0.1, 0.1))), 0.09, Color(0.04, 0.04, 0.045), 0.4, i, 2, 5)
		mk.cyl("cloth", Transform3D(Basis(), Vector3(0, 0.6, 0)), 0.2, 0.24, 0.1, 8, Color(0.3, 0.27, 0.22))
		return mk.commit())

static func coal_pile_mesh() -> Mesh:
	return cached("pile", func() -> Mesh:
		var mk := MK.new()
		var rng := RandomNumberGenerator.new(); rng.seed = 91
		for i in 26:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0, 0.5)
			mk.blob("coal", Transform3D(Basis(), Vector3(cos(a) * r, 0.05 + (0.5 - r) * 0.35, sin(a) * r)), rng.randf_range(0.08, 0.15), Color(0.045, 0.045, 0.05), 0.4, i, 2, 5)
		return mk.commit())

static func bandage_mesh() -> Mesh:
	return cached("bandage", func() -> Mesh:
		var mk := MK.new()
		mk.cyl("cloth", Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(-0.07, 0.07, 0)), 0.07, 0.07, 0.14, 10, Color(0.78, 0.76, 0.7))
		mk.boxp("cloth", Vector3(0.12, 0.005, 0.03), Vector3(0.2, 0.01, 0.08), Color(0.75, 0.73, 0.68), 0.4)
		return mk.commit())

static func medkit_mesh() -> Mesh:
	return cached("medkit", func() -> Mesh:
		var mk := MK.new()
		mk.boxp("metal", Vector3(0, 0.1, 0), Vector3(0.45, 0.2, 0.3), Color(0.55, 0.54, 0.5))
		mk.boxp("plain", Vector3(0, 0.205, 0), Vector3(0.22, 0.01, 0.06), Color(0.55, 0.08, 0.06))
		mk.boxp("plain", Vector3(0, 0.205, 0), Vector3(0.06, 0.01, 0.22), Color(0.55, 0.08, 0.06))
		return mk.commit())

static func lantern_mesh() -> Mesh:
	return cached("lantern", func() -> Mesh:
		var mk := MK.new()
		mk.cyl("metal", Transform3D(), 0.1, 0.1, 0.04, 8, IRON)
		mk.cyl("metal", Transform3D(Basis(), Vector3(0, 0.25, 0)), 0.1, 0.05, 0.08, 8, IRON)
		for i in 4:
			var a := TAU * i / 4.0
			mk.cyl("metal", Transform3D(Basis(), Vector3(cos(a) * 0.085, 0.04, sin(a) * 0.085)), 0.012, 0.012, 0.21, 4, IRON)
		mk.cyl("metal", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.38, -0.06)), 0.08, 0.08, 0.012, 8, IRON, false)
		mk.cyl("glow", Transform3D(Basis(), Vector3(0, 0.06, 0)), 0.05, 0.03, 0.14, 6, Color.WHITE)
		return mk.commit())

static func axe_mesh() -> Mesh:
	return cached("axe", func() -> Mesh:
		var mk := MK.new()
		mk.cyl("wood", Transform3D(), 0.022, 0.018, 0.75, 6, Color(0.36, 0.3, 0.24))
		var head := [Vector3(0, 0.62, 0), Vector3(0.0, 0.76, 0), Vector3(0.2, 0.8, 0), Vector3(0.2, 0.56, 0)]
		for z: float in [-0.018, 0.018]:
			var p := []
			for h in head:
				p.append(h + Vector3(0, 0, z))
			if z > 0:
				mk.quad("metal", p[0], p[3], p[2], p[1], Color(0.42, 0.42, 0.43))
			else:
				mk.quad("metal", p[0], p[1], p[2], p[3], Color(0.42, 0.42, 0.43))
		mk.boxp("metal", Vector3(0.02, 0.69, 0), Vector3(0.08, 0.16, 0.05), Color(0.2, 0.2, 0.21))
		mk.boxp("metal", Vector3(0.2, 0.68, 0), Vector3(0.012, 0.24, 0.04), Color(0.7, 0.7, 0.7))
		return mk.commit())

static func shovel_mesh() -> Mesh:
	return cached("shovel", func() -> Mesh:
		var mk := MK.new()
		mk.cyl("wood", Transform3D(), 0.02, 0.02, 0.9, 6, Color(0.36, 0.3, 0.24))
		mk.box("metal", Transform3D(Basis(Vector3.RIGHT, 0.15), Vector3(0, -0.12, 0.01)), Vector3(0.24, 0.3, 0.02), Color(0.3, 0.3, 0.3))
		return mk.commit())

static func note_mesh() -> Mesh:
	return cached("note", func() -> Mesh:
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.21, 0.28)
		pm.material = note_face_material(false)
		return pm)

static var _note_mats := {}
static func note_face_material(face: bool) -> ShaderMaterial:
	if _note_mats.has(face):
		return _note_mats[face]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform bool face = false;
uniform float sway = 0.0;
void vertex() {
	if (sway > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		VERTEX.z += sin(TIME * 1.3 + wp.x * 3.1 + wp.z * 1.7) * 0.03 * sway * (1.0 - UV.y);
	}
}
void fragment() {
	vec2 uv = UV;
	float fib = fract(sin(dot(floor(uv * 90.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 paper = vec3(0.86, 0.85, 0.8) * (0.96 + fib * 0.04);
	float ink = 0.0;
	if (face) {
		vec2 p = (uv - vec2(0.5, 0.48)) * vec2(1.0, 1.3);
		ink += smoothstep(0.045, 0.03, length(p - vec2(-0.13, -0.1)));
		ink += smoothstep(0.045, 0.03, length(p - vec2(0.13, -0.1)));
		float r = length(p - vec2(0.0, -0.02));
		float ang = atan(p.y - (-0.02), p.x);
		ink += smoothstep(0.025, 0.0, abs(r - 0.2)) * step(0.35, ang) * step(ang, 2.8);
	} else {
		float line = step(0.55, fract(uv.y * 9.0)) * step(fract(uv.y * 9.0), 0.62);
		float len = fract(sin(floor(uv.y * 9.0) * 17.3) * 431.1) * 0.5 + 0.35;
		ink += line * step(0.12, uv.x) * step(uv.x, len) * step(0.15, uv.y) * step(uv.y, 0.85) * 0.7;
	}
	ALBEDO = mix(paper, vec3(0.08, 0.08, 0.09), clamp(ink, 0.0, 1.0));
	ROUGHNESS = 0.8;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("face", face)
	m.set_shader_parameter("sway", 1.0 if face else 0.0)
	_note_mats[face] = m
	return m

## The tree hung with notes (story landmark).
static func note_tree() -> Node3D:
	var root := Node3D.new()
	var tips: Array = []
	var mi := MeshInstance3D.new()
	mi.mesh = tree_bare(4242, 1.9, Color(0.16, 0.155, 0.15), tips)
	root.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new(); cyl.radius = 0.6; cyl.height = 6.0
	cs.shape = cyl; cs.position.y = 3.0
	body.add_child(cs)
	root.add_child(body)
	var rng := RandomNumberGenerator.new(); rng.seed = 99
	var strings := MK.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(0.24, 0.3)
	var count := 0
	for t in tips:
		for k in 2:
			if count > 46:
				break
			var drop := rng.randf_range(0.4, 1.4)
			var anchor: Vector3 = t - Vector3(0, 0.02, 0) + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
			if anchor.y < 2.2:
				continue
			strings.cyl_between("plain", anchor, anchor - Vector3(0, drop, 0), 0.006, 0.006, 3, Color(0.1, 0.1, 0.1), false)
			var note := MeshInstance3D.new()
			note.mesh = plane
			note.material_override = note_face_material(rng.randf() < 0.75)
			note.position = anchor - Vector3(0, drop + 0.15, 0)
			note.rotation.y = rng.randf() * TAU
			note.rotation.z = rng.randf_range(-0.15, 0.15)
			note.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(note)
			count += 1
	strings.build(root, "Strings", false)
	# a few notes nailed to the trunk and lying in the grass
	for i in 6:
		var n := MeshInstance3D.new()
		n.mesh = plane
		n.material_override = note_face_material(i % 2 == 0)
		var a := rng.randf() * TAU
		n.position = Vector3(cos(a) * rng.randf_range(0.8, 2.5), 0.03, sin(a) * rng.randf_range(0.8, 2.5))
		n.rotation = Vector3(-PI / 2, rng.randf() * TAU, 0)
		root.add_child(n)
	return root

# ---------------------------------------------------------------- Greyhaven

static func town_house(seed: int, lit: bool) -> Node3D:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var root := Node3D.new()
	var mk := MK.new()
	var W := rng.randf_range(5.0, 7.0); var D := rng.randf_range(5.0, 6.5); var H := rng.randf_range(4.5, 6.5)
	var wall := _shade(Color(0.42, 0.41, 0.39), rng, 0.15)
	mk.boxp("stone", Vector3(0, H / 2, 0), Vector3(W, H, D), wall, 0.0, true)
	for s: float in [-1, 1]:
		var b := Basis(Vector3.FORWARD, s * 0.75)
		mk.box("wood", Transform3D(b, Vector3(s * W * 0.25, H + W * 0.17, 0)), Vector3(W * 0.66, 0.12, D + 0.5), Color(0.12, 0.12, 0.13))
	mk.tri("stone", Vector3(-W / 2, H, D / 2), Vector3(W / 2, H, D / 2), Vector3(0, H + W * 0.38, D / 2), wall)
	mk.tri("stone", Vector3(W / 2, H, -D / 2), Vector3(-W / 2, H, -D / 2), Vector3(0, H + W * 0.38, -D / 2), wall)
	mk.boxp("stone", Vector3(W * 0.25, H + W * 0.3, 0), Vector3(0.5, 1.4, 0.5), Color(0.25, 0.25, 0.25))
	mk.build(root, "House", true, 1, {"surface": "gravel"})
	var wins := MK.new()
	for side: float in [1, -1]:
		for i in 2:
			for fl in 2:
				var on := lit and rng.randf() < 0.75
				var p := Vector3(-W * 0.25 + i * W * 0.5, 1.4 + fl * 2.0, side * (D / 2 + 0.02))
				wins.boxp("window" if on else "iron", p, Vector3(0.8, 1.0, 0.03), Color(0.06, 0.06, 0.07) if not on else Color.WHITE)
	wins.build(root, "Windows", false)
	if lit:
		var l := omni(Color(1.0, 0.65, 0.35), 1.6, 9.0)
		l.position = Vector3(0, 1.6, D / 2 + 1.0)
		root.add_child(l)
	return root

static func church() -> Node3D:
	var root := Node3D.new()
	var mk := MK.new()
	var c := Color(0.4, 0.4, 0.38)
	mk.boxp("stone", Vector3(0, 3.5, 0), Vector3(7, 7, 13), c, 0.0, true)
	for s: float in [-1, 1]:
		mk.box("wood", Transform3D(Basis(Vector3.FORWARD, s * 0.8), Vector3(s * 1.9, 8.6, 0)), Vector3(5.2, 0.15, 13.6), Color(0.12, 0.12, 0.13))
	mk.boxp("stone", Vector3(0, 7, 7.5), Vector3(3.2, 14, 3.2), c, 0.0, true)
	mk.cyl("wood", Transform3D(Basis(), Vector3(0, 14, 7.5)), 2.3, 0.0, 8.0, 4, Color(0.12, 0.12, 0.13))
	mk.build(root, "Church", true)
	var w := MK.new()
	for i in 3:
		for s: float in [-1, 1]:
			w.boxp("window", Vector3(s * 3.52, 3.2, -4 + i * 4), Vector3(0.03, 2.4, 1.0), Color.WHITE)
	w.boxp("window", Vector3(0, 10.5, 9.12), Vector3(0.9, 1.4, 0.03), Color.WHITE)
	w.build(root, "ChurchWin", false)
	return root

static func lamp_post(with_light := true) -> Node3D:
	var root := Node3D.new()
	var mk := MK.new()
	mk.cyl("iron", Transform3D(), 0.08, 0.05, 3.4, 6, IRON)
	mk.boxp("iron", Vector3(0, 3.45, 0), Vector3(0.35, 0.08, 0.35), IRON)
	mk.boxp("glow", Vector3(0, 3.25, 0), Vector3(0.24, 0.32, 0.24), Color.WHITE)
	mk.cyl("iron", Transform3D(Basis(), Vector3(0, 3.48, 0)), 0.22, 0.0, 0.25, 4, IRON)
	mk.build(root, "Lamp", true)
	if with_light:
		var l := omni(Color(1.0, 0.68, 0.38), 2.2, 11.0)
		l.position = Vector3(0, 3.1, 0)
		root.add_child(l)
	return root

## A person waiting on the platform holding a lantern (victory sequence).
static func townsperson(seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var root := Node3D.new()
	var mk := MK.new()
	var coat := _shade(Color(0.13, 0.13, 0.14), rng, 0.3)
	var h := rng.randf_range(0.92, 1.05)
	mk.cyl("cloth", Transform3D(Basis(), Vector3(0, 0.0, 0)), 0.28 * h, 0.2 * h, 1.35 * h, 7, coat)
	mk.blob("cloth", Transform3D(Basis(), Vector3(0, 1.5 * h, 0)), 0.13, Color(0.55, 0.5, 0.46), 0.1, seed, 3, 6)
	mk.cyl("cloth", Transform3D(Basis(), Vector3(0, 1.6 * h, 0)), 0.2, 0.14, 0.06, 8, Color(0.1, 0.1, 0.1))
	mk.cyl("cloth", Transform3D(Basis(), Vector3(0, 1.62 * h, 0)), 0.13, 0.12, 0.14, 8, Color(0.1, 0.1, 0.1))
	mk.cyl_between("cloth", Vector3(0.22, 1.25 * h, 0), Vector3(0.3, 0.85 * h, -0.15), 0.06, 0.05, 5, coat)
	mk.build(root, "Person", true)
	var lan := MeshInstance3D.new()
	lan.mesh = lantern_mesh()
	lan.position = Vector3(0.3, 0.5 * h, -0.18)
	root.add_child(lan)
	var l := omni(Color(1.0, 0.65, 0.35), 0.9, 5.0)
	l.position = Vector3(0.3, 0.65 * h, -0.25)
	root.add_child(l)
	return root
