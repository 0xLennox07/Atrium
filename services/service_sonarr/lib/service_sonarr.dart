/// Public surface of `service_sonarr`.
///
/// Sonarr v3 API client, models, Riverpod providers, and the per-instance
/// [SonarrHome] UI. This module is the canonical template the other *arr
/// services (Radarr, Prowlarr, Bazarr, Lidarr, Readarr) follow.
library;

export 'src/add_series_screen.dart';
export 'src/models/sonarr_add_models.dart';
export 'src/models/sonarr_calendar.dart';
export 'src/models/sonarr_episode.dart';
export 'src/models/sonarr_queue.dart';
export 'src/models/sonarr_release.dart';
export 'src/models/sonarr_series.dart';
export 'src/series_detail_screen.dart';
export 'src/sonarr_api.dart';
export 'src/sonarr_home.dart';
export 'src/sonarr_providers.dart';
export 'src/sonarr_release_search_screen.dart';
