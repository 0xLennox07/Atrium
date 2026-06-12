import 'package:freezed_annotation/freezed_annotation.dart';

part 'overseerr_request.freezed.dart';
part 'overseerr_request.g.dart';

/// `GET /api/v1/request` → `{ "pageInfo": {…}, "results": [ … ] }`.
@freezed
abstract class OverseerrRequestPage with _$OverseerrRequestPage {
  const factory OverseerrRequestPage({
    @Default(<OverseerrRequest>[]) List<OverseerrRequest> results,
  }) = _OverseerrRequestPage;

  factory OverseerrRequestPage.fromJson(Map<String, dynamic> json) =>
      _$OverseerrRequestPageFromJson(json);
}

/// A media request.
///
/// `status`: 1 = pending approval, 2 = approved, 3 = declined.
@freezed
abstract class OverseerrRequest with _$OverseerrRequest {
  const factory OverseerrRequest({
    required int id,
    @Default(1) int status,
    /// 'movie' or 'tv'.
    @Default('') String type,
    OverseerrMedia? media,
    OverseerrUser? requestedBy,
    String? createdAt,
  }) = _OverseerrRequest;

  factory OverseerrRequest.fromJson(Map<String, dynamic> json) =>
      _$OverseerrRequestFromJson(json);
}

/// The media a request targets.
///
/// `status`: 1 unknown, 2 pending, 3 processing, 4 partially available,
/// 5 available.
@freezed
abstract class OverseerrMedia with _$OverseerrMedia {
  const factory OverseerrMedia({
    @Default('') String mediaType,
    int? tmdbId,
    @Default(1) int status,
  }) = _OverseerrMedia;

  factory OverseerrMedia.fromJson(Map<String, dynamic> json) =>
      _$OverseerrMediaFromJson(json);
}

@freezed
abstract class OverseerrUser with _$OverseerrUser {
  const factory OverseerrUser({
    @Default('') String displayName,
    @Default('') String username,
  }) = _OverseerrUser;

  factory OverseerrUser.fromJson(Map<String, dynamic> json) =>
      _$OverseerrUserFromJson(json);
}
