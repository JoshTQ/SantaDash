#!/usr/bin/env python3
"""Clean a Meshy suit texture for Roblox: the khaki/brown stains and dark
scuffs Meshy painted on Santa's red suit come out (Josh, 13 Nov 2026: "Santa
texture is slightly off"), and every texel outside the UV islands takes the
nearest island colour, so Roblox's downscale to 1024 and its mipmaps never
pull black gutter into the seams (dark smudgy edges at a distance).

    python3 tools/meshy/clean_texture.py art/meshy/Santa/model.glb <colour.png> art/meshy/Santa/texture.png [1024]

<colour.png> is the base colour Meshy baked (build/meshy/Santa/color.png, or
the texture inside model.glb). upload.py uploads art/meshy/<Name>/texture.png
instead of Meshy's colour when it exists. Needs numpy, Pillow and scipy.
Tuned on the Classic Santa: the face, beard, fur, belt, buckle and boots are
left alone; check a render before using it on another model.
"""
import json
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd


def uv_islands(glb, size):
    """Where the mesh's triangles sit in the texture (True = painted texel)."""
    f = open(glb, "rb").read()
    n = struct.unpack("<I", f[12:16])[0]
    j = json.loads(f[20:20 + n])
    b0 = 20 + n + 8

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        o = b0 + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        k = {"SCALAR": 1, "VEC2": 2}[a["type"]]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a["componentType"]]
        arr = np.frombuffer(f, dt, a["count"] * k, o)
        return arr.reshape(a["count"], k) if k > 1 else arr

    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    for mesh in j["meshes"]:
        for p in mesh["primitives"]:
            uv = acc(p["attributes"]["TEXCOORD_0"])
            for t in acc(p["indices"]).reshape(-1, 3):
                d.polygon([(uv[k, 0] * size, uv[k, 1] * size) for k in t], fill=255, outline=255)
    return np.asarray(im) > 0


glbp, src, out = sys.argv[1:4]
im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255
isl = uv_islands(glbp, im.shape[0])
def hsv(a):
    mx=a.max(-1);mn=a.min(-1);d=np.maximum(mx-mn,1e-6);r,g,b=a[...,0],a[...,1],a[...,2]
    h=np.where(mx==r,((g-b)/d)%6,np.where(mx==g,(b-r)/d+2,(r-g)/d+4))*60
    return np.where(h>180,h-360,h),np.where(mx>0,(mx-mn)/np.maximum(mx,1e-6),0),mx
h,s,v=hsv(im)
ilab,_=nd.label(isl)
def grow(seed,it):
    # dilate, but only within the UV islands the seed is on (neighbouring
    # islands in the texture are usually far apart on the model)
    keep=np.isin(ilab,np.unique(ilab[seed]))
    return nd.binary_dilation(seed,iterations=it)&keep
