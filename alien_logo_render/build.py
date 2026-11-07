import bpy, bmesh, json, math, random, sys
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
random.seed(7)
OUT=sys.argv[sys.argv.index('--')+1]
d=json.load(open('outline.json'))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc=bpy.context.scene
CX,CY,K=(375+876)/2,(345+967)/2,310.0   # px -> BU (logo ~2 BU tall)
DEPTH=0.34

# --- geometry: 2D curve with holes, extruded, converted to mesh
cu=bpy.data.curves.new('alien_curve','CURVE'); cu.dimensions='2D'; cu.fill_mode='BOTH'
cu.extrude=DEPTH/2; cu.resolution_u=1
for L in d['loops']:
    sp=cu.splines.new('POLY'); pts=L['pts']; sp.points.add(len(pts)-1); sp.use_cyclic_u=True
    for p,(x,y) in zip(sp.points,pts): p.co=((x-CX)/K,-(y-CY)/K,0,1)
ob=bpy.data.objects.new('Alien_Emblem',cu); sc.collection.objects.link(ob)
bpy.context.view_layer.objects.active=ob; ob.select_set(True)
bpy.ops.object.convert(target='MESH')
ob=bpy.context.active_object; ob.name='Alien_Emblem'
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=1e-5); bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')
ob.rotation_euler=(math.pi/2,0,0); bpy.ops.object.transform_apply(rotation=True)
bv=ob.modifiers.new('Bevel','BEVEL'); bv.width=0.03; bv.segments=5; bv.limit_method='ANGLE'; bv.angle_limit=math.radians(35); bv.profile=0.6
ws=ob.modifiers.new('WeightedNormals','WEIGHTED_NORMAL'); ws.keep_sharp=True
bpy.ops.object.shade_smooth()
ob.data.polygons.foreach_set('use_smooth',[True]*len(ob.data.polygons))
# pose: slight three-quarter
ob.rotation_euler=(math.radians(-6),math.radians(-24),math.radians(-3))
bpy.context.view_layer.update()

# --- materials
def mat(name):
    m=bpy.data.materials.new(name); m.use_nodes=True; return m,m.node_tree
chrome,t=mat('Chrome_Violet')
b=t.nodes['Principled BSDF']
b.inputs['Base Color'].default_value=(0.80,0.85,0.95,1); b.inputs['Metallic'].default_value=1
b.inputs['Roughness'].default_value=0.06
# violet tint at grazing angles
lw=t.nodes.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value=0.35
mix=t.nodes.new('ShaderNodeMix'); mix.data_type='RGBA'
mix.inputs[6].default_value=(0.80,0.86,0.97,1); mix.inputs[7].default_value=(0.55,0.35,1.0,1)
cr=t.nodes.new('ShaderNodeMapRange'); cr.inputs[1].default_value=0.5; cr.inputs[2].default_value=1.0; cr.inputs[4].default_value=0.0; cr.inputs[3].default_value=0.0; cr.inputs[4].default_value=0.7
t.links.new(lw.outputs['Facing'],cr.inputs[0]); t.links.new(cr.outputs[0],mix.inputs[0]); t.links.new(mix.outputs[2],b.inputs['Base Color'])
ob.data.materials.append(chrome)

