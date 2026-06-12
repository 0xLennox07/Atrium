import 'package:freezed_annotation/freezed_annotation.dart';

part 'sonarr_queue.freezed.dart';
part 'sonarr_queue.g.dart';

/// A page of queue records from `GET /api/v3/queue`.
@freezed
abstract class SonarrQueuePage with _$SonarrQueuePage {
  const factory SonarrQueuePage({
    @Default(0) int page,
    @Default(0) int pageSize,
    @Default(0) int totalRecords,
    @Default(<SonarrQueueRecord>[]) List<SonarrQueueRecord> records,
  }) = _SonarrQueuePage;

  factory SonarrQueuePage.fromJson(Map<String, dynamic> json) =>
      _$SonarrQueuePageFromJson(json);
}

/// One item being downloaded / imported.
@freezed
abstract class SonarrQueueRecord with _$SonarrQueueRecord {
  const factory SonarrQueueRecord({
    required int id,
    int? seriesId,
    int? episodeId,
    String? title,
    String? status,
    String? trackedDownloadStatus,
    String? trackedDownloadState,
    @Default(0) double size,
    @Default(0) double sizeleft,
    String? timeleft,
    String? downloadClient,
    String? protocol,
  }) = _SonarrQueueRecord;

  factory SonarrQueueRecord.fromJson(Map<String, dynamic> json) =>
      _$SonarrQueueRecordFromJson(json);
}
