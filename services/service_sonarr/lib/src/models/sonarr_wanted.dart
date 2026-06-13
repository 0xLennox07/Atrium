import 'package:freezed_annotation/freezed_annotation.dart';
import 'sonarr_series.dart';

part 'sonarr_wanted.freezed.dart';
part 'sonarr_wanted.g.dart';

@freezed
abstract class SonarrWantedRecord with _$SonarrWantedRecord {
  const factory SonarrWantedRecord({
    required int id,
    required int seriesId,
    int? episodeFileId,
    required int seasonNumber,
    required int episodeNumber,
    String? title,
    String? airDate,
    DateTime? airDateUtc,
    @Default(false) bool monitored,
    @Default(false) bool hasFile,
    SonarrSeries? series,
  }) = _SonarrWantedRecord;

  factory SonarrWantedRecord.fromJson(Map<String, dynamic> json) =>
      _$SonarrWantedRecordFromJson(json);
}

@freezed
abstract class SonarrWantedPage with _$SonarrWantedPage {
  const factory SonarrWantedPage({
    required int page,
    required int pageSize,
    required int totalRecords,
    required List<SonarrWantedRecord> records,
  }) = _SonarrWantedPage;

  factory SonarrWantedPage.fromJson(Map<String, dynamic> json) =>
      _$SonarrWantedPageFromJson(json);
}
