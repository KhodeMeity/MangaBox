import 'dart:typed_data';
import '../platform/native.dart';
import 'comic_source.dart';

/// PDF با android.graphics.PdfRenderer (سمت Kotlin، روی ترد پس‌زمینه).
/// خروجی هر صفحه JPEG است و از همان مسیر PageCache/دیکد مشترک عبور می‌کند.
class PdfSource extends ComicSource {
  PdfSource._(this._path, this._count);
  final String _path;
  final int _count;

  @override
  int get pageCount => _count;

  static Future<PdfSource> open(String path) async => PdfSource._(path, await Native.pdfOpen(path));

  static const _targetWidth = 1600;

  @override
  Future<Uint8List> page(int index) => Native.pdfPage(_path, index, _targetWidth);

  @override
  Future<void> dispose() => Native.pdfClose(_path);
}
