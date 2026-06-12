import 'tautulli_json.dart';

/// One page of watch history from `cmd=get_history`.
///
/// Plain hand-written classes (no codegen): display-only data whose field
/// types drift across Tautulli versions, so everything parses tolerantly.
class TautulliHistoryPage {
  const TautulliHistoryPage({
    required this.recordsTotal,
    required this.records,
  });

  factory TautulliHistoryPage.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rows = (json['data'] as List<dynamic>?) ?? <dynamic>[];
    return TautulliHistoryPage(
      recordsTotal: tInt(json['recordsTotal']),
      records: rows
          .map(
            (dynamic e) =>
                TautulliHistoryRecord.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final int recordsTotal;
  final List<TautulliHistoryRecord> records;
}

class TautulliHistoryRecord {
  const TautulliHistoryRecord({
    required this.date,
    required this.fullTitle,
    required this.friendlyName,
    required this.playDuration,
    required this.percentComplete,
    required this.watchedStatus,
    required this.mediaType,
    required this.platform,
    required this.player,
    required this.transcodeDecision,
  });

  factory TautulliHistoryRecord.fromJson(Map<String, dynamic> json) {
    return TautulliHistoryRecord(
      date: tInt(json['date']),
      fullTitle: tString(json['full_title']),
      friendlyName: tString(json['friendly_name']),
      // Newer Tautulli reports play_duration; older only duration.
      playDuration: json.containsKey('play_duration')
          ? tInt(json['play_duration'])
          : tInt(json['duration']),
      percentComplete: tInt(json['percent_complete']),
      watchedStatus: tDouble(json['watched_status']),
      mediaType: tString(json['media_type']),
      platform: tString(json['platform']),
      player: tString(json['player']),
      transcodeDecision: tString(json['transcode_decision']),
    );
  }

  /// Epoch seconds when playback started.
  final int date;
  final String fullTitle;
  final String friendlyName;

  /// Seconds actually played.
  final int playDuration;
  final int percentComplete;

  /// 0 = unwatched, 0.5 = partial, 1 = watched.
  final double watchedStatus;
  final String mediaType;
  final String platform;
  final String player;
  final String transcodeDecision;
}

/// One section from `cmd=get_home_stats` (e.g. top_movies, top_users).
///
/// Row shapes differ per stat, so rows stay raw maps behind a thin typed
/// view - the same pattern as the *arr lookup results.
class TautulliHomeStat {
  const TautulliHomeStat({required this.statId, required this.rows});

  factory TautulliHomeStat.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rows = (json['rows'] as List<dynamic>?) ?? <dynamic>[];
    return TautulliHomeStat(
      statId: tString(json['stat_id']),
      rows: rows
          .map((dynamic e) => TautulliStatRow(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String statId;
  final List<TautulliStatRow> rows;

  /// Human section header for a stat_id.
  String get title => switch (statId) {
        'top_movies' => 'Top movies',
        'popular_movies' => 'Popular movies',
        'top_tv' => 'Top TV shows',
        'popular_tv' => 'Popular TV shows',
        'top_music' => 'Top music',
        'popular_music' => 'Popular music',
        'top_libraries' => 'Top libraries',
        'top_users' => 'Top users',
        'top_platforms' => 'Top platforms',
        'last_watched' => 'Recently watched',
        'most_concurrent' => 'Most concurrent streams',
        _ => statId,
      };
}

/// Thin view over one home-stats row.
class TautulliStatRow {
  const TautulliStatRow(this.raw);

  final Map<String, dynamic> raw;

  /// Display label for a row within [statId]'s section.
  ///
  /// Rows carry several name-ish fields at once (a top_users row has both
  /// the user's `friendly_name` AND the last-played `title`), so the right
  /// one depends on which stat the row belongs to.
  String labelFor(String statId) {
    final List<String> keys = switch (statId) {
      'top_users' => const <String>['friendly_name', 'user', 'title'],
      'top_libraries' => const <String>[
          'section_name',
          'library_name',
          'title',
        ],
      'top_platforms' => const <String>['platform', 'title'],
      _ => const <String>['title', 'friendly_name', 'platform', 'section_name'],
    };
    for (final String key in keys) {
      final String v = tString(raw[key]);
      if (v.isNotEmpty) {
        return v;
      }
    }
    return '-';
  }

  int get totalPlays => tInt(raw['total_plays']);

  /// Seconds. Only some stats carry it.
  int get totalDuration => tInt(raw['total_duration']);

  /// For most_concurrent rows the interesting number is `count`.
  int get count => tInt(raw['count']);

  /// For last_watched rows.
  String get user => tString(raw['user']);
}

/// One row from `cmd=get_users_table`.
class TautulliUser {
  const TautulliUser({
    required this.userId,
    required this.friendlyName,
    required this.lastSeen,
    required this.plays,
    required this.duration,
    required this.lastPlayed,
    required this.isActive,
  });

  factory TautulliUser.fromJson(Map<String, dynamic> json) {
    return TautulliUser(
      userId: tInt(json['user_id']),
      friendlyName: tString(json['friendly_name']),
      lastSeen: tInt(json['last_seen']),
      plays: tInt(json['plays']),
      duration: tInt(json['duration']),
      lastPlayed: tString(json['last_played']),
      isActive: tInt(json['is_active']) == 1,
    );
  }

  final int userId;
  final String friendlyName;

  /// Epoch seconds; 0 = never seen.
  final int lastSeen;
  final int plays;

  /// Total seconds watched.
  final int duration;
  final String lastPlayed;
  final bool isActive;
}
