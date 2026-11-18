package com.mangabox.mangabox

/**
 * پشتیبانی CBR (RAR5). junrar فقط RAR4 را می‌خواند، پس از libarchive استفاده کنید:
 *   implementation("me.zhanghai.android.libarchive:library:<latest>")
 *
 * قرارداد:
 *   list(path)            -> نام فایل‌های داخل آرشیو
 *   extract(path, name)   -> بایت‌های همان فایل
 *
 * ⚠️ این فایل عمداً اسکلت است؛ API دقیق کتابخانه را از README خودش پیاده کنید.
 * RAR solid دسترسی تصادفی ندارد → راهکار پیشنهادی: در اولین extract، همه‌ی صفحات را
 * به‌ترتیب در cacheDir/<hash>/ بنویسید (روی ترد پس‌زمینه) و بعدی‌ها را از همان فایل‌ها بخوانید؛
 * پوشه را با سقف حجم (LRU) پاک کنید.
 */
object RarBridge {
    fun list(path: String): List<String> = TODO("libarchive: iterate entries, collect pathnames")
    fun extract(path: String, name: String): ByteArray = TODO("libarchive: read entry data")
}
