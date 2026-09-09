import 'package:cached_network_image/cached_network_image.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'emby_client.dart';
import 'emby_providers.dart';
import 'models/emby_item.dart';
import 'models/emby_remote_image.dart';

class EmbyRemoteImagesScreen extends ConsumerStatefulWidget {
  const EmbyRemoteImagesScreen({
    required this.instance,
    required this.itemId,
    this.imageType = 'Primary',
    super.key,
  });

  final Instance instance;
  final String itemId;
  final String imageType;

  @override
  ConsumerState<EmbyRemoteImagesScreen> createState() =>
      _EmbyRemoteImagesScreenState();
}

class _EmbyRemoteImagesScreenState
    extends ConsumerState<EmbyRemoteImagesScreen> {
  bool _isSaving = false;

  /// Server-supplied remote image URLs must be absolute https URLs before we
  /// render them or echo them back to the server.
  bool _isValidRemoteImageUrl(String? u) {
    if (u == null) return false;
    final Uri? uri = Uri.tryParse(u);
    return uri != null && uri.scheme == 'https' && uri.hasAuthority;
  }

  Future<void> _confirmAndSet(String imageUrl) async {
    final bool needsConfirm =
        widget.imageType == 'Primary' || widget.imageType == 'Banner';
    if (needsConfirm) {
      final bool confirmed = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: Text('Replace ${widget.imageType.toLowerCase()}?'),
              content: Text(
                'This replaces the current ${widget.imageType.toLowerCase()} '
                'image and cannot be undone.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Replace'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    await _setImage(imageUrl);
  }

  Future<void> _setImage(String imageUrl) async {
    if (_isSaving) return;
    if (!_isValidRemoteImageUrl(imageUrl)) return;
    setState(() => _isSaving = true);
    try {
      final EmbyClient client =
          await ref.read(embyClientProvider(widget.instance).future);
      if (!mounted) return;
      final EmbyItem? oldItem = ref
          .read(embyItemDetailsProvider((widget.instance, widget.itemId)))
          .value;
      String? oldTaggedUrl;
      if (oldItem != null) {
        if (widget.imageType == 'Backdrop') {
          oldTaggedUrl = client.backdropImageUrl(oldItem);
        } else if (widget.imageType == 'Primary') {
          oldTaggedUrl = client.imageUrl(oldItem);
        } else if (widget.imageType == 'Banner') {
          oldTaggedUrl = client.bannerImageUrl(oldItem);
        }
      }

      await client.setRemoteImage(widget.itemId, imageUrl, widget.imageType);

      // Evict untagged URL from cache for sessions that don't use tags
      final String untaggedUrl =
          client.untaggedImageUrl(widget.itemId, widget.imageType);
      await CachedNetworkImage.evictFromCache(untaggedUrl);

      if (oldTaggedUrl != null) {
        await CachedNetworkImage.evictFromCache(oldTaggedUrl);
      }

      // Give the server time to download and apply the new image.
      // We poll until the tag actually changes, or time out after ~5 seconds.
      // The write already succeeded, so a transient poll error must not be
      // surfaced as a failure - fall through and refresh regardless.
      try {
        int attempts = 0;
        while (attempts < 10) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          final EmbyItem updatedItem =
              await client.getItemDetails(widget.itemId);
          String? newTaggedUrl;
          if (widget.imageType == 'Backdrop') {
            newTaggedUrl = client.backdropImageUrl(updatedItem);
          } else if (widget.imageType == 'Primary') {
            newTaggedUrl = client.imageUrl(updatedItem);
          } else if (widget.imageType == 'Banner') {
            newTaggedUrl = client.bannerImageUrl(updatedItem);
          }

          if (newTaggedUrl != oldTaggedUrl) {
            break; // The tag has successfully changed!
          }
          attempts++;
        }
      } catch (_) {
        // Best-effort wait only; the write already succeeded.
      }

      if (!mounted) return;

      // Invalidate relevant providers to force refresh of the image
      ref.invalidate(embyItemDetailsProvider((widget.instance, widget.itemId)));
      ref.invalidate(embyItemsProvider);
      ref.invalidate(embyLibraryItemsProvider);
      ref.invalidate(embyFastSessionsProvider(widget.instance));
      ref.invalidate(embySessionsProvider(widget.instance));

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.imageType} updated'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          showCloseIcon: true,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Failed to update ${widget.imageType.toLowerCase()}: $e'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          showCloseIcon: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<EmbyRemoteImage>> imagesAsync = ref.watch(
      embyRemoteImagesProvider(
        (widget.instance, widget.itemId, widget.imageType),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Select ${widget.imageType}'),
      ),
      body: Stack(
        children: <Widget>[
          AsyncValueView<List<EmbyRemoteImage>>(
            value: imagesAsync,
            onRetry: () => ref.invalidate(
              embyRemoteImagesProvider(
                (widget.instance, widget.itemId, widget.imageType),
              ),
            ),
            data: (List<EmbyRemoteImage> images) {
              if (images.isEmpty) {
                return const Center(child: Text('No alternate images found.'));
              }
              return GridView.builder(
                padding: const EdgeInsets.all(Insets.lg),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: widget.imageType == 'Primary' ? 3 : 2,
                  childAspectRatio:
                      widget.imageType == 'Primary' ? 2 / 3 : 16 / 9,
                  crossAxisSpacing: Insets.md,
                  mainAxisSpacing: Insets.md,
                ),
                itemCount: images.length,
                itemBuilder: (BuildContext context, int index) {
                  final EmbyRemoteImage image = images[index];
                  final String? url = image.url ?? image.thumbnailUrl;
                  if (!_isValidRemoteImageUrl(url)) {
                    return const SizedBox.shrink();
                  }
                  final String validUrl = url!;

                  return InkWell(
                    onTap: () => _confirmAndSet(validUrl),
                    borderRadius: Radii.card,
                    child: ClipRRect(
                      borderRadius: Radii.card,
                      child: AtriumNetworkImage(
                        imageUrl: validUrl,
                        fit: BoxFit.cover,
                        placeholder: (BuildContext context, String url) =>
                            Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Center(
                            child: ExpressiveProgressIndicator(),
                          ),
                        ),
                        errorWidget:
                            (BuildContext context, String url, dynamic error) =>
                                Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.error),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (_isSaving)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(child: ExpressiveProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
