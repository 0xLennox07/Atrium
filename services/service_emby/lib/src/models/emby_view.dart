import 'package:freezed_annotation/freezed_annotation.dart';

part 'emby_view.freezed.dart';
part 'emby_view.g.dart';

/// An Emby library/view from `GET /Users/{userId}/Views`.
@freezed
abstract class EmbyView with _$EmbyView {
  const factory EmbyView({
    @JsonKey(name: 'Id') required String id,
    @JsonKey(name: 'Name') @Default('') String name,
    @JsonKey(name: 'CollectionType') String? collectionType,
  }) = _EmbyView;

  factory EmbyView.fromJson(Map<String, dynamic> json) =>
      _$EmbyViewFromJson(json);
}
