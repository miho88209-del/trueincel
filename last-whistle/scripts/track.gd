class_name Track
extends RefCounted
## Railway centre-line, terrain height field and the route definition.
## Distance d (metres) runs along -Z: world z = -d.

const RAIL_Y := 0.62          # top of rail
const BALLAST_Y := 0.36
const STATION_D := 4680.0     # where the platform centre is
const END_D := 4760.0         # buffer stop
const STATION_ZONE := 4575.0  # stopping past here counts as arriving
const CHUNK := 80.0

## Fallen trees that block the line.
const OBSTACLES := [
	{"id": "tree1", "d": 900.0, "hits": 5},
	{"id": "tree2", "d": 2180.0, "hits": 6},
	{"id": "tree3", "d": 3360.0, "hits": 7},
]
## Signal posts: d, side offset, red?
const SIGNALS := [
	[-40.0, -3.4, false], [700.0, -3.4, true], [1980.0, -3.4, true], [3150.0, -3.4, true],
	[3950.0, -3.4, false], [4350.0, -3.4, false],
]

static var flats: Array = []      # [x, z, radius, height]
static var clear_zones: Array = [] # [x, z, radius] no trees
static var _n1: FastNoiseLite
static var _n2: FastNoiseLite
static var _n3: FastNoiseLite

static func init() -> void:
	if _n1 != null:
		return
	_n1 = FastNoiseLite.new(); _n1.seed = 11; _n1.frequency = 0.008; _n1.fractal_octaves = 3
	_n2 = FastNoiseLite.new(); _n2.seed = 23; _n2.frequency = 0.06; _n2.fractal_octaves = 2
	_n3 = FastNoiseLite.new(); _n3.seed = 37; _n3.frequency = 0.0025; _n3.fractal_octaves = 2

static func x_at(z: float) -> float:
	return 26.0 * sin(z * 0.0019 + 0.4) + 11.0 * sin(z * 0.0051 + 1.3) - (26.0 * sin(0.4) + 11.0 * sin(1.3))

static func pos(d: float, y := RAIL_Y) -> Vector3:
	return Vector3(x_at(-d), y, -d)

static func fwd(d: float) -> Vector3:
	return (pos(d + 1.0) - pos(d - 1.0)).normalized()

static func right(d: float) -> Vector3:
	return fwd(d).cross(Vector3.UP).normalized()

## Transform of a car centred at distance d (local -Z = direction of travel).
static func xform(d: float) -> Transform3D:
	return Transform3D(Basis.looking_at(fwd(d), Vector3.UP), pos(d))

## World position offset sideways from the line (+side = right of travel).
static func side(d: float, offset: float, y := 0.0) -> Vector3:
	var p := pos(d, 0.0) + right(d) * offset
	p.y = height(p.x, p.z) + y
	return p

static func dist_to_track(x: float, z: float) -> float:
	return absf(x - x_at(z)) / sqrt(1.0 + pow(slope(z), 2.0))

static func slope(z: float) -> float:
	return (x_at(z + 0.5) - x_at(z - 0.5))

## Openness 0 (deep forest) .. 1 (fields near Greyhaven).
static func openness(d: float) -> float:
	return smoothstep(3750.0, 4350.0, d)

## "Dead wood" stretch where bare trees dominate.
static func deadness(d: float) -> float:
	return smoothstep(2450.0, 2750.0, d) * (1.0 - smoothstep(3450.0, 3700.0, d))

static func height(x: float, z: float) -> float:
	init()
	var dx := dist_to_track(x, z)
	var big := _n1.get_noise_2d(x, z)
	var small := _n2.get_noise_2d(x, z)
	var k := smoothstep(9.0, 55.0, dx)
	var h := big * 6.5 * k + small * 0.45 * smoothstep(4.5, 12.0, dx) - 0.06
	h += smoothstep(70.0, 220.0, dx) * (_n3.get_noise_2d(x, z) * 0.5 + 0.6) * 16.0
	for f in flats:
		var dd := Vector2(x - f[0], z - f[1]).length()
		if dd < f[2] + 14.0:
			var w := 1.0 - smoothstep(f[2], f[2] + 14.0, dd)
			h = lerpf(h, f[3], w)
	return h

static func normal(x: float, z: float) -> Vector3:
	var e := 0.6
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()

static func in_clear_zone(x: float, z: float, pad := 0.0) -> bool:
	for c in clear_zones:
		if Vector2(x - c[0], z - c[1]).length() < c[2] + pad:
			return true
	return false

static func add_site(p: Vector3, radius: float, flatten := true) -> void:
	clear_zones.append([p.x, p.z, radius])
	if flatten:
		flats.append([p.x, p.z, radius * 0.75, p.y])

static func reset_sites() -> void:
	flats.clear()
	clear_zones.clear()
