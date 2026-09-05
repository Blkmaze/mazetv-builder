# MazeTV Builder — white-label Android TV / Fire TV IPTV player

Your own "APK builder": fill in a form, get a branded, signed APK a few
minutes later. No Android Studio needed, no reseller panel, no billing —
this is a personal build tool for your own use.

The app itself (in `app/`) is an original Flutter player:
- Xtream Codes login (`player_api.php`) **and** M3U playlist URL
- **Multiple servers with failover** — add several Xtream/M3U sources, prioritize
  and enable/disable them; if the top one is down, the app automatically tries
  the next one at login
- XMLTV EPG (auto-detected from Xtream / `url-tvg`, or a default you set) — streamed, so big guides don't crash a Fire Stick
- TV guide screen with a live "now playing" preview panel: a muted live thumbnail
  of whichever channel has focus, its current programme with a progress bar, and
  what's up next
- Collapsible icon nav rail — sits as icons-only, expands to show labels while
  D-pad focus is anywhere inside it, collapses back once focus moves into the
  categories or channel list (the categories column itself stays put)
- Household profiles ("Who's watching?") — each profile keeps its own favorites;
  only shown at startup once you've added a second profile
- Favorites — hold OK on any channel to star it; shows up in the "★ Favorites" row
- Search, categories, channel logos
- Full-screen player on `libmpv` (media_kit) — remote Up/Down changes channel, OK toggles info
- Built-in OpenVPN (`openvpn_flutter`) that loads a `.ovpn` profile URL you set at build time
- Leanback launcher + TV banner, so it shows up on the Fire TV / Android TV home row
- Checks GitHub Releases on launch for a newer build of the same brand and offers
  a one-tap update (opens the signed APK's download link)

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

Two ways to trigger the same workflow — pick whichever's easier:

**Option A — the build page (`web/builder.html`)**

A single static HTML file, no server, no hosting required:

1. Open `web/builder.html` directly in a browser (double-click it), or serve it
   locally (`python3 -m http.server` from the `web/` folder), or enable
   **Settings → Pages → Deploy from a branch → `/web`** on this repo to get it at
   `https://<you>.github.io/mazetv-builder/builder.html`.
2. Paste in a GitHub [personal access token](https://github.com/settings/tokens/new?description=mazetv-builder&scopes=repo,workflow)
   (classic, scopes `repo` + `workflow`; or a fine-grained token scoped to this repo
   with Actions read/write + Contents read). It's stored only in that browser's
   local storage and only ever sent to `api.github.com` — there's no backend.
3. Fill in the brand fields and click **Build APK**. The page dispatches the
   workflow, polls the run, and shows the signed APK's direct download link the
   moment the release is published.

**Option B — the GitHub Actions form**

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

Either way, when it finishes the signed APK is attached to a GitHub Release
(tag `build-<run number>`) — sideload the download URL with Downloader / `adb install`.
The app itself also checks this list on launch and offers an in-app update when a
newer build of the same brand shows up (see OTA below).

## OTA updates

Every brand built from this repo shares one release list, so the app matches by
asset filename (`<SafeAppName>-tv.apk`) rather than by tag alone. `tools/brand.py`
stamps the repo (`owner/name`) and this build's Actions run number into
`assets/branding.json` at build time; on launch the app fetches
`GET /repos/<repo>/releases`, finds the newest release whose assets include a
matching filename, and — if its run number is higher than the running app's —
offers **Update now** (opens the APK URL in the browser to sideload) or **Skip
this version**. It's a best-effort check: offline or rate-limited just skips it
silently, it never blocks normal use.

## Layout

```
app/lib/
  main.dart               boot: load branding, pick login vs home
  config/branding.dart    reads assets/branding.json (incl. repo + build_number for OTA)
  models/                 Channel, Programme, Account, ServerConfig, Profile
  services/
    xtream_service.dart   player_api.php client
    m3u_service.dart      #EXTINF parser (tvg-id/logo/group, url-tvg)
    epg_service.dart      streaming XMLTV parser, 12-hour window
    channel_repo.dart     glue: server(s) → channels + epg, with failover
    ota_service.dart      checks GitHub Releases for a newer build of this brand
    storage.dart          servers, profiles, favorites, last channel
  ui/
    login_screen.dart     first-run: add your one server (portal picker + code sign-in, if configured)
    code_signin_screen.dart  shows the pairing code, polls until claimed from web/pair.html
    server_form.dart      shared add/edit-a-server form (tests the connection first)
    servers_screen.dart   manage the failover list (reorder / enable / edit / delete)
    profiles_screen.dart  "Who's watching?" + profile management
    home_screen.dart       channel browser, favorites, collapsible nav rail
    settings_screen.dart   refresh channels/guide, VPN, sign out, version
    guide_screen.dart      TV guide + live now-playing preview panel
    player_screen.dart, vpn_screen.dart, tv_widgets.dart (shared D-pad-friendly widgets)
tools/brand.py            stamps name/package/color/icon/banner/repo/build#/portals/pair-base-url
web/builder.html          personal build page (GitHub Actions, no backend)
web/index.html, web/pair.html, netlify/functions/  optional Netlify dashboard + code sign-in backend
.github/workflows/        the builder
```

## Known limits / next steps
- VOD & series (Xtream `get_vod_streams` / `get_series`) not wired yet — same client, new screens.
- Guide is per-channel now/next strips plus a live preview panel, not a fully synced
  timeline grid (all channels sharing one scrolling time axis) — a bigger feature
  that's a reasonable next step if you want it.
- Failover happens when a server can't be logged into / fetched at all; if a server
  is up but returns a mostly-broken channel list, it's still "successful" and won't
  fail over mid-stream to another source's copy of the same channel.
- If the build fails inside `openvpn_flutter` (it lags Flutter/AGP releases sometimes), comment it out in
  `app/pubspec.yaml` and delete `app/lib/ui/vpn_screen.dart` + its two references in `home_screen.dart`
  to get a clean build, then re-add once the plugin updates.
- No Flutter toolchain was available to compile-check these changes locally — they were written
  and reviewed carefully, but give the next Actions build a look before relying on it.
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
