import 'package:freezed_annotation/freezed_annotation.dart';

part 'plex_models.freezed.dart';
part 'plex_models.g.dart';

/// Plex wraps every response in a `MediaContainer`. With
/// `Accept: application/json` (set by the auth interceptor) it returns JSON
/// rather than the default XML.
@freezed
abstract class PlexLibrariesResponse with _$PlexLibrariesResponse {
  const factory PlexLibrariesResponse({
    @JsonKey(name: 'MediaContainer') PlexLibrariesContainer? mediaContainer,
  }) = _PlexLibrariesResponse;

  factory PlexLibrariesResponse.fromJson(Map<String, dynamic> json) =>
      _$PlexLibrariesResponseFromJson(json);
}

@freezed
abstract class PlexLibrariesContainer with _$PlexLibrariesContainer {
  const factory PlexLibrariesContainer({
    @JsonKey(name: 'Directory')
    @Default(<PlexLibrary>[])
    List<PlexLibrary> directory,
  }) = _PlexLibrariesContainer;

  factory PlexLibrariesContainer.fromJson(Map<String, dynamic> json) =>
      _$PlexLibrariesContainerFromJson(json);
}

/// A Plex library section.
@freezed
abstract class PlexLibrary with _$PlexLibrary {
  const factory PlexLibrary({
    required String key,
    @Default('') String title,
    /// "movie", "show", "artist", "photo".
    @Default('') String type,
  }) = _PlexLibrary;

  factory PlexLibrary.fromJson(Map<String, dynamic> json) =>
      _$PlexLibraryFromJson(json);
}

@freezed
abstract class PlexItemsResponse with _$PlexItemsResponse {
  const factory PlexItemsResponse({
    @JsonKey(name: 'MediaContainer') PlexItemsContainer? mediaContainer,
  }) = _PlexItemsResponse;

  factory PlexItemsResponse.fromJson(Map<String, dynamic> json) =>
      _$PlexItemsResponseFromJson(json);
}

@freezed
abstract class PlexItemsContainer with _$PlexItemsContainer {
  const factory PlexItemsContainer({
    @JsonKey(name: 'Metadata')
    @Default(<PlexMetadata>[])
    List<PlexMetadata> metadata,
    @JsonKey(name: 'size') @Default(0) int size,
  }) = _PlexItemsContainer;

  factory PlexItemsContainer.fromJson(Map<String, dynamic> json) =>
      _$PlexItemsContainerFromJson(json);
}

/// A Plex library item (movie, show, …).
@freezed
abstract class PlexMetadata with _$PlexMetadata {
  const factory PlexMetadata({
    @JsonKey(name: 'ratingKey') @Default('') String ratingKey,
    @Default('') String title,
    int? year,
    /// Relative thumbnail path, e.g. `/library/metadata/123/thumb/456`.
    String? thumb,
    @Default('') String type,
    /// Present and > 0 when the user has watched it.
    @JsonKey(name: 'viewCount') @Default(0) int viewCount,
    /// Resume point in milliseconds, when partially watched.
    @JsonKey(name: 'viewOffset') int? viewOffset,
    /// Total runtime in milliseconds.
    @JsonKey(name: 'duration') int? duration,
    /// Playable media (present on movies/episodes; absent on shows/seasons).
    @JsonKey(name: 'Media') @Default(<PlexMedia>[]) List<PlexMedia> media,
  }) = _PlexMetadata;

  factory PlexMetadata.fromJson(Map<String, dynamic> json) =>
      _$PlexMetadataFromJson(json);
}

/// One media version of an item (a quality/format). Holds the file parts.
@freezed
abstract class PlexMedia with _$PlexMedia {
  const factory PlexMedia({
    @JsonKey(name: 'Part') @Default(<PlexPart>[]) List<PlexPart> parts,
  }) = _PlexMedia;

  factory PlexMedia.fromJson(Map<String, dynamic> json) =>
      _$PlexMediaFromJson(json);
}

/// One physical file backing a [PlexMedia]. [key] is the streamable path
/// (e.g. `/library/parts/123/456/file.mkv`).
@freezed
abstract class PlexPart with _$PlexPart {
  const factory PlexPart({
    @JsonKey(name: 'key') String? key,
    @JsonKey(name: 'duration') int? duration,
  }) = _PlexPart;

  factory PlexPart.fromJson(Map<String, dynamic> json) =>
      _$PlexPartFromJson(json);
}
