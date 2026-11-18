import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'comic_source.dart';

/// یک Isolate اختصاصی به‌ازای هر کمیک. فایل با InputFileStream از دیسک خوانده می‌شود
/// (فقط central directory در حافظه است)، هر صفحه on-demand استخراج می‌شود و
/// با TransferableTypedData بدون کپی به ترد اصلی می‌رسد.
class ZipSource extends ComicSource {
  ZipSource._(this._iso, this._rx, this._cmd, this._count);
  final Isolate _iso;
  final ReceivePort _rx;
  final SendPort _cmd;
  final int _count;
  final _pending = <int, Completer<Uint8List>>{};
  int _id = 0;

  @override
  int get pageCount => _count;

  static Future<ZipSource> open(String path) async {
    final rx = ReceivePort();
    final ready = Completer<List>();
    ZipSource? self;
    rx.listen((m) {
      if (!ready.isCompleted) {
        ready.complete(m as List);
      } else {
        self!._onMessage(m as List);
      }
    });
    final iso = await Isolate.spawn(_worker, [rx.sendPort, path]);
    final init = await ready.future;
    if (init[0] is String) {
      rx.close();
      iso.kill();
      throw StateError(init[0] as String);
    }
    return self = ZipSource._(iso, rx, init[0] as SendPort, (init[1] as List).length);
  }

  void _onMessage(List m) {
    final c = _pending.remove(m[0] as int);
    if (c == null) return;
    if (m[2] != null) {
      c.completeError(m[2] as String);
    } else {
      c.complete((m[1] as TransferableTypedData).materialize().asUint8List());
    }
  }

  @override
  Future<Uint8List> page(int index) {
    final id = _id++;
    final c = _pending[id] = Completer<Uint8List>();
    _cmd.send([id, index]);
    return c.future;
  }

  @override
  Future<void> dispose() async {
    _cmd.send([-1, -1]);
    _rx.close();
    _iso.kill(priority: Isolate.beforeNextEvent);
    for (final c in _pending.values) {
      c.completeError('disposed');
    }
    _pending.clear();
  }
}

void _worker(List args) {
  final SendPort out = args[0];
  final String path = args[1];
  try {
    final input = InputFileStream(path);
    final archive = ZipDecoder().decodeBuffer(input);
    final files = archive.files
        .where((f) => f.isFile && isImageName(f.name))
        .toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));
    final cmd = ReceivePort();
    out.send([cmd.sendPort, files.map((f) => f.name).toList()]);
    cmd.listen((m) {
      final id = m[0] as int, idx = m[1] as int;
      if (id < 0) {
        input.close();
        cmd.close();
        return;
      }
      try {
        final f = files[idx];
        final data = f.content as List<int>;
        final bytes = data is Uint8List ? data : Uint8List.fromList(data);
        out.send([id, TransferableTypedData.fromList([bytes]), null]);
        // ⚠️ archive محتوای دیکامپرس‌شده را کش می‌کند؛ بدون clear() حافظه با هر صفحه بالا می‌رود.
        f.clear();
      } catch (e) {
        out.send([id, null, e.toString()]);
      }
    });
  } catch (e) {
    out.send([e.toString()]);
  }
}
