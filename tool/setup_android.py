#!/usr/bin/env python3
"""
پوشه‌ی android/ را (در صورت نبود) با `flutter create` می‌سازد و کدهای native پروژه را روی آن اعمال می‌کند:
  • کپی MainActivity.kt و RarBridge.kt
  • افزودن intent-filter ها، launchMode=singleTask و نام برنامه (MangaBox)
  • افزودن وابستگی documentfile
اجرای دوباره بی‌خطر است (idempotent). هم روی CI اجرا می‌شود هم محلی.
"""
import pathlib, re, shutil, subprocess

ORG, NAME, LABEL = "com.mangabox", "mangabox", "MangaBox"
PKG = f"{ORG}.{NAME}"
root = pathlib.Path(__file__).resolve().parent.parent

if not (root / "android").exists():
    subprocess.check_call(
        ["flutter", "create", "--platforms=android", "--org", ORG, "--project-name", NAME, "."], cwd=root)
    shutil.rmtree(root / "test", ignore_errors=True)   # تست پیش‌فرض به MyApp ارجاع دارد

app = root / "android" / "app"

# 1) Kotlin
kt_dir = app / "src/main/kotlin" / PKG.replace(".", "/")
for old in (app / "src/main/kotlin").rglob("MainActivity.kt"):
    old.unlink()
kt_dir.mkdir(parents=True, exist_ok=True)
for f in (root / "android_native").glob("*.kt"):
    code = re.sub(r"^package .*$", f"package {PKG}", f.read_text(), count=1, flags=re.M)
    (kt_dir / f.name).write_text(code)

# 2) Manifest
mf = app / "src/main/AndroidManifest.xml"
x = mf.read_text()
x = re.sub(r'android:label="[^"]*"', f'android:label="{LABEL}"', x, count=1)
x = re.sub(r'android:launchMode="[^"]*"', 'android:launchMode="singleTask"', x, count=1)
if "application/x-cbz" not in x:
    snippet = (root / "android_native/AndroidManifest.snippet.xml").read_text()
    x = x.replace("</activity>", snippet + "\n        </activity>", 1)
mf.write_text(x)

# 2.5) آیکون برنامه (adaptive + قدیمی + تک‌رنگ) روی آیکون پیش‌فرض Flutter کپی می‌شود
res_src = root / "android_native" / "res"
if res_src.exists():
    shutil.copytree(res_src, app / "src/main/res", dirs_exist_ok=True)

# 3) Gradle dependencies
DEPS = {
    "documentfile": ('implementation("androidx.documentfile:documentfile:1.0.1")',
                     "implementation 'androidx.documentfile:documentfile:1.0.1'"),
    "junrar": ('implementation("com.github.junrar:junrar:7.5.5")',
               "implementation 'com.github.junrar:junrar:7.5.5'"),
}
NO_SHRINK = {
    True: """

// mangabox-no-shrink: R8 با کلاس‌های ناموجودِ junrar (VFS/slf4j) خطا می‌دهد؛ برای APK شخصی shrink لازم نیست.
android {
    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
""",
    False: """

// mangabox-no-shrink: R8 با کلاس‌های ناموجودِ junrar (VFS/slf4j) خطا می‌دهد؛ برای APK شخصی shrink لازم نیست.
android {
    buildTypes {
        release {
            minifyEnabled false
            shrinkResources false
        }
    }
}
""",
}
for name, kts in (("build.gradle.kts", True), ("build.gradle", False)):
    g = app / name
    if g.exists():
        t = g.read_text()
        lines = [v[0 if kts else 1] for k, v in DEPS.items() if k not in t]
        if lines:
            t += "\n\ndependencies {\n    " + "\n    ".join(lines) + "\n}\n"
        if "mangabox-no-shrink" not in t:
            t += NO_SHRINK[kts]
        g.write_text(t)
        break
print("android setup done:", PKG)
