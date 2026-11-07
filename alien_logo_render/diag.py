import bpy,sys
sc=bpy.context.scene; r=sc.render; r.resolution_x=r.resolution_y=160; sc.cycles.samples=16
from mathutils import Vector
tests={'base':[], 'nocards':[o for o in bpy.data.objects if o.name.startswith('Card')],
'nolights':[o for o in bpy.data.objects if o.type=='LIGHT'],'nofx':list(bpy.data.collections['Background_FX'].objects)}
import numpy as np
for k,objs in tests.items():
    for o in objs:o.hide_render=True
    r.filepath=f'/tmp/d_{k}.png'; bpy.ops.render.render(write_still=True)
    im=bpy.data.images.load(r.filepath); a=np.array(im.pixels[:]).reshape(160,160,4)
    print('DIAG',k,a[30:60,50:100,:3].mean())
    for o in objs:o.hide_render=False
