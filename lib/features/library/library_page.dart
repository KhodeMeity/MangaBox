import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/comic_entry.dart';
import '../../data/comic_repo.dart';
import '../../platform/native.dart';
import '../reader/reader_page.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  Future<void> _import(BuildContext ctx, Future<List<PickedFile>> Function() pick) async {
    final files = await pick();
    final entries = <ComicEntry>[];
    for (final f in files) {
      entries.add(await ComicRepo.register(f)); // فقط URI ذخیره می‌شود؛ فایل کپی نمی‌شود
    }
    ComicRepo.generateCovers(entries.where((e) => e.coverPath == null)); // پس‌زمینه
  }

  void _importSheet(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        backgroundColor: const Color(0xFF111111),
        builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Add files'),
              onTap: () { Navigator.pop(ctx); _import(ctx, Native.pickFiles); },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Scan folder'),
              onTap: () { Navigator.pop(ctx); _import(ctx, Native.pickFolder); },
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('MangaBox', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .5))),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _importSheet(context),
          child: const Icon(Icons.add),
        ),
        body: ValueListenableBuilder<int>(
          valueListenable: ComicRepo.changes,
          builder: (_, __, ___) {
            final list = ComicRepo.all();
            if (list.isEmpty) return const Center(child: Text('Tap + to add comics'));
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160, childAspectRatio: .58, crossAxisSpacing: 12, mainAxisSpacing: 12,
              ),
              itemCount: list.length,
              itemBuilder: (c, i) => _Tile(entry: list[i]),
            );
          },
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.entry});
  final ComicEntry entry;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => ReaderPage.open(context, entry).catchError((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot open file (moved or permission lost)')),
          );
        }),
        onLongPress: () => ComicRepo.remove(entry.id), // فقط رکورد حذف می‌شود، نه فایل
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(fit: StackFit.expand, children: [
                entry.coverPath != null && File(entry.coverPath!).existsSync()
                    ? Image.file(File(entry.coverPath!), fit: BoxFit.cover, cacheWidth: 360)
                    : Container(color: const Color(0xFF161616), child: const Icon(Icons.menu_book, color: Colors.white24)),
                if (entry.progress > 0)
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: LinearProgressIndicator(value: entry.progress, minHeight: 3, backgroundColor: Colors.black54),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          if (entry.pageCount > 0)
            Text('${(entry.progress * 100).round()}%', style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ]),
      );
}
