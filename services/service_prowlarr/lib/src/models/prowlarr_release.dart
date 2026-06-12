import 'package:freezed_annotation/freezed_annotation.dart';

part 'prowlarr_release.freezed.dart';
part 'prowlarr_release.g.dart';

/// One release returned by `GET /api/v1/search`.
///
/// Grabbing a release back through `POST /api/v1/search` only needs the
/// `guid` + `indexerId` pair - Prowlarr resolves the rest from its release
/// cache - so a trimmed typed model is safe here (unlike *arr add/update,
/// which need the complete raw object).
@freezed
abstract class ProwlarrRelease with _$ProwlarrRelease {
  const ProwlarrRelease._();

  const factory ProwlarrRelease({
    required String guid,
    required int indexerId,
    required String title,
    String? indexer,
    @Default(0) int size,
    int? seeders,
    int? leechers,
    @Default(0) int age,
    double? ageHours,
    DateTime? publishDate,
    String? protocol,
    @Default(<ProwlarrReleaseCategory>[]) List<ProwlarrReleaseCategory>
        categories,
    String? downloadUrl,
    String? infoUrl,
    int? grabs,
  }) = _ProwlarrRelease;

  factory ProwlarrRelease.fromJson(Map<String, dynamic> json) =>
      _$ProwlarrReleaseFromJson(json);

  bool get isTorrent => protocol == 'torrent';

  /// Compact age: hours under a day, days otherwise.
  String get ageLabel {
    if (age <= 0 && ageHours != null) {
      final int hours = ageHours!.round();
      return hours <= 0 ? 'new' : '${hours}h';
    }
    return '${age}d';
  }
}

/// Category tag on a release (`categories[].{id,name}`).
@freezed
abstract class ProwlarrReleaseCategory with _$ProwlarrReleaseCategory {
  const factory ProwlarrReleaseCategory({
    @Default(0) int id,
    String? name,
  }) = _ProwlarrReleaseCategory;

  factory ProwlarrReleaseCategory.fromJson(Map<String, dynamic> json) =>
      _$ProwlarrReleaseCategoryFromJson(json);
}
