import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

/// Icon + brand-ish accent color for each [ServiceKind].
///
/// These are Material icons (no bundled brand logos) so the F-Droid build
/// carries no third-party trademarked assets. Colors are approximations of
/// each project's accent, used only as a tint behind the icon.
abstract final class ServiceVisuals {
  static IconData icon(ServiceKind kind) => switch (kind) {
        ServiceKind.sonarr => Icons.live_tv_outlined,
        ServiceKind.radarr => Icons.movie_outlined,
        ServiceKind.prowlarr => Icons.travel_explore_outlined,
        ServiceKind.bazarr => Icons.subtitles_outlined,
        ServiceKind.overseerr => Icons.playlist_add_check_outlined,
        ServiceKind.tautulli => Icons.insights_outlined,
        ServiceKind.jellyfin => Icons.theaters_outlined,
        ServiceKind.emby => Icons.ondemand_video_outlined,
        ServiceKind.plex => Icons.play_circle_outline,
        ServiceKind.qbittorrent => Icons.cloud_download_outlined,
        ServiceKind.sabnzbd => Icons.downloading_outlined,
        ServiceKind.glances => Icons.memory_outlined,
      };

  static Color accent(ServiceKind kind) => switch (kind) {
        ServiceKind.sonarr => const Color(0xFF3FAFE4),
        ServiceKind.radarr => const Color(0xFFFFC230),
        ServiceKind.prowlarr => const Color(0xFFE56F2C),
        ServiceKind.bazarr => const Color(0xFF6C8EBF),
        ServiceKind.overseerr => const Color(0xFF6366F1),
        ServiceKind.tautulli => const Color(0xFFDBA81C),
        ServiceKind.jellyfin => const Color(0xFF00A4DC),
        ServiceKind.emby => const Color(0xFF52B54B),
        ServiceKind.plex => const Color(0xFFE5A00D),
        ServiceKind.qbittorrent => const Color(0xFF2F67BA),
        ServiceKind.sabnzbd => const Color(0xFFFFD24D),
        ServiceKind.glances => const Color(0xFF10B981),
      };

  /// Human label for a [ServiceRole] section header.
  static String roleLabel(ServiceRole role) => switch (role) {
        ServiceRole.automation => 'Automation',
        ServiceRole.requests => 'Requests',
        ServiceRole.analytics => 'Analytics',
        ServiceRole.mediaServer => 'Media servers',
        ServiceRole.downloader => 'Download clients',
      };
}
