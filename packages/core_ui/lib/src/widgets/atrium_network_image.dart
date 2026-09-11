import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../artwork_headers.dart';

/// A network image that carries the instance's configured headers.
///
/// Use this rather than `CachedNetworkImage` directly for anything served by
/// a user's own instance. It is a drop-in for the parameters the app actually
/// uses; the only difference is that it resolves the headers for the URL and
/// passes them along, which is what makes artwork work behind a forward-auth
/// proxy. See [ArtworkHeaders] for why that lookup is by URL.
class AtriumNetworkImage extends StatelessWidget {
  const AtriumNetworkImage({
    required this.imageUrl,
    super.key,
    this.fit,
    this.width,
    this.height,
    this.memCacheWidth,
    this.memCacheHeight,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
    this.placeholder,
    this.errorWidget,
    this.imageBuilder,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.fadeInDuration = const Duration(milliseconds: 500),
    this.color,
    this.colorBlendMode,
  });

  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;
  final ImageWidgetBuilder? imageBuilder;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final Duration fadeInDuration;
  final Color? color;
  final BlendMode? colorBlendMode;

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: ArtworkHeaders.forUrl(imageUrl),
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        maxWidthDiskCache: maxWidthDiskCache,
        maxHeightDiskCache: maxHeightDiskCache,
        placeholder: placeholder,
        errorWidget: errorWidget,
        imageBuilder: imageBuilder,
        alignment: alignment,
        filterQuality: filterQuality,
        fadeInDuration: fadeInDuration,
        color: color,
        colorBlendMode: colorBlendMode,
      );
}

/// The same idea as [AtriumNetworkImage] for the places that need an
/// `ImageProvider` rather than a widget: `DecorationImage` backgrounds and
/// `PaletteGenerator`, which pulls the poster colours for the now-playing
/// cards and would otherwise fetch a login page and theme the card from it.
CachedNetworkImageProvider atriumImageProvider(
  String url, {
  int? maxWidth,
  int? maxHeight,
}) =>
    CachedNetworkImageProvider(
      url,
      headers: ArtworkHeaders.forUrl(url),
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
