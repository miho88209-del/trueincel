class_name Chunk
extends Node3D
## One 80 m slice of the route: terrain, forest, grass, ground cover, track and
## trackside furniture. Built over several frames to avoid hitches.

const XMIN := -240.0
const XMAX := 240.0
const DX := 6.0
const DZ := 4.0

var index := 0
var built := false
var _z0 := 0.0
var _z1 := 0.0
var _cols := 0
var _rows := 0
var _hgrid := PackedFloat32Array()

static func tree_mesh(kind: String, v: int) -> Mesh:
	var key := "%s%d" % [kind, v]
	if not Props._mesh_cache.has(key):
		var m: Mesh
		if kind == "broad":
			m = Props.tree_broad(100 + v * 17)
		elif kind == "pine":
			m = Props.tree_pine(200 + v * 13)
		elif kind == "bare":
			m = Props.tree_bare(300 + v * 7, 1.15)
		else:
			m = Props.tree_snag(400 + v * 5)
		Props._mesh_cache[key] = m
	return Props._mesh_cache[key]

static func grass_mesh(v: int) -> Mesh:
	return Props.cached("grass%d" % v, func() -> Mesh: return Props.grass_tuft(500 + v, v >= 3))

func build(i: int, grass_density: float) -> void:
	index = i
	name = "Chunk%d" % i
	var d0 := i * Track.CHUNK
	_z0 = -(d0 + Track.CHUNK)
	_z1 = -d0
	_build_terrain()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_track(d0, d0 + Track.CHUNK)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_trees(i)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_grass(i, grass_density)
	built = true

func _h(x: float, z: float) -> float:
	var fx := clampf((x - XMIN) / DX, 0.0, _cols - 1.001)
	var fz := clampf((z - _z0) / DZ, 0.0, _rows - 1.001)
	var ix := int(fx); var iz := int(fz)
	var tx := fx - ix; var tz := fz - iz
	var a := _hgrid[iz * _cols + ix]
	var b := _hgrid[iz * _cols + ix + 1]
	var c := _hgrid[(iz + 1) * _cols + ix]
	var d := _hgrid[(iz + 1) * _cols + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

func _build_terrain() -> void:
	_cols = int((XMAX - XMIN) / DX) + 1
	_rows = int((_z1 - _z0) / DZ) + 1
	_hgrid.resize(_cols * _rows)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in _rows:
		var z := _z0 + r * DZ
		for c in _cols:
			var x := XMIN + c * DX
			var h := Track.height(x, z)
			_hgrid[r * _cols + c] = h
			st.set_color(Color(0, 0, 0, 0))
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, h, z))
	for r in _rows - 1:
		for c in _cols - 1:
			var a := r * _cols + c
			var b := a + 1
			var cc := a + _cols
			var d := cc + 1
			# clockwise seen from above (Godot front face)
			st.add_index(a); st.add_index(b); st.add_index(d)
			st.add_index(a); st.add_index(d); st.add_index(cc)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, Mats.get_mat("ground"))
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.set_meta("surface", "terrain")
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)

