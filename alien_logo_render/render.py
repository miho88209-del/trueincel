import bpy,sys
a=sys.argv[sys.argv.index('--')+1:]; mode,res,samples,out=a[0],int(a[1]),int(a[2]),a[3]
sc=bpy.context.scene; r=sc.render; r.resolution_x=r.resolution_y=res; r.resolution_percentage=100; sc.cycles.samples=samples
fx=bpy.data.collections['Background_FX']
if mode=='transparent':
    r.film_transparent=True; fx.hide_render=True
elif mode=='front':
    fx.hide_render=True; r.film_transparent=False
    for o in list(bpy.data.objects):
        if o.type=='LIGHT': o.hide_render=True
    sc.use_nodes=False; sc.view_settings.view_transform='Standard'; sc.view_settings.look='None'
    w=sc.world.node_tree.nodes['Background']; w.inputs[0].default_value=(1,1,1,1); w.inputs[1].default_value=1
    m=bpy.data.materials.new('flat'); m.use_nodes=True; n=m.node_tree.nodes; n.clear()
    e=n.new('ShaderNodeEmission'); e.inputs[0].default_value=(0,0,0,1); o=n.new('ShaderNodeOutputMaterial'); m.node_tree.links.new(e.outputs[0],o.inputs[0])
    ob=bpy.data.objects['Alien_Emblem']; ob.rotation_euler=(0,0,0); ob.data.materials[0]=m
    ob.modifiers['Bevel'].width=0.0001
    cam=bpy.data.cameras['Cam']; cam.type='ORTHO'; cam.ortho_scale=1254/310.0; cam.dof.use_dof=False
    co=bpy.data.objects['Camera']; co.constraints.clear(); co.location=(0,-10,0); co.rotation_euler=(1.5707963,0,0)
    sc.cycles.use_denoising=False
r.filepath=out; bpy.ops.render.render(write_still=True)
