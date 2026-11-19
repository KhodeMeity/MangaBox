import 'dart:io';
import 'package:flutter/material.dart';
import 'engine.dart';
import 'reader_page.dart';
import 'store.dart';
import 'strings.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.store});
  final LibraryStore store;

  Future<void> _import(BuildContext ctx, Future<List<PickedFile>> Function() pick, {required bool folder}) async {
    final messenger = ScaffoldMessenger.of(ctx);
    try {
      final files = await pick();
      if (files.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(folder ? S.noComicInFolder : S.noFilePicked)));
        return;
      }
      for (final f in files) {
        await store.add(f); // فقط آدرس فایل ذخیره می‌شود
      }
      messenger.showSnackBar(SnackBar(content: Text(S.added(files.length))));
      store.generateCovers(); // پس‌زمینه
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'), duration: const Duration(seconds: 8)));
    }
  }

  void _sheet(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        backgroundColor: const Color(0xFF111111),
        builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text(S.addFiles),
              onTap: () {
                Navigator.pop(ctx);
                _import(ctx, Engine.pickFiles, folder: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text(S.scanFolder),
              onTap: () {
                Navigator.pop(ctx);
                _import(ctx, Engine.pickFolder, folder: true);
              },
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text(S.appName, style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .5)),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _sheet(context),
          icon: const Icon(Icons.add),
          label: const Text(S.add),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (_, __) {
            final list = store.items;
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_stories, size: 64, color: Colors.white24),
                    const SizedBox(height: 16),
                    const Text(S.emptyTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text(S.emptyHint, textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, height: 1.8)),
                  ]),
                ),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160, childAspectRatio: .56, crossAxisSpacing: 12, mainAxisSpacing: 12,
              ),
              itemCount: list.length,
              itemBuilder: (c, i) => _Tile(comic: list[i], store: store),
            );
          },
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.comic, required this.store});
  final Comic comic;
  final LibraryStore store;

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(S.removeTitle),
        content: const Text(S.removeBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.cancel)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text(S.remove)),
        ],
      ),
    );
    if (ok == true) store.remove(comic);
  }

  @override
  Widget build(BuildContext context) {
    final hasCover = comic.cover != null && File(comic.cover!).existsSync();
    return GestureDetector(
      onTap: () => ReaderPage.open(context, comic, store),
      onLongPress: () => _confirmRemove(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(fit: StackFit.expand, children: [
              hasCover
                  ? Image.file(File(comic.cover!), fit: BoxFit.cover, cacheWidth: 360)
                  : Container(color: const Color(0xFF161616), child: const Icon(Icons.menu_book, color: Colors.white24)),
              if (comic.progress > 0)
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: LinearProgressIndicator(value: comic.progress, minHeight: 3, backgroundColor: Colors.black54),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(comic.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.5)),
        if (comic.progress > 0)
          Text('${S.fa((comic.progress * 100).round())}٪', style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ]),
    );
  }
}
