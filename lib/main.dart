import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'engine.dart';
import 'library_page.dart';
import 'reader_page.dart';
import 'store.dart';
import 'strings.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 160 * 1024 * 1024
    ..maximumSize = 40;
  final store = await LibraryStore.load();
  runApp(MangaBoxApp(store: store));
}

class MangaBoxApp extends StatefulWidget {
  const MangaBoxApp({super.key, required this.store});
  final LibraryStore store;
  @override
  State<MangaBoxApp> createState() => _MangaBoxAppState();
}

class _MangaBoxAppState extends State<MangaBoxApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Engine.start(_incoming); // فایل‌های ورودی از تلگرام/فایل‌منیجر
      widget.store.generateCovers();
    });
  }

  Future<void> _incoming(PickedFile f) async {
    final comic = await widget.store.add(f);
    final ctx = navKey.currentContext;
    if (ctx != null && ctx.mounted) ReaderPage.open(ctx, comic, widget.store);
    widget.store.generateCovers();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF7C83FF), brightness: Brightness.dark)
        .copyWith(surface: Colors.black);
    return MaterialApp(
      navigatorKey: navKey,
      title: S.appName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Waw',
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.black, // مشکی واقعی (OLED)
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black, elevation: 0, scrolledUnderElevation: 0),
      ),
      home: LibraryPage(store: widget.store),
    );
  }
}
