package com.lyf.reading_app

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity : FlutterFragmentActivity() {
    private companion object {
        const val FILE_CHANNEL = "com.lyf.reading_app/file_picker"
        const val STORAGE_CHANNEL = "com.lyf.reading_app/storage"
        const val DOCUMENT_CHANNEL = "com.lyf.reading_app/documents"
        const val MAX_IMPORT_BYTES = 50 * 1024 * 1024L
        const val MAX_BACKUP_BYTES = 300 * 1024 * 1024L
    }

    private var pendingFileResult: MethodChannel.Result? = null
    private var pendingDocumentResult: MethodChannel.Result? = null
    private var pendingDocumentBytes: ByteArray? = null
    private var pendingDocumentMime: String = "application/octet-stream"

    private val openFile = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val result = pendingFileResult ?: return@registerForActivityResult
        pendingFileResult = null
        if (uri == null) {
            result.success(null)
            return@registerForActivityResult
        }
        readSelectedBook(uri, result)
    }

    private val createDocument = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val result = pendingDocumentResult ?: return@registerForActivityResult
        pendingDocumentResult = null
        val bytes = pendingDocumentBytes ?: byteArrayOf()
        pendingDocumentBytes = null
        val uri = if (activityResult.resultCode == Activity.RESULT_OK) {
            activityResult.data?.data
        } else {
            null
        }
        if (uri == null) {
            result.success(false)
            return@registerForActivityResult
        }
        thread {
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: error("Could not create document")
                runOnUiThread { result.success(true) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("document_write_failed", error.message, null)
                }
            }
        }
    }

    private val openBackup = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val result = pendingDocumentResult ?: return@registerForActivityResult
        pendingDocumentResult = null
        if (uri == null) {
            result.success(null)
            return@registerForActivityResult
        }
        thread {
            try {
                val metadata = queryMetadata(uri)
                if (metadata.second != null && metadata.second!! > MAX_BACKUP_BYTES) {
                    runOnUiThread {
                        result.error("backup_too_large", "Backup is larger than 300 MB", null)
                    }
                    return@thread
                }
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: error("Could not read backup")
                if (bytes.size.toLong() > MAX_BACKUP_BYTES) {
                    runOnUiThread {
                        result.error("backup_too_large", "Backup is larger than 300 MB", null)
                    }
                    return@thread
                }
                runOnUiThread { result.success(bytes) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("document_read_failed", error.message, null)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "pickFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingFileResult != null) {
                    result.error("picker_busy", "A file picker is already open", null)
                    return@setMethodCallHandler
                }
                pendingFileResult = result
                val coverImage = call.argument<Boolean>("coverImage") == true
                openFile.launch(
                    if (coverImage) {
                        arrayOf("image/*")
                    } else {
                        arrayOf("application/epub+zip", "application/pdf", "text/plain")
                    }
                )
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getApplicationSupportPath") {
                    result.success(filesDir.absolutePath)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOCUMENT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveText", "saveBytes" -> {
                        if (pendingDocumentResult != null) {
                            result.error("document_busy", "A document action is already active", null)
                            return@setMethodCallHandler
                        }
                        pendingDocumentResult = result
                        pendingDocumentBytes = if (call.method == "saveBytes") {
                            call.argument<ByteArray>("content") ?: byteArrayOf()
                        } else {
                            (call.argument<String>("content") ?: "").toByteArray(Charsets.UTF_8)
                        }
                        pendingDocumentMime = call.argument<String>("mimeType")
                            ?: "application/octet-stream"
                        createDocument.launch(
                            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = pendingDocumentMime
                                putExtra(
                                    Intent.EXTRA_TITLE,
                                    call.argument<String>("name") ?: "shiye-backup"
                                )
                            }
                        )
                    }
                    "openBackupBytes" -> {
                        if (pendingDocumentResult != null) {
                            result.error("document_busy", "A document action is already active", null)
                            return@setMethodCallHandler
                        }
                        pendingDocumentResult = result
                        openBackup.launch(arrayOf("application/zip", "application/json", "*/*"))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readSelectedBook(uri: Uri, result: MethodChannel.Result) {
        thread {
            try {
                val metadata = queryMetadata(uri)
                if (metadata.second != null && metadata.second!! > MAX_IMPORT_BYTES) {
                    runOnUiThread {
                        result.error("file_too_large", "The selected file is larger than 50 MB", null)
                    }
                    return@thread
                }
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: error("Could not open selected file")
                if (bytes.size.toLong() > MAX_IMPORT_BYTES) {
                    runOnUiThread {
                        result.error("file_too_large", "The selected file is larger than 50 MB", null)
                    }
                    return@thread
                }
                runOnUiThread {
                    result.success(
                        mapOf(
                            "name" to (metadata.first ?: uri.lastPathSegment ?: "未命名书籍"),
                            "bytes" to bytes,
                            "coverBytes" to null
                        )
                    )
                }
            } catch (error: Throwable) {
                runOnUiThread { result.error("file_read_failed", error.message, null) }
            }
        }
    }

    private fun queryMetadata(uri: Uri): Pair<String?, Long?> {
        var name: String? = null
        var size: Long? = null
        val cursor: Cursor? = contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0 && !it.isNull(nameIndex)) name = it.getString(nameIndex)
                if (sizeIndex >= 0 && !it.isNull(sizeIndex)) size = it.getLong(sizeIndex)
            }
        }
        return name to size
    }
}
