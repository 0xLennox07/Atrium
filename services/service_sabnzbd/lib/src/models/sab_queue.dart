import 'package:freezed_annotation/freezed_annotation.dart';

part 'sab_queue.freezed.dart';
part 'sab_queue.g.dart';

/// `GET /api?mode=queue&output=json` → `{ "queue": { … } }`.
///
/// SABnzbd returns nearly everything as strings (e.g. `"percentage": "45"`),
/// so the numeric-looking fields are typed `String` and parsed at the UI.
@freezed
abstract class SabQueueResponse with _$SabQueueResponse {
  const factory SabQueueResponse({SabQueue? queue}) = _SabQueueResponse;

  factory SabQueueResponse.fromJson(Map<String, dynamic> json) =>
      _$SabQueueResponseFromJson(json);
}

@freezed
abstract class SabQueue with _$SabQueue {
  const factory SabQueue({
    @Default('') String status,
    /// Human speed string, e.g. "1.2 M".
    @Default('') String speed,
    @Default('') String sizeleft,
    @Default('') String timeleft,
    @Default('') String mbleft,
    @Default('') String mb,
    @Default(<SabSlot>[]) List<SabSlot> slots,
  }) = _SabQueue;

  factory SabQueue.fromJson(Map<String, dynamic> json) =>
      _$SabQueueFromJson(json);
}

@freezed
abstract class SabSlot with _$SabSlot {
  const factory SabSlot({
    @JsonKey(name: 'nzo_id') @Default('') String nzoId,
    @Default('') String filename,
    @Default('') String percentage,
    @Default('') String mb,
    @Default('') String mbleft,
    @Default('') String timeleft,
    @Default('') String status,
    @Default('') String cat,
  }) = _SabSlot;

  factory SabSlot.fromJson(Map<String, dynamic> json) =>
      _$SabSlotFromJson(json);
}
