import 'package:freezed_annotation/freezed_annotation.dart';

part 'qbit_transfer_info.freezed.dart';
part 'qbit_transfer_info.g.dart';

/// Global transfer stats from `GET /api/v2/transfer/info`.
@freezed
abstract class QbitTransferInfo with _$QbitTransferInfo {
  const factory QbitTransferInfo({
    /// Global download speed, bytes/s.
    @JsonKey(name: 'dl_info_speed') @Default(0) int dlSpeed,
    /// Global upload speed, bytes/s.
    @JsonKey(name: 'up_info_speed') @Default(0) int upSpeed,
    /// Bytes downloaded this session.
    @JsonKey(name: 'dl_info_data') @Default(0) int dlData,
    /// Bytes uploaded this session.
    @JsonKey(name: 'up_info_data') @Default(0) int upData,
    /// connected / firewalled / disconnected.
    @JsonKey(name: 'connection_status') @Default('disconnected')
    String connectionStatus,
  }) = _QbitTransferInfo;

  factory QbitTransferInfo.fromJson(Map<String, dynamic> json) =>
      _$QbitTransferInfoFromJson(json);
}
