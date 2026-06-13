import 'package:freezed_annotation/freezed_annotation.dart';

part 'sonarr_episode.freezed.dart';
part 'sonarr_episode.g.dart';

/// An episode object from `GET /api/v3/episode`.
@freezed
abstract class SonarrEpisode with _$SonarrEpisode {
  const factory SonarrEpisode({
    required int id,
    required int seriesId,
    required int seasonNumber,
    required int episodeNumber,
    String? title,
    String? overview,
    String? airDate,
    DateTime? airDateUtc,
    @Default(false) bool hasFile,
    @Default(false) bool monitored,
    @Default(0) int episodeFileId,
  }) = _SonarrEpisode;

  factory SonarrEpisode.fromJson(Map<String, dynamic> json) =>
      _$SonarrEpisodeFromJson(json);
}
