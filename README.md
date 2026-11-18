# MangaBox 📚

کمیک‌خوان کاملاً آفلاین برای اندروید (CBZ / CBR / PDF) با Flutter. فونت: **Waw**.

## ساخت APK با GitHub Actions (بدون نصب چیزی روی سیستم خودتان)
```bash
git init && git add . && git commit -m "MangaBox initial"
git branch -M main
git remote add origin https://github.com/<USER>/mangabox.git
git push -u origin main
```
- بعد از push، تب **Actions** ← workflow به اسم *Build MangaBox (Android)* خودکار اجرا می‌شود.
- خروجی: همان صفحه‌ی اجرا ← بخش **Artifacts** ← `mangabox-apk` (سه APK: arm64-v8a، armeabi-v7a، x86_64؛ روی بیشتر گوشی‌ها `arm64-v8a`).
- **Release خودکار:** `git tag v1.0.0 && git push origin v1.0.0` ← APK ها در بخش Releases مخزن منتشر می‌شوند.
- اجرای دستی: Actions ← Run workflow.

> پوشه‌ی `android/` داخل مخزن نیست؛ `tool/setup_android.py` در CI آن را با `flutter create` می‌سازد
> و MainActivity، intent-filter ها و نام «MangaBox» را اعمال می‌کند. اجرای محلی: `python3 tool/setup_android.py`.

> APK خروجی با کلید debug امضا می‌شود (برای نصب مستقیم مشکلی ندارد). برای Google Play / آپدیت پایدار باید keystore شخصی بسازید و به‌صورت GitHub Secrets به workflow بدهید.

## فونت
`assets/fonts/` شامل ۹ وزن Waw (UltraLight=100 … Black=900) و در `pubspec.yaml` ثبت شده؛ فونت پیش‌فرض کل تم است (`fontFamily: 'Waw'`).
دو فایل `DemiBold` و `UltraBold` عمداً در پروژه نیستند چون وزن‌شان با `Medium` و `Bold` یکی است و فلاتر برای هر وزن فقط یک فایل می‌پذیرد. فونت هم حروف لاتین دارد هم فارسی/ارقام فارسی.

## معماری
```
lib/
 core/        ComicSource + Zip(Isolate) / Rar(native) / Pdf + PageCache (LRU)
 platform/    Native (MethodChannel)، ComicOpener (uri → fd → path)
 data/        ComicEntry + ComicRepo (Hive، کاور، پیشرفت)
 features/    reader (۳ حالت خواندن، Scrubber)، library
android_native/   Kotlin (SAF، Intent، RAR bridge) + Manifest snippet
tool/setup_android.py   ساخت/پچ پروژه‌ی اندروید
```

## موارد باز (صادقانه)
1. **CBR/RAR5:** `RarBridge.kt` فعلاً اسکلت است (`TODO`) و باید با libarchive کامل شود؛ تا آن موقع فایل‌های CBZ و PDF کار می‌کنند.
2. **اولین build روی CI ممکن است خطا بدهد** (نسخه‌ی `pdfrx` و API آن، یا نسخه‌ی Flutter/Gradle). متن لاگ را بفرستید تا رفع شود.
3. حافظه‌ی `archive` (کش محتوا)، زوم Webtoon و فایل‌های تلگرام (دسترسی ماندگار) را روی گوشی واقعی تست کنید.
4. آیکون لانچر هنوز پیش‌فرض Flutter است (پیشنهاد: پکیج `flutter_launcher_icons`).
5. متن‌های UI فعلاً انگلیسی‌اند؛ فونت فارسی را پشتیبانی می‌کند و می‌توان رابط را فارسی/RTL کرد.
