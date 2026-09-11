import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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
  final ConnectionResolver resolver = ref.watch(connectionResolverProvider);
  final Uri baseUrl = await resolver.resolve(instance);
  final (String username, String password, String? apiKey) =
      switch (instance.auth) {
    InstanceAuthCookie(:final String username, :final String password) => (
        username,
        password,
        null,
      ),
    // qBittorrent 5.2+ stateless key auth (Authorization: Bearer).
    InstanceAuthApiKey(:final String apiKey) => ('', '', apiKey),
    _ => ('', '', null),
  };
  final Map<String, String> customHeaders = mergeHeaders(
    ref.watch(globalHeadersProvider),
    instance.customHeaders,
  );
  final QbittorrentClient client = QbittorrentClient.create(
    baseUrl: baseUrl,
    username: username,
    password: password,
    apiKey: apiKey,
    allowSelfSigned: instance.allowSelfSignedCerts,
    customHeaders: customHeaders,
  );
  ref.onDispose(client.close);
  return client;
});

enum QbitSortField {
  addedOn,
  name,
  size,
  progress,
  status,
  seeds,
  peers,
  dlSpeed,
  upSpeed,
  eta,
  ratio,
  queue,
  category,
  completedOn,
  sessionDl,
  sessionUp,
}

extension QbitSortFieldExt on QbitSortField {
  String get displayName {
    switch (this) {
      case QbitSortField.addedOn:
        return 'Added On';
      case QbitSortField.name:
        return 'Name';
      case QbitSortField.size:
        return 'Size';
      case QbitSortField.progress:
        return 'Progress';
      case QbitSortField.status:
        return 'Status';
      case QbitSortField.seeds:
        return 'Seeds';
      case QbitSortField.peers:
        return 'Peers';
      case QbitSortField.dlSpeed:
        return 'Down Speed';
      case QbitSortField.upSpeed:
        return 'Up Speed';
      case QbitSortField.eta:
        return 'ETA';
      case QbitSortField.ratio:
        return 'Ratio';
      case QbitSortField.queue:
        return 'Queue Position';
      case QbitSortField.category:
        return 'Category';
      case QbitSortField.completedOn:
        return 'Completed On';
      case QbitSortField.sessionDl:
        return 'Session Download';
      case QbitSortField.sessionUp:
        return 'Session Upload';
    }
  }
}

class QbitSortConfig {
  const QbitSortConfig({required this.field, required this.ascending});
  final QbitSortField field;
  final bool ascending;

  QbitSortConfig copyWith({QbitSortField? field, bool? ascending}) {
    return QbitSortConfig(
      field: field ?? this.field,
      ascending: ascending ?? this.ascending,
    );
  }
}

final qbitSortProvider =
    NotifierProvider.family<QbitSort, QbitSortConfig, Instance>(QbitSort.new);

/// The order a qBittorrent list is shown in, remembered across launches.
///
/// Kept per instance, because someone running two servers is likely to want
/// them ordered differently. It lives in the shared settings box; where Hive
/// was never booted (widget tests, for one) this simply behaves in memory and
/// forgets, which is the old behaviour rather than a crash.
class QbitSort extends Notifier<QbitSortConfig> {
  QbitSort(this.instance);

  final Instance instance;

  /// What a list is ordered by until someone says otherwise: newest first.
  static const QbitSortConfig fallback =
      QbitSortConfig(field: QbitSortField.addedOn, ascending: false);

  static String _keyFor(String instanceId) => 'qbit.sort.$instanceId';

  Box<String>? get _box => Hive.isBoxOpen(AtriumBoxes.settings)
      ? Hive.box<String>(AtriumBoxes.settings)
      : null;

  @override
  QbitSortConfig build() {
    final String? raw = _box?.get(_keyFor(instance.id));
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    // Stored as `<fieldName>:<asc|desc>`, which survives the enum gaining
    // values in a later version where an index would not.
    final List<String> parts = raw.split(':');
    if (parts.length != 2) {
      return fallback;
    }
    final QbitSortField? field = QbitSortField.values.asNameMap()[parts.first];
    // A field dropped from the enum between versions must not wedge the list
    // on a name nothing answers to.
    if (field == null) {
      return fallback;
    }
    return QbitSortConfig(field: field, ascending: parts[1] == 'asc');
  }

  Future<void> setField(QbitSortField field) =>
      _write(state.copyWith(field: field));

  Future<void> toggleDirection() =>
      _write(state.copyWith(ascending: !state.ascending));

