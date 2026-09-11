import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The profile's headers have to reach every client, not just the ones the
/// screens use.
///
/// Reported by a user running Authelia: the app worked, but "Test connection"
/// answered "Reachable, but the check did not pass" and the dashboard showed
/// warnings. The headers were configured globally, which is the natural place
/// when one proxy fronts everything, and [DioFactory.create] used to take them
/// as an optional argument that five of its six callers never passed. Holding
/// them on the factory is what makes forgetting impossible, so these pin that
/// down rather than the old per-call behaviour.
void main() {
  Instance instance({Map<String, String> headers = const <String, String>{}}) =>
      Instance(
        id: 'sonarr',
        name: 'Sonarr',
        kind: ServiceKind.sonarr,
        localUrl: 'http://sonarr.example.test',
        externalUrl: '',
        urlMode: UrlMode.auto,
        auth: const InstanceAuth.apiKey(apiKey: 'k'),
        customHeaders: headers,
      );

  ConnectionResolver resolverFor(Dio Function() probe) => ConnectionResolver(
        connectivity: Connectivity(),
        probeClientFactory: (bool _) => probe(),
      );

  DioFactory factoryWith(
    Map<String, String> global, {
    HttpClientAdapter? adapter,
  }) =>
      DioFactory(
        resolver: resolverFor(
          () => Dio()..httpClientAdapter = adapter ?? _OkAdapter(),
        ),
        globalHeaders: global,
      );

  test('a client carries the profile headers without being asked', () async {
    final Dio dio = await factoryWith(
      const <String, String>{'Authorization': 'Basic dGVzdDp0ZXN0'},
    ).create(instance());

    expect(dio.options.headers['Authorization'], 'Basic dGVzdDp0ZXN0');
  });

  test('an instance header still wins over the profile one', () async {
    final Dio dio = await factoryWith(
      const <String, String>{'X-Which': 'global'},
    ).create(instance(headers: const <String, String>{'X-Which': 'instance'}));

    expect(dio.options.headers['X-Which'], 'instance');
  });

  test('profile headers the instance does not mention still ride along',
      () async {
    final Dio dio = await factoryWith(
      const <String, String>{'CF-Access-Client-Id': 'id'},
    ).create(instance(headers: const <String, String>{'X-Other': 'x'}));

    expect(dio.options.headers['CF-Access-Client-Id'], 'id');
    expect(dio.options.headers['X-Other'], 'x');
  });

  test('the health probe sends them too', () async {
    // The probe builds its own client off the factory. This is the call site
    // the user actually hit: the dashboard dot and "Test connection" both go
    // through here, and both used to drop the profile's headers.
    final _RecordingAdapter recorder = _RecordingAdapter();
    final Dio dio = await factoryWith(
      const <String, String>{'Authorization': 'Basic seen'},
    ).create(instance());
    dio.httpClientAdapter = recorder;

    await dio.get<dynamic>(
      'api/v3/system/status',
      options: Options(validateStatus: (_) => true),
    );

    expect(recorder.seen['Authorization'], 'Basic seen');
  });
}

/// Answers any probe so the resolver settles on the local URL.
class _OkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString('{}', 200);

  @override
  void close({bool force = false}) {}
}

class _RecordingAdapter implements HttpClientAdapter {
  Map<String, dynamic> seen = <String, dynamic>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen = options.headers;
    return ResponseBody.fromString('{}', 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
