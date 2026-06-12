# Atrium - Status

> Snapshot of what genuinely works and what is left, as of 2026-06-11.
> Atrium is in early development; nothing here is a release promise.

## What is DONE (genuinely complete)

- Core foundation: profiles, multi-instance, dual-URL routing, secure key
  storage, import/export, per-service health dots, theming, launcher icon
- **qBittorrent** (phone-verified live): cookie login (qBit 5.x 204 fix),
  3s realtime list polling, add magnet/file, categories, pause/resume/
  delete/recheck/queue moves, detail screen (overview/files/trackers),
  per-file priority
- **Sonarr** (live-verified): poster grid, series detail (seasons, monitor
  toggles, season search, delete), search-and-add (quality profile + root
  folder + monitor options), queue 3s / library 60s polling
- **Radarr** (live-verified): same depth as Sonarr, movie flavored
- **Prowlarr** (near-complete, live-verified except grab): indexer list +
  stats w/ 60s polling, enable/disable toggle, test, manual search across
  indexers w/ sort; grab-to-client is built but deliberately untested

## What is LEFT

### Media servers - Jellyfin / Emby / Plex (only browse + basic playback exist)

Current state: auth, library chips + poster grid, folder drill-down,
tap-to-play with resume, progress reporting. Missing:

1. Home sections: Continue Watching / Next Up / Recently Added rows
2. Item detail screen (synopsis, cast, ratings, runtime, media info,
   play/resume buttons, proper season/episode lists w/ metadata)
3. Now Playing / active sessions tab
4. In-server search
5. Watched/unwatched + favorite toggles
6. Player: audio/subtitle track selection, chapters, next-episode autoplay
7. Confirm video decode on real hardware (black on emulator GPU)

### Tautulli (only the active-streams list exists)

1. Now Playing detail: direct play vs transcode, bandwidth, progress,
   terminate stream action
2. History tab (w/ filters per user/media)
3. Statistics: top media, top users, play counts, graphs
4. Users tab
5. Polling for activity

### Other incomplete modules

- Bazarr: only badges + wanted list; missing search/download subtitle
  actions, history, per-item language profiles
- Overseerr: request list + approve/decline only; missing titles/posters
  (needs tmdbId lookup), discover/search, issue reporting
- SABnzbd: queue control only; missing history, categories, speed limits,
  polling

### App-wide

1. Release signing + F-Droid metadata (debug-signed right now)
2. iOS platform scaffold
3. Sonarr calendar screen (API method exists, no UI)
4. Live-stack testing of Bazarr/Overseerr/SABnzbd (built from docs only)
5. Possible profile loss after Android hard-kill (seen once - investigate
   crash-safe Hive writes/backup)
6. Polish: empty states, tablet layouts, localization
