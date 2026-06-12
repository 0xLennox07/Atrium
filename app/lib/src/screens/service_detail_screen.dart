import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:service_bazarr/service_bazarr.dart';
import 'package:service_emby/service_emby.dart';
import 'package:service_jellyfin/service_jellyfin.dart';
import 'package:service_overseerr/service_overseerr.dart';
import 'package:service_plex/service_plex.dart';
import 'package:service_prowlarr/service_prowlarr.dart';
import 'package:service_qbittorrent/service_qbittorrent.dart';
import 'package:service_radarr/service_radarr.dart';
import 'package:service_sabnzbd/service_sabnzbd.dart';
import 'package:service_sonarr/service_sonarr.dart';
import 'package:service_tautulli/service_tautulli.dart';

/// Routes an instance to its service-specific screen, dispatching on
/// [ServiceKind]. The switch is exhaustive - every service has a UI module.
class ServiceDetailScreen extends ConsumerWidget {
  const ServiceDetailScreen({
    required this.kindName,
    required this.instanceId,
    super.key,
  });

  final String kindName;
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Instance? instance = ref.watch(instanceByIdProvider(instanceId));
    if (instance == null) {
      return const _NotFound();
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(instance.name),
        actions: <Widget>[
          if (instance.kind == ServiceKind.emby || instance.kind == ServiceKind.jellyfin)
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: () {
                showSearch<void>(
                  context: context,
                  delegate: instance.kind == ServiceKind.emby 
                    ? EmbySearchDelegate(instance: instance)
                    : JellyfinSearchDelegate(instance: instance) as SearchDelegate<void>,
                );
              },
            ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.goNamed(
              'edit-instance',
              pathParameters: <String, String>{'instanceId': instance.id},
            ),
          ),
        ],
      ),
      body: _bodyFor(instance),
    );
  }

  Widget _bodyFor(Instance instance) {
    return switch (instance.kind) {
      ServiceKind.sonarr => SonarrHome(instance: instance),
      ServiceKind.radarr => RadarrHome(instance: instance),
      ServiceKind.prowlarr => ProwlarrHome(instance: instance),
      ServiceKind.bazarr => BazarrHome(instance: instance),
      ServiceKind.overseerr => OverseerrHome(instance: instance),
      ServiceKind.tautulli => TautulliHome(instance: instance),
      ServiceKind.jellyfin => JellyfinHome(instance: instance),
      ServiceKind.emby => EmbyHome(instance: instance),
      ServiceKind.plex => PlexHome(instance: instance),
      ServiceKind.qbittorrent => QbittorrentHome(instance: instance),
      ServiceKind.sabnzbd => SabnzbdHome(instance: instance),
    };
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const ErrorView(
        title: 'Service not found',
        message: 'This instance may have been deleted.',
      ),
    );
  }
}
