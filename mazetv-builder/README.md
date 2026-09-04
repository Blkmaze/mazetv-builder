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
