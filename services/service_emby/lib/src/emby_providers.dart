import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'emby_client.dart';
import 'models/emby_item.dart';
import 'models/emby_view.dart';

/// A logged-in [EmbyClient] for an instance. Resolves the base URL via the
/// shared [ConnectionResolver] then builds its own token-aware Dio.
final FutureProviderFamily<EmbyClient, Instance> embyClientProvider =
    FutureProvider.family<EmbyClient, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final ConnectionResolver resolver =
          ref.watch(connectionResolverProvider);
      final Uri baseUrl = await resolver.resolve(instance);
      final (String username, String password) = switch (instance.auth) {
        InstanceAuthUserPass(:final String username, :final String password) =>
          (username, password),
        _ => ('', ''),
      };
      final EmbyClient client = EmbyClient.create(
        baseUrl: baseUrl,
        username: username,
        password: password,
        deviceId: instance.id,
        allowSelfSigned: instance.allowSelfSignedCerts,
      );
      ref.onDispose(client.close);
      return client;
    });

/// Libraries for an instance.
final FutureProviderFamily<List<EmbyView>, Instance> embyViewsProvider =
    FutureProvider.family<List<EmbyView>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final EmbyClient client =
          await ref.watch(embyClientProvider(instance).future);
      return client.getViews();
    });

/// Items within a library, keyed by (instance, libraryId).
final FutureProviderFamily<List<EmbyItem>, (Instance, String)>
    embyItemsProvider =
    FutureProvider.family<List<EmbyItem>, (Instance, String)>((
      Ref ref,
      (Instance, String) key,
    ) async {
      final (Instance instance, String libraryId) = key;
      final EmbyClient client =
          await ref.watch(embyClientProvider(instance).future);
      return client.getItems(libraryId);
    });

final FutureProviderFamily<List<EmbyItem>, Instance>
    embyResumeItemsProvider =
    FutureProvider.family<List<EmbyItem>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final EmbyClient client =
          await ref.watch(embyClientProvider(instance).future);
      return client.getResumeItems();
    });

final FutureProviderFamily<List<EmbyItem>, Instance>
    embyNextUpProvider =
    FutureProvider.family<List<EmbyItem>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final EmbyClient client =
          await ref.watch(embyClientProvider(instance).future);
      return client.getNextUp();
    });

final FutureProviderFamily<List<EmbyItem>, Instance>
    embyLatestItemsProvider =
    FutureProvider.family<List<EmbyItem>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final EmbyClient client =
          await ref.watch(embyClientProvider(instance).future);
      return client.getLatestItems();
    });

final FutureProviderFamily<List<EmbyItem>, Instance>
    embyFavoritesProvider =
    FutureProvider.family<List<EmbyItem>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final EmbyClient client =
          await ref.watch(embyClientProvider(instance).future);
      return client.getFavorites();
    });

final FutureProviderFamily<EmbyItem, (Instance, String)>
    embyItemDetailsProvider =
    FutureProvider.family<EmbyItem, (Instance, String)>((
      Ref ref,
      (Instance, String) key,
    ) async {
      final (Instance instance, String itemId) = key;
      final EmbyClient client =
          await ref.watch(embyClientProvider(instance).future);
      return client.getItemDetails(itemId);
    });

final FutureProviderFamily<List<EmbyItem>, (Instance, String)>
    embySeasonsProvider =
    FutureProvider.family<List<EmbyItem>, (Instance, String)>((
      Ref ref,
      (Instance, String) key,
    ) async {
      final (Instance instance, String seriesId) = key;
      final EmbyClient client =
          await ref.watch(embyClientProvider(instance).future);
      return client.getSeasons(seriesId);
    });

final FutureProviderFamily<List<EmbyItem>, (Instance, String, String)>
    embyEpisodesProvider =
    FutureProvider.family<List<EmbyItem>, (Instance, String, String)>((
      Ref ref,
      (Instance, String, String) key,
    ) async {
      final (Instance instance, String seriesId, String seasonId) = key;
      final EmbyClient client =
          await ref.watch(embyClientProvider(instance).future);
      return client.getEpisodes(seriesId, seasonId);
    });
