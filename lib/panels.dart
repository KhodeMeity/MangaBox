import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// پنل‌های یک صفحه (مختصات نرمال‌شده‌ی ۰ تا ۱) + ابعاد اصلی تصویر.
class PanelInfo {
  const PanelInfo(this.width, this.height, this.panels);
  final int width, height;
  final List<ui.Rect> panels;
}

class _Job {
  const _Job(this.gray, this.w, this.h);
  final Uint8List gray;
  final int w, h;
}

/// تشخیص پنل با روش XY-cut روی نسخه‌ی کوچک صفحه:
/// «فاصله‌ی سفید (یا سیاه) بین پنل‌ها» پیدا و صفحه به‌صورت بازگشتی برش داده می‌شود.
/// فقط برای صفحه‌هایی که پنل‌هایشان با فاصله از هم جدا شده‌اند خوب کار می‌کند؛
/// برای طرح‌های مورب/هم‌پوشان نتیجه‌ی کمتر از ۲ پنل می‌دهد (و برنامه به زوم معمولی برمی‌گردد).
Future<PanelInfo?> detectPanels(Uint8List bytes) async {
  try {
    final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buf);
    final ow = desc.width, oh = desc.height;
    final codec = await desc.instantiateCodec(targetWidth: 240);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = img.width, h = img.height;
    img.dispose();
    codec.dispose();
    desc.dispose();
    buf.dispose();
    if (data == null) return null;

    final rgba = data.buffer.asUint8List();
    final gray = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      gray[i] = (rgba[i * 4] * 299 + rgba[i * 4 + 1] * 587 + rgba[i * 4 + 2] * 114) ~/ 1000;
    }
    final flat = await compute(_analyze, _Job(gray, w, h));
    final rects = <ui.Rect>[
      for (var i = 0; i + 3 < flat.length; i += 4) ui.Rect.fromLTRB(flat[i], flat[i + 1], flat[i + 2], flat[i + 3]),
    ];
    return PanelInfo(ow, oh, rects);
  } catch (_) {
    return null;
  }
}

List<double> _analyze(_Job j) {
  final w = j.w, h = j.h, g = j.gray;

  // رنگ پس‌زمینه = میانه‌ی پیکسل‌های حاشیه‌ی صفحه
  final bw = math.max(2, (w * 0.02).round()), bh = math.max(2, (h * 0.02).round());
  final border = <int>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (x < bw || x >= w - bw || y < bh || y >= h - bh) border.add(g[y * w + x]);
    }
  }
  border.sort();
  final bg = border[border.length ~/ 2];

  final fg = Uint8List(w * h); // ۱ = پیکسلِ «محتوا» (غیر پس‌زمینه)
  for (var i = 0; i < w * h; i++) {
    fg[i] = (g[i] - bg).abs() > 28 ? 1 : 0;
  }

  final minW = math.max(6, (w * 0.06).round()), minH = math.max(6, (h * 0.04).round());
  final gapY = math.max(3, (h * 0.012).round()), gapX = math.max(3, (w * 0.015).round());
  final out = <double>[];

  // دنباله‌های «خالی» که کاملاً داخل بازه‌اند و حداقل طول minGap دارند
  List<List<int>> gaps(bool Function(int) empty, int a, int b, int minGap) {
    final res = <List<int>>[];
    var i = a;
    while (i < b) {
      if (empty(i)) {
        var k = i;
        while (k < b && empty(k)) {
          k++;
        }
        if (k - i >= minGap && i > a && k < b) res.add([i, k]);
        i = k;
      } else {
        i++;
      }
    }
    return res;
  }

  void cut(int x0, int y0, int x1, int y1, int depth) {
    final rw = x1 - x0, rh = y1 - y0;
    if (rw <= 0 || rh <= 0) return;
    final rows = List<int>.filled(rh, 0), cols = List<int>.filled(rw, 0);
    for (var y = 0; y < rh; y++) {
      final base = (y0 + y) * w + x0;
      for (var x = 0; x < rw; x++) {
        if (fg[base + x] == 1) {
          rows[y]++;
          cols[x]++;
        }
      }
    }
    bool rowEmpty(int i) => rows[i] <= rw * 0.012; // کمی نویز/لکه قابل‌تحمل است
    bool colEmpty(int i) => cols[i] <= rh * 0.012;

    // حذف حاشیه‌های خالی
    var a = 0, b = rh;
    while (a < b && rowEmpty(a)) {
      a++;
    }
    while (b > a && rowEmpty(b - 1)) {
      b--;
    }
    var c = 0, d = rw;
    while (c < d && colEmpty(c)) {
      c++;
    }
    while (d > c && colEmpty(d - 1)) {
      d--;
    }
    if (b - a < minH || d - c < minW) return; // خالی یا نویز

    if (depth < 8) {
      // اول برش افقی (ردیف‌ها، بالا ← پایین)
      final gy = gaps(rowEmpty, a, b, gapY);
      if (gy.isNotEmpty) {
        var s = a;
        for (final gp in gy) {
          cut(x0, y0 + s, x1, y0 + gp[0], depth + 1);
          s = gp[1];
        }
        cut(x0, y0 + s, x1, y0 + b, depth + 1);
        return;
      }
      // بعد برش عمودی (ستون‌ها)
      final gx = gaps(colEmpty, c, d, gapX);
      if (gx.isNotEmpty) {
        var s = c;
        for (final gp in gx) {
          cut(x0 + s, y0, x0 + gp[0], y1, depth + 1);
          s = gp[1];
        }
        cut(x0 + s, y0, x0 + d, y1, depth + 1);
        return;
      }
    }
    out
      ..add((x0 + c) / w)
      ..add((y0 + a) / h)
      ..add((x0 + d) / w)
      ..add((y0 + b) / h);
  }

  cut(0, 0, w, h, 0);

  // حذف تکه‌های بسیار کوچک (شماره‌ی صفحه، لکه)
  final res = <double>[];
  for (var i = 0; i + 3 < out.length; i += 4) {
    final area = (out[i + 2] - out[i]) * (out[i + 3] - out[i + 1]);
    if (area >= 0.015) res.addAll(out.sublist(i, i + 4));
  }
  return res;
}
