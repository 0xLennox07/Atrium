import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/glances_stats.dart';

class GlancesApi {
  GlancesApi(this._dio);

  final Dio _dio;

  Future<GlancesStats> getStats() async {
    try {
      final List<Response<dynamic>> responses = await Future.wait(<Future<Response<dynamic>>>[
        _dio.get<dynamic>('api/4/cpu'),
        _dio.get<dynamic>('api/4/percpu'),
        _dio.get<dynamic>('api/4/core'),
        _dio.get<dynamic>('api/4/sensors'),
        _dio.get<dynamic>('api/4/mem'),
        _dio.get<dynamic>('api/4/memswap'),
        _dio.get<dynamic>('api/4/network'),
        _dio.get<dynamic>('api/4/fs'),
        _dio.get<dynamic>('api/4/uptime'),
      ]);

      final Map<String, dynamic> cpuData = responses[0].data as Map<String, dynamic>;
      final List<dynamic> perCpuData = responses[1].data as List<dynamic>;
      final Map<String, dynamic> coreData = responses[2].data as Map<String, dynamic>;
      final List<dynamic> sensorsData = responses[3].data as List<dynamic>;
      final Map<String, dynamic> memData = responses[4].data as Map<String, dynamic>;
      final Map<String, dynamic> swapData = responses[5].data as Map<String, dynamic>;
      final List<dynamic> networkData = responses[6].data as List<dynamic>;
      final List<dynamic> fsData = responses[7].data as List<dynamic>;
      final String uptimeStr = responses[8].data.toString();

      final int physCores = (coreData['phys'] as num?)?.toInt() ?? 0;
      final int logCores = (coreData['log'] as num?)?.toInt() ?? 0;
      final double cpuTotal = (cpuData['total'] as num?)?.toDouble() ?? 0.0;

      double packageTemp = 0.0;
      if (sensorsData.isNotEmpty) {
        final Iterable<dynamic> packageSensors = sensorsData.where(
          (dynamic s) => ((s as Map<String, dynamic>)['label'] as String).toLowerCase().contains('package'),
        );
        if (packageSensors.isNotEmpty) {
          packageTemp = ((packageSensors.first as Map<String, dynamic>)['value'] as num).toDouble();
        } else {
          final Iterable<dynamic> coreSensors = sensorsData.where(
            (dynamic s) => ((s as Map<String, dynamic>)['label'] as String).toLowerCase().contains('core'),
          );
          if (coreSensors.isNotEmpty) {
            double sum = 0;
            for (final dynamic s in coreSensors) {
              sum += ((s as Map<String, dynamic>)['value'] as num).toDouble();
            }
            packageTemp = sum / coreSensors.length;
          }
        }
      }

      final List<GlancesCpuCore> cores = perCpuData.map((dynamic c) {
        final Map<String, dynamic> cMap = c as Map<String, dynamic>;
        final int id = (cMap['cpu_number'] as num?)?.toInt() ?? 0;
        final double usage = (cMap['total'] as num?)?.toDouble() ?? 0.0;

        double coreTemp = 0.0;
        final Iterable<dynamic> coreSensor = sensorsData.where(
          (dynamic s) => ((s as Map<String, dynamic>)['label'] as String).toLowerCase() == 'core $id',
        );
        if (coreSensor.isNotEmpty) {
          coreTemp = ((coreSensor.first as Map<String, dynamic>)['value'] as num).toDouble();
        }

        return GlancesCpuCore(id: id, usage: usage, temp: coreTemp);
      }).toList();

      final GlancesMemory memory = GlancesMemory(
        percentage: (memData['percent'] as num?)?.toDouble() ?? 0.0,
        used: (memData['used'] as num?)?.toInt() ?? 0,
        total: (memData['total'] as num?)?.toInt() ?? 0,
      );

      final GlancesSwap swap = GlancesSwap(
        percentage: (swapData['percent'] as num?)?.toDouble() ?? 0.0,
        used: (swapData['used'] as num?)?.toInt() ?? 0,
        total: (swapData['total'] as num?)?.toInt() ?? 0,
      );

      final List<GlancesNetwork> network = networkData.map((dynamic n) {
        final Map<String, dynamic> map = n as Map<String, dynamic>;
        return GlancesNetwork(
          interface: map['interface_name'] as String? ?? 'Unknown',
          rxSpeed: (map['bytes_recv_rate_per_sec'] as num?)?.toInt() ?? 0,
          txSpeed: (map['bytes_sent_rate_per_sec'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      final List<GlancesDisk> disks = fsData.map((dynamic d) {
        final Map<String, dynamic> map = d as Map<String, dynamic>;
        return GlancesDisk(
          path: map['mnt_point'] as String? ?? 'Unknown',
          percentage: (map['percent'] as num?)?.toDouble() ?? 0.0,
          used: (map['used'] as num?)?.toInt() ?? 0,
          total: (map['size'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      final RegExp uptimeRegex = RegExp(r'(?:(?<days>[0-9]+) days?, )?(?<hours>[0-9]+):(?<minutes>[0-9]+):(?<seconds>[0-9]+)');
      final RegExpMatch? match = uptimeRegex.firstMatch(uptimeStr);
      int days = 0;
      int hours = 0;
      int minutes = 0;
      int seconds = 0;
      if (match != null) {
        days = int.tryParse(match.namedGroup('days') ?? '0') ?? 0;
        hours = int.tryParse(match.namedGroup('hours') ?? '0') ?? 0;
        minutes = int.tryParse(match.namedGroup('minutes') ?? '0') ?? 0;
        seconds = int.tryParse(match.namedGroup('seconds') ?? '0') ?? 0;
      }
      final int totalSeconds = (days * 86400) + (hours * 3600) + (minutes * 60) + seconds;

      final GlancesUptime uptime = GlancesUptime(
        days: days,
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        totalSeconds: totalSeconds,
      );

      return GlancesStats(
        cpu: GlancesCpu(
          physicalCores: physCores,
          logicalCores: logCores,
          totalUsage: cpuTotal,
          packageTemp: packageTemp,
          cores: cores,
        ),
        memory: memory,
        swap: swap,
        network: network,
        disks: disks,
        uptime: uptime,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }
}
