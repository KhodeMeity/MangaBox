import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'engine.dart';
import 'page_cache.dart';
import 'scrubber.dart';
import 'store.dart';
import 'strings.dart';

enum ReadMode { ltr, rtl, webtoon }

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.doc, required this.comic, required this.store});
  final ComicDoc doc;
  final Comic comic;
  final LibraryStore store;

  /// نقطه‌ی ورود واحد (از کتابخانه و از فایل‌های ورودی). خطاها همیشه با پیام فارسی نشان داده می‌شوند.
  static Future<void> open(BuildContext context, Comic comic, LibraryStore store) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
    );
    ComicDoc? doc;
    Object? error;
    try {
      doc = await Engine.open(comic.uri);
    } catch (e) {
      error = e;
    }
    nav.pop(); // بستن دیالوگ «در حال باز کردن»
    if (doc != null) {
      await nav.push(MaterialPageRoute(builder: (_) => ReaderPage(doc: doc!, comic: comic, store: store)));
    } else {
      final text = error is ComicError ? error.toString() : '${S.openFailed}\n$error';
      messenger.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 10)));
    }
  }

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  late final PageCache cache = PageCache(widget.doc);
  late final int count = widget.doc.pages;
  late int page = widget.comic.lastPage.clamp(0, count - 1);
  late PageController pc = PageController(initialPage: page);
  late ReadMode mode = ReadMode.values[widget.store.mode.clamp(0, 2)];
  final itemScroll = ItemScrollController();
  final itemPos = ItemPositionsListener.create();

  bool chrome = true;
  bool locked = false;
  double webZoom = 1;
  Timer? _saveTimer;

  bool get rtl => mode == ReadMode.rtl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    itemPos.itemPositions.addListener(_onPositions);
    cache.prefetch(page, 1);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _save();
    widget.store.flush();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    cache.clear();
    widget.doc.close();
    pc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      _save();
      widget.store.flush(); // حتی اگر برنامه کشته شود موقعیت ذخیره شده است
    }
  }

  // ───── وضعیت ─────
  void _save() => widget.store.setProgress(widget.comic, page, count);

  void _onPage(int i) {
    if (i == page) return;
    final dir = i > page ? 1 : -1;
    setState(() => page = i);
    cache.prefetch(i, dir);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  void _onPositions() {
    if (mode != ReadMode.webtoon) return;
    final v = itemPos.itemPositions.value.where((p) => p.itemTrailingEdge > 0.35);
    if (v.isEmpty) return;
    _onPage(v.reduce((a, b) => a.index < b.index ? a : b).index);
  }

  // ───── رابط ─────
  void _toggleChrome() {
    setState(() => chrome = !chrome);
    SystemChrome.setEnabledSystemUIMode(chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  void _setMode(ReadMode m) {
    if (m == mode) return;
    final old = pc;
    pc = PageController(initialPage: page);
    setState(() {
      mode = m;
      webZoom = 1;
    });
    widget.store.setMode(m.index);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _toggleLock() {
    locked = !locked;
    SystemChrome.setPreferredOrientations(locked ? [DeviceOrientation.portraitUp] : []);
    setState(() {});
  }

  void _seek(int i) {
    if (mode == ReadMode.webtoon) {
      itemScroll.jumpTo(index: i);
    } else {
      pc.jumpToPage(i);
    }
  }

  void _step(int d) {
    final t = (page + d).clamp(0, count - 1);
    pc.animateToPage(t, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  /// تپ روی لبه‌ها = صفحه‌ی قبل/بعد (در مانگا برعکس)، تپ وسط = نمایش/پنهان‌کردن منوها
  void _tap(Offset p) {
    final x = p.dx / MediaQuery.of(context).size.width;
    final fwd = rtl ? -1 : 1;
    if (x < .28) {
      _step(-fwd);
    } else if (x > .72) {
      _step(fwd);
    } else {
      _toggleChrome();
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = targetWidthFor(context, factor: mode == ReadMode.webtoon ? 1.2 * webZoom : 2);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // جهت صفحه‌ی خواندن همیشه LTR است؛ جهت مانگا را خودمان با reverse کنترل می‌کنیم
        Positioned.fill(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: mode == ReadMode.webtoon ? _webtoon(w) : _paged(w),
          ),
        ),
        _bar(top: true, child: _topBar()),
        _bar(top: false, child: _bottomBar()),
      ]),
    );
  }

  Widget _paged(int w) => PhotoViewGallery.builder(
        key: ValueKey(mode),
        itemCount: count,
        pageController: pc,
        reverse: rtl,
        onPageChanged: _onPage,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        builder: (ctx, i) => PhotoViewGalleryPageOptions(
          imageProvider: ComicPageProvider(widget.doc.id, cache, i, w),
          minScale: PhotoViewComputedScale.contained,
          initialScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          // دابل‌تپ: کل صفحه ↔ پر کردن عرض/ارتفاع
          scaleStateCycle: (s) => s == PhotoViewScaleState.initial
              ? PhotoViewScaleState.covering
              : PhotoViewScaleState.initial,
          onTapUp: (c, d, v) => _tap(d.globalPosition),
          filterQuality: FilterQuality.medium,
          errorBuilder: (c, e, st) => Center(
            child: Padding(padding: const EdgeInsets.all(24), child: Text('$e', textAlign: TextAlign.center)),
          ),
        ),
      );

  /// وبتون: اسکرول عمودی پیوسته. دابل‌تپ = زوم ۲× (با اسکرول افقی)
  Widget _webtoon(int w) => LayoutBuilder(
        builder: (ctx, c) => GestureDetector(
          onTap: _toggleChrome,
          onDoubleTap: () => setState(() => webZoom = webZoom == 1 ? 2 : 1),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: webZoom == 1 ? const NeverScrollableScrollPhysics() : null,
            child: SizedBox(
              width: c.maxWidth * webZoom,
              height: c.maxHeight,
              child: ScrollablePositionedList.builder(
                key: ValueKey(mode),
                itemCount: count,
                initialScrollIndex: page,
                itemScrollController: itemScroll,
                itemPositionsListener: itemPos,
                itemBuilder: (_, i) => Image(
                  image: ComicPageProvider(widget.doc.id, cache, i, w),
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  gaplessPlayback: true,
                  frameBuilder: (ctx, child, frame, sync) => frame == null
                      ? const AspectRatio(aspectRatio: .7, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                      : child,
                  errorBuilder: (ctx, e, st) => SizedBox(height: 200, child: Center(child: Text('$e'))),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _bar({required bool top, required Widget child}) => Positioned(
        top: top ? 0 : null,
        bottom: top ? null : 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          ignoring: !chrome,
          child: AnimatedOpacity(
            opacity: chrome ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                  end: top ? Alignment.bottomCenter : Alignment.topCenter,
                  colors: [Colors.black.withOpacity(.85), Colors.transparent],
                ),
              ),
              child: SafeArea(top: top, bottom: !top, child: child),
            ),
          ),
        ),
      );

  Widget _topBar() => Row(children: [
        const BackButton(),
        Expanded(child: Text(widget.comic.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        IconButton(
          tooltip: S.lockRotation,
          icon: Icon(locked ? Icons.screen_lock_rotation : Icons.screen_rotation),
          onPressed: _toggleLock,
        ),
        PopupMenuButton<ReadMode>(
          icon: const Icon(Icons.chrome_reader_mode_outlined),
          onSelected: _setMode,
          itemBuilder: (_) => [
            CheckedPopupMenuItem(value: ReadMode.ltr, checked: mode == ReadMode.ltr, child: const Text(S.modeLtr)),
            CheckedPopupMenuItem(value: ReadMode.rtl, checked: mode == ReadMode.rtl, child: const Text(S.modeRtl)),
            CheckedPopupMenuItem(value: ReadMode.webtoon, checked: mode == ReadMode.webtoon, child: const Text(S.modeWebtoon)),
          ],
        ),
      ]);

  Widget _bottomBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Scrubber(
          count: count,
          current: page,
          rtl: rtl,
          onSeek: _seek,
          thumbBuilder: (i) => Image(
            image: ComicPageProvider(widget.doc.id, cache, i, 200),
            fit: BoxFit.cover,
          ),
        ),
      );
}
