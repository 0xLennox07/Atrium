class SonarrHealth {
  const SonarrHealth({
    required this.source,
    required this.type,
    required this.message,
    this.wikiUrl,
  });

  factory SonarrHealth.fromJson(Map<String, dynamic> json) => SonarrHealth(
        source: (json['source'] as String?) ?? '',
        type: (json['type'] as String?) ?? '',
        message: (json['message'] as String?) ?? '',
        wikiUrl: json['wikiUrl'] as String?,
      );

  final String source;
  final String type;
  final String message;
  final String? wikiUrl;
}

class SonarrBackup {
  const SonarrBackup({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    required this.time,
  });

  factory SonarrBackup.fromJson(Map<String, dynamic> json) => SonarrBackup(
        id: ((json['id'] as num?) ?? 0).toInt(),
        name: (json['name'] as String?) ?? '',
        path: (json['path'] as String?) ?? '',
        type: (json['type'] as String?) ?? '',
        size: ((json['size'] as num?) ?? 0).toInt(),
        time: json['time'] != null ? DateTime.parse(json['time'] as String) : DateTime.now(),
      );

  final int id;
  final String name;
  final String path;
  final String type;
  final int size;
  final DateTime time;
}

class SonarrTag {
  const SonarrTag({
    required this.id,
    required this.label,
  });

  factory SonarrTag.fromJson(Map<String, dynamic> json) => SonarrTag(
        id: ((json['id'] as num?) ?? 0).toInt(),
        label: (json['label'] as String?) ?? '',
      );

  final int id;
  final String label;
}

class SonarrIndexer {
  const SonarrIndexer(this.raw);

  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get name => (raw['name'] as String?) ?? '';
  bool get enableRss => (raw['enableRss'] as bool?) ?? false;
  bool get enableAutomaticSearch => (raw['enableAutomaticSearch'] as bool?) ?? false;
  bool get enableInteractiveSearch => (raw['enableInteractiveSearch'] as bool?) ?? false;
  String get protocol => (raw['protocol'] as String?) ?? '';
}

class SonarrDownloadClient {
  const SonarrDownloadClient(this.raw);

  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get name => (raw['name'] as String?) ?? '';
  bool get enable => (raw['enable'] as bool?) ?? false;
  String get protocol => (raw['protocol'] as String?) ?? '';
}

class SonarrNotification {
  const SonarrNotification(this.raw);

  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get name => (raw['name'] as String?) ?? '';
  bool get onGrab => (raw['onGrab'] as bool?) ?? false;
  bool get onDownload => (raw['onDownload'] as bool?) ?? false;
  bool get onUpgrade => (raw['onUpgrade'] as bool?) ?? false;
}

class SonarrImportList {
  const SonarrImportList(this.raw);

  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get name => (raw['name'] as String?) ?? '';
  bool get enable => (raw['enable'] as bool?) ?? false;
}

