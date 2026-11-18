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

# 3) Gradle dependency
for name, line in (("build.gradle.kts", 'implementation("androidx.documentfile:documentfile:1.0.1")'),
                   ("build.gradle", "implementation 'androidx.documentfile:documentfile:1.0.1'")):
    g = app / name
    if g.exists():
        t = g.read_text()
        if "documentfile" not in t:
            t += f"\n\ndependencies {{\n    {line}\n}}\n"
            g.write_text(t)
        break
print("android setup done:", PKG)
