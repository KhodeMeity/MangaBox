import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:pdfrx/pdfrx.dart';
import 'comic_source.dart';

/// PDFium از طریق pdfrx. صفحه را رندر و با انکودر native به PNG تبدیل می‌کنیم
/// تا همان مسیر یکسان (Cache + دیکد) برای همه فرمت‌ها کار کند.
/// ⚠️ API پکیج pdfrx بین نسخه‌ها فرق می‌کند؛ این بخش را با نسخه‌ی نصب‌شده تطبیق دهید.
class PdfSource extends ComicSource {
  PdfSource._(this._doc);
  final PdfDocument _doc;

  @override
  int get pageCount => _doc.pages.length;

  static Future<PdfSource> open(String path) async =>
      PdfSource._(await PdfDocument.openFile(path));

  static const _targetWidth = 1600.0;

  @override
  Future<Uint8List> page(int index) async {
    final p = _doc.pages[index];
    final scale = _targetWidth / p.width;
    final img = await p.render(
      fullWidth: _targetWidth,
      fullHeight: p.height * scale,
    );
    final uiImg = await img!.createImage();
    final data = await uiImg.toByteData(format: ui.ImageByteFormat.png);
    uiImg.dispose();
    img.dispose();
    return data!.buffer.asUint8List();
  }

  @override
  Future<void> dispose() async => _doc.dispose();
}