func _build_track(d0: float, d1: float) -> void:
	var a := maxf(d0, -160.0)
	var b := minf(d1, Track.END_D + 1.0)
	if b <= a:
		return
	var mk := MK.new()
	var step := 2.0
	var prof := [[-2.7, -0.12], [-1.75, Track.BALLAST_Y], [1.75, Track.BALLAST_Y], [2.7, -0.12]]
	var d := a
	while d < b - 0.001:
		var e := minf(d + step, b)
		var r0 := Track.right(d); var r1 := Track.right(e)
		var p0 := Track.pos(d, 0.0); var p1 := Track.pos(e, 0.0)
		for k in 3:
			var q0: Vector3 = p0 + r0 * prof[k][0] + Vector3(0, prof[k][1], 0)
			var q1: Vector3 = p0 + r0 * prof[k + 1][0] + Vector3(0, prof[k + 1][1], 0)
			var q2: Vector3 = p1 + r1 * prof[k + 1][0] + Vector3(0, prof[k + 1][1], 0)
			var q3: Vector3 = p1 + r1 * prof[k][0] + Vector3(0, prof[k][1], 0)
			mk.quad("ballast", q0, q1, q2, q3, Color(0.3, 0.3, 0.29) if k == 1 else Color(0.25, 0.25, 0.24))
		d = e
	# rails
	d = a
	while d < b - 0.001:
		var e := minf(d + 4.0, b)
		var mid := (d + e) * 0.5
		var basis := Basis.looking_at(Track.fwd(mid), Vector3.UP)
		for s: float in [-0.72, 0.72]:
			var c := Track.pos(mid, Track.RAIL_Y - 0.07) + Track.right(mid) * s
			mk.box("metal", Transform3D(basis, c), Vector3(0.08, 0.14, e - d + 0.02), Color(0.3, 0.29, 0.28))
			mk.box("metal", Transform3D(basis, c + Vector3(0, 0.072, 0)), Vector3(0.06, 0.005, e - d + 0.02), Color(0.62, 0.62, 0.62))
		d = e
	mk.build(self, "Track", true)
	# sleepers
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sl := BoxMesh.new()
	sl.size = Vector3(2.5, 0.13, 0.24)
	var slm := StandardMaterial3D.new()
	slm.albedo_color = Color(0.16, 0.15, 0.14)
	slm.albedo_texture = Mats.noise_tex()
	slm.uv1_triplanar = true
	slm.roughness = 0.95
	sl.material = slm
	mm.mesh = sl
	var n := int((b - a) / 0.72)
	mm.instance_count = n
	for k in n:
		var dd := a + k * 0.72 + 0.36
		var xf := Track.xform(dd)
		xf.origin.y = Track.BALLAST_Y + 0.05
		mm.set_instance_transform(k, xf)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "Sleepers"
	add_child(mmi)
	# telegraph poles and wires along the left side
	var wires := MK.new()
	var pole_d := ceilf(a / 45.0) * 45.0
	while pole_d < b:
		var p := Track.side(pole_d, -5.8)
		var mi := MeshInstance3D.new()
		mi.mesh = Props.telegraph_pole(int(pole_d) % 3)
		mi.transform = Transform3D(Basis.looking_at(Track.fwd(pole_d), Vector3.UP).rotated(Vector3.UP, PI / 2), p)
		add_child(mi)
		var q := Track.side(pole_d + 45.0, -5.8)
		var r := Track.right(pole_d)
		for wx: float in [-0.65, -0.2, 0.2, 0.65]:
			var w0 := p + Vector3(0, 6.72, 0) + Track.fwd(pole_d) * 0.0 + r * 0.0 + Track.fwd(pole_d).cross(Vector3.UP).normalized() * wx
			var w2 := q + Vector3(0, 6.72, 0) + Track.fwd(pole_d).cross(Vector3.UP).normalized() * wx
			var w1 := (w0 + w2) * 0.5 - Vector3(0, 0.55, 0)
			wires.cyl_between("iron", w0, w1, 0.008, 0.008, 3, Color(0.08, 0.08, 0.08), false)
			wires.cyl_between("iron", w1, w2, 0.008, 0.008, 3, Color(0.08, 0.08, 0.08), false)
		pole_d += 45.0
	wires.build(self, "Wires", false)
	# fences as the land opens up near Greyhaven
	if b > 3950.0:
		var fm := MultiMesh.new()
		fm.transform_format = MultiMesh.TRANSFORM_3D
		fm.mesh = Props.fence_segment()
		var xfs := []
		var fd := maxf(a, 3950.0)
		while fd < b and fd < Track.END_D - 120.0:
			for s: float in [-13.0, 13.0]:
				var fp := Track.side(fd, s)
				var fb := Basis.looking_at(Track.fwd(fd), Vector3.UP).rotated(Vector3.UP, PI / 2 if s > 0 else -PI / 2)
				if fmod(fd * 0.37 + s, 7.0) > 0.6:
					xfs.append(Transform3D(fb, fp))
			fd += 3.0
		fm.instance_count = xfs.size()
		for k in xfs.size():
			fm.set_instance_transform(k, xfs[k])
		var fmi := MultiMeshInstance3D.new()
		fmi.multimesh = fm
		add_child(fmi)

