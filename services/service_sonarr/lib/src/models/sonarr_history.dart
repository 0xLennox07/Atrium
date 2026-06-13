import 'package:freezed_annotation/freezed_annotation.dart';

part 'sonarr_history.freezed.dart';
part 'sonarr_history.g.dart';

@freezed
abstract class SonarrHistoryRecord with _$SonarrHistoryRecord {
  const factory SonarrHistoryRecord({
    required int id,
    required int seriesId,
    required int episodeId,
    required String sourceTitle,
    required String eventType,
    required DateTime date,
    @Default(<String, dynamic>{}) Map<String, dynamic> data,
    Map<String, dynamic>? quality,
  }) = _SonarrHistoryRecord;

  factory SonarrHistoryRecord.fromJson(Map<String, dynamic> json) =>
      _$SonarrHistoryRecordFromJson(json);
}

@freezed
abstract class SonarrHistoryPage with _$SonarrHistoryPage {
  const factory SonarrHistoryPage({
    required int page,
    required int pageSize,
    required int totalRecords,
    required List<SonarrHistoryRecord> records,
  }) = _SonarrHistoryPage;

  factory SonarrHistoryPage.fromJson(Map<String, dynamic> json) =>
      _$SonarrHistoryPageFromJson(json);
}
