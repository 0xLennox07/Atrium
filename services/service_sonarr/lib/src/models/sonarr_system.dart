import 'package:freezed_annotation/freezed_annotation.dart';

part 'sonarr_system.freezed.dart';
part 'sonarr_system.g.dart';

@freezed
abstract class SonarrSystemStatus with _$SonarrSystemStatus {
  const factory SonarrSystemStatus({
    required String version,
    required String appName,
    required String osName,
    required String osVersion,
    required bool isDocker,
    required bool isLinux,
    required bool isWindows,
    required bool isOsx,
    String? databaseType,
    String? databaseVersion,
    String? runtimeVersion,
    String? runtimeName,
  }) = _SonarrSystemStatus;

  factory SonarrSystemStatus.fromJson(Map<String, dynamic> json) =>
      _$SonarrSystemStatusFromJson(json);
}

@freezed
abstract class SonarrDiskSpace with _$SonarrDiskSpace {
  const factory SonarrDiskSpace({
    required String path,
    required String label,
    required int freeSpace,
    required int totalSpace,
  }) = _SonarrDiskSpace;

  factory SonarrDiskSpace.fromJson(Map<String, dynamic> json) =>
      _$SonarrDiskSpaceFromJson(json);
}

@freezed
abstract class SonarrSystemTask with _$SonarrSystemTask {
  const factory SonarrSystemTask({
    required int id,
    required String name,
    required String taskName,
    required int interval,
    DateTime? lastExecution,
    DateTime? lastStartTime,
    DateTime? nextExecution,
    String? lastDuration,
  }) = _SonarrSystemTask;

  factory SonarrSystemTask.fromJson(Map<String, dynamic> json) =>
      _$SonarrSystemTaskFromJson(json);
}
