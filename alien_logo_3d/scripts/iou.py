import numpy as np, cv2, json, sys
d = json.load(open(sys.argv[2])); z = np.load(sys.argv[1]); v, t = z["v"], z["t"]
g = cv2.imread(sys.argv[3], 0); ref = (g < 128).astype(np.uint8)
s, (cx, cy) = d["px_per_unit"], d["center_px"]
P = np.c_[v[:,0]*s+cx, -v[:,1]*s+cy]
m = np.zeros_like(ref)
for tri in t: cv2.fillConvexPoly(m, np.round(P[tri]*16).astype(np.int32), 1, cv2.LINE_8, shift=4)
inter = (m & ref).sum(); uni = (m | ref).sum()
print("IoU %.4f  extra_px %d  missing_px %d" % (inter/uni, (m & ~ref & 1).sum(), (ref & ~m & 1).sum()))
if len(sys.argv) > 4:
    vis = np.dstack([ref*255, m*255, ref*0]).astype(np.uint8); cv2.imwrite(sys.argv[4], vis[330:990, 360:900])
