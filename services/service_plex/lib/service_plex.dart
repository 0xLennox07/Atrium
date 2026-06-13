/// Public surface of `service_plex`.
///
/// Plex Media Server client (X-Plex-Token + JSON over the shared Dio), models,
/// Riverpod providers, and the per-instance [PlexHome] UI: a hub view
/// (Continue Watching + Recently Added), library poster grids, item detail
/// with a watched toggle, and global search. Browse/manage only - playback is
/// handled by the official Plex app.
library;

export 'src/models/plex_models.dart';
export 'src/plex_api.dart';
export 'src/plex_home.dart';
export 'src/plex_item_detail.dart';
export 'src/plex_providers.dart';
export 'src/plex_search.dart';
