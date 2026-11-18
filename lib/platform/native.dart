import 'dart:typed_data';
import 'package:flutter/services.dart';

class PickedFile {
  PickedFile(this.uri, this.name, this.size);
  final String uri, name;
  final int size;
  factory PickedFile.fromMap(Map m) =>
      PickedFile(m['uri'] as String, m['name'] as String, (m['size'] as num?)?.toInt() ?? 0);
}

/// پل به Kotlin: SAF، Intent، و باز کردن content:// به‌صورت file-descriptor (بدون کپی فایل).
class Native {
  static const _ch = MethodChannel('comic/native');

  static void listenIncoming(void Function(PickedFile) onFile) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onUri') onFile(PickedFile.fromMap(call.arguments as Map));
    });
  }

  static Future<PickedFile?> initialFile() async {
    final m = await _ch.invokeMethod<Map>('initialUri');
    return m == null ? null : PickedFile.fromMap(m);
  }

  static Future<List<PickedFile>> pickFiles() async =>
      ((await _ch.invokeMethod<List>('pickFiles')) ?? []).map((e) => PickedFile.fromMap(e as Map)).toList();

  /// پوشه را (بازگشتی) اسکن می‌کند و فقط cbz/cbr/zip/rar/pdf را برمی‌گرداند.
  static Future<List<PickedFile>> pickFolder() async =>
      ((await _ch.invokeMethod<List>('pickFolder')) ?? []).map((e) => PickedFile.fromMap(e as Map)).toList();

  static Future<int> openFd(String uri) async => (await _ch.invokeMethod<int>('openFd', {'uri': uri}))!;
  static Future<void> closeFd(int fd) => _ch.invokeMethod('closeFd', {'fd': fd});

  static Future<List<String>> rarList(String path) async =>
      ((await _ch.invokeMethod<List>('rarList', {'path': path})) ?? []).cast<String>();
  static Future<Uint8List> rarExtract(String path, String name) async =>
      (await _ch.invokeMethod<Uint8List>('rarExtract', {'path': path, 'name': name}))!;

  // PDF با android.graphics.PdfRenderer (بدون وابستگی خارجی)
  static Future<int> pdfOpen(String path) async => (await _ch.invokeMethod<int>('pdfOpen', {'path': path}))!;
  static Future<Uint8List> pdfPage(String path, int index, int width) async =>
      (await _ch.invokeMethod<Uint8List>('pdfPage', {'path': path, 'index': index, 'width': width}))!;
  static Future<void> pdfClose(String path) => _ch.invokeMethod('pdfClose', {'path': path});
}
