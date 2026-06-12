import 'package:core_models/core_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_resolver.dart';
import 'dio_factory.dart';

/// The app's [ConnectionResolver]. Overridden in `main()` with a started
/// instance (its connectivity subscription must be live before first use):
///
/// ```dart
/// final resolver = ConnectionResolver(connectivity: Connectivity());
/// await resolver.start();
/// ProviderScope(overrides: [
///   connectionResolverProvider.overrideWithValue(resolver),
/// ], child: ...);
/// ```
final Provider<ConnectionResolver> connectionResolverProvider =
    Provider<ConnectionResolver>((Ref ref) {
  throw UnimplementedError(
    'connectionResolverProvider must be overridden in main()',
  );
});

/// Builds [Dio] clients for instances, using the resolver above.
final Provider<DioFactory> dioFactoryProvider = Provider<DioFactory>((Ref ref) {
  return DioFactory(resolver: ref.watch(connectionResolverProvider));
});

/// A [Dio] bound to a specific [Instance], with the right base URL and auth
/// wired in. Cached per instance value; closed automatically when no longer
/// watched.
final instanceDioProvider =
    FutureProvider.family<Dio, Instance>((Ref ref, Instance instance) async {
  final Dio dio = await ref.watch(dioFactoryProvider).create(instance);
  ref.onDispose(() => dio.close(force: true));
  return dio;
});
