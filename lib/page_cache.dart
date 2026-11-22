import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'engine.dart';

/// LRU بر اساس حجم (بایت). فقط بایت‌های فشرده‌ی تصویر نگه‌داری می‌شود؛
/// نسخه‌ی دیکدشده را ImageCache خود فلاتر مدیریت می‌کند.
class PageCache {
  PageCache(this.doc, {this.maxBytes = 80 * 1024 * 1024});
  final ComicDoc doc;
  final int maxBytes;
  int _bytes = 0;
  final _lru = LinkedHashMap<int, Uint8List>();
  final _inflight = <int, Future<Uint8List>>{};

  Future<Uint8List> get(int i) {
    final hit = _lru.remove(i);
    if (hit != null) {
      _lru[i] = hit;
      return Future.value(hit);
    }
    return _inflight[i] ??= () async {
      try {
        final b = await doc.page(i, width: 1600);
        _put(i, b);
        return b;
      } finally {
        _inflight.remove(i);
      }
    }();
  }

  void _put(int i, Uint8List b) {
    _lru[i] = b;
    _bytes += b.length;
    while (_bytes > maxBytes && _lru.length > 1) {
      _bytes -= _lru.remove(_lru.keys.first)!.length;
    }
  }

  /// پیش‌بارگذاری جهت‌دار (۳ صفحه‌ی جلو، ۱ صفحه‌ی عقب)
  void prefetch(int center, int dir, {int ahead = 3}) {
    for (var k = 1; k <= ahead; k++) {
      _warm(center + dir * k);
    }
    _warm(center - dir);
  }

  void _warm(int i) {
    if (i < 0 || i >= doc.pages || _lru.containsKey(i)) return;
    get(i).ignore();
  }

  void clear() {
    _lru.clear();
    _inflight.clear();
    _bytes = 0;
  }
}

/// ImageProvider: بایت‌ها را از PageCache می‌گیرد و فقط تا «عرض لازم» دیکد می‌کند
/// (صفحه‌ی ۶۰۰۰ پیکسلی کل رم را نمی‌گیرد).
@immutable
class ComicPageProvider extends ImageProvider<ComicPageProvider> {
  const ComicPageProvider(this.docId, this.cache, this.index, this.maxWidth);
  final int docId, index, maxWidth;
  final PageCache cache;

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
      o is ComicPageProvider && o.docId == docId && o.index == index && o.maxWidth == maxWidth;
  @override
  int get hashCode => Object.hash(docId, index, maxWidth);
}

/// عرض هدف دیکد (پیکسل). در حالت ورق‌زدن، «ضلع کوتاه» صفحه‌نمایش ملاک است (در حالت افقی هم
/// صفحه‌ی عمودی با ارتفاع جا می‌شود، نه عرض) تا رم هدر نرود؛ وبتون عرض کامل می‌خواهد.
int targetWidthFor(BuildContext c, {double factor = 2, bool useWidth = false}) {
  final mq = MediaQuery.of(c);
  final base = useWidth ? mq.size.width : mq.size.shortestSide;
  return math.max(480, (base * mq.devicePixelRatio * factor).round());
}
