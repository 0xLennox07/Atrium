import 'package:freezed_annotation/freezed_annotation.dart';

part 'jellyfin_item.freezed.dart';
part 'jellyfin_item.g.dart';

/// A page of items from `GET /Users/{userId}/Items`.
@freezed
class JellyfinItemsResult with _$JellyfinItemsResult {
  const factory JellyfinItemsResult({
    @JsonKey(name: 'Items') @Default(<JellyfinItem>[]) List<JellyfinItem> items,
    @JsonKey(name: 'TotalRecordCount') @Default(0) int totalRecordCount,
  }) = _JellyfinItemsResult;

  factory JellyfinItemsResult.fromJson(Map<String, dynamic> json) =>
      _$JellyfinItemsResultFromJson(json);
}

/// A library item (movie, series, episode, album, …).
@freezed
class JellyfinItem with _$JellyfinItem {
  const factory JellyfinItem({
    @JsonKey(name: 'Id') required String id,
    @JsonKey(name: 'Name') @Default('') String name,
    @JsonKey(name: 'Type') @Default('') String type,
    @JsonKey(name: 'ProductionYear') int? productionYear,

    /// Image type → tag. We use the `Primary` tag to build the poster URL.
    @JsonKey(name: 'ImageTags')
    @Default(<String, String>{})
    Map<String, String> imageTags,
    @JsonKey(name: 'UserData') JellyfinUserData? userData,
    @JsonKey(name: 'Overview') String? overview,
    @JsonKey(name: 'RunTimeTicks') int? runTimeTicks,
    @JsonKey(name: 'CommunityRating') double? communityRating,
    @JsonKey(name: 'OfficialRating') String? officialRating,
    @JsonKey(name: 'IndexNumber') int? indexNumber,
    @JsonKey(name: 'ParentIndexNumber') int? parentIndexNumber,
    @JsonKey(name: 'SeriesName') String? seriesName,
    @JsonKey(name: 'SeriesId') String? seriesId,
    @JsonKey(name: 'SeriesPrimaryImageTag') String? seriesPrimaryImageTag,
    @JsonKey(name: 'ParentId') String? parentId,
    @JsonKey(name: 'ParentPrimaryImageTag') String? parentPrimaryImageTag,
    @JsonKey(name: 'People') @Default(<JellyfinPerson>[]) List<JellyfinPerson> people,
  }) = _JellyfinItem;

  factory JellyfinItem.fromJson(Map<String, dynamic> json) =>
      _$JellyfinItemFromJson(json);
}

/// Per-user playback state for an item.
@freezed
class JellyfinUserData with _$JellyfinUserData {
  const factory JellyfinUserData({
    @JsonKey(name: 'PlayedPercentage') @Default(0.0) double playedPercentage,
    @JsonKey(name: 'Played') @Default(false) bool played,
    @JsonKey(name: 'IsFavorite') @Default(false) bool isFavorite,
    /// Resume point in Jellyfin ticks (100ns units). 0 = start from the top.
    @JsonKey(name: 'PlaybackPositionTicks') @Default(0) int positionTicks,
  }) = _JellyfinUserData;

  factory JellyfinUserData.fromJson(Map<String, dynamic> json) =>
      _$JellyfinUserDataFromJson(json);
}

/// A cast or crew member attached to an item.
@freezed
class JellyfinPerson with _$JellyfinPerson {
  const factory JellyfinPerson({
    @JsonKey(name: 'Id') required String id,
    @JsonKey(name: 'Name') @Default('') String name,
    @JsonKey(name: 'Role') String? role,
    @JsonKey(name: 'Type') String? type,
    @JsonKey(name: 'PrimaryImageTag') String? primaryImageTag,
  }) = _JellyfinPerson;

  factory JellyfinPerson.fromJson(Map<String, dynamic> json) =>
      _$JellyfinPersonFromJson(json);
}


