import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../generated/generated.dart';
import '../../lidarr_artwork.dart';
import '../../lidarr_providers.dart';
import 'edit_artist_sheet.dart';

/// Opens the dedicated M3 modal bottom sheet for inspecting an artist's
/// metadata, biography, system paths, and curated external links.
void showLidarrArtistInfoSheet(
  BuildContext context, {
  required Instance instance,
  required ArtistResource? artist,
  required WidgetRef ref,
}) {
  if (artist == null) return;

  final ThemeData theme = Theme.of(context);
  final ColorScheme cs = theme.colorScheme;

  final qualityProfilesAsync =
      ref.watch(lidarrQualityProfilesProvider(instance));
  final metadataProfilesAsync =
      ref.watch(lidarrMetadataProfilesProvider(instance));

  final String qualityName = qualityProfilesAsync.value
          ?.firstWhere(
            (p) => p.id == artist.qualityProfileId,
            orElse: () => const QualityProfileResource(name: 'Standard'),
          )
          .name ??
      'Profile ${artist.qualityProfileId ?? 1}';

  final String metadataName = metadataProfilesAsync.value
          ?.firstWhere(
            (p) => p.id == artist.metadataProfileId,
            orElse: () => const MetadataProfileResource(name: 'Standard'),
          )
          .name ??
      'Standard';

  final String? posterUrl =
      LidarrArtwork.artistPosterUrl(instance, artist.images);

  // Group and format external links
  final List<Links> rawLinks = artist.links ?? [];
  final Map<String, Links> uniqueLinks = {};
  for (final link in rawLinks) {
    final url = link.url;
    if (url != null && url.isNotEmpty) {
      uniqueLinks.putIfAbsent(url.toLowerCase().trim(), () => link);
    }
  }

  final List<Links> streamingLinks = [];
  final List<Links> databaseLinks = [];
  final List<Links> webSocialLinks = [];

  final Set<String> seenStreamingNames = <String>{};
  final Set<String> seenDatabaseNames = <String>{};

  for (final link in uniqueLinks.values) {
    final name = (link.name ?? '').toLowerCase();
    final url = (link.url ?? '').toLowerCase();

    if (name.contains('spotify') ||
        name.contains('apple') ||
        name.contains('deezer') ||
        name.contains('amazon') ||
        name.contains('youtube') ||
        name.contains('soundcloud') ||
        name.contains('bandcamp') ||
        name.contains('tidal') ||
        url.contains('spotify.com') ||
        url.contains('music.apple.com') ||
        url.contains('deezer.com') ||
        url.contains('youtube.com') ||
        url.contains('soundcloud.com') ||
        url.contains('bandcamp.com')) {
      final serviceKey = _getNormalizedServiceName(name, url);
      if (!seenStreamingNames.contains(serviceKey)) {
        seenStreamingNames.add(serviceKey);
        streamingLinks.add(link);
      }
    } else if (name.contains('musicbrainz') ||
        name.contains('discogs') ||
        name.contains('allmusic') ||
        name.contains('last') ||
        name.contains('wikidata') ||
        name.contains('vgmdb') ||
        name.contains('rateyourmusic') ||
        name.contains('metal-archives') ||
        name.contains('imdb') ||
        url.contains('discogs.com') ||
        url.contains('allmusic.com') ||
        url.contains('last.fm') ||
        url.contains('wikidata.org')) {
      final serviceKey = _getNormalizedServiceName(name, url);
      if (!seenDatabaseNames.contains(serviceKey)) {
        seenDatabaseNames.add(serviceKey);
        databaseLinks.add(link);
      }
    } else {
      webSocialLinks.add(link);
    }
  }

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artist Avatar + Name + Genres
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: posterUrl != null
                          ? AtriumNetworkImage(
                              imageUrl: posterUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  const Icon(Icons.person, size: 32),
                            )
                          : Container(
                              color: cs.surfaceContainerHighest,
                              child: const Icon(Icons.person, size: 32),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artist.artistName ?? 'Artist',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (artist.disambiguation != null &&
                            artist.disambiguation!.isNotEmpty)
                          Text(
                            '(${artist.disambiguation!})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (artist.genres != null && artist.genres!.isNotEmpty)
                          Text(
                            artist.genres!.join(', '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Configuration & Profiles
              Text(
                'Configuration & Library',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.high_quality, size: 16),
                    label: Text('Quality: $qualityName'),
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    avatar: const Icon(Icons.library_music, size: 16),
                    label: Text('Metadata: $metadataName'),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (artist.status != null)
                    Chip(
                      avatar: Icon(
                        artist.status == ArtistStatusType.ended
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline,
                        size: 16,
                      ),
                      label: Text(artist.status!.name.toUpperCase()),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (artist.path != null && artist.path!.isNotEmpty) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Disk Path'),
                  subtitle: Text(
                    artist.path!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit Artist Settings'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    LidarrEditArtistSheet.show(
                      context,
                      instance: instance,
                      artist: artist,
                    );
                  },
                ),
              ),

              // Biography / Overview
              if (artist.overview != null && artist.overview!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Biography',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 6),
                OverviewBox(overview: artist.overview!),
              ],

              // External Links
              if (rawLinks.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'External Services & Databases',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 8),

                // Streaming Services
                if (streamingLinks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Text(
                      'Streaming & Media',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: streamingLinks
                        .map((link) => _buildLinkChip(context, link))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                // Databases & Discography
                if (databaseLinks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Text(
                      'Databases & Discography',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: databaseLinks
                        .map((link) => _buildLinkChip(context, link))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                // Web & Social
                if (webSocialLinks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Text(
                      'Web & Social',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: webSocialLinks
                        .map((link) => _buildLinkChip(context, link))
                        .toList(),
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}

String _getNormalizedServiceName(String rawName, String url) {
  final lowerName = rawName.toLowerCase();
  final lowerUrl = url.toLowerCase();
  if (lowerName.contains('spotify') || lowerUrl.contains('spotify.com')) {
    return 'Spotify';
  }
  if (lowerName.contains('apple') ||
      lowerUrl.contains('music.apple.com') ||
      lowerUrl.contains('itunes.apple.com')) {
    return 'Apple Music';
  }
  if (lowerName.contains('deezer') || lowerUrl.contains('deezer.com')) {
    return 'Deezer';
  }
  if (lowerName.contains('tidal') || lowerUrl.contains('tidal.com')) {
    return 'Tidal';
  }
  if (lowerName.contains('youtube') ||
      lowerUrl.contains('youtube.com') ||
      lowerUrl.contains('youtu.be')) {
    return 'YouTube';
  }
  if (lowerName.contains('soundcloud') || lowerUrl.contains('soundcloud.com')) {
    return 'SoundCloud';
  }
  if (lowerName.contains('bandcamp') || lowerUrl.contains('bandcamp.com')) {
    return 'Bandcamp';
  }
  if (lowerName.contains('amazon') || lowerUrl.contains('amazon.')) {
    return 'Amazon Music';
  }
  if (lowerName.contains('musicbrainz') ||
      lowerUrl.contains('musicbrainz.org')) {
    return 'MusicBrainz';
  }
  if (lowerName.contains('discogs') || lowerUrl.contains('discogs.com')) {
    return 'Discogs';
  }
  if (lowerName.contains('last') || lowerUrl.contains('last.fm')) {
    return 'Last.fm';
  }
  if (lowerName.contains('allmusic') || lowerUrl.contains('allmusic.com')) {
    return 'AllMusic';
  }
  if (lowerName.contains('wikidata') || lowerUrl.contains('wikidata.org')) {
    return 'Wikidata';
  }
  if (lowerName.contains('rateyourmusic') ||
      lowerUrl.contains('rateyourmusic.com')) {
    return 'RateYourMusic';
  }
  if (lowerName.contains('vgmdb') || lowerUrl.contains('vgmdb.net')) {
    return 'VGMdb';
  }
  if (lowerName.contains('imdb') || lowerUrl.contains('imdb.com')) {
    return 'IMDb';
  }
  if (lowerName.contains('twitter') ||
      lowerUrl.contains('twitter.com') ||
      lowerUrl.contains('x.com')) {
    return 'X / Twitter';
  }
  if (lowerName.contains('instagram') || lowerUrl.contains('instagram.com')) {
    return 'Instagram';
  }
  if (lowerName.contains('facebook') || lowerUrl.contains('facebook.com')) {
    return 'Facebook';
  }
  if (rawName.isEmpty) {
    return 'Website';
  }

  return rawName
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

Widget _buildLinkChip(BuildContext context, Links link) {
  final String rawName = link.name ?? 'Link';
  final String url = link.url ?? '';
  final String displayName = _getNormalizedServiceName(rawName, url);

  IconData icon = Icons.open_in_new;
  final lowerName = displayName.toLowerCase();
  if (lowerName.contains('spotify') ||
      lowerName.contains('apple') ||
      lowerName.contains('deezer') ||
      lowerName.contains('tidal') ||
      lowerName.contains('soundcloud') ||
      lowerName.contains('bandcamp') ||
      lowerName.contains('amazon')) {
    icon = Icons.headphones_outlined;
  } else if (lowerName.contains('youtube')) {
    icon = Icons.smart_display_outlined;
  } else if (lowerName.contains('discogs') ||
      lowerName.contains('musicbrainz') ||
      lowerName.contains('allmusic') ||
      lowerName.contains('vgmdb')) {
    icon = Icons.album_outlined;
  }

  return ActionChip(
    avatar: Icon(icon, size: 15),
    label: Text(displayName),
    visualDensity: VisualDensity.compact,
    onPressed: url.isNotEmpty
        ? () async {
            final Uri? uri = Uri.tryParse(url);
            if (uri != null &&
                uri.hasScheme &&
                (uri.scheme == 'http' || uri.scheme == 'https')) {
              if (await canLaunchUrl(uri)) {
                await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              }
            }
          }
        : null,
  );
}
