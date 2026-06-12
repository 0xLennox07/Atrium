import 'package:freezed_annotation/freezed_annotation.dart';

part 'sonarr_calendar.freezed.dart';
part 'sonarr_calendar.g.dart';

/// A calendar entry (an episode airing) from `GET /api/v3/calendar`.
@freezed
abstract class SonarrCalendarEntry with _$SonarrCalendarEntry {
  const factory SonarrCalendarEntry({
    required int id,
    required int seriesId,
    String? title,
    int? seasonNumber,
    int? episodeNumber,
    String? airDate,
    DateTime? airDateUtc,
    @Default(false) bool hasFile,
    @Default(false) bool monitored,
  }) = _SonarrCalendarEntry;

  factory SonarrCalendarEntry.fromJson(Map<String, dynamic> json) =>
      _$SonarrCalendarEntryFromJson(json);
}