# --- world: near black
w=bpy.data.worlds.new('World'); w.use_nodes=True; sc.world=w
wn=w.node_tree.nodes; wl=w.node_tree.links
bg0=wn['Background']; bg0.inputs[0].default_value=(0.004,0.003,0.008,1)
bg1=wn.new('ShaderNodeBackground'); bg1.inputs[1].default_value=1.0
lp=wn.new('ShaderNodeLightPath'); mxs=wn.new('ShaderNodeMixShader'); wo=wn['World Output']
tcw=wn.new('ShaderNodeTexCoord'); sp=wn.new('ShaderNodeSeparateXYZ'); wl.new(tcw.outputs['Generated'],sp.inputs[0])
vz=wn.new('ShaderNodeMath'); vz.operation='MULTIPLY_ADD'; vz.inputs[1].default_value=0.5; vz.inputs[2].default_value=0.5
wl.new(sp.outputs[2],vz.inputs[0])
rp=wn.new('ShaderNodeValToRGB'); ce=rp.color_ramp
ce.elements[0].position=0.0; ce.elements[0].color=(0.01,0.01,0.02,1)
e1=ce.elements.new(0.35); e1.color=(0.12,0.14,0.22,1)
e2=ce.elements.new(0.6); e2.color=(0.9,0.95,1.0,1)
e3=ce.elements.new(0.72); e3.color=(0.15,0.12,0.3,1)
ce.elements[-1].position=1.0; ce.elements[-1].color=(0.4,0.28,0.8,1)
wl.new(vz.outputs[0],rp.inputs[0])
wv=wn.new('ShaderNodeTexWave'); wv.wave_type='BANDS'; wv.bands_direction='X'; wv.inputs['Scale'].default_value=0.9; wv.inputs['Distortion'].default_value=2.0
wl.new(tcw.outputs['Generated'],wv.inputs[0])
wm=wn.new('ShaderNodeMix'); wm.data_type='RGBA'; wm.blend_type='MULTIPLY'; wm.inputs[0].default_value=0.6
wl.new(rp.outputs[0],wm.inputs[6]); wl.new(wv.outputs[0],wm.inputs[7])
wl.new(wm.outputs[2],bg1.inputs[0])
wl.new(lp.outputs['Is Camera Ray'],mxs.inputs[0]); wl.new(bg1.outputs[0],mxs.inputs[1]); wl.new(bg0.outputs[0],mxs.inputs[2]); wl.new(mxs.outputs[0],wo.inputs[0])

# --- studio lights (large softboxes, camera-invisible)
def area(name,loc,size,energy,col,shape='RECTANGLE',sy=None):
    l=bpy.data.lights.new(name,'AREA'); l.energy=energy; l.color=col; l.shape=shape; l.size=size
    if sy: l.size_y=sy
    o=bpy.data.objects.new(name,l); sc.collection.objects.link(o); o.location=loc
    c=o.constraints.new('TRACK_TO'); c.target=ob; c.track_axis='TRACK_NEGATIVE_Z'; c.up_axis='UP_Y'
    o.visible_camera=False; return o
area('Key_Top_Left',(-3.5,3.5,4.5),3.0,900,(0.9,0.95,1.0),sy=3.5)
area('Fill_Right_Violet',(4.5,0.8,3.0),3.5,900,(0.62,0.42,1.0),sy=5)
area('Rim_Strip_Left',(-4.2,-0.5,-1.0),0.8,600,(0.8,0.88,1.0),sy=6)
area('Rim_Strip_Right',(4.5,2.5,-2.0),0.8,700,(0.7,0.55,1.0),sy=6)
area('Front_Soft',(0.5,-0.5,6.5),5,0,(0.95,0.97,1.0),sy=5)
area('Floor_Card',(0,-4.5,1.5),5,0,(0.85,0.9,1.0),sy=2)

# --- camera
cam=bpy.data.cameras.new('Cam'); cam.lens=85; cam.sensor_width=36
co=bpy.data.objects.new('Camera',cam); sc.collection.objects.link(co); sc.camera=co
co.location=(0,-8.4,0.4)
tc=co.constraints.new('TRACK_TO'); tc.target=ob; tc.track_axis='TRACK_NEGATIVE_Z'; tc.up_axis='UP_Y'
cam.dof.use_dof=True; cam.dof.focus_object=ob; cam.dof.aperture_fstop=5.6
sc.render.resolution_x=sc.render.resolution_y=2048
bpy.context.view_layer.update()

# --- FX collection (camera-only)
fx=bpy.data.collections.new('Background_FX'); sc.collection.children.link(fx)
def em(name,col,strength,alpha_tex=None):
    m=bpy.data.materials.new(name); m.use_nodes=True; n=m.node_tree.nodes; l=m.node_tree.links
    for x in list(n): n.remove(x)
    out=n.new('ShaderNodeOutputMaterial'); e=n.new('ShaderNodeEmission'); e.inputs[0].default_value=col; e.inputs[1].default_value=strength
    tr=n.new('ShaderNodeBsdfTransparent'); mx=n.new('ShaderNodeMixShader')
    l.new(e.outputs[0],mx.inputs[2]); l.new(tr.outputs[0],mx.inputs[1]); l.new(mx.outputs[0],out.inputs[0])
    return m,n,l,mx
