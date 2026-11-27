#!/usr/bin/env python3
"""Chromium verification of LIVE MN-B44 full-game GitHub Pages WebGL build.
This is browser smoke, NOT a claim to manually solve 26 acts."""
import asyncio
import json
import os
import time
from pathlib import Path
from playwright.async_api import async_playwright
from PIL import Image, ImageChops

BASE = "https://walexjung.github.io/myeongnyang-test/"
LANG = os.getenv("MN_LANG", "ko")
OUT = Path("browser-results") / LANG
OUT.mkdir(parents=True, exist_ok=True)
events = []
console_errors = []

def color_metrics(image_path):
    with Image.open(image_path) as im:
        img = im.convert("RGB")
        thumb = img.resize((160,90))
        vals = list(thumb.getdata())
        unique = len(set(vals))
        nonblack = sum(1 for r,g,b in vals if max(r,g,b)>32)
        return {"unique_colors":unique,"nonblack_ratio":round(nonblack/len(vals),3)}

def difference(a,b):
    with Image.open(a) as im1, Image.open(b) as im2:
        x=im1.convert("RGB").resize((160,90))
        y=im2.convert("RGB").resize((160,90))
        diff=ImageChops.difference(x,y)
        return {"changed_bbox":bool(diff.getbbox()),
                "changed_pixels":sum(1 for p in diff.getdata() if max(p)>24)}
async def main():
    async with async_playwright() as p:
        browser=await p.chromium.launch(headless=True,args=[
            "--use-gl=angle","--use-angle=swiftshader",
            "--enable-webgl","--enable-unsafe-swiftshader",
            "--disable-dev-shm-usage","--no-sandbox",
            "--autoplay-policy=no-user-gesture-required"
        ])
        context=await browser.new_context(viewport={"width":1280,"height":720},device_scale_factor=1,
                                           locale="ko-KR" if LANG=="ko" else "en-US")
        page=await context.new_page()
        page.on("pageerror",lambda e: console_errors.append({"type":"pageerror","text":str(e)}))
        page.on("console",lambda m: console_errors.append({"type":"console","text":m.text}) if m.type=="error" else None)
        url=BASE+"?lang="+LANG+"&qa="+os.getenv("GITHUB_RUN_ID","direct")
        resp=await page.goto(url,wait_until="domcontentloaded",timeout=120000)
        events.append({"step":"http","status":resp.status if resp else None,"url":page.url})
        assert resp and resp.status==200
        canvas=page.locator("#canvas")
        await canvas.wait_for(timeout=60000)
        events.append({"step":"canvas-present","count":await canvas.count()})
        await page.screenshot(path=str(OUT/"initial.png"))
        # Allow the Godot large PCK/WASM loading up to 150 seconds.
        try:
            await page.locator("#mn-enable-audio").wait_for(state="visible",timeout=150000)
            events.append({"step":"audio-start-overlay","visible":True})
        except Exception:
            events.append({"step":"audio-start-overlay","visible":False,
                           "status":await page.locator("#status").inner_text()})
            raise AssertionError("no ready audio overlay (Godot never finished loading)")
        await page.screenshot(path=str(OUT/"audio-ready.png"))
        await page.locator("#mn-enable-audio").click(timeout=15000)
        events.append({"step":"audio-overlay-click","removed":await page.locator("#mn-enable-audio").count()==0})
        await page.wait_for_timeout(2000)
        await page.screenshot(path=str(OUT/"language-picker.png"))
        rect=await canvas.bounding_box()
        assert rect and rect["width"]>320 and rect["height"]>180
        def cv(x,y):
            return (rect["x"]+x*rect["width"]/640,rect["y"]+y*rect["height"]/360)
        await page.mouse.click(*cv(240 if LANG=="ko" else 400,180))
        events.append({"step":"language-choice","language":LANG})
        await page.wait_for_timeout(1300)
        await page.screenshot(path=str(OUT/"opening-start.png"))
        # Click the REAL skip button, at (532..630, 10..36) in 640x360 canvas.
        # Clicking arbitrary video content only arms skip and caused a false pass.
        await page.mouse.click(*cv(581,22))
        await page.wait_for_timeout(2500)
        await page.screenshot(path=str(OUT/"after-skip-title.png"))
        # Distinguish actual title from still-playing full screen opening video:
        # the opening has a wide black caption band across y=0..40.
        def opening_top_black_ratio(path):
            with Image.open(path) as im:
                im=im.convert("RGB")
                # Canvas is scaled to page pixels. Inspect area away from menu/skip.
                xs=[int(im.width*x) for x in (0.15,0.25,0.35,0.45)]
                ys=[int(im.height*y) for y in (0.03,0.05,0.08)]
                colors=[im.getpixel((xx,yy)) for xx in xs for yy in ys]
                return sum(max(rgb)<32 for rgb in colors)/len(colors)
        black=opening_top_black_ratio(OUT/"after-skip-title.png")
        events.append({"step":"title-verified","top_black_ratio":black})
        if black>0.8:
            # WebGL resizing may transition late; press Esc fallback and recapture.
            await page.keyboard.press("Escape")
            await page.wait_for_timeout(1500)
            await page.screenshot(path=str(OUT/"after-skip-title.png"))
            black=opening_top_black_ratio(OUT/"after-skip-title.png")
            events.append({"step":"title-escape-fallback","top_black_ratio":black})
        assert black<0.8, "still in opening movie, not at title"
        # Real title NEW GAME entry is at x~64-204, y~196-214.
        await page.mouse.click(*cv(122,206))
        await page.wait_for_timeout(3500)
        await page.screenshot(path=str(OUT/"after-new-game.png"))
        screenshots={n:color_metrics(OUT/(n+".png")) for n in
             ["initial","audio-ready","language-picker","opening-start","after-skip-title","after-new-game"]}
        deltas={n:difference(OUT/(a+".png"),OUT/(b+".png")) for n,a,b in
             [("initial_to_ready","initial","audio-ready"),
              ("lang_to_opening","language-picker","opening-start"),
              ("opening_to_title","opening-start","after-skip-title"),
              ("title_to_game","after-skip-title","after-new-game")]}
        events.append({"step":"pixel-analysis","screenshots":screenshots,"deltas":deltas})
        # Basic browser-stage success, not full gameplay or English language quality.
        assert screenshots["language-picker"]["unique_colors"]>20, "canvas likely black after loading"
        assert deltas["lang_to_opening"]["changed_pixels"]>400, "language choice did not advance scene"
        assert not any("Failed loading file" in x.get("text","") for x in console_errors)
        (OUT/"result.json").write_text(json.dumps({
            "build":"MN-B44","kind":"REAL-LIVE-CHROMIUM-SMOKE-NOT-26-ACT-PLAY",
            "language":LANG,"events":events,"console_errors":console_errors[:200],
            "javascript_errors":[e for e in console_errors if e["type"]=="pageerror"]
        },ensure_ascii=False,indent=2))
        print("BROWSER_LIVE_SMOKE_OK",LANG,json.dumps(events,ensure_ascii=False)[-5000:])
        print("BROWSER_CONSOLE_ERROR_COUNT",len(console_errors))
        await browser.close()
if __name__=="__main__":
    try:
        asyncio.run(main())
    except Exception as e:
        output=OUT/"error.txt"
        output.write_text(repr(e)+"\n"+json.dumps(events,ensure_ascii=False,indent=2)+"\n"+json.dumps(console_errors,ensure_ascii=False,indent=2))
        print("BROWSER_LIVE_SMOKE_FAIL", LANG,repr(e),flush=True)
        raise
