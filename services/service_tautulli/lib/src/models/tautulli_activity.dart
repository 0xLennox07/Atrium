import 'package:freezed_annotation/freezed_annotation.dart';

import 'tautulli_json.dart';

part 'tautulli_activity.freezed.dart';
part 'tautulli_activity.g.dart';

/// Tautulli wraps responses as `{ "response": { "result": …, "data": … } }`.
@freezed
abstract class TautulliActivityEnvelope with _$TautulliActivityEnvelope {
  const factory TautulliActivityEnvelope({
    required TautulliActivityBody response,
  }) = _TautulliActivityEnvelope;

  factory TautulliActivityEnvelope.fromJson(Map<String, dynamic> json) =>
      _$TautulliActivityEnvelopeFromJson(json);
}

@freezed
abstract class TautulliActivityBody with _$TautulliActivityBody {
  const factory TautulliActivityBody({
    @JsonKey(fromJson: tString) @Default('') String result,
    TautulliActivity? data,
  }) = _TautulliActivityBody;

  factory TautulliActivityBody.fromJson(Map<String, dynamic> json) =>
      _$TautulliActivityBodyFromJson(json);
}

@freezed
abstract class TautulliActivity with _$TautulliActivity {
  const factory TautulliActivity({
    @JsonKey(name: 'stream_count', fromJson: tInt) @Default(0) int streamCount,
    @JsonKey(name: 'stream_count_direct_play', fromJson: tInt)
    @Default(0)
    int directPlayCount,
    @JsonKey(name: 'stream_count_direct_stream', fromJson: tInt)
    @Default(0)
    int directStreamCount,
    @JsonKey(name: 'stream_count_transcode', fromJson: tInt)
    @Default(0)
    int transcodeCount,
    @JsonKey(name: 'total_bandwidth', fromJson: tInt)
    @Default(0)
    int totalBandwidth,
    @JsonKey(name: 'lan_bandwidth', fromJson: tInt)
    @Default(0)
    int lanBandwidth,
    @Default(<TautulliSession>[]) List<TautulliSession> sessions,
  }) = _TautulliActivity;

  factory TautulliActivity.fromJson(Map<String, dynamic> json) =>
      _$TautulliActivityFromJson(json);
}

/// A single active stream.
///
/// Every field is converted tolerantly - Tautulli mixes strings and numbers
/// freely across versions and players.
@freezed
abstract class TautulliSession with _$TautulliSession {
  const factory TautulliSession({
    @JsonKey(name: 'session_key', fromJson: tString)
    @Default('')
    String sessionKey,
    @JsonKey(name: 'session_id', fromJson: tString)
    @Default('')
    String sessionId,
    @JsonKey(name: 'friendly_name', fromJson: tString)
    @Default('')
    String friendlyName,
    @JsonKey(name: 'full_title', fromJson: tString)
    @Default('')
    String fullTitle,
    @JsonKey(name: 'grandparent_title', fromJson: tString)
    @Default('')
    String grandparentTitle,
    @JsonKey(name: 'parent_media_index', fromJson: tString)
    @Default('')
    String seasonNumber,
    @JsonKey(name: 'media_index', fromJson: tString)
    @Default('')
    String episodeNumber,
    @JsonKey(fromJson: tString) @Default('') String year,
    @JsonKey(name: 'progress_percent', fromJson: tInt)
    @Default(0)
    int progressPercent,
    @JsonKey(fromJson: tString) @Default('') String state,
    @JsonKey(fromJson: tString) @Default('') String player,
    @JsonKey(fromJson: tString) @Default('') String product,
    @JsonKey(fromJson: tString) @Default('') String platform,
    @JsonKey(name: 'quality_profile', fromJson: tString)
    @Default('')
    String qualityProfile,
    @JsonKey(name: 'transcode_decision', fromJson: tString)
    @Default('')
    String transcodeDecision,
    @JsonKey(name: 'video_decision', fromJson: tString)
    @Default('')
    String videoDecision,
    @JsonKey(name: 'audio_decision', fromJson: tString)
    @Default('')
    String audioDecision,
    @JsonKey(name: 'video_codec', fromJson: tString)
    @Default('')
    String videoCodec,
    @JsonKey(name: 'audio_codec', fromJson: tString)
    @Default('')
    String audioCodec,
    @JsonKey(name: 'stream_video_codec', fromJson: tString)
    @Default('')
    String streamVideoCodec,
    @JsonKey(name: 'stream_audio_codec', fromJson: tString)
    @Default('')
    String streamAudioCodec,
    @JsonKey(name: 'video_full_resolution', fromJson: tString)
    @Default('')
    String videoResolution,
    @JsonKey(fromJson: tString) @Default('') String container,
    @JsonKey(fromJson: tInt) @Default(0) int bandwidth,
    @JsonKey(fromJson: tString) @Default('') String location,
    @JsonKey(name: 'media_type', fromJson: tString)
    @Default('')
    String mediaType,
  }) = _TautulliSession;

  const TautulliSession._();

  factory TautulliSession.fromJson(Map<String, dynamic> json) =>
      _$TautulliSessionFromJson(json);

  /// `S2 E5` for episodes, empty otherwise.
  String get episodeLabel {
    if (mediaType != 'episode' ||
        seasonNumber.isEmpty ||
        episodeNumber.isEmpty) {
      return '';
    }
    return 'S$seasonNumber E$episodeNumber';
  }
}
