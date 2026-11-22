package com.mangabox.mangabox

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private lateinit var ch: MethodChannel
    private lateinit var engine: ComicEngine
    private var pending: MethodChannel.Result? = null
    private var dartReady = false
    private val queue = mutableListOf<Map<String, Any?>>()
    private val exts = setOf("cbz", "cbr", "zip", "rar", "pdf")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engine = ComicEngine(applicationContext)
        ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mangabox/engine")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {                       // Dart آماده است؛ فایل‌های منتظر را بفرست
                    dartReady = true
                    queue.forEach { ch.invokeMethod("onUri", it) }
                    queue.clear()
                    result.success(null)
                }
                "open" -> engine.open(call.argument<String>("uri")!!, call.argument<Boolean>("cover") ?: false, result)
                "page" -> engine.page(call.argument<Int>("id")!!, call.argument<Int>("index")!!, call.argument<Int>("width") ?: 0, result)
                "close" -> engine.close(call.argument<Int>("id")!!, result)
                "pickFiles" -> {
                    pending = result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }, 1)
                }
                "pickFolder" -> {
                    pending = result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }, 2)
                }
                "deleteImported" -> {              // حذف کپی داخلی فایل‌هایی که از تلگرام/اینتنت آمده‌اند
                    val p = call.argument<String>("path")!!
                    if (p.startsWith(File(filesDir, "imported").absolutePath)) File(p).delete()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    // ───────────── فایل ورودی از بیرون (تلگرام، فایل‌منیجر، Share) ─────────────
    @Suppress("DEPRECATION")
    private fun handleIntent(i: Intent?) {
        val it0 = i ?: return
        val uri: Uri? = when (it0.action) {
            Intent.ACTION_VIEW -> it0.data
            Intent.ACTION_SEND -> it0.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return
        Thread {
            try {
                val durable = durableUri(uri)
                val m = describe(durable)
                runOnUiThread {
                    if (dartReady) ch.invokeMethod("onUri", m) else queue.add(m)
                }
            } catch (_: Throwable) {}
        }.start()
    }

    /**
     * اگر اندروید اجازه‌ی «دسترسی ماندگار» بدهد همان URI نگه داشته می‌شود؛
     * وگرنه (مثل تلگرام) فایل یک بار در حافظه‌ی داخلی اپ کپی می‌شود تا بعد از بستن اپ هم در کتابخانه قابل‌باز شدن باشد.
     */
    private fun durableUri(uri: Uri): Uri {
        if (uri.scheme == "file") return uri
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            return uri
        } catch (_: Exception) {}
        val name = describe(uri)["name"] as String
        val dir = File(filesDir, "imported").apply { mkdirs() }
        val dst = File(dir, Integer.toHexString(uri.toString().hashCode()) + "_" + name.replace('/', '_'))
        if (!dst.exists()) {
            val tmp = File(dir, dst.name + ".tmp")
            contentResolver.openInputStream(uri)!!.use { i -> tmp.outputStream().use { o -> i.copyTo(o, 1 shl 16) } }
            tmp.renameTo(dst)
        }
        return Uri.fromFile(dst)
    }

    private fun describe(u: Uri): Map<String, Any?> {
        if (u.scheme == "file") return mapOf("uri" to u.toString(), "name" to (File(u.path!!).name))
        var name = u.lastPathSegment ?: "comic"
        try {
            contentResolver.query(u, null, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) name = c.getString(idx)
                }
            }
        } catch (_: Exception) {}
        return mapOf("uri" to u.toString(), "name" to name)
    }

    // ───────────── انتخاب فایل/پوشه (SAF) ─────────────
    private fun persist(u: Uri) {
        try {
            contentResolver.takePersistableUriPermission(u, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {}
    }

    private fun scan(dir: DocumentFile, out: MutableList<Map<String, Any?>>) {
        for (f in dir.listFiles()) {
            if (f.isDirectory) scan(f, out)
            else if (exts.contains(f.name?.substringAfterLast('.', "")?.lowercase()))
                out.add(mapOf("uri" to f.uri.toString(), "name" to (f.name ?: "comic")))
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 1 && requestCode != 2) return
        val r = pending ?: return
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            r.success(emptyList<Any>())
            return
        }
        Thread {
            val out = mutableListOf<Map<String, Any?>>()
            try {
                if (requestCode == 1) {
                    val clip = data.clipData
                    val uris = if (clip != null) (0 until clip.itemCount).map { clip.getItemAt(it).uri } else listOfNotNull(data.data)
                    uris.forEach { persist(it); out.add(describe(it)) }
                } else {
                    val tree = data.data!!
                    persist(tree)
                    DocumentFile.fromTreeUri(this, tree)?.let { scan(it, out) }
                }
            } catch (_: Throwable) {}
            runOnUiThread { r.success(out) }
        }.start()
    }
}
