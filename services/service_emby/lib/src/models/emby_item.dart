import 'package:freezed_annotation/freezed_annotation.dart';

part 'emby_item.freezed.dart';
part 'emby_item.g.dart';

/// A page of items from `GET /Users/{userId}/Items`.
@freezed
class EmbyItemsResult with _$EmbyItemsResult {
  const factory EmbyItemsResult({
    @JsonKey(name: 'Items') @Default(<EmbyItem>[]) List<EmbyItem> items,
    @JsonKey(name: 'TotalRecordCount') @Default(0) int totalRecordCount,
  }) = _EmbyItemsResult;

  factory EmbyItemsResult.fromJson(Map<String, dynamic> json) =>
      _$EmbyItemsResultFromJson(json);
}

/// A library item (movie, series, episode, album, …).
@freezed
class EmbyItem with _$EmbyItem {
  const factory EmbyItem({
    @JsonKey(name: 'Id') required String id,
    @JsonKey(name: 'Name') @Default('') String name,
    @JsonKey(name: 'Type') @Default('') String type,
    @JsonKey(name: 'ProductionYear') int? productionYear,
    @JsonKey(name: 'ImageTags')
    @Default(<String, String>{})
    Map<String, String> imageTags,
    @JsonKey(name: 'UserData') EmbyUserData? userData,
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
    @JsonKey(name: 'People') @Default(<EmbyPerson>[]) List<EmbyPerson> people,
  }) = _EmbyItem;

  factory EmbyItem.fromJson(Map<String, dynamic> json) =>
      _$EmbyItemFromJson(json);
}

/// Per-user playback state for an item.
@freezed
class EmbyUserData with _$EmbyUserData {
  const factory EmbyUserData({
    @JsonKey(name: 'PlayedPercentage') @Default(0.0) double playedPercentage,
    @JsonKey(name: 'Played') @Default(false) bool played,
    @JsonKey(name: 'IsFavorite') @Default(false) bool isFavorite,
    /// Resume point in Emby ticks (100ns units). 0 = start from the top.
    @JsonKey(name: 'PlaybackPositionTicks') @Default(0) int positionTicks,
  }) = _EmbyUserData;

  factory EmbyUserData.fromJson(Map<String, dynamic> json) =>
      _$EmbyUserDataFromJson(json);
}

/// A cast or crew member attached to an item.
@freezed
class EmbyPerson with _$EmbyPerson {
  const factory EmbyPerson({
    @JsonKey(name: 'Id') required String id,
    @JsonKey(name: 'Name') @Default('') String name,
    @JsonKey(name: 'Role') String? role,
    @JsonKey(name: 'Type') String? type,
    @JsonKey(name: 'PrimaryImageTag') String? primaryImageTag,
  }) = _EmbyPerson;

  factory EmbyPerson.fromJson(Map<String, dynamic> json) =>
      _$EmbyPersonFromJson(json);
}
