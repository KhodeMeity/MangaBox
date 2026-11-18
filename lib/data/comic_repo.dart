import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../platform/comic_opener.dart';
import '../platform/native.dart';
import 'comic_entry.dart';

class ComicRepo {
  static late Box _box;
  /// UI با این notifier بعد از هر تغییر بازسازی می‌شود.
  static final changes = ValueNotifier<int>(0);

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('comics');
  }

  static List<ComicEntry> all() {
    int key(ComicEntry e) => e.lastRead != 0 ? e.lastRead : e.addedAt;
    return _box.values
        .map((e) => ComicEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => key(b).compareTo(key(a)));
  }

  static ComicEntry? get(String id) {
    final m = _box.get(id);
    return m == null ? null : ComicEntry.fromMap(Map<String, dynamic>.from(m as Map));
  }

  static Future<void> put(ComicEntry e) async {
    await _box.put(e.id, e.toMap());
    changes.value++;
  }

  /// فایل جدید را ثبت می‌کند (اگر قبلاً بوده، پیشرفتش حفظ می‌شود).
  static Future<ComicEntry> register(PickedFile f) async {
    final id = ComicEntry.idFor(f.uri);
    final existing = get(id);
    if (existing != null) return existing;
    final title = f.name.replaceFirst(RegExp(r'\.(cbz|cbr|zip|rar|pdf)$', caseSensitive: false), '');
    final e = ComicEntry(id: id, uri: f.uri, title: title, addedAt: DateTime.now().millisecondsSinceEpoch);
    await put(e);
    return e;
  }

  static Future<void> saveProgress(String id, int page, int count) async {
    final e = get(id);
    if (e == null) return;
    await put(e.copyWith(lastPage: page, pageCount: count, lastRead: DateTime.now().millisecondsSinceEpoch));
  }

  static Future<void> remove(String id) async {
    await _box.delete(id);
    changes.value++;
  }

  // ───── کاور: صفحه‌ی اول، کوچک‌شده، روی دیسک ─────
  static Future<void> ensureCover(ComicEntry e) async {
    if (e.coverPath != null && File(e.coverPath!).existsSync()) return;
    final s = await ComicOpener.open(e.uri);
    try {
      final bytes = await s.source.page(0);
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 360);
      final img = (await codec.getNextFrame()).image;
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      codec.dispose();
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/covers/${e.id}.png')..createSync(recursive: true);
      await f.writeAsBytes(png!.buffer.asUint8List());
      await put((get(e.id) ?? e).copyWith(coverPath: f.path, pageCount: s.source.pageCount));
    } finally {
      await s.dispose();
    }
  }

  /// صف ترتیبی تا باز شدن هم‌زمان چندین آرشیو، رم را نبرد.
  static Future<void> generateCovers(Iterable<ComicEntry> list) async {
    for (final e in list) {
      try {
        await ensureCover(e);
      } catch (_) {/* فایل خراب/ناموجود */}
    }
  }
}
