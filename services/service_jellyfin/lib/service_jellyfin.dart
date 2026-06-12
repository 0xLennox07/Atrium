/// Public surface of `service_jellyfin`.
///
/// Jellyfin REST client (token-session auth via AuthenticateByName), models,
/// Riverpod providers, and the per-instance [JellyfinHome] UI (library chips +
/// poster grid with watched-progress overlays). First media-server module;
/// browse only - playback is a later, larger piece.
library;

export 'src/jellyfin_client.dart';
export 'src/jellyfin_home.dart';
export 'src/jellyfin_providers.dart';
export 'src/jellyfin_search.dart';
export 'src/models/jellyfin_auth.dart';
export 'src/models/jellyfin_item.dart';
export 'src/models/jellyfin_view.dart';
