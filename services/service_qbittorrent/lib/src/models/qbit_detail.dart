import 'package:freezed_annotation/freezed_annotation.dart';

part 'qbit_detail.freezed.dart';
part 'qbit_detail.g.dart';

/// Detailed torrent properties from `GET /api/v2/torrents/properties`.
///
/// Only the fields the detail screen renders are modeled.
@freezed
abstract class QbitTorrentProperties with _$QbitTorrentProperties {
  const factory QbitTorrentProperties({
    @JsonKey(name: 'save_path') @Default('') String savePath,
    @JsonKey(name: 'creation_date') @Default(0) int creationDate,
    @JsonKey(name: 'addition_date') @Default(0) int additionDate,
    @JsonKey(name: 'completion_date') @Default(-1) int completionDate,
    @JsonKey(name: 'total_size') @Default(0) int totalSize,
    @JsonKey(name: 'total_downloaded') @Default(0) int totalDownloaded,
    @JsonKey(name: 'total_uploaded') @Default(0) int totalUploaded,
    @JsonKey(name: 'share_ratio') @Default(0) double shareRatio,
    @JsonKey(name: 'dl_speed') @Default(0) int dlSpeed,
    @JsonKey(name: 'up_speed') @Default(0) int upSpeed,
    @JsonKey(name: 'seeds_total') @Default(0) int seedsTotal,
    @JsonKey(name: 'peers_total') @Default(0) int peersTotal,
    @Default(0) int seeds,
    @Default(0) int peers,
    @JsonKey(name: 'time_elapsed') @Default(0) int timeElapsed,
    @JsonKey(name: 'seeding_time') @Default(0) int seedingTime,
    @JsonKey(name: 'nb_connections') @Default(0) int nbConnections,
    @JsonKey(name: 'pieces_num') @Default(0) int piecesNum,
    @JsonKey(name: 'pieces_have') @Default(0) int piecesHave,
    @JsonKey(name: 'piece_size') @Default(0) int pieceSize,
    @Default('') String comment,
  }) = _QbitTorrentProperties;

  factory QbitTorrentProperties.fromJson(Map<String, dynamic> json) =>
      _$QbitTorrentPropertiesFromJson(json);
}

/// One file inside a torrent, from `GET /api/v2/torrents/files`.
@freezed
abstract class QbitFile with _$QbitFile {
  const factory QbitFile({
    /// File index used by `/torrents/filePrio`.
    @Default(0) int index,
    @Default('') String name,
    @Default(0) int size,
    /// 0.0 - 1.0.
    @Default(0) double progress,
    /// 0 = skip, 1 = normal, 6 = high, 7 = maximal.
    @Default(1) int priority,
  }) = _QbitFile;

  factory QbitFile.fromJson(Map<String, dynamic> json) =>
      _$QbitFileFromJson(json);
}

/// One tracker row from `GET /api/v2/torrents/trackers`.
///
/// qBittorrent also returns synthetic rows (`** [DHT] **`, `** [PeX] **`,
/// `** [LSD] **`) - keep or filter at the UI layer.
@freezed
abstract class QbitTracker with _$QbitTracker {
  const factory QbitTracker({
    @Default('') String url,
    /// 0 disabled, 1 not-contacted, 2 working, 3 updating, 4 not-working.
    @Default(0) int status,
    @JsonKey(name: 'num_seeds') @Default(-1) int numSeeds,
    @JsonKey(name: 'num_peers') @Default(-1) int numPeers,
    @JsonKey(name: 'num_leeches') @Default(-1) int numLeeches,
    @Default('') String msg,
  }) = _QbitTracker;

  factory QbitTracker.fromJson(Map<String, dynamic> json) =>
      _$QbitTrackerFromJson(json);
}
