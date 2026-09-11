# Atrium

The central courtyard for your self-hosted media stack.
One Android app that fronts Sonarr, Radarr, Lidarr, Prowlarr, Bazarr,
Seerr, Tautulli, Tracearr, Jellyfin, Emby, Plex, qBittorrent, Deluge,
Transmission, rTorrent, SABnzbd, NZBGet, Glances, Speedtest Tracker, Beszel, dashdot and Unraid - and routes every request through the right URL
whether you're on the home Wi-Fi or out in the world.

**[Website][site]** - screenshots and a tour, no install needed.

> **Status:** v1.6.1. Install from [F-Droid][fdroid], or grab a signed APK
> from the [releases page][releases].

## Why

[LunaSea][lunasea] (Flutter, GPL-3) was archived in 2024 and the niche is
open. Atrium picks up that space with a modern Flutter codebase, a focus
on multi-instance setups, and first-class handling of split local /
external URLs.

## Highlights

- **Multi-instance per service.** Run two Sonarrs, three qBits, whatever
  - every instance is a first-class profile entry.
- **Dual-URL routing.** Every instance has a LAN URL and a WAN URL. The
  app probes the LAN URL with a short timeout, caches the verdict per
  network, and falls back to WAN. You can pin Force-Local or
  Force-External per instance.
- **Activity feed.** One tab aggregates live activity across every
  instance: active streams from Plex / Jellyfin / Emby / Tautulli and
  transfers (downloads and active uploads) from qBittorrent, Deluge,
  Transmission, rTorrent, SABnzbd, NZBGet, and the *arr queues.
- **Controller, not a player.** Media servers are browse/manage/remote-
  control surfaces; playback stays with the official apps (deep links
  provided).
- **Wake-on-LAN.** Store your machines (MAC / broadcast / port) in the
  profile and wake them from Settings; magic packets are sent with pure
  Dart UDP.
- **Reverse-proxy friendly.** Global and per-instance custom HTTP
  headers (Authelia / Cloudflare Access style) ride every request.
- **Hardware-backed credentials.** API keys live in the Android Keystore
  via `flutter_secure_storage`. Optional biometric unlock on launch.
  Profiles export/import as JSON (including WOL devices and headers).
- **Material 3 Expressive.** Tonal cards, poster-palette theming,
  backdrop now-playing cards, and dynamic color throughout.
- **F-Droid first.** Reproducible build; no proprietary blobs and no
  runtime-fetching dependencies.

## Services

Every service below works today. Depth varies, and the table says what
each one covers:

| Service                | What works today                                                      |
| ---------------------- | --------------------------------------------------------------------- |
| Sonarr                 | 7 tabs incl. full Settings editor, sort/filter, calendar              |
| Radarr                 | same depth as Sonarr, movie flavored                                  |
| Lidarr                 | artists, albums and tracks, wanted, activity, settings, log reader (beta) |
| Prowlarr               | indexers, search + grab, history, settings, system                    |
| Bazarr                 | series/movies, wanted, manual subtitle search, system                 |
| Seerr                  | discover, search, requests management                                 |
| Tautulli               | activity, history, stats, users, terminate                            |
| Tracearr               | fleet overview, live streams, media catalog, user profiles, policy incidents |
| Jellyfin               | libraries, detail, seasons, music, sessions with remote control       |
| Emby                   | same depth as Jellyfin                                                |
| Plex                   | libraries, detail, seasons, music, genres, now-playing controller     |
| qBittorrent            | realtime list, add/manage, torrent detail, queue reorder, full settings |
| Deluge                 | torrent list, add/manage, queue moves, speed limits, torrent detail   |
| Transmission           | torrent list, add/manage, queue moves, turtle mode, torrent detail    |
| rTorrent               | torrent list, add/manage, priorities, speed limits, torrent detail    |
| SABnzbd                | queue, history with retry, speed limit, server stats                  |
| NZBGet                 | queue with reorder/priority/category, add NZB, speed limit, history   |
| Glances                | CPU/memory/network/disk monitoring                                    |
| Speedtest Tracker      | latest result, history chart, dashboard, confirmed remote test runs   |
| Beszel                 | systems list, live metrics, per-system detail screen                  |
| dashdot                | live CPU, memory, disk, and GPU usage with a system-info tab           |
| Unraid                 | array and disk health, system with per-core load, Docker, VM control  |

