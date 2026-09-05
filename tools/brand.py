#!/usr/bin/env python3
"""
Stamps branding into a freshly `flutter create`d Android project.

  brand.py --project build/proj --app-name "Maze TV" --package com.example.mazetv \
           --color "#E50914" [--portal-url ...] [--epg-url ...] [--vpn-url ...] \
           [--support-text ...] [--icon path-or-url]

What it does:
  1. writes assets/branding.json (read by the app at startup)
  2. sets applicationId + minSdk in android/app/build.gradle(.kts)
  3. patches AndroidManifest.xml for Android TV / Fire TV (leanback launcher,
     banner, no-touchscreen, INTERNET/WAKE_LOCK, cleartext http)
  4. generates launcher icons + TV banner (from --icon or auto-made initials)
"""
import argparse, io, json, os, re, sys, urllib.request
from PIL import Image, ImageDraw, ImageFont

ap = argparse.ArgumentParser()
ap.add_argument("--project", required=True)
ap.add_argument("--app-name", required=True)
ap.add_argument("--package", required=True)
ap.add_argument("--color", default="#E50914")
ap.add_argument("--portal-url", default="")
ap.add_argument("--epg-url", default="")
ap.add_argument("--vpn-url", default="")
ap.add_argument("--support-text", default="")
ap.add_argument("--icon", default="")
ap.add_argument("--portals", default="[]", help='JSON list like [{"name":"Prada","host":"http://pradahype.com:33726"}]')
ap.add_argument("--pair-base-url", default="")
ap.add_argument("--repo", default="", help="owner/name this build is published from (for in-app OTA update checks)")
ap.add_argument("--build-number", default="0", help="GitHub Actions run number for this build")
a = ap.parse_args()

P = a.project
if not re.fullmatch(r"[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+", a.package):
    sys.exit(f"Bad package id: {a.package} (use e.g. com.mybrand.tv)")
color = a.color if a.color.startswith("#") else "#" + a.color
if not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
    sys.exit(f"Bad color: {a.color} (use #RRGGBB)")

# 1. branding.json -----------------------------------------------------------
os.makedirs(f"{P}/assets", exist_ok=True)
try:
    portals = json.loads(a.portals)
    assert isinstance(portals, list)
except Exception:
    sys.exit(f"--portals must be a JSON list, got: {a.portals}")

with open(f"{P}/assets/branding.json", "w") as f:
    json.dump({
        "app_name": a.app_name, "primary_color": color, "portal_url": a.portal_url,
        "epg_url": a.epg_url, "vpn_config_url": a.vpn_url, "support_text": a.support_text,
        "portals": portals, "pair_base_url": a.pair_base_url,
        "repo": a.repo, "build_number": int(a.build_number or 0),
    }, f, indent=2)
print("[brand] wrote branding.json")

# 2. gradle ------------------------------------------------------------------
def patch(path, subs):
    s = open(path).read()
    for pat, rep in subs:
        s, n = re.subn(pat, rep, s, count=1)
        if n == 0:
            print(f"[brand] WARN pattern not found in {os.path.basename(path)}: {pat}")
    open(path, "w").write(s)

gradle = f"{P}/android/app/build.gradle.kts"
if os.path.exists(gradle):
    patch(gradle, [
        (r'applicationId\s*=\s*"[^"]+"', f'applicationId = "{a.package}"'),
        (r'minSdk\s*=\s*[^\n]+', 'minSdk = 21\n        ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }'),
    ])
else:
    gradle = f"{P}/android/app/build.gradle"
    patch(gradle, [
        (r'applicationId\s+"[^"]+"', f'applicationId "{a.package}"'),
        (r'minSdkVersion\s+[^\n]+', 'minSdkVersion 21\n        ndk { abiFilters "armeabi-v7a", "arm64-v8a" }'),
    ])
print(f"[brand] applicationId -> {a.package}, minSdk 21, ABIs: armeabi-v7a + arm64-v8a only")

# 3. manifest ----------------------------------------------------------------
man = f"{P}/android/app/src/main/AndroidManifest.xml"
s = open(man).read()
perms = """
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-feature android:name="android.software.leanback" android:required="true"/>
    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>
"""
s = s.replace("<application", perms + "    <application", 1)
s = re.sub(r'android:label="[^"]*"', f'android:label="{a.app_name}"', s, count=1)
s = s.replace("<application", '<application\n        android:banner="@mipmap/ic_banner"\n        android:usesCleartextTraffic="true"', 1)
s = s.replace('<category android:name="android.intent.category.LAUNCHER"/>',
              '<category android:name="android.intent.category.LAUNCHER"/>\n'
              '                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>', 1)
open(man, "w").write(s)
print("[brand] manifest patched for Android TV")

# 4. icons -------------------------------------------------------------------
def load_icon():
    if a.icon:
        data = urllib.request.urlopen(a.icon).read() if a.icon.startswith("http") else open(a.icon, "rb").read()
        return Image.open(io.BytesIO(data)).convert("RGBA")
    # auto: colored rounded square with initials
    img = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, 511, 511), radius=96, fill=color)
    initials = "".join(w[0] for w in a.app_name.split()[:2]).upper() or "TV"
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 240)
    except Exception:
        font = ImageFont.load_default()
    bb = d.textbbox((0, 0), initials, font=font)
    d.text(((512 - bb[2] + bb[0]) / 2 - bb[0], (512 - bb[3] + bb[1]) / 2 - bb[1]), initials, font=font, fill="white")
    return img

icon = load_icon()
res = f"{P}/android/app/src/main/res"
for d, sz in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    os.makedirs(f"{res}/mipmap-{d}", exist_ok=True)
    icon.resize((sz, sz), Image.LANCZOS).save(f"{res}/mipmap-{d}/ic_launcher.png")

# TV banner 320x180 (xhdpi): icon on the left, name on the right
ban = Image.new("RGBA", (320, 180), color)
ban.alpha_composite(icon.resize((140, 140), Image.LANCZOS), (20, 20))
d = ImageDraw.Draw(ban)
try:
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28)
except Exception:
    f = ImageFont.load_default()
d.text((175, 76), a.app_name[:14], font=f, fill="white")
os.makedirs(f"{res}/mipmap-xhdpi", exist_ok=True)
ban.save(f"{res}/mipmap-xhdpi/ic_banner.png")
print("[brand] icons + TV banner generated")
