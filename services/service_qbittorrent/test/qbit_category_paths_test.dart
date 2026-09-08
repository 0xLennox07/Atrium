import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_qbittorrent/service_qbittorrent.dart';

/// Answers the categories endpoint with a fixed body.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        body,
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

QbittorrentClient _clientFor(String body) => QbittorrentClient(
      dio: Dio(BaseOptions(baseUrl: 'https://qbit.example.test/'))
        ..httpClientAdapter = _CannedAdapter(body),
      cookies: CookieJar(),
      username: '',
      password: '',
      apiKey: 'k',
    );

/// The save path a category defines has to survive the trip.
///
/// Issue #150: the add sheet left the save path blank, so the whole path had
/// to be typed for every torrent. Prefilling it needs the per-category path,
/// which this endpoint carries and the client used to throw away.
void main() {
  test('a category keeps the save path it defines', () async {
    // Shape taken from a live qBittorrent 5.1 server.
    final String body = jsonEncode(<String, dynamic>{
      'movies': <String, dynamic>{
        'name': 'movies',
        'savePath': '/data/torrents/movies',
        'download_path': null,
      },
    });

    final Map<String, String> paths = await _clientFor(body).getCategories();

    expect(paths, <String, String>{'movies': '/data/torrents/movies'});
  });

  test('a category defining no path comes back empty, not missing', () async {
    // Real servers have plenty of these. Empty means "use the global default",
    // and the sheet relies on being able to tell that apart from a category it
    // has never heard of.
    final String body = jsonEncode(<String, dynamic>{
      'games': <String, dynamic>{'name': 'games', 'savePath': ''},
    });

    final Map<String, String> paths = await _clientFor(body).getCategories();

    expect(paths.containsKey('games'), isTrue);
    expect(paths['games'], isEmpty);
  });

  test('the save_path spelling is accepted too', () async {
    // qBittorrent says savePath here and save_path in app/preferences. Reading
    // only one spelling would silently yield an empty path if that ever moved.
    final String body = jsonEncode(<String, dynamic>{
      'books': <String, dynamic>{'name': 'books', 'save_path': '/data/books'},
    });

    final Map<String, String> paths = await _clientFor(body).getCategories();

    expect(paths['books'], '/data/books');
  });

  test('a category that is not a map does not bring the list down', () async {
    // Older servers answered with a bare name list. One odd entry must not
    // cost the rest of the categories.
    final String body = jsonEncode(<String, dynamic>{
      'odd': 'not-an-object',
      'movies': <String, dynamic>{'name': 'movies', 'savePath': '/data/m'},
    });

    final Map<String, String> paths = await _clientFor(body).getCategories();

    expect(paths['odd'], isEmpty);
    expect(paths['movies'], '/data/m');
  });

  test('no categories at all is empty rather than an error', () async {
    final Map<String, String> paths = await _clientFor('{}').getCategories();

    expect(paths, isEmpty);
  });
}
