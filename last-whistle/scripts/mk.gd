class_name MK
extends RefCounted
## Accumulates flat-shaded, vertex-coloured triangles per material key and commits
## them into one ArrayMesh. Optionally records box colliders for the same geometry.
## Triangles are given counter-clockwise seen from outside; they are emitted in
## Godot's clockwise front-face order.

var tools := {}
var cols: Array = []   # [Transform3D, Vector3 size]

func _st(key: String) -> SurfaceTool:
	var s: SurfaceTool = tools.get(key)
	if s == null:
		s = SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = s
	return s

func tri(key: String, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	var s := _st(key)
	for p in [a, c, b]:
		s.set_color(col)
		s.set_normal(n)
		s.set_uv(Vector2(p.x + p.z, p.y))
		s.add_vertex(p)

func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(key, a, b, c, col)
	tri(key, a, c, d, col)

const _BOX_FACES := [
	[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
	[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
	[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
	[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
	[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
	[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
]

## Box centred on xf.origin. `shade` darkens the bottom face slightly for readability.
func box(key: String, xf: Transform3D, size: Vector3, col: Color, collide := false) -> void:
	var h := size * 0.5
	for f in _BOX_FACES:
		var p := []
		for c in f:
			p.append(xf * Vector3(c.x * h.x, c.y * h.y, c.z * h.z))
		quad(key, p[0], p[1], p[2], p[3], col)
	if collide:
		cols.append([xf, size])

## Axis-aligned convenience: box at position with optional yaw (radians).
func boxp(key: String, pos: Vector3, size: Vector3, col: Color, yaw := 0.0, collide := false) -> void:
	box(key, Transform3D(Basis(Vector3.UP, yaw), pos), size, col, collide)

## Cylinder / cone along local +Y from 0 to h.
func cyl(key: String, xf: Transform3D, rb: float, rt: float, h: float, sides: int, col: Color, caps := true) -> void:
	var bot := []
	var top := []
	for i in sides:
		var a := TAU * float(i) / sides
		var c := cos(a); var s := sin(a)
		bot.append(xf * Vector3(c * rb, 0, s * rb))
		top.append(xf * Vector3(c * rt, h, s * rt))
	for i in sides:
		var j := (i + 1) % sides
		if rt > 0.0001:
			quad(key, bot[j], bot[i], top[i], top[j], col)
		else:
			tri(key, bot[j], bot[i], top[i], col)
	if caps:
		var cb := xf * Vector3.ZERO
		var ct := xf * Vector3(0, h, 0)
		for i in sides:
			var j := (i + 1) % sides
			tri(key, cb, bot[i], bot[j], col)
			if rt > 0.0001:
				tri(key, ct, top[j], top[i], col)

static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)

func cyl_between(key: String, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, col: Color, caps := true) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	cyl(key, Transform3D(basis_y(d), a), ra, rb, d.length(), sides, col, caps)

## Low-poly jittered ellipsoid (canopies, rocks, coal lumps).
func blob(key: String, xf: Transform3D, radius: float, col: Color, jitter := 0.25, seed := 0, rings := 4, segs := 7) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts := []
	for r in rings + 1:
		var row := []
		var phi := PI * float(r) / rings
		for s in segs:
			var th := TAU * float(s) / segs + (0.0 if r % 2 == 0 else PI / segs)
			var p := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var j := 1.0 + rng.randf_range(-jitter, jitter)
			if r == 0 or r == rings:
				j = 1.0 + rng.randf_range(-jitter, jitter) * 0.5
			row.append(xf * (p * radius * j))
		pts.append(row)
	var top := xf * (Vector3.UP * radius)
	var bottom := xf * (Vector3.DOWN * radius)
	for r in rings:
		for s in segs:
			var s1 := (s + 1) % segs
			if r == 0:
				tri(key, top, pts[1][s1], pts[1][s], col)
			elif r == rings - 1:
				tri(key, bottom, pts[r][s], pts[r][s1], col)
			else:
				quad(key, pts[r + 1][s1], pts[r + 1][s], pts[r][s], pts[r][s1], col)

func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	for key in tools.keys():
		var s: SurfaceTool = tools[key]
		s.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Mats.get_mat(key))
	return mesh

## Builds a MeshInstance3D (and a StaticBody3D for recorded colliders) under parent.
func build(parent: Node3D, name := "Mesh", shadows := true, layer := 1, meta := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if not cols.is_empty():
		var body := StaticBody3D.new()
		body.name = name + "Body"
		body.collision_layer = layer
		body.collision_mask = 0
		for k in meta:
			body.set_meta(k, meta[k])
		parent.add_child(body)
		add_cols_to(body)
	return mi

func add_cols_to(body: CollisionObject3D) -> void:
	for c in cols:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = c[1]
		cs.shape = sh
		cs.transform = c[0]
		body.add_child(cs)
