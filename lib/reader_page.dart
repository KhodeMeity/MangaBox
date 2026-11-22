import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'engine.dart';
import 'page_cache.dart';
import 'panels.dart';
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
      builder: (_) => const PopScope(
        canPop: false,
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(S.opening),
            ]),
          ),
        ),
      ),
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

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final PageCache cache = PageCache(widget.doc);
  late final int count = widget.doc.pages;
  late int page = widget.comic.lastPage.clamp(0, count - 1);
  late PageController pc = PageController(initialPage: page);
  late ReadMode mode = ReadMode.values[widget.store.mode.clamp(0, 2)];
  final itemScroll = ItemScrollController();
  final itemPos = ItemPositionsListener.create();

  // ───── زوم هوشمند روی پنل ─────
  late final AnimationController _zoomAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  VoidCallback? _tick;
  final _ctrls = <int, PhotoViewController>{};
  final _panelJobs = <int, Future<PanelInfo?>>{};
  final _zoomedPage = <int, double>{}; // صفحه‌هایی که الان زوم‌اند ← مقیاس عادی (contain) آن‌ها
  Offset _lastTap = Offset.zero;
  int _decodeW = 0;
  bool _spreadPrev = false; // آیا pager فعلی دو صفحه‌ای ساخته شده؟

  bool chrome = true;
  bool locked = false;
  double webZoom = 1;                       // زوم وبتون (۱ تا ۴)
  bool pinching = false;
  final hCtrl = ScrollController();         // پن افقی وقتی زوم شده
  final _pointers = <int, Offset>{};
  double _pinchDist = 0, _pinchStartZoom = 1, _dtFocalX = 0;
  Timer? _saveTimer;

  bool get rtl => mode == ReadMode.rtl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    itemPos.itemPositions.addListener(_onPositions);
    cache.prefetch(page, 1);
    _warmPanels(page);
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
    hCtrl.dispose();
    _zoomAnim.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
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
    final gi = _spreadPrev ? _spreadOf(page) : page; // کلید صفحه/اسپرد فعلی در pager
    final s0 = _zoomedPage.remove(gi); // صفحه‌ی قبلی را از زوم درآور
    if (s0 != null) _ctrls[gi]?.updateMultiple(scale: s0, position: Offset.zero);
    setState(() => page = i);
    cache.prefetch(i, dir, ahead: _spreadPrev ? 5 : 3);
    _warmPanels(i);
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
    setState(() {
      mode = m;
      webZoom = 1;
      _rebuildPager();
    });
    widget.store.setMode(m.index);
  }

  // ───── دو صفحه‌ای (اسپرد) در حالت افقی ─────
  bool get _cover => widget.store.spreadCover;
  int get _spreadCount => _cover ? 1 + count ~/ 2 : (count + 1) ~/ 2;

  /// صفحه‌های هر اسپرد: با «جلد تنها»: [0]، [1,2]، [3,4]… وگرنه [0,1]، [2,3]…
  List<int> _spreadPages(int sIdx) {
    final a = _cover ? (sIdx == 0 ? 0 : 2 * sIdx - 1) : 2 * sIdx;
    final single = _cover && sIdx == 0;
    return (!single && a + 1 < count) ? [a, a + 1] : [a];
  }

  int _spreadOf(int p) => _cover ? (p == 0 ? 0 : (p + 1) ~/ 2) : p ~/ 2;

  bool _wantSpread(ReadMode m) {
    final sz = MediaQuery.of(context).size;
    return widget.store.dualPage && m != ReadMode.webtoon && sz.width > sz.height;
  }

  /// pager (کنترلر صفحه + کنترلرهای زوم) را از نو می‌سازد؛ صفحه‌ی فعلی حفظ می‌شود.
  void _rebuildPager() {
    final spread = _wantSpread(mode);
    final old = pc;
    pc = PageController(initialPage: spread ? _spreadOf(page) : page);
    _spreadPrev = spread;
    final oldCtrls = _ctrls.values.toList();
    _ctrls.clear();
    _zoomedPage.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
      for (final c in oldCtrls) {
        c.dispose();
      }
    });
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
      pc.jumpToPage(_spreadPrev ? _spreadOf(i) : i);
    }
  }

  void _step(int d) {
    final cur = _spreadPrev ? _spreadOf(page) : page;
    final last = (_spreadPrev ? _spreadCount : count) - 1;
    final t = (cur + d).clamp(0, last);
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
    final bucket = webZoom.ceil().clamp(1, 4); // پله‌ای: فقط وقتی از ۱→۲→۳→۴ رد شد کیفیت تصویر عوض می‌شود
    final web = mode == ReadMode.webtoon;
    final w = targetWidthFor(context, factor: web ? 1.2 * bucket : 2, useWidth: web);
    final spread = _wantSpread(mode);
    if (spread != _spreadPrev) _rebuildPager(); // چرخش گوشی یا تغییر تنظیم
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // جهت صفحه‌ی خواندن همیشه LTR است؛ جهت مانگا را خودمان با reverse کنترل می‌کنیم
        Positioned.fill(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: web ? _webtoon(w) : _paged(w, spread),
          ),
        ),
        _bar(top: true, child: _topBar()),
        _bar(top: false, child: _bottomBar()),
      ]),
    );
  }

  Widget _paged(int w, bool spread) {
    _decodeW = w;
    final size = MediaQuery.of(context).size;
    final smart = widget.store.smartZoom && !spread;
    return PhotoViewGallery.builder(
      key: ValueKey('$mode-$spread'),
      itemCount: spread ? _spreadCount : count,
      pageController: pc,
      reverse: rtl,
      onPageChanged: (i) => _onPage(spread ? _spreadPages(i).last : i),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      builder: (ctx, i) {
        if (spread) return _spreadOptions(i, w, size);
        return PhotoViewGalleryPageOptions(
          imageProvider: ComicPageProvider(widget.doc.id, cache, i, w),
          controller: _ctrls.putIfAbsent(i, () => PhotoViewController()),
          minScale: PhotoViewComputedScale.contained,
          initialScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 6,
          // دابل‌تپ: با زوم هوشمند، callback چرخه‌ی زوم را به تابع خودمان می‌دهیم و وضعیت را تغییر نمی‌دهیم
          scaleStateCycle: (s) {
            if (smart) {
              _smartDoubleTap(i);
              return s;
            }
            return s == PhotoViewScaleState.initial ? PhotoViewScaleState.covering : PhotoViewScaleState.initial;
          },
          onTapDown: (c, d, v) => _lastTap = d.globalPosition,
          onTapUp: (c, d, v) => _tap(d.globalPosition),
          filterQuality: FilterQuality.medium,
          errorBuilder: (c, e, st) => Center(
            child: Padding(padding: const EdgeInsets.all(24), child: Text('$e', textAlign: TextAlign.center)),
          ),
        );
      },
    );
  }

  /// یک اسپرد = دو صفحه‌ی کنار هم (در مانگا ترتیب برعکس) که وسط به هم می‌چسبند.
  PhotoViewGalleryPageOptions _spreadOptions(int sIdx, int w, Size size) {
    final pages = _spreadPages(sIdx);
    final ordered = rtl ? pages.reversed.toList() : pages;
    Widget img(int p, Alignment al) => Image(
          image: ComicPageProvider(widget.doc.id, cache, p, w),
          fit: BoxFit.contain,
          alignment: al,
          gaplessPlayback: true,
          frameBuilder: (ctx, child, frame, sync) =>
              frame == null ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : child,
          errorBuilder: (ctx, e, st) => Center(child: Text('$e', textAlign: TextAlign.center)),
        );
    final child = SizedBox(
      width: size.width,
      height: size.height,
      child: ordered.length == 1
          ? img(ordered[0], Alignment.center)
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: img(ordered[0], Alignment.centerRight)),
              Expanded(child: img(ordered[1], Alignment.centerLeft)),
            ]),
    );
    return PhotoViewGalleryPageOptions.customChild(
      child: child,
      childSize: size,
      controller: _ctrls.putIfAbsent(sIdx, () => PhotoViewController()),
      minScale: PhotoViewComputedScale.contained,
      initialScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.contained * 4,
      scaleStateCycle: (s) {
        _spreadDoubleTap(sIdx);
        return s;
      },
      onTapDown: (c, d, v) => _lastTap = d.globalPosition,
      onTapUp: (c, d, v) => _tap(d.globalPosition),
    );
  }

  /// دابل‌تپ روی اسپرد: زوم ۲٫۲× روی نقطه‌ی لمس؛ دابل‌تپ دوباره = برگشت
  void _spreadDoubleTap(int sIdx) {
    final c = _ctrls[sIdx];
    if (c == null) return;
    final back = _zoomedPage.remove(sIdx);
    if (back != null) {
      _animateZoom(c, back, Offset.zero);
      return;
    }
    final size = MediaQuery.of(context).size;
    const z = 2.2;
    final s0 = c.scale ?? 1.0;
    final t = _lastTap - Offset(size.width / 2, size.height / 2);
    final mx = (z - 1) * size.width / 2, my = (z - 1) * size.height / 2;
    final pos = Offset((-(z - 1) * t.dx).clamp(-mx, mx).toDouble(), (-(z - 1) * t.dy).clamp(-my, my).toDouble());
    _zoomedPage[sIdx] = s0;
    _animateZoom(c, s0 * z, pos);
  }

  // ───── زوم هوشمند: تشخیص پنل و زوم روی پنلی که دابل‌تپ شده ─────
  Future<PanelInfo?> _panelsFor(int i) => _panelJobs[i] ??= () async {
        final bytes = await cache.get(i);
        return detectPanels(bytes);
      }();

  void _warmPanels(int i) {
    if (widget.store.smartZoom && mode != ReadMode.webtoon && i >= 0 && i < count) {
      _panelsFor(i).ignore();
    }
  }

  Rect _panelAt(List<Rect> ps, double x, double y) {
    var best = ps.first;
    var bd = double.infinity;
    for (final r in ps) {
      final dx = x < r.left ? r.left - x : (x > r.right ? x - r.right : 0.0);
      final dy = y < r.top ? r.top - y : (y > r.bottom ? y - r.bottom : 0.0);
      final d = dx * dx + dy * dy;
      if (d < bd) {
        bd = d;
        best = r;
      }
    }
    return best;
  }

  void _animateZoom(PhotoViewController c, double s1, Offset p1) {
    if (_tick != null) _zoomAnim.removeListener(_tick!);
    _zoomAnim.stop();
    final s0 = c.scale ?? s1;
    final p0 = c.position;
    _tick = () {
      final t = Curves.easeOutCubic.transform(_zoomAnim.value);
      c.updateMultiple(scale: s0 + (s1 - s0) * t, position: Offset.lerp(p0, p1, t)!);
    };
    _zoomAnim.addListener(_tick!);
    _zoomAnim.forward(from: 0);
  }

  Future<void> _smartDoubleTap(int i) async {
    final c = _ctrls[i];
    if (c == null) return;

    // دابل‌تپ دوباره = برگشت به حالت «کل صفحه»
    final back = _zoomedPage.remove(i);
    if (back != null) {
      _animateZoom(c, back, Offset.zero);
      return;
    }

    final info = await _panelsFor(i);
    if (!mounted || i != page) return;
    final size = MediaQuery.of(context).size;

    if (info == null || _decodeW <= 0) {
      // تشخیص ممکن نشد: زوم ساده‌ی ۲×
      final s0 = c.scale ?? 1.0;
      _zoomedPage[i] = s0;
      _animateZoom(c, s0 * 2, Offset.zero);
      return;
    }

    // اندازه‌ی تصویرِ دیکدشده و مقیاس «contain» (دقیقاً همان که PhotoView حساب می‌کند)
    final wd = math.min(info.width, _decodeW).toDouble();
    final hd = info.height * wd / info.width;
    final s0 = math.min(size.width / wd, size.height / hd);
    final dw = wd * s0, dh = hd * s0; // اندازه‌ی نمایش در حالت contain

    double z;
    Offset pos;
    if (info.panels.length >= 2) {
      final nx = (_lastTap.dx - size.width / 2) / dw + .5;
      final ny = (_lastTap.dy - size.height / 2) / dh + .5;
      final p = _panelAt(info.panels, nx, ny);
      z = (math.min(size.width / (p.width * dw), size.height / (p.height * dh)) * .94).clamp(1.15, 6.0).toDouble();
      pos = Offset(-(z * dw) * (p.center.dx - .5), -(z * dh) * (p.center.dy - .5));
    } else {
      // پنل جدا پیدا نشد: پر کردن عرض/ارتفاع صفحه
      z = math.max(size.width / dw, size.height / dh).clamp(1.2, 3.0).toDouble();
      pos = Offset.zero;
    }
    // مرکز تصویر را طوری محدود کن که لبه‌ی صفحه از لبه‌ی صفحه‌نمایش داخل‌تر نیاید
    final mx = math.max(0.0, (z * dw - size.width) / 2), my = math.max(0.0, (z * dh - size.height) / 2);
    pos = Offset(pos.dx.clamp(-mx, mx).toDouble(), pos.dy.clamp(-my, my).toDouble());

    _zoomedPage[i] = s0;
    _animateZoom(c, s0 * z, pos);
  }

  // ───── زوم وبتون: پینچ دو انگشتی + دابل‌تپ ─────
  // پینچ را خودمان با Listener حساب می‌کنیم (بدون ورود به arena ژست‌ها)،
  // پس اسکرول عمودی با یک انگشت هیچ تداخلی ندارد. وقتی دو انگشت روی صفحه است، اسکرول موقتاً قفل می‌شود.
  double _pointerDist() {
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _ptrDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchDist = _pointerDist();
      _pinchStartZoom = webZoom;
      if (!pinching) setState(() => pinching = true);
    }
  }

  void _ptrMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && _pinchDist > 10) {
      final pts = _pointers.values.toList();
      final focal = (pts[0] + pts[1]) / 2;
      _setZoom(_pinchStartZoom * _pointerDist() / _pinchDist, focal.dx);
    }
  }

  void _ptrEnd(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _pinchDist = 0;
      if (pinching) setState(() => pinching = false);
    }
  }

  /// تغییر زوم با حفظ نقطه‌ی زیر انگشت در راستای افقی
  void _setZoom(double target, double focalX) {
    var nz = target.clamp(1.0, 4.0).toDouble();
    if (nz < 1.03) nz = 1.0;
    final old = webZoom;
    if (nz == old) return;
    final off = hCtrl.hasClients ? hCtrl.offset : 0.0;
    final newOff = nz == 1.0 ? 0.0 : (off + focalX) * nz / old - focalX;
    setState(() => webZoom = nz);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hCtrl.hasClients) {
        hCtrl.jumpTo(newOff.clamp(0.0, hCtrl.position.maxScrollExtent).toDouble());
      }
    });
  }

  Widget _webtoon(int w) => LayoutBuilder(
        builder: (ctx, c) {
          final zoomed = webZoom > 1.01;
          return Listener(
            onPointerDown: _ptrDown,
            onPointerMove: _ptrMove,
            onPointerUp: _ptrEnd,
            onPointerCancel: _ptrEnd,
            child: GestureDetector(
              onTap: _toggleChrome,
              onDoubleTapDown: (d) => _dtFocalX = d.globalPosition.dx,
              onDoubleTap: () => _setZoom(webZoom > 1.05 ? 1.0 : 2.5, _dtFocalX),
              child: SingleChildScrollView(
                controller: hCtrl,
                scrollDirection: Axis.horizontal,
                physics: (zoomed && !pinching) ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: c.maxWidth * webZoom,
                  height: c.maxHeight,
                  child: ScrollablePositionedList.builder(
                    key: ValueKey(mode),
                    physics: pinching ? const NeverScrollableScrollPhysics() : null,
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
        },
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
        if (mode != ReadMode.webtoon && MediaQuery.of(context).size.width > MediaQuery.of(context).size.height)
          PopupMenuButton<int>(
            tooltip: S.dualPage,
            icon: Icon(widget.store.dualPage ? Icons.auto_stories : Icons.auto_stories_outlined),
            onSelected: (v) {
              if (v == 0) {
                widget.store.setDualPage(!widget.store.dualPage);
              } else {
                widget.store.setSpreadCover(!widget.store.spreadCover);
              }
              setState(_rebuildPager);
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 0, checked: widget.store.dualPage, child: const Text(S.dualPage)),
              CheckedPopupMenuItem(
                value: 1,
                checked: widget.store.spreadCover,
                enabled: widget.store.dualPage,
                child: const Text(S.coverAlone),
              ),
            ],
          ),
        if (mode != ReadMode.webtoon)
          IconButton(
            tooltip: S.smartZoom,
            icon: Icon(widget.store.smartZoom ? Icons.auto_awesome : Icons.auto_awesome_outlined),
            onPressed: () {
              final on = !widget.store.smartZoom;
              widget.store.setSmartZoom(on);
              setState(() {});
              if (on) _warmPanels(page);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(on ? S.smartZoomOn : S.smartZoomOff),
                duration: const Duration(seconds: 2),
              ));
            },
          ),
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