  Future<void> _write(QbitSortConfig config) async {
    state = config;
    await _box?.put(
      _keyFor(instance.id),
      '${config.field.name}:${config.ascending ? 'asc' : 'desc'}',
    );
  }
}

final qbitFilterStatusProvider = StateProvider.autoDispose
    .family<String?, Instance>((ref, instance) => null);
final qbitFilterCategoryProvider = StateProvider.autoDispose
    .family<String?, Instance>((ref, instance) => null);
final qbitFilterTagProvider = StateProvider.autoDispose
    .family<String?, Instance>((ref, instance) => null);
final qbitFilterTrackerProvider = StateProvider.autoDispose
    .family<String?, Instance>((ref, instance) => null);

/// Whether a torrent belongs to the given status filter bucket.
///
/// The buckets align with the friendly-state mapping used by the torrent
/// list: every derivative state (stalled, queued, checking, forced,
/// allocating) lands in its Downloading/Seeding bucket, and Stopped covers
/// both the 4.x paused* and 5.x stopped* state names, so no torrent
/// vanishes when a filter is active. Shared by the list provider and the
/// filter drawer counts.
bool qbitStatusMatches(String status, QbitTorrent t) {
  switch (status) {
    case 'active':
      return t.state == 'downloading' ||
          t.state == 'uploading' ||
          t.state == 'forcedDL' ||
          t.state == 'forcedUP' ||
          t.state == 'metaDL';
    case 'downloading':
      return t.state == 'downloading' ||
          t.state == 'stalledDL' ||
          t.state == 'queuedDL' ||
          t.state == 'checkingDL' ||
          t.state == 'forcedDL' ||
          t.state == 'metaDL' ||
          t.state == 'allocating';
    case 'seeding':
      return t.state == 'uploading' ||
          t.state == 'stalledUP' ||
          t.state == 'queuedUP' ||
          t.state == 'checkingUP' ||
          t.state == 'forcedUP';
    case 'stopped':
      return t.state == 'pausedDL' ||
          t.state == 'pausedUP' ||
          t.state == 'stoppedDL' ||
          t.state == 'stoppedUP';
    case 'completed':
      return t.progress == 1.0;
    case 'errored':
      return t.state == 'error' || t.state == 'missingFiles';
    default:
      return true; // 'all'
  }
}

/// Splits qBittorrent's comma-separated `tags` string into trimmed,
/// non-empty tag names. qBit joins tags with ", ", so trimming matters.
List<String> qbitParseTags(String tags) => tags
    .split(',')
    .map((String s) => s.trim())
    .where((String s) => s.isNotEmpty)
    .toList();

/// Whether a torrent belongs to the given tag filter bucket.
///
/// 'untagged' matches torrents carrying no tags; any other value matches
/// torrents that carry that exact tag. Shared by the list provider and the
/// filter drawer counts.
bool qbitTagMatches(String tag, QbitTorrent t) {
  final List<String> tags = qbitParseTags(t.tags);
  if (tag == 'untagged') {
    return tags.isEmpty;
  }
  return tags.contains(tag);
}

/// Host of a tracker announce URL, or '' when there is nothing usable.
///
/// Only the host is ever surfaced. Private tracker announce URLs carry a
/// passkey in the path or query, so rendering the raw URL would put a
/// credential on screen and into any screenshot of the filter drawer.
String qbitTrackerHost(String announceUrl) {
  if (announceUrl.isEmpty) return '';
  final Uri? uri = Uri.tryParse(announceUrl.trim());
  return uri?.host.toLowerCase() ?? '';
}

/// Whether a torrent belongs to the given tracker filter bucket.
///
/// 'none' covers torrents qBittorrent reports no working tracker for; any
/// other value matches that tracker host exactly.
bool qbitTrackerMatches(String tracker, QbitTorrent t) {
  final String host = qbitTrackerHost(t.tracker);
  if (tracker == 'none') {
    return host.isEmpty;
  }
  return host == tracker;
}

/// All torrents for an instance, sorted by the active [qbitSortProvider].
/// Polls every [qbitListPollInterval] while watched; stops when the screen
/// goes away (autoDispose).
final qbitRawTorrentsProvider =
    FutureProvider.autoDispose.family<List<QbitTorrent>, Instance>((
  Ref ref,
  Instance instance,
) async {
  ref.pollEvery(qbitListPollInterval);
  final QbittorrentClient client =
      await ref.watch(qbittorrentClientProvider(instance).future);
  return client.getTorrents();
});

