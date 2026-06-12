import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/qbit_detail.dart';
import 'models/qbit_torrent.dart';
import 'models/qbit_transfer_info.dart';
import 'qbittorrent_client.dart';

/// How often list-level data (torrents, global speeds) refreshes while a
/// qBittorrent screen is visible. qBit's own web UI polls at 1.5s; 3s is a
/// good mobile compromise.
const Duration qbitListPollInterval = Duration(seconds: 3);

/// How often detail-level data (properties, files, trackers) refreshes.
const Duration qbitDetailPollInterval = Duration(seconds: 10);

/// A logged-in [QbittorrentClient] for an instance.
///
/// Resolves the LAN/WAN base URL via the shared [ConnectionResolver], then
/// builds a cookie-aware client (qBittorrent can't reuse `instanceDioProvider`
/// because it needs cookie persistence rather than the static-key
/// interceptor).
///
/// Deliberately NOT autoDispose: the client holds the login session, and
/// re-logging-in on every screen visit would hammer qBit's auth (and its
/// failed-login ban counter on flaky networks).
final qbittorrentClientProvider =
    FutureProvider.family<QbittorrentClient, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final ConnectionResolver resolver =
          ref.watch(connectionResolverProvider);
      final Uri baseUrl = await resolver.resolve(instance);
      final (String username, String password) = switch (instance.auth) {
        InstanceAuthCookie(:final String username, :final String password) => (
            username,
            password,
          ),
        _ => ('', ''),
      };
      final QbittorrentClient client = QbittorrentClient.create(
        baseUrl: baseUrl,
        username: username,
        password: password,
        allowSelfSigned: instance.allowSelfSignedCerts,
      );
      ref.onDispose(client.close);
      return client;
    });

/// All torrents for an instance, sorted by most-recently-added first.
/// Polls every [qbitListPollInterval] while watched; stops when the screen
/// goes away (autoDispose).
final qbitTorrentsProvider =
    FutureProvider.autoDispose.family<List<QbitTorrent>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      ref.pollEvery(qbitListPollInterval);
      final QbittorrentClient client =
          await ref.watch(qbittorrentClientProvider(instance).future);
      final List<QbitTorrent> torrents = await client.getTorrents();
      torrents.sort((QbitTorrent a, QbitTorrent b) => b.addedOn - a.addedOn);
      return torrents;
    });

/// Global transfer stats for an instance. Polls with the list.
final qbitTransferProvider =
    FutureProvider.autoDispose.family<QbitTransferInfo, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      ref.pollEvery(qbitListPollInterval);
      final QbittorrentClient client =
          await ref.watch(qbittorrentClientProvider(instance).future);
      return client.getTransferInfo();
    });

/// Category names defined on an instance. Fetched on demand (no polling -
/// categories rarely change).
final qbitCategoriesProvider =
    FutureProvider.autoDispose.family<List<String>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final QbittorrentClient client =
          await ref.watch(qbittorrentClientProvider(instance).future);
      return client.getCategories();
    });

/// Detailed properties for one torrent, keyed by (instance, hash).
final qbitPropertiesProvider = FutureProvider.autoDispose
        .family<QbitTorrentProperties, (Instance, String)>((
      Ref ref,
      (Instance, String) key,
    ) async {
      ref.pollEvery(qbitDetailPollInterval);
      final (Instance instance, String hash) = key;
      final QbittorrentClient client =
          await ref.watch(qbittorrentClientProvider(instance).future);
      return client.getProperties(hash);
    });

/// File list for one torrent, keyed by (instance, hash).
final qbitFilesProvider =
    FutureProvider.autoDispose.family<List<QbitFile>, (Instance, String)>((
      Ref ref,
      (Instance, String) key,
    ) async {
      ref.pollEvery(qbitDetailPollInterval);
      final (Instance instance, String hash) = key;
      final QbittorrentClient client =
          await ref.watch(qbittorrentClientProvider(instance).future);
      return client.getFiles(hash);
    });

/// Tracker list for one torrent, keyed by (instance, hash).
final qbitTrackersProvider =
    FutureProvider.autoDispose.family<List<QbitTracker>, (Instance, String)>((
      Ref ref,
      (Instance, String) key,
    ) async {
      ref.pollEvery(qbitDetailPollInterval);
      final (Instance instance, String hash) = key;
      final QbittorrentClient client =
          await ref.watch(qbittorrentClientProvider(instance).future);
      return client.getTrackers(hash);
    });
