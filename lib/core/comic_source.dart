import 'dart:io';
import 'dart:typed_data';
import 'zip_source.dart';
import 'rar_source.dart';
import 'pdf_source.dart';

/// رابط یکسان برای همه فرمت‌ها: خروجی هر صفحه = بایت‌های انکودشده (JPEG/PNG/WebP).
/// دیکد پیکسلی را خود Flutter روی ترد جدا انجام می‌دهد.
abstract class ComicSource {
  int get pageCount;
  Future<Uint8List> page(int index);
  Future<void> dispose();

  /// فرمت را از magic bytes تشخیص می‌دهیم، نه پسوند (مسیر /proc/self/fd پسوند ندارد
  /// و خیلی از فایل‌های .cbr در واقع ZIP هستند).
  static Future<ComicSource> open(String path) async {
    final raf = await File(path).open();
    final head = await raf.read(8);
    await raf.close();
    bool starts(List<int> m) =>
        head.length >= m.length && List.generate(m.length, (i) => head[i] == m[i]).every((e) => e);

    if (starts([0x50, 0x4B])) return ZipSource.open(path);                 // PK
    if (starts([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07])) return RarSource.open(path); // Rar!
    if (starts([0x25, 0x50, 0x44, 0x46])) return PdfSource.open(path);     // %PDF
    throw UnsupportedError('Unsupported comic format');
  }
}

const _imgExt = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'avif'};

bool isImageName(String name) {
  final n = name.toLowerCase();
  if (n.contains('__macosx') || n.split('/').last.startsWith('.')) return false;
  final dot = n.lastIndexOf('.');
  return dot > 0 && _imgExt.contains(n.substring(dot + 1));
}

/// مرتب‌سازی طبیعی: page2 قبل از page10
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final y = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final nx = int.tryParse(x[i]), ny = int.tryParse(y[i]);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}
