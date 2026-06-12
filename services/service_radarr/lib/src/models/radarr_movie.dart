import 'package:freezed_annotation/freezed_annotation.dart';

part 'radarr_movie.freezed.dart';
part 'radarr_movie.g.dart';

/// A Radarr movie as returned by `GET /api/v3/movie`.
///
/// Only the fields Atrium currently renders are modeled; Radarr returns many
/// more. Unmodeled fields are ignored by json_serializable.
@freezed
abstract class RadarrMovie with _$RadarrMovie {
  const factory RadarrMovie({
    required int id,
    required String title,
    int? year,
    String? overview,
    String? status,
    String? studio,
    int? runtime,
    @Default(false) bool monitored,
    @Default(false) bool hasFile,
    @Default(0) int sizeOnDisk,
    RadarrRatings? ratings,
    @Default(<RadarrImage>[]) List<RadarrImage> images,
  }) = _RadarrMovie;

  factory RadarrMovie.fromJson(Map<String, dynamic> json) =>
      _$RadarrMovieFromJson(json);
}

@freezed
abstract class RadarrRatings with _$RadarrRatings {
  const factory RadarrRatings({
    RadarrRatingValue? imdb,
    RadarrRatingValue? tmdb,
    RadarrRatingValue? rottenTomatoes,
  }) = _RadarrRatings;

  factory RadarrRatings.fromJson(Map<String, dynamic> json) =>
      _$RadarrRatingsFromJson(json);
}

@freezed
abstract class RadarrRatingValue with _$RadarrRatingValue {
  const factory RadarrRatingValue({
    @Default(0) double value,
    @Default(0) int votes,
  }) = _RadarrRatingValue;

  factory RadarrRatingValue.fromJson(Map<String, dynamic> json) =>
      _$RadarrRatingValueFromJson(json);
}

@freezed
abstract class RadarrImage with _$RadarrImage {
  const factory RadarrImage({
    required String coverType,
    String? remoteUrl,
    String? url,
  }) = _RadarrImage;

  factory RadarrImage.fromJson(Map<String, dynamic> json) =>
      _$RadarrImageFromJson(json);
}
