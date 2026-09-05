# MazeTV Builder — white-label Android TV / Fire TV IPTV player

Your own "APK builder": fill in a form on GitHub, get a branded, signed APK
a few minutes later. No Android Studio needed.

The app itself (in `app/`) is an original Flutter player:
- Xtream Codes login (`player_api.php`) **and** M3U playlist URL
- XMLTV EPG (auto-detected from Xtream / `url-tvg`, or a default you set) — streamed, so big guides don't crash a Fire Stick
- TV guide screen (now/next), search, categories, channel logos
- Full-screen player on `libmpv` (media_kit) — remote Up/Down changes channel, OK toggles info
- Built-in OpenVPN (`openvpn_flutter`) that loads a `.ovpn` profile URL you set at build time
- Leanback launcher + TV banner, so it shows up on the Fire TV / Android TV home row

## One-time setup (10 minutes)

1. Create a **private** GitHub repo and push this folder to it.
2. In the repo: **Settings → Actions → General → Workflow permissions** → allow read/write (default is fine).
3. *(Recommended)* add a permanent signing key so updates install over old builds:
   ```bash
   keytool -genkeypair -v -keystore release.jks -alias release -keyalg RSA -keysize 2048 -validity 10000
   base64 -w0 release.jks     # copy the output
   ```
   Then **Settings → Secrets and variables → Actions → New repository secret**:
   - `KEYSTORE_B64` = the base64 string
   - `KEYSTORE_PASSWORD` = the password you chose
   - `KEY_ALIAS` = `release`

   Keep `release.jks` backed up. If you skip this step, the builder makes a throwaway key each run (fine for testing).

## Building a branded APK

**Actions → "Build branded Android TV APK" → Run workflow**, fill in:

| Field | Example |
|---|---|
| app_name | `Maze TV` |
| package_id | `com.mazetv.player` (must be unique per brand) |
| primary_color | `#E50914` |
| portal_url | `http://portal.example.com:8080` (pre-fills the login) |
| epg_url | XMLTV URL for M3U users (Xtream users get theirs automatically) |
| vpn_url | URL to an `.ovpn` file |
| support_text | "Text your reseller for login info" |
| icon_url | Direct link to a 512×512 PNG (blank = auto icon from initials) |

When it finishes, download the artifact (`MazeTV-tv.apk`). Sideload with
Downloader / `adb install`.

## Layout

```
app/lib/
  main.dart               boot: load branding, pick login vs home
  config/branding.dart    reads assets/branding.json
  models/                 Channel, Programme, Account
  services/
    xtream_service.dart   player_api.php client
    m3u_service.dart      #EXTINF parser (tvg-id/logo/group, url-tvg)
    epg_service.dart      streaming XMLTV parser, 12-hour window
    channel_repo.dart     glue: account → channels + epg
    storage.dart          saved login
  ui/                     login, home, player, guide, vpn, shared TV widgets
tools/brand.py            stamps name/package/color/icon/banner into the project
.github/workflows/        the builder
```

## Known limits / next steps
- VOD & series (Xtream `get_vod_streams` / `get_series`) not wired yet — same client, new screens.
- Guide is now/next, not a full timeline grid.
- If the build fails inside `openvpn_flutter` (it lags Flutter/AGP releases sometimes), comment it out in
  `app/pubspec.yaml` and delete `app/lib/ui/vpn_screen.dart` + its two references in `home_screen.dart`
  to get a clean build, then re-add once the plugin updates.
- The player is legal on its own; what you point it at is your responsibility.

## The dashboard (GhostAPK-style builder page)

`web/` + `netlify/functions/` is a small site that puts a form and a live TV preview in
front of the GitHub build. Host it on Netlify (free):

1. Netlify → **Add new site → Import an existing project** → pick this repo.
   Build command: *(leave empty)*. Publish directory: `web`. Deploy.
2. On GitHub, make a **fine-grained personal access token** (Settings → Developer settings)
   scoped to this one repo with **Actions: Read and write** and **Contents: Read**.
3. Netlify → Site configuration → **Environment variables**, add:
   - `GITHUB_TOKEN` — the token from step 2
   - `GITHUB_REPO` — `Blkmaze/mazetv-builder`
   - `BUILDER_PASSWORD` — anything you like; the page asks for it
   - `BITLY_TOKEN` — optional (Bitly → Settings → API); if set, every build gets its own bit.ly code
4. Redeploy once so the variables take effect.

Then open the site, fill in a brand, click **Build APK**, and watch it go from
"Starting" to a download link and short code in about 6–8 minutes. Each build is also
published as a GitHub Release, so `releases/latest/download/…` always has the newest one.

## Embedded servers + "sign in with a code"

Two more ways to keep viewers away from typing a server URL:

**Pre-configured server list.** Pass `portals` (a JSON list) to a build:
```json
[{"name":"Prada","host":"http://pradahype.com:33726"}, {"name":"CDN","host":"http://kytv.xyz"}]
```
The login screen then shows a **Server** dropdown of those names (plus "Other server…" as an
escape hatch) instead of a URL field — viewers only ever type username and password. The
dashboard and the GitHub workflow both default this to your 4 known providers; edit or clear
it per build.

**Sign in with a code.** Set `pair_base_url` to your Netlify site's own URL (e.g.
`https://mazetv.netlify.app`) and the login screen gains a "Sign in with a code instead" link.
On the TV it shows a 6-digit code; the viewer opens `<your-site>/pair.html` on their phone,
types that code plus their login details once, and the TV signs itself in within a few
seconds — no remote-control typing at all. This uses **Netlify Blobs** (`netlify/functions/pair-*.js`),
which needs no extra setup beyond deploying the site; each code is single-use and expires
in 10 minutes.

This is the same shape GhostAPK's QR sign-in uses — a phone hands credentials to a small backend,
the TV polls for them. A literal QR code (instead of typing a 6-digit number) is a small further
step: generate one client-side on `pair.html` that encodes the same claim URL.
