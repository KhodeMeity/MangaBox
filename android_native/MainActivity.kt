package com.mangabox.mangabox

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var ch: MethodChannel
    private var pending: MethodChannel.Result? = null
    private var initial: Map<String, Any?>? = null
    private val exts = setOf("cbz", "cbr", "zip", "rar", "pdf")

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        ch = MethodChannel(engine.dartExecutor.binaryMessenger, "comic/native")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialUri" -> { result.success(initial); initial = null }
                "pickFiles" -> {
                    pending = result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
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
                // content:// → fd جداشده؛ Dart آن را با /proc/self/fd/N باز می‌کند (بدون کپی)
                "openFd" -> try {
                    val pfd = contentResolver.openFileDescriptor(Uri.parse(call.argument<String>("uri")), "r")
                    result.success(pfd!!.detachFd())
                } catch (e: Exception) { result.error("OPEN", e.message, null) }
                "closeFd" -> { ParcelFileDescriptor.adoptFd(call.argument<Int>("fd")!!).close(); result.success(null) }
                "rarList" -> result.success(RarBridge.list(call.argument("path")!!))
                "rarExtract" -> result.success(RarBridge.extract(call.argument("path")!!, call.argument("name")!!))
                else -> result.notImplemented()
            }
        }
        handleIntent(intent, startup = true)
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); handleIntent(intent, false) }

    private fun handleIntent(i: Intent?, startup: Boolean) {
        val uri: Uri? = when (i?.action) {
            Intent.ACTION_VIEW -> i.data
            Intent.ACTION_SEND -> @Suppress("DEPRECATION") i.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        uri ?: return
        persist(uri)                         // اگر provider اجازه دهد، دسترسی ماندگار می‌شود (تلگرام معمولاً نه)
        val m = describe(uri)
        if (startup) initial = m else ch.invokeMethod("onUri", m)
    }

    private fun persist(u: Uri) = try {
        contentResolver.takePersistableUriPermission(u, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    } catch (_: Exception) {}

    private fun describe(u: Uri): Map<String, Any?> {
        var name = u.lastPathSegment ?: "comic"; var size = 0L
        contentResolver.query(u, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { name = c.getString(it) }
                c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 }?.let { size = c.getLong(it) }
            }
        }
        return mapOf("uri" to u.toString(), "name" to name, "size" to size)
    }

    private fun scan(dir: DocumentFile, out: MutableList<Map<String, Any?>>) {
        for (f in dir.listFiles()) {
            if (f.isDirectory) scan(f, out)
            else if (exts.contains(f.name?.substringAfterLast('.', "")?.lowercase()))
                out.add(mapOf("uri" to f.uri.toString(), "name" to f.name, "size" to f.length()))
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(req: Int, res: Int, data: Intent?) {
        super.onActivityResult(req, res, data)
        val r = pending ?: return; pending = null
        if (res != Activity.RESULT_OK || data == null) { r.success(emptyList<Any>()); return }
        Thread {   // اسکن پوشه‌های بزرگ روی ترد پس‌زمینه
            val out = mutableListOf<Map<String, Any?>>()
            if (req == 1) {
                val clip = data.clipData
                val uris = if (clip != null) (0 until clip.itemCount).map { clip.getItemAt(it).uri } else listOfNotNull(data.data)
                uris.forEach { persist(it); out.add(describe(it)) }
            } else {
                val tree = data.data!!
                contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                DocumentFile.fromTreeUri(this, tree)?.let { scan(it, out) }
            }
            runOnUiThread { r.success(out) }
        }.start()
    }
}
