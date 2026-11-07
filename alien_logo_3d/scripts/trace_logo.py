"""Trace image 5 into a symmetric outline (outer + 2 eye holes) -> logo_outline.json."""
import cv2, numpy as np, json, sys
src = sys.argv[1]; out = sys.argv[2]
g = cv2.imread(src, cv2.IMREAD_GRAYSCALE).astype(np.float32) / 255.0
ink = 1.0 - g                                     # 1 = logo
ys, xs = np.nonzero(ink > 0.5)
# Symmetry axis from the outer silhouette's horizontal extent per row (robust to eye holes).
cx = (xs.min() + xs.max()) / 2.0
# Symmetrize: average with mirror about cx (sub-pixel via remap), then upsample for sub-pixel contours.
H, W = ink.shape
mx = (2 * cx - np.arange(W)).astype(np.float32)
mapx = np.tile(mx, (H, 1)); mapy = np.tile(np.arange(H, dtype=np.float32)[:, None], (1, W))
mir = cv2.remap(ink, mapx, mapy, cv2.INTER_LINEAR, borderValue=0)
sym = 0.5 * (ink + mir)
S = 4
up = cv2.resize(sym, (W * S, H * S), interpolation=cv2.INTER_CUBIC)
up = cv2.GaussianBlur(up, (0, 0), 1.2 * S)         # remove JPEG-ish wobble, keep corners
mask = (up > 0.5).astype(np.uint8)
cnts, hier = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
cnts = [c[:, 0, :].astype(np.float64) / S for c in cnts]
order = sorted(range(len(cnts)), key=lambda i: -cv2.contourArea(cnts[i].astype(np.float32)))
outer = cnts[order[0]]
holes = [cnts[i] for i in order[1:3]]
print("contours", len(cnts), "areas", [round(abs(cv2.contourArea(cnts[i].astype(np.float32)))) for i in order[:4]])

def resample(p, n):
    p = np.vstack([p, p[:1]])
    d = np.r_[0, np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))]
    t = np.linspace(0, d[-1], n, endpoint=False)
    return np.c_[np.interp(t, d, p[:, 0]), np.interp(t, d, p[:, 1])]

y0, y1 = ys.min(), ys.max()
scale = 2.0 / (y1 - y0)                           # logo height = 2 Blender units
cy = (y0 + y1) / 2.0
def norm(p):  # image px -> Blender XY (Y up), centered
    return np.c_[(p[:, 0] - cx) * scale, -(p[:, 1] - cy) * scale]

def ccw(p):
    a = 0.5 * np.sum(p[:, 0] * np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1) * p[:, 1])
    return p if a > 0 else p[::-1]

outer_n = ccw(norm(resample(outer, 360)))
# Use the right eye and mirror it so both eyes are exact mirror images.
holes_n = [norm(h) for h in holes]
right = max(holes_n, key=lambda h: h[:, 0].mean())
right = ccw(norm(resample(holes[holes_n.index(right) if False else [h[:,0].mean() for h in holes_n].index(right[:,0].mean())], 200)))
left = ccw(right * np.array([-1, 1]))
json.dump({"outer": outer_n.tolist(), "holes": [left.tolist(), right.tolist()],
           "px_per_unit": 1 / scale, "center_px": [cx, cy]}, open(out, "w"))
print("axis cx", cx, "height px", y1 - y0, "width units", np.ptp(outer_n[:, 0]))

# Overlay check: draw traced outline on the original.
vis = cv2.cvtColor((g * 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
def topx(p): return np.c_[p[:, 0] / scale + cx, -p[:, 1] / scale + cy]
for p, col in [(outer_n, (0, 0, 255)), (left, (0, 200, 0)), (right, (255, 0, 0))]:
    cv2.polylines(vis, [np.round(topx(p) * 4).astype(np.int32)], True, col, 2, cv2.LINE_AA, shift=2)
cv2.imwrite(out.replace(".json", "_overlay.png"), vis)
