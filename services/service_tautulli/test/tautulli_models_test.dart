import 'package:flutter_test/flutter_test.dart';
import 'package:service_tautulli/service_tautulli.dart';

// Trimmed but shape-faithful payloads. Tautulli mixes strings and numbers
// freely (and flips between them across versions), so these deliberately use
// the WORST mix: numeric strings, real ints, nulls, and empty strings.
const Map<String, dynamic> activityJson = <String, dynamic>{
  'response': <String, dynamic>{
    'result': 'success',
    'data': <String, dynamic>{
      'stream_count': '2',
      'stream_count_direct_play': 1,
      'stream_count_transcode': '1',
      'total_bandwidth': 24300,
      'lan_bandwidth': '20100',
      'sessions': <dynamic>[
        <String, dynamic>{
          'session_key': '77',
          'session_id': 'abcdef123',
          'friendly_name': 'Alice',
          'full_title': 'The Matrix',
          'progress_percent': '30',
          'state': 'playing',
          'player': 'Living Room TV',
          'product': 'Plex for Android (TV)',
          'platform': 'Android',
          'quality_profile': '1080p',
          'transcode_decision': 'transcode',
          'video_decision': 'transcode',
          'audio_decision': 'copy',
          'video_codec': 'hevc',
          'stream_video_codec': 'h264',
          'audio_codec': 'eac3',
          'stream_audio_codec': 'eac3',
          'video_full_resolution': '1080p',
          'container': 'mkv',
          'bandwidth': '24300',
          'location': 'wan',
          'media_type': 'episode',
          'grandparent_title': 'Some Show',
          'parent_media_index': 2,
          'media_index': '5',
          'year': 2024,
        },
      ],
    },
  },
};

const Map<String, dynamic> historyDataJson = <String, dynamic>{
  'recordsTotal': 1543,
  'data': <dynamic>[
    <String, dynamic>{
      'date': 1765432100,
      'full_title': 'Some Show - Pilot',
      'friendly_name': 'Bob',
      'play_duration': '2520',
      'percent_complete': 98,
      'watched_status': 1,
      'media_type': 'episode',
      'platform': 'Android',
      'player': 'Pixel 7',
      'transcode_decision': 'direct play',
    },
    <String, dynamic>{
      // Older server: only `duration`, watched_status as double, nulls.
      'date': '1765000000',
      'full_title': 'Old Movie',
      'friendly_name': 'Carol',
      'duration': 600,
      'percent_complete': '47',
      'watched_status': 0.5,
      'media_type': 'movie',
      'platform': null,
      'player': 'Web',
      'transcode_decision': 'transcode',
    },
  ],
};

const List<dynamic> homeStatsJson = <dynamic>[
  <String, dynamic>{
    'stat_id': 'top_movies',
    'rows': <dynamic>[
      <String, dynamic>{'title': 'The Matrix', 'total_plays': 12},
      <String, dynamic>{'title': 'Dune', 'total_plays': '8'},
    ],
  },
  <String, dynamic>{
    'stat_id': 'top_users',
    'rows': <dynamic>[
      <String, dynamic>{
        'friendly_name': 'Alice',
        // Real top_users rows also carry the last-played title; the label
        // must still be the user, not the media.
        'title': 'Some Show - Pilot',
        'total_plays': 99,
        'total_duration': '180000',
      },
    ],
  },
  <String, dynamic>{
    'stat_id': 'most_concurrent',
    'rows': <dynamic>[
      <String, dynamic>{'title': 'Concurrent Streams', 'count': '4'},
    ],
  },
  <String, dynamic>{'stat_id': 'top_music', 'rows': <dynamic>[]},
];

const Map<String, dynamic> userRowJson = <String, dynamic>{
  'user_id': 123456,
  'friendly_name': 'Alice',
  'last_seen': '1765432100',
  'plays': '420',
  'duration': 987654,
  'last_played': 'Some Show - Pilot',
  'is_active': 1,
};

void main() {
  test('parses activity with mixed string/int types', () {
    final TautulliActivityEnvelope env =
        TautulliActivityEnvelope.fromJson(activityJson);
    final TautulliActivity a = env.response.data!;
    expect(a.streamCount, 2);
    expect(a.directPlayCount, 1);
    expect(a.transcodeCount, 1);
    expect(a.totalBandwidth, 24300);
    expect(a.lanBandwidth, 20100);

    final TautulliSession s = a.sessions.single;
    expect(s.sessionKey, '77');
    expect(s.progressPercent, 30);
    expect(s.bandwidth, 24300);
    expect(s.transcodeDecision, 'transcode');
    expect(s.videoCodec, 'hevc');
    expect(s.streamVideoCodec, 'h264');
    expect(s.episodeLabel, 'S2 E5');
    expect(s.year, '2024');
  });

  test('parses history rows incl. legacy duration field', () {
    final TautulliHistoryPage page =
        TautulliHistoryPage.fromJson(historyDataJson);
    expect(page.recordsTotal, 1543);
    expect(page.records, hasLength(2));

    final TautulliHistoryRecord modern = page.records[0];
    expect(modern.playDuration, 2520);
    expect(modern.watchedStatus, 1);
    expect(modern.percentComplete, 98);

    final TautulliHistoryRecord legacy = page.records[1];
    expect(legacy.date, 1765000000);
    expect(legacy.playDuration, 600);
    expect(legacy.watchedStatus, 0.5);
    expect(legacy.percentComplete, 47);
    expect(legacy.platform, '');
  });

  test('parses home stats with per-stat row shapes', () {
    final List<TautulliHomeStat> stats = homeStatsJson
        .map((dynamic e) => TautulliHomeStat.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(stats, hasLength(4));

    expect(stats[0].title, 'Top movies');
    expect(stats[0].rows[0].labelFor('top_movies'), 'The Matrix');
    expect(stats[0].rows[1].totalPlays, 8);

    expect(stats[1].rows.single.labelFor('top_users'), 'Alice');
    expect(stats[1].rows.single.totalDuration, 180000);

    expect(stats[2].statId, 'most_concurrent');
    expect(stats[2].rows.single.count, 4);

    expect(stats[3].rows, isEmpty);
  });

  test('parses a users-table row', () {
    final TautulliUser u = TautulliUser.fromJson(userRowJson);
    expect(u.userId, 123456);
    expect(u.friendlyName, 'Alice');
    expect(u.lastSeen, 1765432100);
    expect(u.plays, 420);
    expect(u.duration, 987654);
    expect(u.lastPlayed, 'Some Show - Pilot');
    expect(u.isActive, isTrue);
  });
}
