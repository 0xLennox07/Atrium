import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

/// The widget types the dashboard board can show, in default display order.
enum DashboardWidgetKind {
  downloads,
  streams,
  upcoming,
  recentlyAdded,
  recentlyDownloaded,
  requests,
  serverInfo,
  speedtestResults,
  wakeOnLan,
}

extension DashboardWidgetKindX on DashboardWidgetKind {
  String get label => switch (this) {
        DashboardWidgetKind.downloads => 'Active downloads',
        DashboardWidgetKind.streams => 'Now streaming',
        DashboardWidgetKind.upcoming => 'Upcoming releases',
        DashboardWidgetKind.recentlyAdded => 'Recently added',
        DashboardWidgetKind.recentlyDownloaded => 'Recently downloaded',
        DashboardWidgetKind.requests => 'Requests',
        DashboardWidgetKind.serverInfo => 'Server info',
        DashboardWidgetKind.speedtestResults => 'Speedtest results',
        DashboardWidgetKind.wakeOnLan => 'Wake on LAN',
      };

  IconData get icon => switch (this) {
        DashboardWidgetKind.downloads => Icons.download_rounded,
        DashboardWidgetKind.streams => Icons.play_circle_outline,
        DashboardWidgetKind.upcoming => Icons.event_outlined,
        DashboardWidgetKind.recentlyAdded => Icons.new_releases_outlined,
        DashboardWidgetKind.recentlyDownloaded => Icons.history,
        DashboardWidgetKind.requests => Icons.bookmark_added_outlined,
        DashboardWidgetKind.serverInfo => Icons.memory,
        DashboardWidgetKind.speedtestResults => Icons.speed_outlined,
        DashboardWidgetKind.wakeOnLan => Icons.power_settings_new_rounded,
      };

  /// Service kinds whose presence makes this widget "configured".
  List<ServiceKind> get serviceKinds => switch (this) {
        DashboardWidgetKind.downloads => const <ServiceKind>[
            ServiceKind.qbittorrent,
            ServiceKind.sabnzbd,
            ServiceKind.nzbget,
            ServiceKind.deluge,
            ServiceKind.transmission,
            ServiceKind.rtorrent,
          ],
        DashboardWidgetKind.streams => const <ServiceKind>[
            ServiceKind.tautulli,
            ServiceKind.jellyfin,
            ServiceKind.emby,
          ],
        DashboardWidgetKind.upcoming => const <ServiceKind>[
            ServiceKind.sonarr,
            ServiceKind.radarr
          ],
        DashboardWidgetKind.recentlyAdded => const <ServiceKind>[
            ServiceKind.sonarr,
            ServiceKind.radarr
          ],
        DashboardWidgetKind.recentlyDownloaded => const <ServiceKind>[
            ServiceKind.sonarr,
            ServiceKind.radarr
          ],
        DashboardWidgetKind.requests => const <ServiceKind>[ServiceKind.seerr],
        DashboardWidgetKind.serverInfo => const <ServiceKind>[
            ServiceKind.glances
          ],
        DashboardWidgetKind.speedtestResults => const <ServiceKind>[
            ServiceKind.speedtestTracker
          ],
        // Wake-on-LAN answers to no service. Its targets are machines on the
        // network, kept on the profile beside the instances, so there is no
        // service whose presence could stand in for being set up.
        DashboardWidgetKind.wakeOnLan => const <ServiceKind>[],
      };

  /// Whether this widget is set up by adding devices rather than a service.
  ///
  /// [serviceKinds] is empty for these, so the usual "is one of these services
  /// configured" test would call them permanently unconfigured and never show
  /// them.
  bool get isDeviceBacked => this == DashboardWidgetKind.wakeOnLan;
}
