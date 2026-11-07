import bpy, json, sys, numpy as np
argv = sys.argv[sys.argv.index("--")+1:]
d = json.load(open(argv[0])); hole_cw = argv[1] == "cw"; off = float(argv[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
cu = bpy.data.curves.new("AlienEmblem", "CURVE"); cu.dimensions = "2D"; cu.fill_mode = "BOTH"
def add(pts, rev):
    pts = pts[::-1] if rev else pts
    s = cu.splines.new("POLY"); s.points.add(len(pts)-1)
    for p, (x, y) in zip(s.points, pts): p.co = (x, y, 0, 1)
    s.use_cyclic_u = True; s.use_smooth = True
add(d["outer"], False)
for h in d["holes"]: add(h, hole_cw)
cu.extrude = 0.15; cu.bevel_depth = 0.05; cu.bevel_resolution = 6; cu.offset = off
ob = bpy.data.objects.new("AlienEmblem", cu); bpy.context.scene.collection.objects.link(ob)
dg = bpy.context.evaluated_depsgraph_get(); m = ob.evaluated_get(dg).to_mesh()
m.calc_loop_triangles()
v = np.array([x.co[:] for x in m.vertices]); t = np.array([lt.vertices[:] for lt in m.loop_triangles])
np.savez(argv[3], v=v, t=t); print("VERTS", len(v), "TRIS", len(t), "Z", v[:,2].min(), v[:,2].max())
