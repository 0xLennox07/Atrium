import 'package:freezed_annotation/freezed_annotation.dart';

part 'sonarr_series.freezed.dart';
part 'sonarr_series.g.dart';

/// A Sonarr series (TV show) as returned by `GET /api/v3/series`.
///
/// Only the fields Atrium currently renders are modeled; Sonarr returns many
/// more. Unmodeled fields are simply ignored by json_serializable.
@freezed
abstract class SonarrSeries with _$SonarrSeries {
  const factory SonarrSeries({
    required int id,
    required String title,
    @Default(0) int seasonCount,
    @Default(<SonarrSeasonStats>[]) List<SonarrSeasonStats> seasons,
    String? overview,
    String? status,
    String? network,
    @Default(false) bool monitored,
    int? year,
    SonarrSeriesStatistics? statistics,
    @Default(<SonarrImage>[]) List<SonarrImage> images,
    @Default(0) int qualityProfileId,
  }) = _SonarrSeries;

  factory SonarrSeries.fromJson(Map<String, dynamic> json) =>
      _$SonarrSeriesFromJson(json);
}

@freezed
abstract class SonarrSeasonStats with _$SonarrSeasonStats {
  const factory SonarrSeasonStats({
    required int seasonNumber,
    @Default(false) bool monitored,
    SonarrSeasonStatistics? statistics,
  }) = _SonarrSeasonStats;

  factory SonarrSeasonStats.fromJson(Map<String, dynamic> json) =>
      _$SonarrSeasonStatsFromJson(json);
}

/// Per-season statistics nested under `seasons[].statistics`.
@freezed
abstract class SonarrSeasonStatistics with _$SonarrSeasonStatistics {
  const factory SonarrSeasonStatistics({
    @Default(0) int episodeCount,
    @Default(0) int episodeFileCount,
    @Default(0) int totalEpisodeCount,
    @Default(0) int sizeOnDisk,
  }) = _SonarrSeasonStatistics;

  factory SonarrSeasonStatistics.fromJson(Map<String, dynamic> json) =>
      _$SonarrSeasonStatisticsFromJson(json);
}

@freezed
abstract class SonarrSeriesStatistics with _$SonarrSeriesStatistics {
  const factory SonarrSeriesStatistics({
    @Default(0) int episodeCount,
    @Default(0) int episodeFileCount,
    @Default(0) int totalEpisodeCount,
    @Default(0) int sizeOnDisk,
    @Default(0) double percentOfEpisodes,
  }) = _SonarrSeriesStatistics;

  factory SonarrSeriesStatistics.fromJson(Map<String, dynamic> json) =>
      _$SonarrSeriesStatisticsFromJson(json);
}

@freezed
abstract class SonarrImage with _$SonarrImage {
  const factory SonarrImage({
    required String coverType,
    String? remoteUrl,
    String? url,
  }) = _SonarrImage;

  factory SonarrImage.fromJson(Map<String, dynamic> json) =>
      _$SonarrImageFromJson(json);
}
