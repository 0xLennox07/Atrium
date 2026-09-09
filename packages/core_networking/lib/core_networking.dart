/// Public surface of `core_networking`.
///
/// Dio factory + dual-URL [ConnectionResolver] that picks between the LAN
/// URL and WAN URL of an instance based on a short probe (with caching per
/// network fingerprint) plus per-instance manual overrides, and the Riverpod
/// providers that expose them.
library;

export 'src/auth_interceptor.dart';
export 'src/connection_resolver.dart';
export 'src/dio_factory.dart';
export 'src/headers.dart';
export 'src/network_exception.dart';
export 'src/network_fingerprint.dart';
export 'src/networking_providers.dart';
export 'src/polling.dart';
export 'src/rate_limit_interceptor.dart';
export 'src/service_auth_headers.dart';
export 'src/service_health.dart';
export 'src/wol.dart';
