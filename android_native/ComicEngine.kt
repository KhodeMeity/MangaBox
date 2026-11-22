package com.mangabox.mangabox

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import com.github.junrar.Archive
import com.github.junrar.exception.UnsupportedRarV5Exception
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStream
import java.io.RandomAccessFile
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.ZipEntry
import java.util.zip.ZipFile

class EngineError(val code: String, message: String) : Exception(message)

/**
 * موتور خواندن کمیک (کاملاً native و بدون پکیج خارجی):
 *   ZIP/CBZ → java.util.zip.ZipFile (دسترسی تصادفی، بدون کش حافظه)
 *   PDF     → android.graphics.pdf.PdfRenderer
 *   RAR/CBR → junrar (RAR نسخه‌ی ۴؛ RAR5 هنوز نه) با استخراج ترتیبی در cache
 * Dart فقط می‌گوید «صفحه‌ی N را بده» و بایت‌های تصویر را می‌گیرد.
 */
class ComicEngine(private val ctx: Context) {
    private val pool = Executors.newFixedThreadPool(3)
    private val ui = Handler(Looper.getMainLooper())
    private val sessions = ConcurrentHashMap<Int, Session>()
    private val ids = AtomicInteger(1)

    // ───────────────────────── Sessions ─────────────────────────
    abstract class Session(private val pfd: ParcelFileDescriptor?) {
        abstract val type: String
        abstract val pageCount: Int
        abstract fun page(index: Int, width: Int): ByteArray
        open fun close() {
            try { pfd?.close() } catch (_: Exception) {}
        }
    }

    class ZipSession(
        private val zip: ZipFile,
        private val entries: List<ZipEntry>,
        pfd: ParcelFileDescriptor?,
    ) : Session(pfd) {
        override val type = "zip"
        override val pageCount get() = entries.size
        override fun page(index: Int, width: Int): ByteArray =
            zip.getInputStream(entries[index]).use { it.readBytes() }

        override fun close() {
            try { zip.close() } catch (_: Exception) {}
            super.close()
        }
    }

    class PdfSession(
        private val renderer: PdfRenderer,
        private val fd: ParcelFileDescriptor,
        pfd: ParcelFileDescriptor?,
    ) : Session(pfd) {
        override val type = "pdf"
        override val pageCount get() = renderer.pageCount

        // PdfRenderer فقط یک صفحه‌ی باز هم‌زمان می‌پذیرد
        @Synchronized
        override fun page(index: Int, width: Int): ByteArray {
            val w = if (width > 0) width else 1600
            val p = renderer.openPage(index)
            try {
                val h = (w.toFloat() * p.height / p.width).toInt().coerceAtLeast(1)
                val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                bmp.eraseColor(Color.WHITE)
                p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                val out = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, 92, out)
                bmp.recycle()
                return out.toByteArray()
            } finally {
                p.close()
            }
        }