## Install

Atrium is on [F-Droid][fdroid], which is the easiest route: it picks the
right build for your device and keeps it updated.

To install by hand instead, grab the APK for your device from the
[releases page][releases]. Most phones want `app-arm64-v8a-release.apk`;
`armeabi-v7a` covers older 32-bit devices. Android 7.0 (API 24) or newer.

Atrium is built reproducibly, so F-Droid rebuilds it from source, verifies
the result matches the published APK byte for byte, and ships it carrying
this project's own signature. The two sources are therefore
interchangeable: you can move between the releases page and F-Droid without
uninstalling. F-Droid builds each tag only after it is published, so it can
sit a version behind the releases page for a few days.

### iOS

There is an iOS target and CI builds it on every change, but there is no
download and there will not be one. Atrium is GPL-3.0-or-later, which is
incompatible with the App Store's terms, and relicensing would need the
agreement of everyone who has contributed. So iOS means building it
yourself and sideloading, with Xcode or a tool like AltStore. iOS 14 or
newer.

Be aware this has never run on a real device - it is verified to compile,
nothing more. The first person to try it will find rough edges; issues and
fixes are welcome. On iOS the theme uses Atrium's own palette rather than
the system one, since there is no wallpaper colour to read, and iOS will
ask permission the first time the app reaches a device on your network.

## Build

Requires Flutter `^3.27` and Dart `^3.6` (pub workspaces).

```sh
flutter pub get
flutter run -d <device>
```

Code-generation step (run after edits to any freezed / json_serializable
model). To run code generation for a specific package, navigate to that
package's directory and run:

```sh
dart run build_runner build --delete-conflicting-outputs
```

Alternatively, to run code generation for all packages in the workspace
from the repository root, run:

```sh
dart run tool/build_all.dart
```

Debug builds need no setup. To try a **release** build without a signing key
of your own, sign it with the debug key:

```sh
flutter build apk --release -PdebugSignRelease=true
```

Without that flag a release build comes out **unsigned**, and an unsigned APK
will not install. That is deliberate rather than an oversight: F-Droid
verifies a release by copying the signature off the published APK onto its
own build of the same source, which only works if its build carries no
signature. So the flag must never be set for anything you publish.

To sign with your own key instead, copy `app/android/key.properties.example`
next to itself as `key.properties` and fill it in; that file and the keystore
it points at are gitignored.

Published releases are built by CI and signed by hand: see
[docs/RELEASING.md](docs/RELEASING.md).

## Repo layout

```
app/                     Flutter application - the APK target
packages/                Cross-service infrastructure
  core_models/           Domain models (Profile, Instance, WolDevice, ...)
  core_storage/          Secure storage, Hive boxes, biometric unlock
  core_networking/       Dio factory, dual-URL resolver, WOL, custom headers
  core_profile/          Profile CRUD, providers, import/export
  core_ui/               Material 3 theme + shared widgets
  core_router/           GoRouter setup (shell with drawer + bottom nav)
services/                One feature package per integrated service
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution guide and
[STATUS.md](STATUS.md) for a detailed feature snapshot.

## License

[GPL-3.0-or-later](LICENSE) - the same license as Sonarr, Radarr,
Jellyfin, qBittorrent, and LunaSea.

[fdroid]: https://f-droid.org/packages/app.atrium/
[lunasea]: https://github.com/JagandeepBrar/LunaSea
[releases]: https://github.com/retransmit/Atrium/releases
[site]: https://retransmit.github.io/Atrium/