def tag(o):
    fx.objects.link(o)
    for a in ('visible_diffuse','visible_glossy','visible_transmission','visible_volume_scatter','visible_shadow'): setattr(o,a,False)
# back haze plane: radial gradient + noise
bpy.ops.mesh.primitive_plane_add(size=1); hz=bpy.context.active_object; hz.name='FX_Haze'
sc.collection.objects.unlink(hz); tag(hz); hz.location=(0,6,0.3); hz.scale=(30,30,1); hz.rotation_euler=(math.pi/2,0,0)
m,n,l,mx=em('Haze',(0.30,0.12,0.75,1),1.0)
tc_=n.new('ShaderNodeTexCoord'); gr=n.new('ShaderNodeTexGradient'); gr.gradient_type='SPHERICAL'
mp=n.new('ShaderNodeMapping'); mp.inputs['Location'].default_value=(-0.5,-0.5,0); mp.inputs['Scale'].default_value=(1,1,1)
nz=n.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value=2.2; nz.inputs['Detail'].default_value=6
cr=n.new('ShaderNodeValToRGB'); cr.color_ramp.elements[0].position=0.0; cr.color_ramp.elements[1].position=0.5
cr.color_ramp.elements[0].color=(1,1,1,1); cr.color_ramp.elements[1].color=(0,0,0,1)
mul=n.new('ShaderNodeMath'); mul.operation='MULTIPLY'
mix2=n.new('ShaderNodeMath'); mix2.operation='MULTIPLY'; mix2.inputs[1].default_value=0.16
mn=n.new('ShaderNodeMath'); mn.operation='ADD'; mn.inputs[1].default_value=0.6
l.new(tc_.outputs['Generated'],mp.inputs[0]); l.new(mp.outputs[0],gr.inputs[0]); l.new(gr.outputs[0],cr.inputs[0])
l.new(tc_.outputs['Generated'],nz.inputs[0]); l.new(nz.outputs[0],mn.inputs[0])
l.new(cr.outputs[0],mul.inputs[0]); l.new(mn.outputs[0],mul.inputs[1]); l.new(mul.outputs[0],mix2.inputs[0]); l.new(mix2.outputs[0],mx.inputs[0])
hz.data.materials.append(m)
# the radial gradient is 0..1 over the half-plane; fine-tune by plane scale
# light rays: long thin fading planes behind emblem fanning from upper-left
for i,(ang,wd,st) in enumerate([(-38,1.3,0.9),(-24,0.7,0.7),(-12,1.8,0.5),(6,0.9,0.6),(20,1.4,0.7),(34,0.8,0.5)]):
    bpy.ops.mesh.primitive_plane_add(size=1); r=bpy.context.active_object; r.name=f'FX_Ray{i}'
    sc.collection.objects.unlink(r); tag(r)
    r.scale=(wd,16,1); r.location=(math.sin(math.radians(ang))*-3.0+1.0,4.5,math.cos(math.radians(ang))*3.0-0.5)
    r.rotation_euler=(math.pi/2,math.radians(ang),0)
    m,n,l,mx=em(f'Ray{i}',(0.55,0.40,1.0,1),st)
    tcx=n.new('ShaderNodeTexCoord'); sp=n.new('ShaderNodeSeparateXYZ'); l.new(tcx.outputs['UV'],sp.inputs[0])
    # across: soft edge, along: fade out
    a1=n.new('ShaderNodeMath'); a1.operation='PINGPONG'; a1.inputs[1].default_value=0.5
    l.new(sp.outputs[0],a1.inputs[0])
    a2=n.new('ShaderNodeMath'); a2.operation='MULTIPLY'; a2.inputs[1].default_value=2
    l.new(a1.outputs[0],a2.inputs[0])
    a3=n.new('ShaderNodeMath'); a3.operation='POWER'; a3.inputs[1].default_value=1.8; l.new(a2.outputs[0],a3.inputs[0])
    b1=n.new('ShaderNodeMath'); b1.operation='SUBTRACT'; b1.inputs[0].default_value=1; l.new(sp.outputs[1],b1.inputs[1])
    b2=n.new('ShaderNodeMath'); b2.operation='POWER'; b2.inputs[1].default_value=2; l.new(b1.outputs[0],b2.inputs[0])
    c=n.new('ShaderNodeMath'); c.operation='MULTIPLY'; l.new(a3.outputs[0],c.inputs[0]); l.new(b2.outputs[0],c.inputs[1])
    c2=n.new('ShaderNodeMath'); c2.operation='MULTIPLY'; c2.inputs[1].default_value=0.12; l.new(c.outputs[0],c2.inputs[0]); l.new(c2.outputs[0],mx.inputs[0])
    r.data.materials.append(m)