class SonarrHostConfig {
  const SonarrHostConfig(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get bindAddress => (raw['bindAddress'] as String?) ?? '';
  int get port => ((raw['port'] as num?) ?? 8989).toInt();
  bool get enableSsl => (raw['enableSsl'] as bool?) ?? false;
  String get logLevel => (raw['logLevel'] as String?) ?? 'info';
  String get branch => (raw['branch'] as String?) ?? 'main';
  int get backupInterval => ((raw['backupInterval'] as num?) ?? 7).toInt();
  int get backupRetention => ((raw['backupRetention'] as num?) ?? 28).toInt();
}

class SonarrNamingConfig {
  const SonarrNamingConfig(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  bool get renameEpisodes => (raw['renameEpisodes'] as bool?) ?? false;
  String get standardEpisodeFormat => (raw['standardEpisodeFormat'] as String?) ?? '';
  String get dailyEpisodeFormat => (raw['dailyEpisodeFormat'] as String?) ?? '';
  String get animeEpisodeFormat => (raw['animeEpisodeFormat'] as String?) ?? '';
  String get seriesFolderFormat => (raw['seriesFolderFormat'] as String?) ?? '';
}

class SonarrMediaManagementConfig {
  const SonarrMediaManagementConfig(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  bool get autoUnmonitorPreviouslyDownloadedEpisodes => (raw['autoUnmonitorPreviouslyDownloadedEpisodes'] as bool?) ?? false;
  bool get recycleBin => raw['recycleBin'] != null && (raw['recycleBin'] as String).isNotEmpty;
  String get downloadPropersAndRepacks => (raw['downloadPropersAndRepacks'] as String?) ?? 'preferAndUpgrade';
  bool get createEmptySeriesFolders => (raw['createEmptySeriesFolders'] as bool?) ?? false;
  bool get deleteEmptyFolders => (raw['deleteEmptyFolders'] as bool?) ?? false;
  bool get copyUsingHardlinks => (raw['copyUsingHardlinks'] as bool?) ?? false;
}

class SonarrUiConfig {
  const SonarrUiConfig(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  int get firstDayOfWeek => ((raw['firstDayOfWeek'] as num?) ?? 0).toInt();
  String get theme => (raw['theme'] as String?) ?? 'dark';
  String get timeFormat => (raw['timeFormat'] as String?) ?? 'h:mm a';
}

class SonarrMetadataProvider {
  const SonarrMetadataProvider(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get name => (raw['name'] as String?) ?? '';
  bool get enable => (raw['enable'] as bool?) ?? false;
}

class SonarrDelayProfile {
  const SonarrDelayProfile(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  bool get enableUsenet => (raw['enableUsenet'] as bool?) ?? false;
  bool get enableTorrent => (raw['enableTorrent'] as bool?) ?? false;
  int get usenetDelay => ((raw['usenetDelay'] as num?) ?? 0).toInt();
  int get torrentDelay => ((raw['torrentDelay'] as num?) ?? 0).toInt();
  String get preferredProtocol => (raw['preferredProtocol'] as String?) ?? 'usenet';
}

class SonarrCustomFormat {
  const SonarrCustomFormat(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get name => (raw['name'] as String?) ?? '';
}

class SonarrQualityDefinition {
  const SonarrQualityDefinition(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get name => (raw['name'] as String?) ?? '';
  double get minSize => ((raw['minSize'] as num?) ?? 0.0).toDouble();
  double get maxSize => ((raw['maxSize'] as num?) ?? 0.0).toDouble();
  double get preferredSize => ((raw['preferredSize'] as num?) ?? 0.0).toDouble();
  Map<String, dynamic> get quality => (raw['quality'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
}

class SonarrReleaseProfile {
  const SonarrReleaseProfile(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get name => (raw['name'] as String?) ?? '';
  bool get enabled => (raw['enabled'] as bool?) ?? false;
  List<String> get requiredTerms => (raw['required'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [];
  List<String> get ignoredTerms => (raw['ignored'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [];
  List<Map<String, dynamic>> get preferredTerms => (raw['preferred'] as List<dynamic>?)
      ?.map((e) => Map<String, dynamic>.from(e as Map))
      .toList() ?? const [];
  List<int> get indexerIds => (raw['indexerIds'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [];
  List<int> get tags => (raw['tags'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [];
}

class SonarrImportListExclusion {
  const SonarrImportListExclusion(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get title => (raw['title'] as String?) ?? '';
  int get tvdbId => ((raw['tvdbId'] as num?) ?? 0).toInt();
}

class SonarrAutoTaggingRule {
  const SonarrAutoTaggingRule(this.raw);
  final Map<String, dynamic> raw;

  int get id => ((raw['id'] as num?) ?? 0).toInt();
  String get name => (raw['name'] as String?) ?? '';
  List<int> get tags => (raw['tags'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [];
  List<Map<String, dynamic>> get specifications => (raw['specifications'] as List<dynamic>?)
      ?.map((e) => Map<String, dynamic>.from(e as Map))
      .toList() ?? const [];
}

