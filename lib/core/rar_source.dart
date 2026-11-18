import 'dart:typed_data';
import 'comic_source.dart';
import '../platform/native.dart';

/// RAR5 در Dart خالص پشتیبانی خوب ندارد → از libarchive سمت Android (کانال native) استفاده می‌شود.
/// Native دو متد دارد: rarList(path) → List<String> و rarExtract(path, name) → Uint8List.
/// نکته: آرشیو RAR «solid» دسترسی تصادفی ندارد؛ در پیاده‌سازی native بهتر است در اولین باز شدن،
/// صفحات به‌ترتیب در یک پوشه‌ی cache استخراج شوند (و با LRU پاک شوند).
class RarSource extends ComicSource {
  RarSource._(this._path, this._names);
  final String _path;
  final List<String> _names;

  @override
  int get pageCount => _names.length;

  static Future<RarSource> open(String path) async {
    final names = (await Native.rarList(path)).where(isImageName).toList()
      ..sort(naturalCompare);
    return RarSource._(path, names);
  }

  @override
  Future<Uint8List> page(int index) => Native.rarExtract(_path, _names[index]);

  @override
  Future<void> dispose() async {}
}
