/// The kinds of self-hosted services Atrium can drive.
///
/// New services append to the end of this list. JSON serialization uses the
/// enum name (`sonarr`, `radarr`, ...) so reordering is safe, but renaming is
/// not - write a migration if you rename.
enum ServiceKind {
  sonarr,
  radarr,
  prowlarr,
  bazarr,
  overseerr,
  tautulli,
  jellyfin,
  emby,
  plex,
  qbittorrent,
  sabnzbd,
  glances,
}

/// Static metadata about a [ServiceKind] - display name, default port, the
/// auth style the service uses, and the broad role it plays in the stack.
///
/// Lives next to the enum so that adding a new service is a one-file change.
extension ServiceKindX on ServiceKind {
  /// Capitalized human label shown in lists, settings, etc.
  String get displayName => switch (this) {
        ServiceKind.sonarr => 'Sonarr',
        ServiceKind.radarr => 'Radarr',
        ServiceKind.prowlarr => 'Prowlarr',
        ServiceKind.bazarr => 'Bazarr',
        ServiceKind.overseerr => 'Overseerr',
        ServiceKind.tautulli => 'Tautulli',
        ServiceKind.jellyfin => 'Jellyfin',
        ServiceKind.emby => 'Emby',
        ServiceKind.plex => 'Plex',
        ServiceKind.qbittorrent => 'qBittorrent',
        ServiceKind.sabnzbd => 'SABnzbd',
        ServiceKind.glances => 'Glances',
      };

  /// One-line role description.
  String get tagline => switch (this) {
        ServiceKind.sonarr => 'TV shows',
        ServiceKind.radarr => 'Movies',
        ServiceKind.prowlarr => 'Indexers',
        ServiceKind.bazarr => 'Subtitles',
        ServiceKind.overseerr => 'Requests',
        ServiceKind.tautulli => 'Plex stats',
        ServiceKind.jellyfin => 'Media server',
        ServiceKind.emby => 'Media server',
        ServiceKind.plex => 'Media server',
        ServiceKind.qbittorrent => 'Torrent client',
        ServiceKind.sabnzbd => 'Usenet client',
        ServiceKind.glances => 'System monitor',
      };

  /// Vendor-default port. Used as a hint when the user is entering a URL
  /// without one.
  int get defaultPort => switch (this) {
        ServiceKind.sonarr => 8989,
        ServiceKind.radarr => 7878,
        ServiceKind.prowlarr => 9696,
        ServiceKind.bazarr => 6767,
        ServiceKind.overseerr => 5055,
        ServiceKind.tautulli => 8181,
        ServiceKind.jellyfin => 8096,
        ServiceKind.emby => 8096,
        ServiceKind.plex => 32400,
        ServiceKind.qbittorrent => 8080,
        ServiceKind.sabnzbd => 8080,
        ServiceKind.glances => 61208,
      };

  /// What auth flow the service uses by default. Some services (Jellyfin) can
  /// be configured either way; this is the typical path.
  AuthStyle get authStyle => switch (this) {
        ServiceKind.sonarr ||
        ServiceKind.radarr ||
        ServiceKind.prowlarr ||
        ServiceKind.bazarr ||
        ServiceKind.overseerr ||
        ServiceKind.tautulli ||
        ServiceKind.sabnzbd =>
          AuthStyle.apiKey,
        ServiceKind.jellyfin || ServiceKind.emby => AuthStyle.userPass,
        ServiceKind.plex => AuthStyle.plexToken,
        ServiceKind.qbittorrent => AuthStyle.cookieLogin,
        ServiceKind.glances => AuthStyle.none,
      };

  /// Broad role of the service in the stack - used for grouping in the
  /// dashboard.
  ServiceRole get role => switch (this) {
        ServiceKind.sonarr ||
        ServiceKind.radarr ||
        ServiceKind.prowlarr ||
        ServiceKind.bazarr =>
          ServiceRole.automation,
        ServiceKind.overseerr => ServiceRole.requests,
        ServiceKind.tautulli => ServiceRole.analytics,
        ServiceKind.jellyfin ||
        ServiceKind.emby ||
        ServiceKind.plex =>
          ServiceRole.mediaServer,
        ServiceKind.qbittorrent ||
        ServiceKind.sabnzbd =>
          ServiceRole.downloader,
        ServiceKind.glances => ServiceRole.analytics,
      };
}

/// The auth flow a service uses to authenticate a request.
enum AuthStyle {
  /// Static API key passed in a header or query param.
  apiKey,

  /// Username + password login that returns a session token.
  userPass,

  /// Plex `X-Plex-Token`, obtained from plex.tv login or pinned in the
  /// server's `Preferences.xml`.
  plexToken,

  /// Username + password login that returns a cookie carried on subsequent
  /// requests (qBittorrent).
  cookieLogin,

  /// No authentication required.
  none,
}

/// Coarse grouping for the dashboard.
enum ServiceRole {
  automation,
  requests,
  analytics,
  mediaServer,
  downloader,
}
