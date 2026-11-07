"""Build the alien emblem scene (Blender 5.2, Cycles).

blender -b --factory-startup --python build_scene.py -- <logo_outline.json> <reference.png> <out.blend>
"""
import bpy, json, sys, math, random
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

argv = sys.argv[sys.argv.index("--") + 1:]
OUTLINE, REF_IMG, OUT_BLEND = argv[:3]
P = dict(  # tweakable look parameters
    extrude=0.15, bevel=0.05, bevel_res=6,
    cam_dist=9.0, cam_yaw=24.0, cam_pitch=8.0, lens=85.0, fstop=2.0,
)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = "AlienEmblem"


def coll(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


C_EMBLEM, C_LIGHT, C_FX, C_CAM, C_REF = (coll(n) for n in
                                         ("Emblem", "Lighting", "Atmosphere_FX", "Cameras", "Reference"))


def link(ob, c):
    c.objects.link(ob)
    return ob


def nodes_of(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    return nt, nt.nodes, nt.links


# ---------------------------------------------------------------- emblem
data = json.load(open(OUTLINE))
cu = bpy.data.curves.new("AlienEmblem_Curve", "CURVE")
cu.dimensions = "2D"
cu.fill_mode = "BOTH"
for pts in [data["outer"]] + data["holes"]:
    s = cu.splines.new("POLY")
    s.points.add(len(pts) - 1)
    for p, (x, y) in zip(s.points, pts):
        p.co = (x, y, 0.0, 1.0)
    s.use_cyclic_u = True
    s.use_smooth = True
cu.extrude = P["extrude"]
cu.bevel_depth = P["bevel"]
cu.bevel_resolution = P["bevel_res"]
cu.offset = -P["bevel"]          # keeps the front silhouette on the traced outline
emblem = link(bpy.data.objects.new("AlienEmblem", cu), C_EMBLEM)

chrome = bpy.data.materials.new("Chrome_SilverViolet")
nt, N, L = nodes_of(chrome)
out = N.new("ShaderNodeOutputMaterial")
bsdf = N.new("ShaderNodeBsdfPrincipled")
bsdf.inputs["Base Color"].default_value = (0.90, 0.92, 0.97, 1)
bsdf.inputs["Metallic"].default_value = 1.0
bsdf.inputs["Specular Tint"].default_value = (0.86, 0.80, 1.0, 1)   # faint violet at grazing angles
# Subtle roughness breakup so broad reflections don't look CG-perfect.
tc = N.new("ShaderNodeTexCoord")
noise = N.new("ShaderNodeTexNoise")
noise.inputs["Scale"].default_value = 3.0
noise.inputs["Detail"].default_value = 4.0
rmap = N.new("ShaderNodeMapRange")
rmap.inputs["To Min"].default_value = 0.10
rmap.inputs["To Max"].default_value = 0.17
L.new(tc.outputs["Object"], noise.inputs["Vector"])
L.new(noise.outputs["Fac"], rmap.inputs["Value"])
L.new(rmap.outputs["Result"], bsdf.inputs["Roughness"])
L.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
cu.materials.append(chrome)

# ---------------------------------------------------------------- cameras
target = link(bpy.data.objects.new("CameraTarget", None), C_CAM)


def make_cam(name, loc, ortho=None):
    cd = bpy.data.cameras.new(name)
    cd.sensor_fit = "HORIZONTAL"
    cd.sensor_width = 36
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    else:
        cd.lens = P["lens"]
        cd.dof.use_dof = True
        cd.dof.focus_object = target
        cd.dof.aperture_fstop = P["fstop"]
        cd.dof.aperture_blades = 7
    cd.clip_end = 100
    ob = link(bpy.data.objects.new(name, cd), C_CAM)
    ob.location = loc
    con = ob.constraints.new("TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    return ob


yaw, pit = math.radians(P["cam_yaw"]), math.radians(P["cam_pitch"])
d = P["cam_dist"]
cam_hero = make_cam("CAM_Hero_ThreeQuarter",
                    (d * math.sin(yaw) * math.cos(pit), d * math.sin(pit), d * math.cos(yaw) * math.cos(pit)))
cam_front = make_cam("CAM_Front_Fidelity", (0, 0, 10), ortho=2.6)
scene.camera = cam_hero

# ---------------------------------------------------------------- lighting
def area(name, loc, size, size_y, color, energy, spread=180):
    ld = bpy.data.lights.new(name, "AREA")
    ld.shape = "RECTANGLE"
    ld.size, ld.size_y = size, size_y
    ld.color = color
    ld.energy = energy
    ld.spread = math.radians(spread)
    ob = link(bpy.data.objects.new(name, ld), C_LIGHT)
    ob.location = loc
    con = ob.constraints.new("TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    return ob


area("Key_Softbox_UpperLeft", (-3.5, 4.5, 6.0), 5.0, 2.5, (0.88, 0.93, 1.0), 900)
area("Top_Strip", (0.5, 6.0, 1.0), 7.0, 0.7, (0.95, 0.96, 1.0), 450)
area("Rim_Violet_Right", (4.5, 0.8, -4.0), 0.6, 6.0, (0.62, 0.32, 1.0), 900)
area("Rim_Violet_Left", (-4.5, 0.3, -3.0), 0.6, 6.0, (0.55, 0.30, 1.0), 600)
area("Fill_Cool_Low", (5.0, -3.0, 4.0), 3.0, 3.0, (0.75, 0.82, 1.0), 120)

# Broad gradient softbox behind/left of camera: this is what the flat front face mirrors,
# giving a large diagonal highlight that falls off into darker chrome.
bpy.ops.mesh.primitive_plane_add(size=1)
sb = bpy.context.active_object
bpy.context.scene.collection.objects.unlink(sb)
link(sb, C_LIGHT)
sb.name = "Front_Gradient_Softbox"
sb.scale = (7.0, 5.0, 1)
sb.location = (-4.5, -1.0, 9.0)
con = sb.constraints.new("TRACK_TO")
con.target = target
con.track_axis = "TRACK_Z"
con.up_axis = "UP_Y"
sbm = bpy.data.materials.new("Softbox_Gradient_Emission")
nt, N, L = nodes_of(sbm)
o = N.new("ShaderNodeOutputMaterial")
em = N.new("ShaderNodeEmission")
tc = N.new("ShaderNodeTexCoord")
grad = N.new("ShaderNodeTexGradient")
grad.gradient_type = "LINEAR"
mp = N.new("ShaderNodeMapping")
mp.inputs["Rotation"].default_value = (0, 0, math.radians(35))
ramp = N.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.25
ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1)
ramp.color_ramp.elements[1].position = 0.85
ramp.color_ramp.elements[1].color = (0.92, 0.95, 1.0, 1)
L.new(tc.outputs["UV"], mp.inputs["Vector"])
L.new(mp.outputs["Vector"], grad.inputs["Vector"])
L.new(grad.outputs["Fac"], ramp.inputs["Fac"])
L.new(ramp.outputs["Color"], em.inputs["Color"])
em.inputs["Strength"].default_value = 6.0
L.new(em.outputs["Emission"], o.inputs["Surface"])
sb.data.materials.append(sbm)
sb.visible_camera = False
sb.visible_diffuse = False

# World: near-black with the faintest violet so dark chrome isn't dead flat.
world = bpy.data.worlds.new("NearBlack_Violet")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.006, 0.004, 0.012, 1)
bg.inputs["Strength"].default_value = 1.0

# ---------------------------------------------------------------- atmosphere
def fx_plane(name, size, loc, mat):
    bpy.ops.mesh.primitive_plane_add(size=size)
    ob = bpy.context.active_object
    bpy.context.scene.collection.objects.unlink(ob)
    link(ob, C_FX)
    ob.name = name
    ob.location = loc
    con = ob.constraints.new("TRACK_TO")   # face the hero camera
    con.target = cam_hero
    con.track_axis = "TRACK_Z"
    con.up_axis = "UP_Y"
    ob.data.materials.append(mat)
    return ob


# Haze backdrop: radial violet glow + low-frequency noise.
haze = bpy.data.materials.new("FX_VioletHaze")
nt, N, L = nodes_of(haze)
o = N.new("ShaderNodeOutputMaterial")
em = N.new("ShaderNodeEmission")
tc = N.new("ShaderNodeTexCoord")
sph = N.new("ShaderNodeTexGradient"); sph.gradient_type = "SPHERICAL"
mp = N.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (0.16, 0.16, 0.16)
mp.inputs["Location"].default_value = (0.0, 0.0, 0)
L.new(tc.outputs["Object"], mp.inputs["Vector"]); L.new(mp.outputs["Vector"], sph.inputs["Vector"])
pw = N.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = 2.2
L.new(sph.outputs["Fac"], pw.inputs[0])
nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 0.35; nz.inputs["Detail"].default_value = 3
L.new(tc.outputs["Object"], nz.inputs["Vector"])
nmap = N.new("ShaderNodeMapRange"); nmap.inputs["To Min"].default_value = 0.55; nmap.inputs["To Max"].default_value = 1.25
L.new(nz.outputs["Fac"], nmap.inputs["Value"])
mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
L.new(pw.outputs["Value"], mul.inputs[0]); L.new(nmap.outputs["Result"], mul.inputs[1])
mixc = N.new("ShaderNodeMix"); mixc.data_type = "RGBA"
mixc.inputs["A"].default_value = (0.004, 0.003, 0.008, 1)
mixc.inputs["B"].default_value = (0.30, 0.14, 0.62, 1)
L.new(mul.outputs["Value"], mixc.inputs["Factor"])
L.new(mixc.outputs["Result"], em.inputs["Color"])
em.inputs["Strength"].default_value = 0.35
L.new(em.outputs["Emission"], o.inputs["Surface"])
fx_plane("FX_Haze_Backdrop", 16, (-1.4, 0.0, -6.0), haze)

# Soft light rays: polar angle -> 1D noise, faded radially; additive over transparency.
rays = bpy.data.materials.new("FX_LightRays")
nt, N, L = nodes_of(rays)
o = N.new("ShaderNodeOutputMaterial")
tc = N.new("ShaderNodeTexCoord")
sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Object"], sep.inputs["Vector"])
at = N.new("ShaderNodeMath"); at.operation = "ARCTAN2"
L.new(sep.outputs["Y"], at.inputs[0]); L.new(sep.outputs["X"], at.inputs[1])
n1 = N.new("ShaderNodeTexNoise"); n1.noise_dimensions = "1D"
n1.inputs["Scale"].default_value = 2.2; n1.inputs["Detail"].default_value = 2.0
L.new(at.outputs["Value"], n1.inputs["W"])
rr = N.new("ShaderNodeMapRange"); rr.inputs["From Min"].default_value = 0.48; rr.inputs["From Max"].default_value = 0.72
L.new(n1.outputs["Fac"], rr.inputs["Value"])
ln = N.new("ShaderNodeVectorMath"); ln.operation = "LENGTH"; L.new(tc.outputs["Object"], ln.inputs[0])
fall = N.new("ShaderNodeMapRange"); fall.inputs["From Min"].default_value = 0.6; fall.inputs["From Max"].default_value = 4.2
fall.inputs["To Min"].default_value = 1.0; fall.inputs["To Max"].default_value = 0.0
L.new(ln.outputs["Value"], fall.inputs["Value"])
f2 = N.new("ShaderNodeMath"); f2.operation = "POWER"; f2.inputs[1].default_value = 2.0
L.new(fall.outputs["Result"], f2.inputs[0])
m2 = N.new("ShaderNodeMath"); m2.operation = "MULTIPLY"
L.new(rr.outputs["Result"], m2.inputs[0]); L.new(f2.outputs["Value"], m2.inputs[1])
em = N.new("ShaderNodeEmission"); em.inputs["Color"].default_value = (0.62, 0.48, 1.0, 1)
strength = N.new("ShaderNodeMath"); strength.operation = "MULTIPLY"; strength.inputs[1].default_value = 0.9
L.new(m2.outputs["Value"], strength.inputs[0]); L.new(strength.outputs["Value"], em.inputs["Strength"])
tr = N.new("ShaderNodeBsdfTransparent")
add = N.new("ShaderNodeAddShader")
L.new(tr.outputs["BSDF"], add.inputs[0]); L.new(em.outputs["Emission"], add.inputs[1])
L.new(add.outputs["Shader"], o.inputs["Surface"])
fx_plane("FX_LightRays", 10, (-0.35, 0.25, -1.5), rays)

# Glowing particles at varied depth/size; kept out of the emblem's screen area.
pmat = bpy.data.materials.new("FX_Particle_Glow")
nt, N, L = nodes_of(pmat)
o = N.new("ShaderNodeOutputMaterial")
em = N.new("ShaderNodeEmission")
oi = N.new("ShaderNodeObjectInfo")
mixp = N.new("ShaderNodeMix"); mixp.data_type = "RGBA"
mixp.inputs["A"].default_value = (1.0, 0.97, 1.0, 1)
mixp.inputs["B"].default_value = (0.70, 0.52, 1.0, 1)
L.new(oi.outputs["Random"], mixp.inputs["Factor"])
L.new(mixp.outputs["Result"], em.inputs["Color"])
sm = N.new("ShaderNodeMapRange"); sm.inputs["To Min"].default_value = 6.0; sm.inputs["To Max"].default_value = 22.0
L.new(oi.outputs["Random"], sm.inputs["Value"]); L.new(sm.outputs["Result"], em.inputs["Strength"])
L.new(em.outputs["Emission"], o.inputs["Surface"])

bpy.context.view_layer.update()
scene.render.resolution_x = scene.render.resolution_y = 1024
rng = random.Random(7)
mesh_p = bpy.data.meshes.new("ParticleSphere")
import bmesh
bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=1.0); bm.to_mesh(mesh_p); bm.free()
for poly in mesh_p.polygons:
    poly.use_smooth = True
mesh_p.materials.append(pmat)
placed, tries = [], 0
cam_loc = cam_hero.matrix_world.translation
while len(placed) < 24 and tries < 5000:
    tries += 1
    near = rng.random() < 0.15
    z = rng.uniform(1.5, 3.2) if near else rng.uniform(-9.0, -1.0)
    pt = Vector((rng.uniform(-7, 7), rng.uniform(-7, 7), z))
    ndc = world_to_camera_view(scene, cam_hero, pt)
    if ndc.z <= 0 or not (0.06 < ndc.x < 0.94 and 0.06 < ndc.y < 0.94):
        continue
    ex, ey = (ndc.x - 0.5) / 0.36, (ndc.y - 0.5) / 0.40
    if ex * ex + ey * ey < 1.0:          # keep the emblem silhouette clear
        continue
    if any((ndc.x - q.x) ** 2 + (ndc.y - q.y) ** 2 < 0.07 ** 2 for q in placed):
        continue
    placed.append(ndc)
    ob = link(bpy.data.objects.new("FX_Particle_%02d" % len(placed), mesh_p), C_FX)
    dist = (pt - cam_loc).length
    r = rng.uniform(0.007, 0.022) * dist / 9.0 * (1.6 if near else 1.0)
    ob.location = pt
    ob.scale = (r, r, r)
    ob.visible_shadow = False
print("particles placed:", len(placed))

for ob in C_FX.objects:
    ob.visible_shadow = False

# ---------------------------------------------------------------- reference image (viewport only, packed)
img = bpy.data.images.load(REF_IMG)
img.name = "Reference_Image5_Logo"
ref = link(bpy.data.objects.new("REF_Image5_Logo", None), C_REF)
ref.empty_display_type = "IMAGE"
ref.data = img
s = data["px_per_unit"]
ref.empty_display_size = img.size[0] / s
ref.location = ((img.size[0] / 2 - data["center_px"][0]) / s, -(img.size[1] / 2 - data["center_px"][1]) / s, -0.3)
ref.show_empty_image_perspective = False
ref.color[3] = 0.5
ref.use_empty_image_alpha = True
ref.hide_render = True

# ---------------------------------------------------------------- render + colour
r = scene.render
r.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 256
scene.cycles.use_adaptive_sampling = True
scene.cycles.adaptive_threshold = 0.01
scene.cycles.use_denoising = True
scene.cycles.denoiser = "OPENIMAGEDENOISE"
scene.cycles.max_bounces = 10
scene.cycles.glossy_bounces = 8
scene.cycles.diffuse_bounces = 2
scene.cycles.transmission_bounces = 2
scene.cycles.transparent_max_bounces = 8
scene.cycles.volume_bounces = 0
scene.cycles.sample_clamp_indirect = 6.0
scene.cycles.blur_glossy = 0.5
scene.cycles.caustics_reflective = False
scene.cycles.caustics_refractive = False
r.resolution_x = r.resolution_y = 2048
r.resolution_percentage = 100
r.image_settings.file_format = "PNG"
r.dither_intensity = 1.0
scene.view_settings.view_transform = "AgX"
try:
    scene.view_settings.look = "AgX - Medium High Contrast"
except TypeError:
    pass
scene.view_settings.exposure = 0.0

# Compositor: restrained bloom.
ng = bpy.data.node_groups.new("Emblem_Compositing", "CompositorNodeTree")
ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
rl = ng.nodes.new("CompositorNodeRLayers")
gl = ng.nodes.new("CompositorNodeGlare")
gl.inputs["Type"].default_value = "Bloom"
gl.inputs["Quality"].default_value = "High"
gl.inputs["Threshold"].default_value = 1.2
gl.inputs["Strength"].default_value = 0.35
gl.inputs["Size"].default_value = 0.6
go = ng.nodes.new("NodeGroupOutput")
ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
ng.links.new(gl.outputs["Image"], go.inputs[0])
scene.compositing_node_group = ng
r.use_compositing = True

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, compress=True)
print("SAVED", OUT_BLEND)
