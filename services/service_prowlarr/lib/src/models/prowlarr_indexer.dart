import 'package:freezed_annotation/freezed_annotation.dart';

part 'prowlarr_indexer.freezed.dart';
part 'prowlarr_indexer.g.dart';

/// A Prowlarr indexer as returned by `GET /api/v1/indexer`.
///
/// Only the fields Atrium renders are modeled; Prowlarr returns many more.
@freezed
abstract class ProwlarrIndexer with _$ProwlarrIndexer {
  const factory ProwlarrIndexer({
    required int id,
    required String name,
    @Default(false) bool enable,
    String? protocol,
    String? privacy,
    @Default(0) int priority,
    // Tag IDs, not names - the *arr APIs return tags as integers.
    @Default(<int>[]) List<int> tags,
    String? sortName,
  }) = _ProwlarrIndexer;

  factory ProwlarrIndexer.fromJson(Map<String, dynamic> json) =>
      _$ProwlarrIndexerFromJson(json);
}
