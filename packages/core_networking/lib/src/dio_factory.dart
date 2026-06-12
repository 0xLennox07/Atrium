import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'auth_interceptor.dart';
import 'connection_resolver.dart';

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
  DioFactory({required ConnectionResolver resolver}) : _resolver = resolver;

  final ConnectionResolver _resolver;

  Future<Dio> create(Instance instance) async {
    final Uri resolvedUrl = await _resolver.resolve(instance);
    final String baseUrlStr = resolvedUrl.toString();
    final String baseUrl = baseUrlStr.endsWith('/') ? baseUrlStr : '$baseUrlStr/';

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

    if (instance.allowSelfSignedCerts) {
      // The user has explicitly chosen to skip cert validation for this
      // instance - common with private IPs on self-signed certs.
      final IOHttpClientAdapter adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      adapter.createHttpClient = () => HttpClient()
        ..badCertificateCallback = (X509Certificate _, String __, int ___) =>
            true;
    }

    dio.interceptors.add(
      AuthInterceptor(kind: instance.kind, auth: instance.auth),
    );

    return dio;
  }
}