        @Synchronized
        override fun close() {
            try { renderer.close() } catch (_: Exception) {}
            try { fd.close() } catch (_: Exception) {}
            super.close()
        }
    }

    /** صفحه‌های RAR از فایل‌های استخراج‌شده در cache خوانده می‌شوند. */
    class RarSession(
        private val files: List<File>,
        private val deleteOnClose: File?,
        pfd: ParcelFileDescriptor?,
        private val total: Int = files.size,
    ) : Session(pfd) {
        override val type = "rar"
        override val pageCount get() = total
        override fun page(index: Int, width: Int): ByteArray {
            if (index >= files.size) throw EngineError("PAGE", "page not extracted")
            return files[index].readBytes()
        }

        override fun close() {
            try { deleteOnClose?.delete() } catch (_: Exception) {}
            super.close()
        }
    }

    // ───────────────────────── API ─────────────────────────
    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        pool.execute {
            try {
                val v = block()
                ui.post { result.success(v) }
            } catch (e: EngineError) {
                ui.post { result.error(e.code, e.message, null) }
            } catch (e: Throwable) {
                ui.post { result.error("OPEN", e.toString(), null) }
            }
        }
    }

    /** cover=true: فقط برای ساخت کاور (در RAR فقط تا صفحه‌ی اول استخراج می‌شود). */
    fun open(uriStr: String, cover: Boolean, result: MethodChannel.Result) = async(result) {
        val (file, pfd) = materialize(Uri.parse(uriStr))
        try {
            val key = Integer.toHexString(uriStr.hashCode()) + "_" + file.length()
            val s = openFile(file, pfd, key, cover)
            val id = ids.getAndIncrement()
            sessions[id] = s
            mapOf("id" to id, "pages" to s.pageCount, "type" to s.type)
        } catch (e: Throwable) {
            try { pfd?.close() } catch (_: Exception) {}
            throw e
        }
    }

    fun page(id: Int, index: Int, width: Int, result: MethodChannel.Result) = async(result) {
        val s = sessions[id] ?: throw EngineError("CLOSED", "closed")
        s.page(index, width)
    }

    fun close(id: Int, result: MethodChannel.Result) = async(result) {
        sessions.remove(id)?.close()
        null
    }

    // ───────────────────────── فایل ─────────────────────────
    private fun magic(f: File): ByteArray = RandomAccessFile(f, "r").use {
        val b = ByteArray(8)
        val n = it.read(b)
        b.copyOf(if (n < 0) 0 else n)
    }

    private fun openFile(file: File, pfd: ParcelFileDescriptor?, key: String, cover: Boolean): Session {
        val m = magic(file)
        fun starts(vararg x: Int) = m.size >= x.size && x.indices.all { (m[it].toInt() and 0xFF) == x[it] }
        return when {
            starts(0x50, 0x4B) -> {                       // "PK" → ZIP / CBZ
                val zip = ZipFile(file)
                val entries = zip.entries().toList()
                    .filter { !it.isDirectory && isImage(it.name) }
                    .sortedWith { a, b -> natural(a.name, b.name) }
                if (entries.isEmpty()) {
                    zip.close()
                    throw EngineError("NO_IMAGES", "no images")
                }
                ZipSession(zip, entries, pfd)
            }
            starts(0x25, 0x50, 0x44, 0x46) -> {           // "%PDF"
                val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                try {
                    PdfSession(PdfRenderer(fd), fd, pfd)
                } catch (e: SecurityException) {
                    fd.close()
                    throw EngineError("PDF_LOCKED", "password")
                }
            }
            starts(0x52, 0x61, 0x72, 0x21) -> openRar(file, key, cover, pfd)   // "Rar!"
            else -> throw EngineError("FORMAT", "unknown format")
        }
    }

    /**
     * content:// → فایل قابل‌خواندن.
     *  ۱) تلاش برای باز کردن مستقیم از طریق fd (بدون کپی)
     *  ۲) اگر اندروید اجازه نداد → کپی موقت در cache (فقط ۳ فایل آخر نگه داشته می‌شود)
     */
    private fun materialize(uri: Uri): Pair<File, ParcelFileDescriptor?> {
        if (uri.scheme == "file") return Pair(File(uri.path!!), null)
        try {
            val pfd = ctx.contentResolver.openFileDescriptor(uri, "r")
            if (pfd != null) {
                val f = File("/proc/self/fd/${pfd.fd}")
                try {
                    RandomAccessFile(f, "r").use { it.read() }
                    return Pair(f, pfd)
                } catch (_: Exception) {
                    pfd.close()
                }
            }
        } catch (_: Exception) {}
        return Pair(copyToCache(uri), null)
    }

    private fun copyToCache(uri: Uri): File {
        val dir = File(ctx.cacheDir, "comics").apply { mkdirs() }
        val dst = File(dir, Integer.toHexString(uri.toString().hashCode()))
        if (!dst.exists()) {
            val tmp = File(dir, dst.name + ".tmp")
            val input = ctx.contentResolver.openInputStream(uri) ?: throw EngineError("OPEN", "cannot read uri")
            input.use { i -> tmp.outputStream().use { o -> i.copyTo(o, 1 shl 16) } }
            tmp.renameTo(dst)
        }
        dst.setLastModified(System.currentTimeMillis())
        dir.listFiles()
            ?.filter { it != dst && !it.name.endsWith(".tmp") }
            ?.sortedByDescending { it.lastModified() }
            ?.drop(2)
            ?.forEach { it.delete() }
        return dst
    }

    // ───────────────────────── RAR ─────────────────────────
    private val rarLock = Any()

    private val discard = object : OutputStream() {
        override fun write(b: Int) {}
        override fun write(b: ByteArray, off: Int, len: Int) {}
    }

    /**
     * RAR (به‌خصوص «solid») دسترسی تصادفی ندارد؛ پس همه‌ی تصویرها یک‌بار به‌ترتیبِ داخل آرشیو
     * در cacheDir/rar/<key>/ استخراج می‌شوند و بعد مثل CBZ خوانده می‌شوند.
     * فقط ۲ کمیک آخر در cache نگه داشته می‌شود. RAR5 توسط junrar پشتیبانی نمی‌شود.
     */
    private fun openRar(file: File, key: String, cover: Boolean, pfd: ParcelFileDescriptor?): Session =
        synchronized(rarLock) {
            val head = magic(file)
            if (head.size > 6 && head[6].toInt() == 1) throw EngineError("RAR5", "rar5")   // Rar!\x1A\x07\x01

            val root = File(ctx.cacheDir, "rar").apply { mkdirs() }
            val dir = File(root, key)
            val done = File(dir, ".done")
            val orderFile = File(dir, ".order")

            if (!cover && done.exists() && orderFile.exists()) {         // قبلاً استخراج شده
                return@synchronized rarFromDir(root, dir, orderFile, pfd)
            }

            try {
                val archive = Archive(file)
                try {
                    @Suppress("DEPRECATION")
                    fun nameOf(i: Int) = archive.fileHeaders[i].fileNameString.replace('\\', '/')

                    val headers = archive.fileHeaders
                    val entries = ArrayList<Pair<Int, String>>()           // (شماره در آرشیو، نام)
                    for (i in headers.indices) {
                        if (headers[i].isDirectory) continue
                        val n = nameOf(i)
                        if (isImage(n)) entries.add(Pair(i, n))
                    }
                    if (entries.isEmpty()) throw EngineError("NO_IMAGES", "no images")
                    val sorted = entries.sortedWith { a, b -> natural(a.second, b.second) }

                    if (cover) {
                        val target = sorted[0].first
                        val out = File(root, "cover_$key.bin")
                        for (i in headers.indices) {
                            if (i > target) break
                            if (headers[i].isDirectory) continue
                            if (i == target) out.outputStream().use { archive.extractFile(headers[i], it) }
                            else archive.extractFile(headers[i], discard)    // برای solid لازم است
                        }
                        return@synchronized RarSession(listOf(out), out, pfd, sorted.size)
                    }

                    dir.deleteRecursively()
                    dir.mkdirs()
                    val wanted = entries.map { it.first }.toHashSet()
                    for (i in headers.indices) {
                        if (headers[i].isDirectory) continue
                        if (wanted.contains(i)) File(dir, "$i.bin").outputStream().use { archive.extractFile(headers[i], it) }
                        else archive.extractFile(headers[i], discard)
                    }
                    orderFile.writeText(sorted.joinToString("\n") { it.first.toString() })
                    done.writeText("ok")
                } finally {
                    try { archive.close() } catch (_: Exception) {}
                }
            } catch (e: EngineError) {
                throw e
            } catch (e: UnsupportedRarV5Exception) {
                throw EngineError("RAR5", "rar5")
            } catch (e: Throwable) {
                throw EngineError("RAR_BAD", e.toString())
            }
            rarFromDir(root, dir, orderFile, pfd)
        }

    private fun rarFromDir(root: File, dir: File, orderFile: File, pfd: ParcelFileDescriptor?): Session {
        val files = orderFile.readLines().filter { it.isNotBlank() }.map { File(dir, it.trim() + ".bin") }
        dir.setLastModified(System.currentTimeMillis())
        root.listFiles()
            ?.filter { it.isDirectory && it != dir }
            ?.sortedByDescending { it.lastModified() }
            ?.drop(1)
            ?.forEach { it.deleteRecursively() }
        return RarSession(files, null, pfd)
    }

    // ───────────────────────── کمکی‌ها ─────────────────────────
    private val imgExt = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp")

    private fun isImage(name: String): Boolean {
        val n = name.lowercase()
        if (n.contains("__macosx") || n.substringAfterLast('/').startsWith(".")) return false
        return imgExt.contains(n.substringAfterLast('.', ""))
    }

    private val chunk = Regex("(\\d+)|(\\D+)")

    /** مرتب‌سازی طبیعی: ۲ قبل از ۱۰ */
    private fun natural(a: String, b: String): Int {
        val x = chunk.findAll(a.lowercase()).map { it.value }.toList()
        val y = chunk.findAll(b.lowercase()).map { it.value }.toList()
        for (i in 0 until minOf(x.size, y.size)) {
            val nx = x[i].toBigIntegerOrNull()
            val ny = y[i].toBigIntegerOrNull()
            val c = if (nx != null && ny != null) nx.compareTo(ny) else x[i].compareTo(y[i])
            if (c != 0) return c
        }
        return x.size.compareTo(y.size)
    }
}
