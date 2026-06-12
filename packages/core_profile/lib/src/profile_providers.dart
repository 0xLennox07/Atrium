import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'profile_repository.dart';

/// Holds the [ProfileRepository]. Must be overridden in `main()` once Hive
/// boxes are open and secure storage is ready:
///
/// ```dart
/// ProviderScope(
///   overrides: [profileRepositoryProvider.overrideWithValue(repo)],
///   child: const AtriumApp(),
/// )
/// ```
final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>((Ref ref) {
  throw UnimplementedError(
    'profileRepositoryProvider must be overridden in main()',
  );
});

/// All profiles, async-loaded. Mutations go through this controller so the
/// rest of the app can watch a single source of truth.
final AsyncNotifierProvider<ProfileListController, List<Profile>>
    profileListProvider =
    AsyncNotifierProvider<ProfileListController, List<Profile>>(
  ProfileListController.new,
);

class ProfileListController extends AsyncNotifier<List<Profile>> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  Future<List<Profile>> build() => _repo.getProfiles();

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.getProfiles);
  }

  Future<Profile> createProfile(String name) async {
    final Profile profile = await _repo.createProfile(name);
    await _reload();
    return profile;
  }

  Future<void> deleteProfile(String id) async {
    await _repo.deleteProfile(id);
    await _reload();
  }

  Future<void> upsertInstance(String profileId, Instance instance) async {
    await _repo.upsertInstance(profileId, instance);
    await _reload();
  }

  Future<void> deleteInstance(String profileId, String instanceId) async {
    await _repo.deleteInstance(profileId, instanceId);
    await _reload();
  }

  Future<Profile> importProfile(String json) async {
    final Profile profile = await _repo.importProfile(json);
    await _reload();
    return profile;
  }
}

/// The id of the active profile (persisted). Null until a profile exists.
final NotifierProvider<ActiveProfileIdController, String?>
    activeProfileIdProvider =
    NotifierProvider<ActiveProfileIdController, String?>(
  ActiveProfileIdController.new,
);

class ActiveProfileIdController extends Notifier<String?> {
  @override
  String? build() => ref.read(profileRepositoryProvider).getActiveProfileId();

  Future<void> select(String? id) async {
    await ref.read(profileRepositoryProvider).setActiveProfileId(id);
    state = id;
  }
}

/// The resolved active [Profile]. Falls back to the first profile when the
/// stored active id is missing or stale.
final Provider<Profile?> activeProfileProvider = Provider<Profile?>((Ref ref) {
  final List<Profile> profiles =
      ref.watch(profileListProvider).value ?? const <Profile>[];
  if (profiles.isEmpty) {
    return null;
  }
  final String? activeId = ref.watch(activeProfileIdProvider);
  return profiles.firstWhereOrNull((Profile p) => p.id == activeId) ??
      profiles.first;
});

/// Instances belonging to the active profile.
final Provider<List<Instance>> activeInstancesProvider =
    Provider<List<Instance>>((Ref ref) {
  return ref.watch(activeProfileProvider)?.instances ?? const <Instance>[];
});

/// Active-profile instances of a particular [ServiceKind].
final ProviderFamily<List<Instance>, ServiceKind> instancesByKindProvider =
    Provider.family<List<Instance>, ServiceKind>((Ref ref, ServiceKind kind) {
  return ref
      .watch(activeInstancesProvider)
      .where((Instance i) => i.kind == kind)
      .toList();
});

/// A single active-profile instance by id, or null.
final ProviderFamily<Instance?, String> instanceByIdProvider =
    Provider.family<Instance?, String>((Ref ref, String id) {
  return ref
      .watch(activeInstancesProvider)
      .firstWhereOrNull((Instance i) => i.id == id);
});
