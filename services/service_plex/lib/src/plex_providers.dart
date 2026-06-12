import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/plex_models.dart';
import 'plex_api.dart';

/// A [PlexApi] for an instance, over the shared `instanceDioProvider`.
final plexApiProvider =
    FutureProvider.family<PlexApi, Instance>((Ref ref, Instance instance) async {
      final dio = await ref.watch(instanceDioProvider(instance).future);
      final String token = switch (instance.auth) {
        InstanceAuthPlex(:final String token) => token,
        _ => '',
      };
      return PlexApi(dio, token: token);
    });

/// Libraries for an instance.
final plexLibrariesProvider =
    FutureProvider.family<List<PlexLibrary>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final PlexApi api = await ref.watch(plexApiProvider(instance).future);
      return api.getLibraries();
    });

/// Items within a library, keyed by (instance, sectionKey).
final plexItemsProvider =
    FutureProvider.family<List<PlexMetadata>, (Instance, String)>((
      Ref ref,
      (Instance, String) key,
    ) async {
      final (Instance instance, String sectionKey) = key;
      final PlexApi api = await ref.watch(plexApiProvider(instance).future);
      return api.getItems(sectionKey);
    });

/// Children of a show (seasons) or season (episodes), keyed by
/// (instance, ratingKey).
final plexChildrenProvider =
    FutureProvider.family<List<PlexMetadata>, (Instance, String)>((
      Ref ref,
      (Instance, String) key,
    ) async {
      final (Instance instance, String ratingKey) = key;
      final PlexApi api = await ref.watch(plexApiProvider(instance).future);
      return api.getChildren(ratingKey);
    });