# particles outside the emblem's projected silhouette
pm,n,l,mx=em('Particle',(0.8,0.7,1.0,1),9)
for x in list(n): 
    if x.type in('MIX_SHADER','BSDF_TRANSPARENT'): n.remove(x)
em_node=[x for x in n if x.type=='EMISSION'][0]; outn=[x for x in n if x.type=='OUTPUT_MATERIAL'][0]
l.new(em_node.outputs[0],outn.inputs[0])
logo_pts=[ob.matrix_world@v.co for v in ob.data.vertices]
def uv(p): 
    v=world_to_camera_view(sc,co,p); return v.x,v.y
silh=[uv(p) for p in logo_pts]
cxu=sum(a for a,b in silh)/len(silh); cyu=sum(b for a,b in silh)/len(silh)
rad=max(math.hypot(a-cxu,b-cyu) for a,b in silh)
made=0
while made<48:
    u,v=random.uniform(0.04,0.96),random.uniform(0.04,0.96)
    if math.hypot(u-cxu,v-cyu)<rad*1.12: continue
    dist=random.choice([-6,-3,-1,0,0,1.5,4,7])  # depth offset in world units along view
    z=dist; 
    # unproject at depth: ray from camera
    ray=co.matrix_world.to_quaternion()@Vector(((u-0.5)*36/85*1,(v-0.5)*36/85,-1)).normalized()
    cd=(ob.location-co.location).length+dist
    p=co.location+ray*(cd/ max(ray.dot((ob.location-co.location).normalized()),0.01))
    s=random.choice([0.008,0.011,0.015,0.02,0.032])*(1+abs(dist)*0.02)*(cd/8.4)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=s,segments=16,ring_count=8,location=p)
    o=bpy.context.active_object; sc.collection.objects.unlink(o); tag(o); o.data.materials.append(pm)
    bpy.ops.object.shade_smooth(); made+=1
print('rad',rad,cxu,cyu)

# --- render settings
r=sc.render; r.engine='CYCLES'; sc.cycles.samples=192; sc.cycles.use_denoising=True; sc.cycles.denoiser='OPENIMAGEDENOISE'
sc.cycles.max_bounces=12; sc.cycles.glossy_bounces=10; sc.cycles.sample_clamp_indirect=10
sc.view_settings.view_transform='AgX'; sc.view_settings.look='AgX - Medium High Contrast'; sc.view_settings.exposure=0.0
r.image_settings.file_format='PNG'; r.image_settings.color_depth='16'
# glow
sc.use_nodes=True; nt=sc.node_tree
for x in list(nt.nodes): nt.nodes.remove(x)
rl=nt.nodes.new('CompositorNodeRLayers'); gl=nt.nodes.new('CompositorNodeGlare'); gl.glare_type='FOG_GLOW'; gl.quality='HIGH'; gl.threshold=1.2; gl.size=7; gl.mix=-0.7
cmp=nt.nodes.new('CompositorNodeComposite')
nt.links.new(rl.outputs['Image'],gl.inputs[0]); nt.links.new(gl.outputs[0],cmp.inputs[0])
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=OUT)
