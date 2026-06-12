import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/sab_queue.dart';
import 'sabnzbd_api.dart';

/// A [SabnzbdApi] for an instance, over the shared `instanceDioProvider`.
final sabnzbdApiProvider =
    FutureProvider.family<SabnzbdApi, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final dio = await ref.watch(instanceDioProvider(instance).future);
      return SabnzbdApi(dio);
    });

/// The current download queue for an instance.
final sabQueueProvider =
    FutureProvider.family<SabQueue, Instance>((Ref ref, Instance instance) async {
      final SabnzbdApi api = await ref.watch(sabnzbdApiProvider(instance).future);
      return api.getQueue();
    });
