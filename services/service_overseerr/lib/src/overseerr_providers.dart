import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/overseerr_request.dart';
import 'overseerr_api.dart';

/// An [OverseerrApi] for an instance, over the shared `instanceDioProvider`.
final overseerrApiProvider =
    FutureProvider.family<OverseerrApi, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final dio = await ref.watch(instanceDioProvider(instance).future);
      return OverseerrApi(dio);
    });

/// Recent media requests for an instance.
final overseerrRequestsProvider =
    FutureProvider.family<List<OverseerrRequest>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final OverseerrApi api =
          await ref.watch(overseerrApiProvider(instance).future);
      return api.getRequests();
    });
