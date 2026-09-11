import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'auth_interceptor.dart';
import 'connection_resolver.dart';
import 'headers.dart';
import 'rate_limit_interceptor.dart';

/// Builds [Dio] clients pre-configured for an [Instance].
///
/// Each service module asks the factory for a Dio bound to a particular
/// instance; the factory wires up:
///
/// * the LAN/WAN base URL chosen by [ConnectionResolver],
/// * sensible timeouts (10s connect, 30s receive),
/// * the [AuthInterceptor] for the service's auth style,
/// * a self-signed-cert override if the user explicitly opted in.
///
/// The returned client is owned by the caller - close it when done with it.
class DioFactory {
  DioFactory({
    required ConnectionResolver resolver,
    Map<String, String> globalHeaders = const <String, String>{},
  })  : _resolver = resolver,
        _globalHeaders = globalHeaders;

  final ConnectionResolver _resolver;

  /// The active profile's headers, held here rather than taken per call.
  ///
  /// It used to be an optional argument to [create] defaulting to none, which
  /// read as harmless and was not: five of the six call sites never passed it,
  /// so the health probe, the connection tester and the Beszel, dashdot and
  /// Glances clients all silently dropped the profile's headers while the rest
  /// of the app sent them. Anyone behind a forward-auth proxy who configured
  /// headers globally, which is the obvious place to put them when the proxy
  /// fronts everything, got a working app whose "Test connection" failed.
  /// Holding them on the factory means a caller cannot forget.
  final Map<String, String> _globalHeaders;

  Future<Dio> create(Instance instance) async {
    final Uri resolvedUrl = await _resolver.resolve(instance);
    final String baseUrlStr = resolvedUrl.toString();
    final String baseUrl =
        baseUrlStr.endsWith('/') ? baseUrlStr : '$baseUrlStr/';

    final Dio dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        // Non-2xx responses surface as DioExceptions; service modules map
        // them to typed errors via NetworkException.fromDio in one place.
      ),
    );

    // User-configured headers: profile-wide first, instance overrides on key
    // collision. The AuthInterceptor below still wins last for its own keys
    // because it runs per-request.
    dio.options.headers
        .addAll(mergeHeaders(_globalHeaders, instance.customHeaders));

    if (instance.allowSelfSignedCerts) {
      // The user has explicitly chosen to skip cert validation for this
      // instance - common with private IPs on self-signed certs.
      final IOHttpClientAdapter adapter =
          dio.httpClientAdapter as IOHttpClientAdapter;
      adapter.createHttpClient = () => HttpClient()
        ..badCertificateCallback =
            (X509Certificate _, String __, int ___) => true;
    }

    dio.interceptors.add(
      AuthInterceptor(kind: instance.kind, auth: instance.auth),
    );

    // After auth, so a replayed request is re-signed rather than reusing a
    // header that may have expired while we waited out the rate limit.
    dio.interceptors.add(RateLimitInterceptor(dio));

    return dio;
  }
}
