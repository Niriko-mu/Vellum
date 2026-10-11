package com.example.vellum

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.CancellationSignal
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** User-granted SAF tree only. Traversal and copying never run on Android's UI thread. */
class LocalBookScanner(private val activity: FlutterActivity) : EventChannel.StreamHandler {
    companion object { const val PICK_TREE = 4817 }
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val generation = AtomicInteger(0)
    private val querySignal = AtomicReference<CancellationSignal?>()
    private val copyInput = AtomicReference<java.io.InputStream?>()
    private var sink: EventChannel.EventSink? = null
    private var pendingPicker: MethodChannel.Result? = null
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null; cancel() }
    private fun cancel() {
        generation.incrementAndGet()
        querySignal.getAndSet(null)?.cancel()
        try { copyInput.getAndSet(null)?.close() } catch (_: Exception) { }
    }
    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> {
                if (pendingPicker != null) { result.error("BUSY", "目录选择器已打开", null); return }
                pendingPicker = result
                try {
                    activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION), PICK_TREE)
                } catch (e: Exception) { pendingPicker = null; result.error("PICK_FAILED", e.message, null) }
            }
            "scanDirectory" -> {
                val value = call.argument<String>("uri")
                if (value == null) { result.error("BAD_URI", "缺少授权目录", null); return }
                cancel()
                val task = generation.get()
                result.success(true)
                executor.execute { scan(Uri.parse(value), task) }
            }
            "copyFile" -> {
                val uri = call.argument<String>("uri")
                val name = call.argument<String>("name") ?: "book.txt"
                if (uri == null) { result.error("BAD_URI", "缺少文件", null); return }
                val task = generation.get()
                executor.execute {
                    var output: File? = null
                    try {
                        val suffix = name.substringAfterLast('.', "txt").lowercase()
                        if (suffix !in listOf("txt", "epub", "mobi")) throw IllegalArgumentException("不支持的文件格式")
                        val target = File.createTempFile("vellum_scan_", ".$suffix", activity.cacheDir)
                        output = target
                        activity.contentResolver.openInputStream(Uri.parse(uri)).use { input ->
                            if (input == null) throw IllegalStateException("文件无法读取")
                            copyInput.set(input)
                            target.outputStream().use { out ->
                                val buffer = ByteArray(65536)
                                var total = 0L
                                while (true) {
                                    if (generation.get() != task) throw InterruptedException("已取消")
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    total += count
                                    if (total > 200L * 1024 * 1024) throw IllegalStateException("文件超过 200 MB，请先拆分")
                                    out.write(buffer, 0, count)
                                }
                            }
                        }
                        copyInput.set(null)
                        val value = mapOf("name" to name, "path" to target.path, "size" to target.length())
                        main.post { result.success(value) }
                    } catch (e: Exception) {
                        copyInput.set(null)
                        output?.delete()
                        main.post { result.error("COPY_FAILED", e.message, null) }
                    }
                }
            }
            "cancel" -> { cancel(); result.success(true) }
            else -> result.notImplemented()
        }
    }
    fun activityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != PICK_TREE) return false
        val result = pendingPicker ?: return true
        pendingPicker = null
        val uri = if (code == Activity.RESULT_OK) data?.data else null
        if (uri != null) {
            try { activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            catch (_: SecurityException) { /* Temporary grants are still useful in this session. */ }
        }
        result.success(uri?.toString())
        return true
    }
    private fun emit(value: Map<String, Any?>, task: Int) {
        main.post { if (generation.get() == task) sink?.success(value) }
    }
    private fun scan(tree: Uri, task: Int) {
        try {
            val directories = ArrayDeque<String>()
            directories.add(DocumentsContract.getTreeDocumentId(tree))
            val visited = HashSet<String>()
            val batch = ArrayList<Map<String, Any?>>()
            var inspected = 0
            while (directories.isNotEmpty() && generation.get() == task) {
                val id = directories.removeFirst()
                if (!visited.add(id)) continue
                val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
                val signal = CancellationSignal()
                querySignal.set(signal)
                activity.contentResolver.query(uri, arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE), null, null, null, signal).use { cursor ->
                    if (cursor == null) return@use
                    while (cursor.moveToNext() && generation.get() == task) {
                        val child = cursor.getString(0)
                        val name = cursor.getString(1) ?: ""
                        val mime = cursor.getString(2)
                        inspected++
                        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) directories.add(child)
                        else if (name.substringAfterLast('.', "").lowercase() in listOf("txt", "epub", "mobi")) {
                            batch.add(mapOf("uri" to DocumentsContract.buildDocumentUriUsingTree(tree, child).toString(),
                                "name" to name, "size" to if (cursor.isNull(3)) 0L else cursor.getLong(3)))
                        }
                        if (batch.size >= 30 || inspected % 100 == 0) {
                            emit(mapOf("files" to batch.toList(), "inspected" to inspected), task)
                            batch.clear()
                        }
                    }
                }
                querySignal.compareAndSet(signal, null)
            }
            if (generation.get() == task) emit(mapOf("files" to batch.toList(), "inspected" to inspected, "done" to true), task)
        } catch (e: Exception) { emit(mapOf("error" to (e.message ?: "授权目录不可访问"), "done" to true), task) }
    }
    fun close() {
        cancel()
        executor.shutdownNow()
        pendingPicker?.success(null)
        pendingPicker = null
        sink = null
    }
}

