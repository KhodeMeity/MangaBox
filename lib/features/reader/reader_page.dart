import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../core/page_cache.dart';
import '../../data/comic_entry.dart';
import '../../data/comic_repo.dart';
import '../../platform/comic_opener.dart';
import 'comic_page_provider.dart';
import 'scrubber.dart';

enum ReadMode { ltr, rtl, webtoon }

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.session, required this.entry});
  final ComicSession session;
  final ComicEntry entry;

  /// نقطه‌ی ورود واحد: هم از کتابخانه، هم از Intent خارجی.
  static Future<void> open(BuildContext context, ComicEntry entry) async {
    final nav = Navigator.of(context);
    final session = await ComicOpener.open(entry.uri);
    await nav.push(MaterialPageRoute(builder: (_) => ReaderPage(session: session, entry: entry)));
  }

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  late final PageCache cache = PageCache(widget.session.source);
  late int count = widget.session.source.pageCount;
  late int page = widget.entry.lastPage.clamp(0, count - 1);
  late PageController pc = PageController(initialPage: page);
  final itemScroll = ItemScrollController();
  final itemPos = ItemPositionsListener.create();

  ReadMode mode = ReadMode.ltr;
  bool chrome = true, orientationLocked = false;
  int _lastDir = 1;
  Timer? _saveTimer;

  bool get rtl => mode == ReadMode.rtl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    itemPos.itemPositions.addListener(_onPositions);
    cache.prefetch(page, 1);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _saveNow();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    cache.clear();
    widget.session.dispose();
    pc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // اپ کشته شد/به پس‌زمینه رفت → موقعیت قطعاً ذخیره شده باشد
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) _saveNow();
  }

  // ───────── وضعیت صفحه و ذخیره ─────────
  void _onPage(int i) {
    if (i == page) return;
    _lastDir = i > page ? 1 : -1;
    setState(() => page = i);
    cache.prefetch(i, _lastDir);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow); // debounce
  }

  void _saveNow() => ComicRepo.saveProgress(widget.entry.id, page, count);

  void _onPositions() {
    if (mode != ReadMode.webtoon) return;
    final v = itemPos.itemPositions.value.where((p) => p.itemTrailingEdge > 0.35);
    if (v.isEmpty) return;
    _onPage(v.reduce((a, b) => a.index < b.index ? a : b).index);
  }

  // ───────── UI immersive ─────────
  void _toggleChrome() {
    setState(() => chrome = !chrome);
    SystemChrome.setEnabledSystemUIMode(chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  void _setMode(ReadMode m) {
    if (m == mode) return;
    final cur = page;
    setState(() {
      mode = m;
      pc.dispose();
      pc = PageController(initialPage: cur);
    });
  }

  void _toggleOrientationLock() {
    orientationLocked = !orientationLocked;
    SystemChrome.setPreferredOrientations(orientationLocked ? [DeviceOrientation.portraitUp] : []);
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

  /// تپ: ۲۸٪ لبه‌ها = صفحه قبل/بعد، مرکز = نمایش/پنهان‌سازی منوها
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

  // ───────── build ─────────
  @override
  Widget build(BuildContext context) {
    final w = targetWidthFor(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: mode == ReadMode.webtoon ? _webtoon(w) : _paged(w)),
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
          imageProvider: ComicPageProvider(widget.entry.id, cache, i, w),
          minScale: PhotoViewComputedScale.contained,       // «فیت» کامل صفحه
          initialScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          // دابل‌تپ: فیت ↔ پر کردن عرض/ارتفاع (covered)
          scaleStateCycle: (s) => s == PhotoViewScaleState.initial
              ? PhotoViewScaleState.covering
              : PhotoViewScaleState.initial,
          onTapUp: (c, d, v) => _tap(d.globalPosition),
          filterQuality: FilterQuality.medium,
        ),
      );

  Widget _webtoon(int w) => _ZoomHost(
        onTap: _toggleChrome,
        child: ScrollablePositionedList.builder(
          key: ValueKey(mode),
          itemCount: count,
          initialScrollIndex: page,
          itemScrollController: itemScroll,
          itemPositionsListener: itemPos,
          itemBuilder: (c, i) => Image(
            image: ComicPageProvider(widget.entry.id, cache, i, w),
            width: double.infinity,
            fit: BoxFit.fitWidth,
            gaplessPlayback: true,
            frameBuilder: (ctx, child, frame, sync) => frame == null
                ? AspectRatio(aspectRatio: .7, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : child,
          ),
        ),
      );

  Widget _bar({required bool top, required Widget child}) => Positioned(
        top: top ? 0 : null, bottom: top ? null : 0, left: 0, right: 0,
        child: IgnorePointer(
          ignoring: !chrome,
          child: AnimatedOpacity(
            opacity: chrome ? 1 : 0, duration: const Duration(milliseconds: 180),
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
        Expanded(child: Text(widget.entry.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        IconButton(
          tooltip: 'Lock rotation',
          icon: Icon(orientationLocked ? Icons.screen_lock_rotation : Icons.screen_rotation),
          onPressed: _toggleOrientationLock,
        ),
        PopupMenuButton<ReadMode>(
          icon: const Icon(Icons.chrome_reader_mode_outlined),
          onSelected: _setMode,
          itemBuilder: (_) => const [
            PopupMenuItem(value: ReadMode.ltr, child: Text('Paged (LTR)')),
            PopupMenuItem(value: ReadMode.rtl, child: Text('Manga (RTL)')),
            PopupMenuItem(value: ReadMode.webtoon, child: Text('Webtoon (vertical)')),
          ],
        ),
      ]);

  Widget _bottomBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Scrubber(
          count: count, current: page, rtl: rtl, onSeek: _seek,
          thumbBuilder: (i) => Image(
            image: ComicPageProvider(widget.entry.id, cache, i, 200), // دیکد کوچک ← ارزان
            fit: BoxFit.cover,
          ),
        ),
      );
}

/// میزبان زوم برای Webtoon: زوم با پینچ، دابل‌تپ، و پن فقط وقتی زوم شده.
/// ⚠️ تداخل ژست InteractiveViewer با ListView را روی دستگاه واقعی تست کنید
/// (در صورت مشکل: پیاده‌سازی Listener-محور با شمارش pointer).
class _ZoomHost extends StatefulWidget {
  const _ZoomHost({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<_ZoomHost> createState() => _ZoomHostState();
}

class _ZoomHostState extends State<_ZoomHost> {
  final tc = TransformationController();
  bool zoomed = false;
  Offset _dt = Offset.zero;

  @override
  void initState() {
    super.initState();
    tc.addListener(() {
      final z = tc.value.getMaxScaleOnAxis() > 1.01;
      if (z != zoomed) setState(() => zoomed = z);
    });
  }

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  void _doubleTap() {
    if (zoomed) {
      tc.value = Matrix4.identity();
    } else {
      const s = 2.2;
      tc.value = Matrix4.identity()
        ..translate(-_dt.dx * (s - 1), -_dt.dy * (s - 1))
        ..scale(s);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.onTap,
        onDoubleTapDown: (d) => _dt = d.localPosition,
        onDoubleTap: _doubleTap,
        child: InteractiveViewer(
          transformationController: tc,
          minScale: 1, maxScale: 4,
          panEnabled: zoomed,
          child: widget.child,
        ),
      );
}