final qbitSearchProvider =
    StateProvider.autoDispose.family<String, Instance>((ref, instance) => '');

/// All torrents for an instance, sorted by the active [qbitSortProvider]
/// and filtered by [qbitSearchProvider].
final qbitTorrentsProvider = Provider.autoDispose
    .family<AsyncValue<List<QbitTorrent>>, Instance>((ref, instance) {
  final AsyncValue<List<QbitTorrent>> rawAsync =
      ref.watch(qbitRawTorrentsProvider(instance));
  final QbitSortConfig sortConfig = ref.watch(qbitSortProvider(instance));
  final String searchQuery =
      ref.watch(qbitSearchProvider(instance)).toLowerCase();

  final String? statusFilter = ref.watch(qbitFilterStatusProvider(instance));
  final String? categoryFilter =
      ref.watch(qbitFilterCategoryProvider(instance));
  final String? tagFilter = ref.watch(qbitFilterTagProvider(instance));
  final String? trackerFilter = ref.watch(qbitFilterTrackerProvider(instance));

  return rawAsync.whenData((List<QbitTorrent> raw) {
    final List<QbitTorrent> torrents = List<QbitTorrent>.of(raw);

    if (searchQuery.isNotEmpty) {
      torrents.retainWhere(
        (QbitTorrent t) => t.name.toLowerCase().contains(searchQuery),
      );
    }

    if (statusFilter != null && statusFilter != 'all') {
      torrents.retainWhere(
        (QbitTorrent t) => qbitStatusMatches(statusFilter, t),
      );
    }

    if (categoryFilter != null) {
      if (categoryFilter == 'uncategorized') {
        torrents.retainWhere((QbitTorrent t) => t.category.isEmpty);
      } else {
        torrents.retainWhere((QbitTorrent t) => t.category == categoryFilter);
      }
    }

    if (tagFilter != null) {
      torrents.retainWhere((QbitTorrent t) => qbitTagMatches(tagFilter, t));
    }

    if (trackerFilter != null) {
      torrents.retainWhere(
        (QbitTorrent t) => qbitTrackerMatches(trackerFilter, t),
      );
    }

    return sortQbitTorrents(torrents, sortConfig);
  });
});

/// Unqueued torrents report priority <= 0 (qBittorrent uses 1-based queue
/// priorities when queueing is enabled; <= 0 means not queued or queueing
/// disabled). We push them to the end of a queue sort so that active queue
/// positions (1, 2, 3...) appear first.
int qbitQueueRank(QbitTorrent t) => t.priority <= 0 ? 1 << 30 : t.priority;

/// Sorts a qBittorrent torrent list according to [sortConfig].
/// Extracted from provider for direct unit testing.
List<QbitTorrent> sortQbitTorrents(
  List<QbitTorrent> torrents,
  QbitSortConfig sortConfig,
) {
  final List<QbitTorrent> out = List<QbitTorrent>.of(torrents);
  out.sort((QbitTorrent a, QbitTorrent b) {
    int cmp = 0;
    switch (sortConfig.field) {
      case QbitSortField.addedOn:
        cmp = a.addedOn.compareTo(b.addedOn);
      case QbitSortField.name:
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case QbitSortField.size:
        cmp = a.size.compareTo(b.size);
      case QbitSortField.progress:
        cmp = a.progress.compareTo(b.progress);
      case QbitSortField.status:
        cmp = a.state.compareTo(b.state);
      case QbitSortField.seeds:
        cmp = a.numSeeds.compareTo(b.numSeeds);
      case QbitSortField.peers:
        cmp = a.numLeechs.compareTo(b.numLeechs);
      case QbitSortField.dlSpeed:
        cmp = a.dlspeed.compareTo(b.dlspeed);
      case QbitSortField.upSpeed:
        cmp = a.upspeed.compareTo(b.upspeed);
      case QbitSortField.eta:
        cmp = a.eta.compareTo(b.eta);
      case QbitSortField.ratio:
        cmp = a.ratio.compareTo(b.ratio);
      case QbitSortField.queue:
        cmp = qbitQueueRank(a).compareTo(qbitQueueRank(b));
      case QbitSortField.category:
        cmp = a.category.compareTo(b.category);
      case QbitSortField.completedOn:
        cmp = a.completionOn.compareTo(b.completionOn);
      case QbitSortField.sessionDl:
        cmp = a.downloadedSession.compareTo(b.downloadedSession);
      case QbitSortField.sessionUp:
        cmp = a.uploadedSession.compareTo(b.uploadedSession);
    }
    if (cmp == 0) {
      cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    return sortConfig.ascending ? cmp : -cmp;
  });
  return out;
}

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

/// Categories on an instance mapped to the save path each defines, empty
/// where a category leaves it to the server default. Fetched on demand (no
/// polling - categories rarely change).
final qbitCategoryPathsProvider =
    FutureProvider.autoDispose.family<Map<String, String>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final QbittorrentClient client =
      await ref.watch(qbittorrentClientProvider(instance).future);
  return client.getCategories();
});

