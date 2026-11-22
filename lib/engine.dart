import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'strings.dart';

class PickedFile {
  const PickedFile(this.uri, this.name);
  final String uri, name;
  factory PickedFile.fromMap(Map m) => PickedFile(m['uri'] as String, (m['name'] ?? 'comic') as String);
}

/// خطایی که پیام فارسی برای کاربر دارد؛ جزئیات فنی (در صورت وجود) زیر آن می‌آید.
class ComicError implements Exception {
  ComicError(this.message, [this.detail]);
  final String message;
  final String? detail;
  @override
  String toString() => detail == null ? message : '$message\n$detail';
}

/// یک کمیک باز (سمت native نگه داشته می‌شود تا close شود).
class ComicDoc {
  ComicDoc._(this.id, this.pages, this.type);
  final int id, pages;
  final String type;

  /// width فقط برای PDF معنی دارد (عرض رندر). تصویرهای ZIP همان‌طور که هستند برمی‌گردند.
  Future<Uint8List> page(int index, {int width = 0}) async {
    try {
      final b = await Engine._ch.invokeMethod<Uint8List>('page', {'id': id, 'index': index, 'width': width});
      return b!;
    } on PlatformException catch (e) {
      throw ComicError(S.pageFailed, e.message);
    }
  }

  Future<void> close() async {
    try {
      await Engine._ch.invokeMethod('close', {'id': id});
    } catch (_) {}
  }
}

class Engine {
  static const _ch = MethodChannel('mangabox/engine');

  /// cover=true فقط برای ساخت کاور است (در RAR فقط تا صفحه‌ی اول استخراج می‌شود).
  static Future<ComicDoc> open(String uri, {bool cover = false}) async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('open', {'uri': uri, 'cover': cover});
      return ComicDoc._(m!['id'] as int, m['pages'] as int, m['type'] as String);
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'RAR5':
          throw ComicError(S.rar5Unsupported);
        case 'RAR_BAD':
          throw ComicError(S.rarBroken, e.message);
        case 'NO_IMAGES':
          throw ComicError(S.noImages);
        case 'FORMAT':
          throw ComicError(S.badFormat);
        case 'PDF_LOCKED':
          throw ComicError(S.pdfLocked);
        default:
          throw ComicError(S.openFailed, e.message);
      }
    }
  }

  static Future<List<PickedFile>> pickFiles() async => _list(await _ch.invokeMethod<List>('pickFiles'));
  static Future<List<PickedFile>> pickFolder() async => _list(await _ch.invokeMethod<List>('pickFolder'));

  static List<PickedFile> _list(List? l) =>
      (l ?? const []).map((e) => PickedFile.fromMap(e as Map)).toList();

  /// فایل‌هایی که از بیرون (تلگرام، فایل‌منیجر، Share) به برنامه داده می‌شوند.
  static void start(void Function(PickedFile) onFile) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onUri') onFile(PickedFile.fromMap(call.arguments as Map));
    });
    _ch.invokeMethod('ready');
  }

  static Future<void> deleteImported(String uri) async {
    if (!uri.startsWith('file://')) return;
    try {
      await _ch.invokeMethod('deleteImported', {'path': Uri.parse(uri).toFilePath()});
    } catch (_) {}
  }
}
