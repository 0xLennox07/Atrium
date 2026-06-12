import 'package:freezed_annotation/freezed_annotation.dart';

part 'radarr_queue.freezed.dart';
part 'radarr_queue.g.dart';

/// A page of queue records from `GET /api/v3/queue`.
@freezed
abstract class RadarrQueuePage with _$RadarrQueuePage {
  const factory RadarrQueuePage({
    @Default(0) int page,
    @Default(0) int pageSize,
    @Default(0) int totalRecords,
    @Default(<RadarrQueueRecord>[]) List<RadarrQueueRecord> records,
  }) = _RadarrQueuePage;

  factory RadarrQueuePage.fromJson(Map<String, dynamic> json) =>
      _$RadarrQueuePageFromJson(json);
}

/// One movie being downloaded / imported.
@freezed
abstract class RadarrQueueRecord with _$RadarrQueueRecord {
  const factory RadarrQueueRecord({
    required int id,
    int? movieId,
    String? title,
    String? status,
    String? trackedDownloadStatus,
    String? trackedDownloadState,
    @Default(0) double size,
    @Default(0) double sizeleft,
    String? timeleft,
    String? downloadClient,
    String? protocol,
  }) = _RadarrQueueRecord;

  factory RadarrQueueRecord.fromJson(Map<String, dynamic> json) =>
      _$RadarrQueueRecordFromJson(json);
}
