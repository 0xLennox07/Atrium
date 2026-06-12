# Atrium - Status

> Snapshot of what genuinely works and what is left, as of 2026-06-12.
> Atrium is in early development; nothing here is a release promise.

## Scope note

Atrium is a **controller** app. Video playback was removed by design
(2026-06-12): media servers are browse/manage only. Do not re-add a player.

## What is DONE (genuinely complete)

- Core foundation: profiles, multi-instance, dual-URL routing, secure key
  storage, import/export (live-verified incl. SAF picker), per-service
  health dots, theming, launcher icon
- **qBittorrent** (phone-verified live): cookie login (qBit 5.x 204 fix),
  3s realtime list polling, add magnet/file, categories, pause/resume/
  delete/recheck/queue moves, detail screen (overview/files/trackers),
  per-file priority
- **Sonarr** (live-verified): poster grid, series detail (seasons, monitor
  toggles, season search, delete), search-and-add (quality profile + root
  folder + monitor options), queue 3s / library 60s polling, calendar tab
  (month grid with status dots; contributed, live-verified)
- **Radarr** (live-verified): same depth as Sonarr, movie flavored
- **Prowlarr** (live-verified incl. grab-to-client): indexer list + stats
  w/ 60s polling, enable/disable (forceSave), test, manual search across
  indexers w/ seeders/size/age sort, grab lands in the download client
- **Tautulli** (live-verified incl. a real stream): Activity tab w/ 10s
  polling, session detail sheet (codecs, decisions, bandwidth, terminate
  w/ inline errors), History, Stats (30-day home stats), Users

## Partially done

### Media servers - Jellyfin / Emby (browse + detail + search)

Have: auth, library chips + poster grid, folder drill-down, Continue
Watching resume rows, item detail screens, in-server search, favorite
toggles (contributed). Missing:

1. Next Up / Recently Added home rows
2. Now Playing / active sessions tab
3. Watched/unwatched toggles

### Plex (browse only)

Library chips + poster grid + folder drill-down. No detail screen,
search, or home rows yet.

### Other shallow modules

- Bazarr: only badges + wanted list; missing search/download subtitle
  actions, history, per-item language profiles
- Overseerr: request list + approve/decline only; missing titles/posters
  (needs tmdbId lookup), discover/search, issue reporting
- SABnzbd: queue control only; missing history, categories, speed limits,
  polling

## App-wide TODO

1. Release signing + F-Droid metadata (debug-signed right now)
2. iOS platform scaffold
3. Live-stack testing of Bazarr/Overseerr/SABnzbd (built from docs only)
4. Possible profile loss after Android hard-kill (seen once - investigate
   crash-safe Hive writes/backup)
5. Polish: empty states, tablet layouts, localization

## Contributing

PRs target `development`. Generated freezed/json files are gitignored -
run build_runner in each changed package after pulling model changes.
All imperative navigation must use `pushScreen` from core_ui (root
navigator); see CONTRIBUTING.md.
