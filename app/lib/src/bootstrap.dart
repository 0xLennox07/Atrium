import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'preferences.dart';

/// Initializes storage and networking, then returns the Riverpod overrides the
/// root [ProviderScope] needs. Call once from `main()` before `runApp`.
Future<List<Override>> bootstrap() async {
  await initAtriumHive();
  final List<Box<String>> boxes = await Future.wait(<Future<Box<String>>>[
    Hive.openBox<String>(AtriumBoxes.settings),
    Hive.openBox<String>(AtriumBoxes.profiles),
  ]);
  final Box<String> settingsBox = boxes[0];
  final Box<String> profilesBox = boxes[1];

  final AtriumSecureStorage secrets = AtriumSecureStorage();
  final ProfileRepository repo = ProfileRepository(
    profilesBox: profilesBox,
    settingsBox: settingsBox,
    secrets: secrets,
  );

  final ConnectionResolver resolver =
      ConnectionResolver(connectivity: Connectivity());
  await resolver.start();

  return <Override>[
    settingsBoxProvider.overrideWithValue(settingsBox),
    profileRepositoryProvider.overrideWithValue(repo),
    connectionResolverProvider.overrideWithValue(resolver),
  ];
}
