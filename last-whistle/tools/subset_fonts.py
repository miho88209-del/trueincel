#!/usr/bin/env python3
"""Builds the small Chinese fallback fonts from the characters used in i18n/zh.json.

Run after editing translations:  python3 tools/subset_fonts.py
Downloads the full source fonts (OFL, Google Fonts) into tools/.font_cache on first use.
Also copies PT Mono (Cyrillic typewriter fallback). Needs: pip install fonttools
"""
import json, os, pathlib, urllib.request
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".font_cache"
BASE = "https://github.com/google/fonts/raw/main/ofl/"
SOURCES = {
    "MaShanZheng-Regular.ttf": "mashanzheng/MaShanZheng-Regular.ttf",
    "NotoSerifSC.ttf": "notoserifsc/NotoSerifSC%5Bwght%5D.ttf",
    "PTM55FT.ttf": "ptmono/PTM55FT.ttf",
}

def fetch(name):
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / name
    if not path.exists():
        print("downloading", name)
        urllib.request.urlretrieve(BASE + SOURCES[name], path)
    return path

def chars():
    text = "".join(json.load(open(ROOT / "i18n" / "zh.json", encoding="utf-8")).values())
    extra = "".join(chr(c) for c in range(0x20, 0x7F)) + "，。！？：；、「」『』（）—…·《》“”‘’％"
    return sorted(set(text + extra) - {"\n"})

def write_subset(font, out, text):
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    sub = subset.Subsetter(opts)
    sub.populate(text="".join(text))
    sub.subset(font)
    font.save(out)
    print(out.name, os.path.getsize(out) // 1024, "KB")

def main():
    cs = chars()
    hand = TTFont(fetch("MaShanZheng-Regular.ttf"))
    cmap = hand.getBestCmap()
    missing = [c for c in cs if ord(c) > 0x7F and ord(c) not in cmap]
    if missing:
        print("not in Ma Shan Zheng (Noto Serif SC covers them):", "".join(missing))
    write_subset(hand, ROOT / "fonts" / "MaShanZheng-zh.ttf", cs)
    serif = instancer.instantiateVariableFont(TTFont(fetch("NotoSerifSC.ttf")), {"wght": 500})
    write_subset(serif, ROOT / "fonts" / "NotoSerifSC-zh.ttf", cs)
    pt = TTFont(fetch("PTM55FT.ttf"))
    pt.save(ROOT / "fonts" / "PTMono-Regular.ttf")
    sc = TTFont(ROOT / "fonts" / "NotoSerifSC-zh.ttf").getBestCmap()
    lost = [c for c in cs if ord(c) not in sc and not c.isspace()]
    assert not lost, "glyphs missing from Noto Serif SC: " + "".join(lost)

if __name__ == "__main__":
    main()
