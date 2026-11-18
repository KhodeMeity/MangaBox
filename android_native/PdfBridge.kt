package com.mangabox.mangabox

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/** PdfRenderer از نظر thread-safe نیست → همه‌ی کارها روی یک executor تک‌ریسمانی. */
object PdfBridge {
    private val exec = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private val renderers = HashMap<String, PdfRenderer>()
    private val fds = HashMap<String, ParcelFileDescriptor>()

    private fun run(result: MethodChannel.Result, block: () -> Any?) = exec.execute {
        try {
            val v = block()
            ui.post { result.success(v) }
        } catch (e: Throwable) {
            ui.post { result.error("PDF", e.message, null) }
        }
    }

    fun open(path: String, result: MethodChannel.Result) = run(result) {
        val pfd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        val r = PdfRenderer(pfd)
        renderers[path] = r; fds[path] = pfd
        r.pageCount
    }

    fun page(path: String, index: Int, width: Int, result: MethodChannel.Result) = run(result) {
        val r = renderers[path] ?: throw IllegalStateException("PDF closed")
        val p = r.openPage(index)
        try {
            val h = (width.toFloat() * p.height / p.width).toInt().coerceAtLeast(1)
            val bmp = Bitmap.createBitmap(width, h, Bitmap.Config.ARGB_8888)
            bmp.eraseColor(Color.WHITE)
            p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 92, out)
            bmp.recycle()
            out.toByteArray()
        } finally {
            p.close()
        }
    }

    fun close(path: String, result: MethodChannel.Result) = run(result) {
        renderers.remove(path)?.close()
        fds.remove(path)?.close()
        null
    }
}