/// Category names defined on an instance (sorted).
///
/// Derived from [qbitCategoryPathsProvider] rather than fetching again, so the
/// callers that only want names cost no extra request.
final qbitCategoriesProvider =
    FutureProvider.autoDispose.family<List<String>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final Map<String, String> paths =
      await ref.watch(qbitCategoryPathsProvider(instance).future);
  return paths.keys.toList()..sort();
});

/// Tag names defined on an instance. Fetched on demand for the tag picker.
final qbitTagsProvider =
    FutureProvider.autoDispose.family<List<String>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final QbittorrentClient client =
      await ref.watch(qbittorrentClientProvider(instance).future);
  return client.getTags();
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

/// Holds the set of currently selected torrent hashes for multi-select actions.
final qbitSelectionProvider =
    StateProvider.autoDispose.family<Set<String>, Instance>((
  Ref ref,
  Instance instance,
) {
  return <String>{};
});

/// Peers list for one torrent, keyed by (instance, hash).
final qbitPeersProvider =
    FutureProvider.autoDispose.family<List<QbitPeer>, (Instance, String)>((
  Ref ref,
  (Instance, String) key,
) async {
  ref.pollEvery(qbitDetailPollInterval);
  final (Instance instance, String hash) = key;
  final QbittorrentClient client =
      await ref.watch(qbittorrentClientProvider(instance).future);
  return client.getPeers(hash);
});

/// Active bottom tab index for qBittorrent home (0: Home, 1: Settings).
final qbitActiveTabBarIndexProvider =
    StateProvider.family<int, Instance>((Ref ref, Instance instance) => 0);

/// Bottom nav bar visibility for qBittorrent home.
final qbitBottomNavVisibleProvider =
    StateProvider.family<bool, Instance>((Ref ref, Instance instance) => true);

/// Scroll-to-top trigger for qBittorrent tabs.
final qbitHomeScrollToTopProvider = StateProvider.family<int, (Instance, int)>(
  (Ref ref, (Instance, int) key) => 0,
);

/// qBittorrent application version provider.
final qbitAppVersionProvider =
    FutureProvider.family<String, Instance>((Ref ref, Instance instance) async {
  final QbittorrentClient client =
      await ref.watch(qbittorrentClientProvider(instance).future);
  return client.getAppVersion();
});

/// qBittorrent web API version provider.
final qbitApiVersionProvider =
    FutureProvider.family<String, Instance>((Ref ref, Instance instance) async {
  final QbittorrentClient client =
      await ref.watch(qbittorrentClientProvider(instance).future);
  return client.getApiVersion();
});

/// qBittorrent global preferences provider.
final qbitPreferencesProvider =
    FutureProvider.family<Map<String, dynamic>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final QbittorrentClient client =
      await ref.watch(qbittorrentClientProvider(instance).future);
  return client.getPreferences();
});

/// qBittorrent alternative speed limits enabled provider.
final qbitAltSpeedModeProvider =
    FutureProvider.family<bool, Instance>((Ref ref, Instance instance) async {
  final QbittorrentClient client =
      await ref.watch(qbittorrentClientProvider(instance).future);
  final int mode = await client.getSpeedLimitsMode();
  return mode == 1;
});

/// qBittorrent available network interfaces provider.
final qbitNetworkInterfacesProvider =
    FutureProvider.family<List<Map<String, String>>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final QbittorrentClient client =
      await ref.watch(qbittorrentClientProvider(instance).future);
  return client.getNetworkInterfaces();
});

/// qBittorrent available network interface addresses provider.
final qbitNetworkInterfaceAddressesProvider =
    FutureProvider.family<List<String>, (Instance, String?)>((
  Ref ref,
  (Instance, String?) arg,
) async {
  final (Instance instance, String? iface) = arg;
  final QbittorrentClient client =
      await ref.watch(qbittorrentClientProvider(instance).future);
  return client.getNetworkInterfaceAddresses(iface: iface);
});
