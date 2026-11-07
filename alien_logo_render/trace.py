import cv2, numpy as np, json
im=cv2.imread("/tmp/hoplite/workspace/.hoplite/attachments/art_upload_e0a67a21b6fd4590b4b6c644a5295443/file_000000001c3882108ce9c6e63e0aceb1.png",0)
S=4
big=cv2.resize(im,None,fx=S,fy=S,interpolation=cv2.INTER_CUBIC)
big=cv2.GaussianBlur(big,(0,0),3)
m=(big<128).astype(np.uint8)*255
cs,h=cv2.findContours(m,cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
out=[]
for c,hh in zip(cs,h[0]):
    if cv2.contourArea(c)<2000*S*S: continue
    p=c[:,0,:].astype(float)/S
    # smooth closed
    k=7
    ker=np.ones(k)/k
    pp=np.vstack([p[-k:],p,p[:k]])
    sm=np.stack([np.convolve(pp[:,i],ker,'same') for i in (0,1)],1)[k:-k]
    a=cv2.approxPolyDP(sm.astype(np.float32).reshape(-1,1,2),0.25,True)[:,0,:]
    out.append({'hole':bool(hh[3]>=0),'pts':a.tolist()})
    print(len(a),out[-1]['hole'],cv2.boundingRect(c))
json.dump({'w':im.shape[1],'h':im.shape[0],'loops':out},open('outline.json','w'))
