import 'dart:io';
import 'package:flutter/material.dart';
import 'engine.dart';
import 'reader_page.dart';
import 'store.dart';
import 'strings.dart';
import 'text_utils.dart';

enum LibrarySort { lastRead, added, name, progress }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.store});
  final LibraryStore store;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryStore get store => widget.store;
  bool searching = false;
  String query = '';
  ReadStatus? filter; // null = همه
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ───── افزودن ─────
  Future<void> _import(Future<List<PickedFile>> Function() pick, {required bool folder}) async {
    final messenger = ScaffoldMessenger.of(context);
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

  void _sheet() => showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF111111),
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text(S.addFiles),
              onTap: () {
                Navigator.pop(ctx);
                _import(Engine.pickFiles, folder: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text(S.scanFolder),
              onTap: () {
                Navigator.pop(ctx);
                _import(Engine.pickFolder, folder: true);
              },
            ),
          ]),
        ),
      );

  // ───── فیلتر و ترتیب ─────
  List<Comic> _visible(List<Comic> all) {
    final q = normalizeFa(query.trim());
    final list = all.where((c) {
      if (filter != null && c.status != filter) return false;
      return q.isEmpty || normalizeFa(c.title).contains(q);
    }).toList();

    int lastKey(Comic c) => c.lastRead != 0 ? c.lastRead : c.addedAt;
    switch (LibrarySort.values[store.sort.clamp(0, 3)]) {
      case LibrarySort.lastRead:
        list.sort((a, b) => lastKey(b).compareTo(lastKey(a)));
      case LibrarySort.added:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case LibrarySort.name:
        list.sort((a, b) => naturalCompare(a.title, b.title));
      case LibrarySort.progress:
        list.sort((a, b) => b.progress.compareTo(a.progress));
    }
    return list;
  }

  void _closeSearch() {
    _searchCtrl.clear();
    setState(() {
      searching = false;
      query = '';
    });
  }

  PreferredSizeWidget _appBar() => AppBar(
        title: searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: S.searchHint, border: InputBorder.none),
                onChanged: (v) => setState(() => query = v),
              )
            : const Text(S.appName, style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .5)),
        actions: [
          if (searching)
            IconButton(tooltip: S.closeSearch, icon: const Icon(Icons.close), onPressed: _closeSearch)
          else
            IconButton(
              tooltip: S.searchTooltip,
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => searching = true),
            ),
          PopupMenuButton<LibrarySort>(
            tooltip: S.sortTooltip,
            icon: const Icon(Icons.sort),
            onSelected: (v) => store.setSort(v.index),
            itemBuilder: (_) {
              final cur = LibrarySort.values[store.sort.clamp(0, 3)];
              return [
                CheckedPopupMenuItem(value: LibrarySort.lastRead, checked: cur == LibrarySort.lastRead, child: const Text(S.sortLastRead)),
                CheckedPopupMenuItem(value: LibrarySort.added, checked: cur == LibrarySort.added, child: const Text(S.sortAdded)),
                CheckedPopupMenuItem(value: LibrarySort.name, checked: cur == LibrarySort.name, child: const Text(S.sortName)),
                CheckedPopupMenuItem(value: LibrarySort.progress, checked: cur == LibrarySort.progress, child: const Text(S.sortProgress)),
              ];
            },
          ),
        ],
      );

  Widget _chips(List<Comic> all) {
    int n(ReadStatus? s) => s == null ? all.length : all.where((c) => c.status == s).length;
    Widget chip(String label, ReadStatus? s) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: ChoiceChip(
            label: Text('$label  ${S.fa(n(s))}'),
            selected: filter == s,
            onSelected: (_) => setState(() => filter = s),
          ),
        );
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        children: [
          chip(S.filterAll, null),
          chip(S.filterReading, ReadStatus.reading),
          chip(S.filterFinished, ReadStatus.finished),
          chip(S.filterUnread, ReadStatus.unread),
        ],
      ),
    );
  }

  Widget _empty(IconData icon, String title, [String? hint]) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, height: 1.8)),
            ],
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: _appBar(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _sheet,
          icon: const Icon(Icons.add),
          label: const Text(S.add),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (_, __) {
            final all = store.all;
            if (all.isEmpty) return _empty(Icons.auto_stories, S.emptyTitle, S.emptyHint);
            final list = _visible(all);
            return Column(children: [
              _chips(all),
              Expanded(
                child: list.isEmpty
                    ? _empty(Icons.search_off, S.noResults)
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160, childAspectRatio: .56, crossAxisSpacing: 12, mainAxisSpacing: 12,
                        ),
                        itemCount: list.length,
                        itemBuilder: (c, i) => _Tile(comic: list[i], store: store),
                      ),
              ),
            ]);
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
              if (comic.status == ReadStatus.finished)
                const Positioned(
                  top: 6, left: 6,
                  child: Icon(Icons.check_circle, size: 20, color: Color(0xFFFFD166)),
                ),
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
