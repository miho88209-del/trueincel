import bpy
import numpy as np
sc=bpy.context.scene; r=sc.render; r.resolution_x=r.resolution_y=160; sc.cycles.samples=16
objs=[o for o in bpy.data.objects if o.type=='LIGHT' or o.name.startswith('Card')]
def meas(k):
    r.filepath=f'/tmp/d_{k}.png'; bpy.ops.render.render(write_still=True)
    a=np.array(bpy.data.images.load(r.filepath).pixels[:]).reshape(160,160,4)
    print('DIAG',k,a[45:60,65:90,:3].mean())
for o in objs: o.hide_render=True
meas('none')
for o in objs:
    o.hide_render=False; meas(o.name); o.hide_render=True
