"""blender -b scene.blend --python render.py -- <mode: hero|transparent|front> <out.png> <res> <samples>"""
import bpy, sys
mode, out, res, spp = sys.argv[sys.argv.index("--") + 1:][:4]
sc = bpy.context.scene
r = sc.render
r.resolution_x = r.resolution_y = int(res)
sc.cycles.samples = int(spp)
sc.cycles.device = "CPU"
r.filepath = out
r.image_settings.file_format = "PNG"
r.image_settings.color_mode = "RGB"
fx = bpy.data.collections["Atmosphere_FX"].objects
if mode == "hero":
    sc.camera = bpy.data.objects["CAM_Hero_ThreeQuarter"]
elif mode == "transparent":
    # Same camera/lights; FX hidden from camera only so reflections stay identical.
    sc.camera = bpy.data.objects["CAM_Hero_ThreeQuarter"]
    r.film_transparent = True
    r.use_compositing = False
    r.image_settings.color_mode = "RGBA"
    for ob in fx:
        ob.visible_camera = False
elif mode == "front":
    sc.camera = bpy.data.objects["CAM_Front_Fidelity"]
    bpy.data.objects["Front_Preview_Card"].hide_render = False
bpy.ops.render.render(write_still=True)
print("RENDERED", mode, out)
