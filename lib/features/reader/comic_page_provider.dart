import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../core/page_cache.dart';

/// ImageProvider اختصاصی: بایت‌ها را از PageCache می‌گیرد و با «عرض هدف» دیکد می‌کند
/// (صفحه ۶۰۰۰px روی رم کامل دیکد نمی‌شود). از ImageCache خود Flutter هم بهره می‌برد.
@immutable
class ComicPageProvider extends ImageProvider<ComicPageProvider> {
  const ComicPageProvider(this.comicId, this.cache, this.index, this.maxWidth);
  final String comicId;
  final PageCache cache;
  final int index;
  final int maxWidth;

  @override
  Future<ComicPageProvider> obtainKey(ImageConfiguration c) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(ComicPageProvider key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await cache.get(index);
    final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buf, getTargetSize: (w, h) {
      if (w <= maxWidth) return ui.TargetImageSize(width: w, height: h);
      return ui.TargetImageSize(width: maxWidth, height: (h * maxWidth / w).round());
    });
  }

  @override
  bool operator ==(Object o) =>
      o is ComicPageProvider && o.comicId == comicId && o.index == index && o.maxWidth == maxWidth;
  @override
  int get hashCode => Object.hash(comicId, index, maxWidth);
}

int targetWidthFor(BuildContext c, {double zoomFactor = 2}) {
  final mq = MediaQuery.of(c);
  return math.max(480, (mq.size.width * mq.devicePixelRatio * zoomFactor).round());
}
