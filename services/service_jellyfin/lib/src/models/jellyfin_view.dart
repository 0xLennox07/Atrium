import 'package:freezed_annotation/freezed_annotation.dart';

part 'jellyfin_view.freezed.dart';
part 'jellyfin_view.g.dart';

/// A Jellyfin library/view from `GET /Users/{userId}/Views`.
@freezed
class JellyfinView with _$JellyfinView {
  const factory JellyfinView({
    @JsonKey(name: 'Id') required String id,
    @JsonKey(name: 'Name') @Default('') String name,
    /// "movies", "tvshows", "music", "boxsets", "homevideos", … or null.
    @JsonKey(name: 'CollectionType') String? collectionType,
  }) = _JellyfinView;

  factory JellyfinView.fromJson(Map<String, dynamic> json) =>
      _$JellyfinViewFromJson(json);
}


