import 'package:freezed_annotation/freezed_annotation.dart';

part 'prowlarr_indexer_stats.freezed.dart';
part 'prowlarr_indexer_stats.g.dart';

/// Aggregate indexer statistics from `GET /api/v1/indexerstats`.
@freezed
abstract class ProwlarrIndexerStats with _$ProwlarrIndexerStats {
  const factory ProwlarrIndexerStats({
    @Default(<ProwlarrIndexerStat>[]) List<ProwlarrIndexerStat> indexers,
  }) = _ProwlarrIndexerStats;

  factory ProwlarrIndexerStats.fromJson(Map<String, dynamic> json) =>
      _$ProwlarrIndexerStatsFromJson(json);
}

/// Per-indexer counters within [ProwlarrIndexerStats].
@freezed
abstract class ProwlarrIndexerStat with _$ProwlarrIndexerStat {
  const factory ProwlarrIndexerStat({
    required int indexerId,
    String? indexerName,
    @Default(0) int numberOfQueries,
    @Default(0) int numberOfGrabs,
    @Default(0) int numberOfRssQueries,
    @Default(0) int numberOfAuthQueries,
    @Default(0) int numberOfFailedQueries,
    @Default(0) int numberOfFailedGrabs,
    @Default(0) int averageResponseTime,
  }) = _ProwlarrIndexerStat;

  factory ProwlarrIndexerStat.fromJson(Map<String, dynamic> json) =>
      _$ProwlarrIndexerStatFromJson(json);
}
