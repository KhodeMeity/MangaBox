import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'engine.dart';

class Comic {
  Comic({
    required this.id, required this.uri, required this.title,
    this.pages = 0, this.lastPage = 0, this.lastRead = 0, this.addedAt = 0, this.cover,
  });
  final String id, uri, title;
  int pages, lastPage, lastRead, addedAt;
  String? cover;

  /// درصد پیشرفت (۰ تا ۱). تا وقتی کمیک باز نشده صفر است.
  double get progress => (lastRead == 0 || pages <= 0) ? 0 : ((lastPage + 1) / pages).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'id': id, 'uri': uri, 'title': title, 'pages': pages,
        'lastPage': lastPage, 'lastRead': lastRead, 'addedAt': addedAt, 'cover': cover,
      };

  factory Comic.fromJson(Map j) => Comic(
        id: j['id'], uri: j['uri'], title: j['title'],
        pages: j['pages'] ?? 0, lastPage: j['lastPage'] ?? 0,
        lastRead: j['lastRead'] ?? 0, addedAt: j['addedAt'] ?? 0, cover: j['cover'],
      );
}

/// کتابخانه: یک فایل JSON در حافظه‌ی داخلی اپ (بدون دیتابیس و پکیج اضافه).
class LibraryStore extends ChangeNotifier {
  LibraryStore._(this._dir) : _file = File('${_dir.path}/library.json');
  final Directory _dir;
  final File _file;
  final List<Comic> _items = [];
  int mode = 0; // 0: چپ‌به‌راست، 1: مانگا، 2: وبتون
  Timer? _timer;
  final _coverFailed = <String>{};

  static Future<LibraryStore> load() async {
    final s = LibraryStore._(await getApplicationSupportDirectory());
    try {
      if (await s._file.exists()) {
        final j = jsonDecode(await s._file.readAsString()) as Map;
        s.mode = (j['mode'] ?? 0) as int;
        for (final c in (j['comics'] as List)) {
          s._items.add(Comic.fromJson(c as Map));
        }
      }
    } catch (_) {/* فایل خراب: با کتابخانه‌ی خالی شروع می‌کنیم */}
    return s;
  }

  List<Comic> get items {
    int key(Comic c) => c.lastRead != 0 ? c.lastRead : c.addedAt;
    final l = [..._items];
    l.sort((a, b) => key(b).compareTo(key(a)));
    return l;
  }

  static String _idFor(String s) {
    var h = 1469598103934665603; // FNV-1a
    for (final c in s.codeUnits) {
      h = (h ^ c) * 1099511628211;
    }
    return h.toUnsigned(64).toRadixString(16);
  }

  Future<Comic> add(PickedFile f) async {
    final id = _idFor(f.uri);
    for (final c in _items) {
      if (c.id == id) return c;
    }
    final title = f.name.replaceFirst(RegExp(r'\.(cbz|cbr|zip|rar|pdf)$', caseSensitive: false), '');
    final c = Comic(id: id, uri: f.uri, title: title, addedAt: DateTime.now().millisecondsSinceEpoch);
    _items.add(c);
    notifyListeners();
    _scheduleSave();
    return c;
  }

  void setProgress(Comic c, int page, int pages) {
    c.lastPage = page;
    c.pages = pages;
    c.lastRead = DateTime.now().millisecondsSinceEpoch;
    _scheduleSave();
  }

  void setMode(int m) {
    mode = m;
    _scheduleSave();
  }

  Future<void> remove(Comic c) async {
    _items.remove(c);
    if (c.cover != null) {
      try { await File(c.cover!).delete(); } catch (_) {}
    }
    notifyListeners();
    await Engine.deleteImported(c.uri);
    _scheduleSave();
  }

  // ───── ذخیره ─────
  void _scheduleSave() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), flush);
  }

  /// فوراً روی دیسک می‌نویسد (هنگام رفتن به پس‌زمینه هم صدا زده می‌شود).
  Future<void> flush() async {
    _timer?.cancel();
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode({'mode': mode, 'comics': _items.map((c) => c.toJson()).toList()}));
      await tmp.rename(_file.path);
    } catch (_) {}
    notifyListeners();
  }

  // ───── کاور ─────
  bool _hasCover(Comic c) => c.cover != null && File(c.cover!).existsSync();

  Comic? _nextPending() {
    for (final c in _items) {
      if (!_coverFailed.contains(c.id) && !_hasCover(c)) return c;
    }
    return null;
  }

  bool _busy = false;

  /// برای هر کمیکِ بدون کاور، صفحه‌ی اول را کوچک می‌کند. یکی‌یکی (تا رم بالا نرود).
  Future<void> generateCovers() async {
    if (_busy) return;
    _busy = true;
    try {
      for (var c = _nextPending(); c != null; c = _nextPending()) {
        try {
          await _makeCover(c);
        } catch (_) {
          _coverFailed.add(c.id);
        }
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _makeCover(Comic c) async {
    final doc = await Engine.open(c.uri);
    try {
      final bytes = await doc.page(0, width: 400);
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 360);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      final f = File('${_dir.path}/covers/${c.id}.png');
      await f.create(recursive: true);
      await f.writeAsBytes(data!.buffer.asUint8List());
      c.cover = f.path;
      c.pages = doc.pages;
      _scheduleSave();
    } finally {
      await doc.close();
    }
  }
}
