import 'package:freezed_annotation/freezed_annotation.dart';

part 'bazarr_models.freezed.dart';
part 'bazarr_models.g.dart';

/// `GET /api/badges` → summary counts shown in the header.
@freezed
abstract class BazarrBadges with _$BazarrBadges {
  const factory BazarrBadges({
    @Default(0) int episodes,
    @Default(0) int movies,
    @Default(0) int providers,
  }) = _BazarrBadges;

  factory BazarrBadges.fromJson(Map<String, dynamic> json) =>
      _$BazarrBadgesFromJson(json);
}

/// `GET /api/episodes/wanted` → `{ "data": [ … ], "total": N }`.
@freezed
abstract class BazarrWantedEpisodes with _$BazarrWantedEpisodes {
  const factory BazarrWantedEpisodes({
    @Default(<BazarrWantedEpisode>[]) List<BazarrWantedEpisode> data,
    @Default(0) int total,
  }) = _BazarrWantedEpisodes;

  factory BazarrWantedEpisodes.fromJson(Map<String, dynamic> json) =>
      _$BazarrWantedEpisodesFromJson(json);
}

@freezed
abstract class BazarrWantedEpisode with _$BazarrWantedEpisode {
  const factory BazarrWantedEpisode({
    @JsonKey(name: 'seriesTitle') @Default('') String seriesTitle,
    @JsonKey(name: 'episodeTitle') @Default('') String episodeTitle,
    @JsonKey(name: 'episode_number') @Default('') String episodeNumber,
    @JsonKey(name: 'missing_subtitles')
    @Default(<BazarrSubtitle>[])
    List<BazarrSubtitle> missingSubtitles,
  }) = _BazarrWantedEpisode;

  factory BazarrWantedEpisode.fromJson(Map<String, dynamic> json) =>
      _$BazarrWantedEpisodeFromJson(json);
}

/// `GET /api/movies/wanted` → `{ "data": [ … ], "total": N }`.
@freezed
abstract class BazarrWantedMovies with _$BazarrWantedMovies {
  const factory BazarrWantedMovies({
    @Default(<BazarrWantedMovie>[]) List<BazarrWantedMovie> data,
    @Default(0) int total,
  }) = _BazarrWantedMovies;

  factory BazarrWantedMovies.fromJson(Map<String, dynamic> json) =>
      _$BazarrWantedMoviesFromJson(json);
}

@freezed
abstract class BazarrWantedMovie with _$BazarrWantedMovie {
  const factory BazarrWantedMovie({
    @Default('') String title,
    @JsonKey(name: 'missing_subtitles')
    @Default(<BazarrSubtitle>[])
    List<BazarrSubtitle> missingSubtitles,
  }) = _BazarrWantedMovie;

  factory BazarrWantedMovie.fromJson(Map<String, dynamic> json) =>
      _$BazarrWantedMovieFromJson(json);
}

@freezed
abstract class BazarrSubtitle with _$BazarrSubtitle {
  const factory BazarrSubtitle({
    @Default('') String name,
    @Default('') String code2,
  }) = _BazarrSubtitle;

  factory BazarrSubtitle.fromJson(Map<String, dynamic> json) =>
      _$BazarrSubtitleFromJson(json);
}

/// A flattened "needs subtitles" row, unifying episodes + movies for the UI.
class BazarrWantedRow {
  const BazarrWantedRow({
    required this.title,
    required this.subtitle,
    required this.missing,
    required this.isMovie,
  });

  final String title;
  final String subtitle;
  final List<BazarrSubtitle> missing;
  final bool isMovie;
}
