import 'dart:collection';
import 'dart:typed_data';
import 'comic_source.dart';

/// LRU بر اساس «بایت» (نه تعداد). فقط بایت‌های فشرده نگه داشته می‌شوند (~۰٫۵–۳ MB)،
/// دیکدشده‌ها را ImageCache خود Flutter مدیریت می‌کند.
class PageCache {
  PageCache(this.source, {this.maxBytes = 96 * 1024 * 1024});
  final ComicSource source;
  final int maxBytes;
  int _bytes = 0;
  final _lru = LinkedHashMap<int, Uint8List>();
  final _inflight = <int, Future<Uint8List>>{};

  Future<Uint8List> get(int i) {
    final hit = _lru.remove(i);
    if (hit != null) {
      _lru[i] = hit; // به انتهای صف (تازه‌ترین)
      return Future.value(hit);
    }
    return _inflight[i] ??= () async {
      try {
        final b = await source.page(i);
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
      final k = _lru.keys.first;
      _bytes -= _lru.remove(k)!.length;
    }
  }

  /// پیش‌بارگذاری جهت‌دار: صفحات بعدی بیشتر، قبلی کمتر.
  void prefetch(int center, int dir, {int ahead = 3, int behind = 1}) {
    for (var k = 1; k <= ahead; k++) {
      _warm(center + dir * k);
    }
    for (var k = 1; k <= behind; k++) {
      _warm(center - dir * k);
    }
  }

  void _warm(int i) {
    if (i < 0 || i >= source.pageCount || _lru.containsKey(i)) return;
    get(i).ignore();
  }

  void clear() {
    _lru.clear();
    _inflight.clear();
    _bytes = 0;
  }
}
