/// A release entry (search result) from `GET /api/v3/release`.
///
/// Deliberately NOT freezed: Sonarr's grab POST must receive the complete
/// release object back (our typed models are trimmed projections), so we keep
/// the raw map and expose only the fields the UI renders.
class SonarrRelease {
  SonarrRelease(this.raw);

  final Map<String, dynamic> raw;

  String get title => (raw['title'] as String?) ?? '';
  int get size => ((raw['size'] as num?) ?? 0).toInt();
  String? get indexer => raw['indexer'] as String?;
  int get indexerId => ((raw['indexerId'] as num?) ?? 0).toInt();
  int? get seeders => raw['seeders'] as int?;
  int? get leechers => raw['leechers'] as int?;
  int? get age => raw['age'] as int?;
  double? get ageHours => (raw['ageHours'] as num?)?.toDouble();
  double? get ageMinutes => (raw['ageMinutes'] as num?)?.toDouble();
  String? get protocol => raw['protocol'] as String?;
  bool get downloadAllowed => (raw['downloadAllowed'] as bool?) ?? false;
  bool get approved => (raw['approved'] as bool?) ?? false;

  List<String> get rejections {
    final List<dynamic>? list = raw['rejections'] as List<dynamic>?;
    if (list == null) return const [];
    return list.map((dynamic e) => e.toString()).toList();
  }

  bool get isTorrent => protocol?.toLowerCase() == 'torrent';

  String get ageLabel {
    final int? a = age;
    if (a != null && a > 0) return '${a}d';
    final double? h = ageHours;
    if (h != null && h >= 1.0) return '${h.toStringAsFixed(1)}h';
    final double? m = ageMinutes;
    if (m != null) return '${m.toStringAsFixed(0)}m';
    return 'new';
  }
}
