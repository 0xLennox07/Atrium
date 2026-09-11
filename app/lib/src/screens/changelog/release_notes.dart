import 'package:flutter/foundation.dart';

/// A category of change within a release, rendered as a colored label.
enum ChangeCategory { added, improved, fixed }

/// One category's bullets within a release.
@immutable
class ChangeGroup {
  const ChangeGroup(this.category, this.items);
  final ChangeCategory category;
  final List<String> items;
}

/// One version and what changed in it.
@immutable
class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.date,
    required this.groups,
  });
  final String version;
  final String date;
  final List<ChangeGroup> groups;
}

/// Newest first. Update alongside appVersion and the pubspec at each release.
const List<ReleaseNote> releaseNotes = <ReleaseNote>[
  ReleaseNote(
    version: '1.6.1',
    date: '2026-09-11',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'A Wake-on-LAN widget for the dashboard. The machines you have set up can be woken with one tap from the board, without going into settings to find them. It tells you the magic packet was sent rather than that the machine woke, since nothing answers one and a machine takes a while to come up.',
        'Adding a torrent in qBittorrent fills in the save path from the server, using its default location or the path the chosen category defines, so it no longer has to be typed out for every torrent.',
        'The sidebar can be pulled down to refresh the health of every service. It also checks again when you open it if the last check is more than a minute old, and keeps them current every 30 seconds while it stays open.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'Custom headers warn you when a header will not survive the trip. Several services use Authorization for their own sign-in and overwrite yours, and qBittorrent refuses one it did not issue, so the warning names the affected services and suggests Proxy-Authorization, which works wherever your proxy accepts it.',
        'The health check no longer mistakes the login page of a reverse proxy for a working server. It used to follow the redirect to a sign-in page, get a normal answer back, and report the service as online. It now recognises a login page and shows a warning instead.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Posters and backdrops load behind a reverse proxy. Artwork never carried your custom headers, so behind Authelia, Cloudflare Access or similar every image was refused and came up blank while the rest of the app worked.',
        'Headers set for the whole profile now reach every request. Test connection, the health dot on each service, and the Beszel, dashdot and Glances clients all dropped them, which is why Test connection could fail while the app itself worked fine.',
        'The Active downloads widget shows what is actually downloading. It sorted purely by progress, so a queue of nearly finished torrents could push the one live download off the card.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.6.0',
    date: '2026-08-30',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Unraid is now a supported service. The array tab shows parity and data disks with per-disk usage, temperature and health, alongside the state of the last parity check. The system tab covers per-core CPU load, memory, network, and an About card naming the processor, uptime, kernel, memory slots and hostname. Docker containers list with their ports and uptime, open to a detail sheet, and can be started, stopped, paused and resumed. Virtual machines can be started, shut down, paused, resumed, rebooted, force stopped and reset. It is marked beta while it settles in.',
        'Radarr and Sonarr interactive search can open a release on its torrent or indexer page, so you can look it over before grabbing it, and copy its download URL or magnet link.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'qBittorrent remembers how you sorted the list. Whatever you last chose is what you get next time you open the app, kept separately for each server, rather than resetting to newest first on every launch.',
        'The dashboard only offers widgets something you have configured can actually fill, and says which service a widget is waiting on rather than adding an empty card.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'The filter button on the qBittorrent screen opens the filter drawer again. It had been asking the wrong part of the screen, which answered by doing nothing at all, so the button looked dead while swiping in from the edge still worked.',
        'When a server refuses a request with 401 or 403, Atrium now shows the reason the server gave instead of replacing it with a generic authentication message. A refusal that turns out to be a cross-site check rather than a bad key now says so.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.5.1',
    date: '2026-08-26',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Adding things in Lidarr works again. Adding an artist, indexer, download client, import list, notification, tag, root folder, custom format or any of the profiles was refused by the server, as was grabbing a release from an interactive search. Atrium was sending empty fields that Lidarr will not accept, and it rejected the whole request without saying which part it disliked.',
        'Interactive search no longer fails on Lidarr nightly and on builds with plugins installed. Those versions name their download protocols differently, and a single name Atrium did not recognise discarded the entire list of results rather than that one field.',
        'Lidarr screens no longer run off the edge at large system text sizes, in the track file editor, the unmapped files list and artist history.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'Lidarr activity history keeps loading as you scroll instead of stopping at the first page.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.5.0',
    date: '2026-08-23',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Lidarr is now a supported service: artists and discography, album and track detail, wanted, queue and history, the full settings tree, an in-app log reader, and album releases in the calendar. It is marked beta while it settles in.',
        'qBittorrent gained a settings page covering what its own web interface offers, across system, behaviour, downloads, connection, speed, BitTorrent, RSS, web UI and advanced.',
        'qBittorrent torrents can be moved around the queue, to the top, up, down or to the bottom, one at a time or several at once, and the list can be sorted by queue position.',
        'The app icon now follows your system palette when Android themed icons are switched on.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'The qBittorrent screen leads with your totals, active downloads and what is seeding, with search and start or stop everything to hand, and splits the torrent list and settings across two tabs.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Changing a qBittorrent setting that would cut Atrium off from the server now asks first. Moving the web UI address or port leaves the app unable to reach it, and turning off CSRF or clickjacking protection weakens the server, so each explains what it will do before going ahead.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.4.2',
    date: '2026-08-21',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'qBittorrent can skip the hash check when you add a torrent whose files are already on disk, instead of rechecking the whole thing.',
        'qBittorrent torrents can be filtered by tracker, with a count next to each one.',
        'The calendar can show unmonitored releases as well as monitored ones, and remembers which you chose.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'Tapping a transfer in Activity opens that torrent, movie or series directly instead of dropping you on the service to find it again. Works for qBittorrent, Deluge, Transmission, rTorrent, Sonarr and Radarr.',
        'A tracker message in qBittorrent now wraps instead of being cut off, so you can read why a tracker is not working.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Cover art is no longer blank when Sonarr or Radarr is served from a subpath with a URL Base configured.',
        'The calendar no longer labels an episode as monitored when the series it belongs to is not.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.4.1',
    date: '2026-08-15',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Interactive search in Sonarr and Radarr now shows the custom format score and the formats each release matched, sorted best match first.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'Tracearr has been rebuilt: an overview of your whole fleet, live streams with playback diagnostics, a media catalog with per-server availability, user profiles, and a security ledger.',
        'Tracearr is no longer marked beta.',
        'When a server asks you to slow down, Atrium now waits the time it asked for and retries instead of showing an error.',
        'Lists that load more as you scroll now tell you when you have reached the end.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Tracearr no longer keeps polling a screen you have left, and its artwork cache no longer grows without limit.',
        'Marking a Tracearr security incident as reviewed now says plainly that it is only stored on this device.',
        'One unreadable item no longer blanks a whole Tracearr list.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.4.0',
    date: '2026-08-13',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Beszel is now a supported service: see your systems, their live metrics, and a detailed screen for each one.',
        'dashdot is now a supported service too, with live CPU, memory, disk, and GPU rings and a system information tab.',
        'qBittorrent gained tag management: filter your torrents by tag, and copy a tracker URL straight from the trackers list.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'The Files tab now shows the full file name instead of cutting it off.',
        'rTorrent, Deluge, Transmission, SABnzbd, and Speedtest Tracker now use their own icons.',
        'Tracearr, Transmission, Deluge, and rTorrent are marked as beta so you know what is still settling in.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Testing a connection now checks your credentials for Beszel and for qBittorrent API keys, instead of only checking that the server answers.',
        'The Deluge torrent detail screen no longer crashes on some torrents.',
        'Scrolling is smoother in Emby, Jellyfin, and Beszel.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.3.3',
    date: '2026-08-07',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Delete a film or an episode from disk while keeping it in your library, so you free the space without losing the entry. Tick unmonitor at the same time and it will not simply download again.',
        'The same thing in bulk: select several films or series, choose Delete files only, and the entries stay behind.',
        'Radarr can be sorted ascending or descending.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Lists no longer run underneath the system navigation buttons at the bottom of the screen.',
        'The buttons on a film or series detail screen no longer wrap onto a second line on narrower phones.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.3.2',
    date: '2026-08-07',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Share a whole batch of .torrent files at once and Atrium adds them together, rather than one share at a time.',
        'Tracearr gained detail screens: tap a title to see its statistics and who has been watching it, or tap an account to see what they have played.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'Tracearr now talks to its public API and asks for an API key instead of a username and password. Open Tracearr, go to Settings, API Key, Generate Key, and paste that into the instance. If you had Tracearr set up before, you will need to do this once.',
        'That public API covers less than the one Atrium used before, so if there is something from Tracearr you want here and cannot find, open a feature request on GitHub and we will see what we can reach.',
        'Sonarr and Radarr remember whether you left them in grid or list view.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'The bottom navigation bar no longer has its icons clipped on phones using three-button navigation.',
        'Recently Downloaded no longer repeats the same episode or film several times, and a season that arrived in one go now reads as a single entry.',
        'Tracearr instances that were answering perfectly no longer report that the server could not be reached when you test the connection.',
        'The Emby search bar lines up with the rest of the screen.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.3.1',
    date: '2026-08-06',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Atrium now turns up in the list when you tap a .torrent file or open a magnet link, and in the share sheet when you share either from another app.',
        'If you have more than one torrent client set up it asks which one to send it to, otherwise it goes straight there.',
        'Either way the usual add sheet opens with the link or file already filled in, so the save path, category and start-paused choices are still yours.',
        'Share several in a row and they queue up one after another rather than only the first arriving.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.3.0',
    date: '2026-08-04',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Deluge, Transmission and rTorrent are now services you can add, so every common torrent client is covered alongside qBittorrent.',
        'Each one gives you a live torrent list with start, stop, remove, recheck and reannounce, filter chips, sorting, global speed limits, and a detail screen with files, peers and trackers.',
        'Add a torrent by magnet link, .torrent URL or file, and pick where it lands.',
        'Tracearr is now a service you can add: who is streaming right now, watch and library statistics, history, and a map of where accounts are being used from.',
        'Atrium builds for iOS. There is no download, since the licence rules out the App Store, so you build and sideload it yourself. It has not run on real hardware yet, so expect rough edges.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'The torrent screens lead with the two live speeds, and a transfer that is actually moving gets a wavy progress bar so you can tell at a glance which ones are running.',
        'A finished torrent shows its share ratio in the progress bar instead of sitting at 100 percent saying nothing.',
        'Detail screens now open over the whole screen rather than inside the tab.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Screens that took longer to load than their refresh interval could restart forever and never finish loading. They now wait for a refresh to finish before scheduling the next, and back off when a server is not answering.',
        'A server that stays unreachable no longer flashes a spinner over the error every few seconds.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.2.0',
    date: '2026-07-29',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'NZBGet is now a service you can add, with a live queue you can drag to reorder, pause and resume item by item, and delete from.',
        'Add an NZB from the app by pasting a URL or picking an .nzb file, and change an item\'s priority or category once it is queued.',
        'Set a download speed limit, or lift it, without leaving the queue.',
        'NZBGet history lists completed and failed downloads, with retry on the ones that failed.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'NZBGet downloads show up in the Active downloads widget and the Activity tab alongside your other download clients.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.1.1',
    date: '2026-07-24',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Check for updates from Settings, About. See whether a newer version is out and open its release page. Atrium never installs updates itself.',
        'When an update is available, the Change log shows it at the top with the release notes read inline.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'The Change log is now per-version cards with New, Improved and Fixed labels in your accent colors, dates, and an Installed marker.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.1.0',
    date: '2026-07-23',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Speedtest Tracker service, follow your download, upload and ping speeds from the dashboard.',
        'Test Connection button on every service, check the URL and login before you save.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.0.7',
    date: '2026-07-19',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Radarr settings now match Sonarr\'s, configurable to the same depth.',
      ]),
      ChangeGroup(ChangeCategory.improved, <String>[
        'New theming engine with a cleaner, flatter look and a live-updating Settings preview.',
        'Glances gauges follow your theme instead of fixed colors.',
        'Logs keep loading as you scroll instead of stopping after the first page.',
        'Series and movie detail screens scroll noticeably more smoothly.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Scrolling no longer over-stretches at the edges.',
        'Dashboard widgets keep their state as you move around.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.0.6',
    date: '2026-07-17',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.improved, <String>[
        'Unified pull to refresh across every screen, smoother and more responsive.',
        'Detail screens fade their title into the app bar, and the bottom bar hides as you scroll down.',
        'Seerr posters, backdrops and cast now load from your own Seerr server rather than TMDB.',
      ]),
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Pull to refresh no longer fires when you swipe a poster row sideways.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.0.5',
    date: '2026-07-17',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Build numbers now follow F-Droid\'s scheme. If you came from an earlier GitHub build, Android needs a one-time reinstall, so export your profiles from Settings first. Nothing after this is affected.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.0.4',
    date: '2026-07-17',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Reproducible builds now match F-Droid\'s byte for byte, a library had carried a build-path fingerprint.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.0.3',
    date: '2026-07-17',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.improved, <String>[
        'Releases are now built by a server so F-Droid can rebuild and verify them, letting the two share one signature so you can move between them without reinstalling.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.0.2',
    date: '2026-07-17',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Removed an encrypted dependency list the Android tools embedded in every APK, it was Play only and never sent anywhere.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.0.1',
    date: '2026-07-16',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.fixed, <String>[
        'Security, 1.0.0 attached your Sonarr or Radarr API key to poster requests sent to TheTVDB, TMDB and Fanart.tv. If you ran 1.0.0, consider rotating those keys.',
        'Posters and backdrops now load from your own Sonarr and Radarr instances, so the artwork sites no longer see your address or what you are browsing.',
      ]),
    ],
  ),
  ReleaseNote(
    version: '1.0.0',
    date: '2026-07-16',
    groups: <ChangeGroup>[
      ChangeGroup(ChangeCategory.added, <String>[
        'Dashboard of at-a-glance widgets (downloads, now streaming, upcoming, recently added and downloaded, requests, server info), reorderable.',
        'Sonarr and Radarr management across library, queue, wanted, history, blocklist, system and settings.',
        'qBittorrent, SABnzbd, Prowlarr, Bazarr, Seerr, Tautulli and Glances modules.',
        'Jellyfin, Emby and Plex browsing with resume rows, item detail and now-playing sessions.',
        'Multiple profiles, each instance with a local and an external URL, plus import and export.',
        'Material 3 Expressive theming with dynamic color, custom palettes and an optional biometric lock.',
      ]),
    ],
  ),
];