func _build_trees(i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9000 + i * 131
	var xforms := {}   # mesh key -> Array[Transform3D]
	var body := StaticBody3D.new()
	body.name = "Trunks"
	body.set_meta("surface", "wood")
	add_child(body)
	var cell := 7.0
	var z := _z0
	var deco := {"leaf": [], "rock": []}
	while z < _z1:
		var x := XMIN + 4.0
		var d := -z
		var o := Track.openness(d)
		var dead := Track.deadness(d)
		while x < XMAX - 4.0:
			var px := x + rng.randf_range(-3.0, 3.0)
			var pz := z + rng.randf_range(0.0, cell)
			var dx := Track.dist_to_track(px, pz)
			var p_near := lerpf(0.62, 0.05, o)
			var p_far := lerpf(0.42, 0.06, o)
			var p := p_near if dx < 60.0 else p_far
			if dx < 7.5 or pz >= _z1:
				p = 0.0
			elif dx < 11.0:
				p *= 0.35
			if p > 0.0 and rng.randf() < p and not Track.in_clear_zone(px, pz, 2.5):
				var r := rng.randf()
				var kind := "broad"
				var wb := lerpf(0.36, 0.08, dead)
				var wp := lerpf(0.38, 0.1, dead) * (1.0 - o)
				var wbare := lerpf(0.14, 0.55, dead)
				if r < wb + o * 0.4:
					kind = "broad"
				elif r < wb + o * 0.4 + wp:
					kind = "pine"
				elif r < wb + o * 0.4 + wp + wbare:
					kind = "bare"
				else:
					kind = "snag"
				var v := rng.randi_range(0, 2)
				var key := "%s%d" % [kind, v]
				var s := rng.randf_range(0.8, 1.25)
				var bas := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
				var pos := Vector3(px, _h(px, pz), pz)
				if not xforms.has(key):
					xforms[key] = []
				xforms[key].append(Transform3D(bas, pos))
				if dx < 75.0:
					var cs := CollisionShape3D.new()
					var cyl := CylinderShape3D.new()
					cyl.radius = 0.3 * s
					cyl.height = 4.0
					cs.shape = cyl
					cs.position = pos + Vector3(0, 2.0, 0)
					body.add_child(cs)
			elif dx > 3.5 and dx < 60.0 and rng.randf() < 0.22:
				deco["leaf"].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.8)), Vector3(px, _h(px, pz), pz)))
			if dx > 4.0 and dx < 90.0 and rng.randf() < 0.05:
				deco["rock"].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(px + 1.5, _h(px + 1.5, pz) - 0.05, pz)))
			x += cell
		z += cell
	for key in xforms:
		var kind: String = key.substr(0, key.length() - 1)
		var v := int(key.substr(key.length() - 1))
		_multi(tree_mesh(kind, v), xforms[key], true, "T_" + key)
	_multi(Props.cached("leaf0", func() -> Mesh: return Props.leaf_patch(1)), deco["leaf"], false, "Leaves", 90.0)
	_multi(Props.cached("rock0", func() -> Mesh: return Props.rock(3)), deco["rock"], true, "Rocks")

func _multi(mesh: Mesh, xfs: Array, shadows: bool, nm: String, vis_end := 0.0) -> MultiMeshInstance3D:
	if xfs.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_end_margin = 15.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	return mmi

func _build_grass(i: int, density: float) -> void:
	if density <= 0.01:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + i * 17
	var count := int(6500.0 * density)
	var groups := [[], [], [], []]
	var zlen := _z1 - _z0
	for k in count:
		var z := _z0 + rng.randf() * zlen
		var off := rng.randf_range(-62.0, 62.0)
		off = sign(off) * pow(absf(off) / 62.0, 1.4) * 62.0   # denser near the line
		var x := Track.x_at(z) + off
		var dx := absf(off)
		if dx < 2.3:
			continue
		if dx < 3.2 and rng.randf() < 0.6:
			continue
		var s := rng.randf_range(0.7, 1.35)
		var g := rng.randi_range(0, 3)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(x, _h(x, z) - 0.02, z))
		groups[g].append(xf)
	for g in 4:
		var mmi := _multi(grass_mesh(g), groups[g], false, "Grass%d" % g, 75.0)
		if mmi:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
