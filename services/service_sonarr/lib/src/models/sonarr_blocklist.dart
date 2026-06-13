import 'package:freezed_annotation/freezed_annotation.dart';
import 'sonarr_series.dart';

part 'sonarr_blocklist.freezed.dart';
part 'sonarr_blocklist.g.dart';

@freezed
abstract class SonarrBlocklistRecord with _$SonarrBlocklistRecord {
  const factory SonarrBlocklistRecord({
    required int id,
    required int seriesId,
    List<int>? episodeIds,
    String? sourceTitle,
    String? indexer,
    String? message,
    DateTime? date,
    String? protocol,
    SonarrSeries? series,
  }) = _SonarrBlocklistRecord;

  factory SonarrBlocklistRecord.fromJson(Map<String, dynamic> json) =>
      _$SonarrBlocklistRecordFromJson(json);
}

@freezed
abstract class SonarrBlocklistPage with _$SonarrBlocklistPage {
  const factory SonarrBlocklistPage({
    required int page,
    required int pageSize,
    required int totalRecords,
    required List<SonarrBlocklistRecord> records,
  }) = _SonarrBlocklistPage;

  factory SonarrBlocklistPage.fromJson(Map<String, dynamic> json) =>
      _$SonarrBlocklistPageFromJson(json);
}