red=(np.abs(h)<15)&(s>0.6)&(v>0.35)&isl
redfrac=nd.uniform_filter(red.astype(np.float32),31)/np.maximum(nd.uniform_filter(isl.astype(np.float32),31),1e-3)
stainc=(h>15)&(h<70)&(s>0.12)&(s<0.75)&(v>0.2)&(v<0.85)&isl
# grow stain regions: label connected candidate blobs, keep blobs mostly surrounded by red
lab,n=nd.label(stainc)
ring=nd.binary_dilation(stainc,iterations=4)&~stainc&isl
near=nd.grey_dilation(lab,size=9)
rr=nd.sum(red&ring,near*ring,range(1,n+1));rt=nd.sum(ring,near*ring,range(1,n+1))
ok=np.zeros(n+1,bool);ok[1:]=(rt>0)&(rr/np.maximum(rt,1)>0.45)
stain=ok[lab]
# speckled stains: fill the whole speckled area, not just each speck
stain|=(nd.uniform_filter(stain.astype(np.float32),9)>0.2)&isl&~red
# also darker/duller red scuffs inside red areas
scuff=(np.abs(h)<25)&isl&~red&(redfrac>0.6)&(v>0.33)&(s>0.25)
m=nd.binary_dilation(stain|scuff,iterations=3)&isl&~((h>35)&(h<65)&(s>0.6)&(v>0.6))  # keep gold buckle
skin0=(h>-12)&(h<28)&(s>0.12)&(s<0.7)&(v>0.68)&isl
bb0=(h>12)&(h<45)&(s>0.66)&(v>0.25)&isl
lb0,nb0=nd.label(bb0);a0=nd.sum(np.ones_like(v),lb0,range(1,nb0+1))
big0=np.zeros(nb0+1,bool);big0[1:]=a0>8000
ls0,ns0=nd.label(skin0);as0=nd.sum(np.ones_like(v),ls0,range(1,ns0+1))
bigs0=np.zeros(ns0+1,bool);bigs0[1:]=as0>0
protect0=grow(bigs0[ls0],12)|grow(big0[lb0],3)|(grow(big0[lb0],30)&(v<0.3))
m&=~protect0
# fill with local mean of clean red
w=nd.gaussian_filter(red.astype(np.float32),12)
fill=np.stack([nd.gaussian_filter(im[...,k]*red,12) for k in range(3)],-1)/np.maximum(w,1e-4)[...,None]
w2=nd.gaussian_filter(red.astype(np.float32),40)
fill2=np.stack([nd.gaussian_filter(im[...,k]*red,40) for k in range(3)],-1)/np.maximum(w2,1e-4)[...,None]
fill=np.where((w>0.02)[...,None],fill,fill2)
o=im.copy();o[m]=fill[m]
# soften the seam where filled meets original
edge=nd.binary_dilation(m,iterations=2)&~nd.binary_erosion(m,iterations=2)&isl&~((h>35)&(h<65)&(s>0.6))
sm=nd.gaussian_filter(o,(1.5,1.5,0));o[edge]=sm[edge]
# pass 2: even out what's left of the suit (faint brown smudges and blotchy
# darker reds) toward the clean suit red, keeping a little fabric detail
h2,s2,v2=hsv(o)
strong=(np.abs(h2)<12)&(s2>0.8)&(v2>0.6)&isl
ws=nd.gaussian_filter(strong.astype(np.float32),30)
tgt=np.stack([nd.gaussian_filter(o[...,k]*strong,30) for k in range(3)],-1)/np.maximum(ws,1e-4)[...,None]
tgt=np.where((ws>0.01)[...,None],tgt,np.array([0.78,0.03,0.04],np.float32))
rf=nd.uniform_filter(((np.abs(h2)<15)&(s2>0.5)).astype(np.float32),41)
suit=isl&(rf>0.45)&(((np.abs(h2)<30)&(s2>0.3)&(v2>0.12))|((h2>=15)&(h2<70)&(s2>0.12)&(v2<0.85)))
suit&=~((h2>35)&(h2<65)&(s2>0.6)&(v2>0.55))  # gold buckle
suit&=~((v2<0.3)&(s2<0.6))  # black belt
suit&=v>0.33  # dark seams, soles and shadows stay as painted
# keep the face (pink cheeks, nose, lips) and the boots (big brown areas) out of it
skin=(h2>-12)&(h2<28)&(s2>0.12)&(s2<0.7)&(v2>0.68)&isl
bb=(h2>12)&(h2<45)&(s2>0.66)&(v2>0.25)&isl
lb,nb=nd.label(bb);area=nd.sum(np.ones_like(v2),lb,range(1,nb+1))
big=np.zeros(nb+1,bool);big[1:]=area>8000
ls,ns=nd.label(skin);as_=nd.sum(np.ones_like(v2),ls,range(1,ns+1))
bigs=np.zeros(ns+1,bool);bigs[1:]=as_>0
protect=grow(bigs[ls],12)|grow(big[lb],3)
protect|=grow(big[lb],30)&(v2<0.3)  # boot soles
suit&=~(protect|protect0)
loc=nd.gaussian_filter(o,(3,3,0))
blend=np.clip((nd.gaussian_filter(suit.astype(np.float32),2)),0,1)[...,None]
o=o*(1-blend)+(tgt+0.45*(o-loc))*blend
print('stain px', stain.sum(), 'scuff', scuff.sum(), 'filled', m.sum())
# pad: every texel outside the UV islands takes the nearest island texel's colour,
# so mipmaps/downsampling never pull black (or another island) into a seam
inner=nd.binary_erosion(isl,iterations=1)
idx=nd.distance_transform_edt(~inner,return_distances=False,return_indices=True)
o=o[idx[0],idx[1]]
img=Image.fromarray((o*255+0.5).clip(0,255).astype(np.uint8))
img.save(out)
if len(sys.argv)>4: img.resize((int(sys.argv[4]),)*2,Image.LANCZOS).save(out)
