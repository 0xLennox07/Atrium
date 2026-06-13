import 'package:freezed_annotation/freezed_annotation.dart';

part 'glances_stats.freezed.dart';
part 'glances_stats.g.dart';

@freezed
class GlancesStats with _$GlancesStats {
  const factory GlancesStats({
    required GlancesCpu cpu,
    required GlancesMemory memory,
    required GlancesSwap swap,
    required List<GlancesNetwork> network,
    required List<GlancesDisk> disks,
    required GlancesUptime uptime,
  }) = _GlancesStats;

  factory GlancesStats.fromJson(Map<String, dynamic> json) =>
      _$GlancesStatsFromJson(json);
}

@freezed
class GlancesCpu with _$GlancesCpu {
  const factory GlancesCpu({
    required int physicalCores,
    required int logicalCores,
    required double totalUsage,
    required double packageTemp,
    required List<GlancesCpuCore> cores,
  }) = _GlancesCpu;

  factory GlancesCpu.fromJson(Map<String, dynamic> json) =>
      _$GlancesCpuFromJson(json);
}

@freezed
class GlancesCpuCore with _$GlancesCpuCore {
  const factory GlancesCpuCore({
    required int id,
    required double usage,
    required double temp,
  }) = _GlancesCpuCore;

  factory GlancesCpuCore.fromJson(Map<String, dynamic> json) =>
      _$GlancesCpuCoreFromJson(json);
}

@freezed
class GlancesUptime with _$GlancesUptime {
  const factory GlancesUptime({
    required int days,
    required int hours,
    required int minutes,
    required int seconds,
    required int totalSeconds,
  }) = _GlancesUptime;

  factory GlancesUptime.fromJson(Map<String, dynamic> json) =>
      _$GlancesUptimeFromJson(json);
}

@freezed
class GlancesMemory with _$GlancesMemory {
  const factory GlancesMemory({
    required double percentage,
    required int used,
    required int total,
  }) = _GlancesMemory;

  factory GlancesMemory.fromJson(Map<String, dynamic> json) =>
      _$GlancesMemoryFromJson(json);
}

@freezed
class GlancesSwap with _$GlancesSwap {
  const factory GlancesSwap({
    required double percentage,
    required int used,
    required int total,
  }) = _GlancesSwap;

  factory GlancesSwap.fromJson(Map<String, dynamic> json) =>
      _$GlancesSwapFromJson(json);
}

@freezed
class GlancesNetwork with _$GlancesNetwork {
  const factory GlancesNetwork({
    required String interface,
    required int rxSpeed,
    required int txSpeed,
  }) = _GlancesNetwork;

  factory GlancesNetwork.fromJson(Map<String, dynamic> json) =>
      _$GlancesNetworkFromJson(json);
}

@freezed
class GlancesDisk with _$GlancesDisk {
  const factory GlancesDisk({
    required String path,
    required double percentage,
    required int used,
    required int total,
  }) = _GlancesDisk;

  factory GlancesDisk.fromJson(Map<String, dynamic> json) =>
      _$GlancesDiskFromJson(json);
}
