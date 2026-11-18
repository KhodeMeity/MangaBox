import 'package:flutter/material.dart';
import 'data/comic_repo.dart';
import 'features/library/library_page.dart';
import 'features/reader/reader_page.dart';
import 'platform/native.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ComicRepo.init();
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 160 * 1024 * 1024
    ..maximumSize = 40;
  runApp(const ComicApp());
}

class ComicApp extends StatefulWidget {
  const ComicApp({super.key});
  @override
  State<ComicApp> createState() => _ComicAppState();
}

class _ComicAppState extends State<ComicApp> {
  @override
  void initState() {
    super.initState();
    Native.listenIncoming(_openIncoming);          // اپ در پس‌زمینه بود
    Native.initialFile().then((f) {                // اپ با کلیک روی فایل راه‌اندازی شد
      if (f != null) WidgetsBinding.instance.addPostFrameCallback((_) => _openIncoming(f));
    });
  }

  Future<void> _openIncoming(PickedFile f) async {
    final entry = await ComicRepo.register(f);
    ReaderPage.open(navKey.currentContext!, entry);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF7C83FF), brightness: Brightness.dark)
        .copyWith(surface: Colors.black);
    return MaterialApp(
      navigatorKey: navKey,
      title: 'MangaBox',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Waw',
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.black, // True Black (OLED)
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black, elevation: 0, scrolledUnderElevation: 0),
      ),
      home: const LibraryPage(),
    );
  }
}
