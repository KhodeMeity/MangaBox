import '../core/comic_source.dart';
import 'native.dart';

/// content:// → fd → /proc/self/fd/N : دسترسی تصادفی (random access) به فایل اصلی
/// بدون کپی. fd تا زمان dispose باز می‌ماند.
class ComicSession {
  ComicSession(this.source, this._fd);
  final ComicSource source;
  final int _fd;
  Future<void> dispose() async {
    await source.dispose();
    await Native.closeFd(_fd);
  }
}

class ComicOpener {
  static Future<ComicSession> open(String uri) async {
    final fd = await Native.openFd(uri);
    try {
      final src = await ComicSource.open('/proc/self/fd/$fd');
      return ComicSession(src, fd);
    } catch (_) {
      await Native.closeFd(fd);
      rethrow;
    }
  }
}
