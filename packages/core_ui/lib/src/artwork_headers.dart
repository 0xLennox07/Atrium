import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';

/// The headers an artwork request needs, worked out from its URL.
///
/// Artwork is the one thing in the app that does not go through Dio. Posters,
/// banners and backdrops are fetched by `CachedNetworkImage` on its own HTTP
/// client, which sends nothing but what it is handed, so the user-configured
/// headers the Dio factory installs never reached them. Behind a forward-auth
/// proxy (Authelia, Cloudflare Access, an nginx `auth_request`) that means the
/// proxy answered every image request instead of the service and every poster
/// came up blank, silently, while the rest of the app worked.
///
/// This is a static holder rather than a provider on purpose. Artwork is
/// requested from places that have no `ref` to read: `PaletteGenerator` calls
/// in plain `State` classes, `DecorationImage`, helper functions several
/// layers down a service module. Threading a ref to all of them would be a
/// far larger change than the bug warrants. It is written from exactly one
/// place, the profile listener in `app.dart`, alongside the existing
/// `globalHeadersProvider` sync, so there is one writer and many readers.
abstract final class ArtworkHeaders {
  /// Normalised instance base URL to the headers requests under it need.
  ///
  /// Both the local and external URL of an instance map to the same headers,
  /// since either may be the one the artwork URL was built from.
  static Map<String, Map<String, String>> _byBase =
      const <String, Map<String, String>>{};

  /// Rebuilds the lookup for [instances], merging each instance's headers
  /// over [global] exactly as the Dio factory does.
  static void update({
    required Iterable<Instance> instances,
    required Map<String, String> global,
  }) {
    final Map<String, Map<String, String>> next =
        <String, Map<String, String>>{};
    for (final Instance instance in instances) {
      final Map<String, String> headers =
          mergeHeaders(global, instance.customHeaders);
      if (headers.isEmpty) {
        continue;
      }
      for (final String base in <String>[
        instance.localUrl,
        instance.externalUrl,
      ]) {
        final String key = _normalise(base);
        if (key.isNotEmpty) {
          next[key] = headers;
        }
      }
    }
    _byBase = next;
  }

  /// Headers for [url], or null when it belongs to no configured instance.
  ///
  /// Null rather than an empty map because that is what `CachedNetworkImage`
  /// and `Image.network` already treat as "send nothing", and because artwork
  /// for something not in the library yet points at TMDB or Fanart.tv, where
  /// the user's proxy credentials have no business being sent.
  static Map<String, String>? forUrl(String? url) {
    if (url == null || url.isEmpty || _byBase.isEmpty) {
      return null;
    }
    final String target = _normalise(url);

    // Longest match wins, so an instance served from a sub-path is preferred
    // over another one sitting at the root of the same host.
    String? best;
    for (final String base in _byBase.keys) {
      if (target == base || target.startsWith('$base/')) {
        if (best == null || base.length > best.length) {
          best = base;
        }
      }
    }
    return best == null ? null : _byBase[best];
  }

  /// Drops every mapping. Only for tests, so one does not leak into the next.
  static void reset() => _byBase = const <String, Map<String, String>>{};

  /// Lowercased and stripped of trailing slashes so the comparison survives
  /// the ways a base URL and the URL built from it can differ in spelling.
  /// Case folding the path too is deliberate: hosts are case-insensitive, and
  /// treating a prefix loosely here can only widen the match to another URL on
  /// the user's own server.
  static String _normalise(String raw) {
    String value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value.toLowerCase();
  }
}
