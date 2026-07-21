package com.lyf.reading_app

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.database.Cursor
import android.net.Uri
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    private companion object {
        const val FILE_CHANNEL = "com.lyf.reading_app/file_picker"
        const val PICK_FILE_REQUEST = 4107
        const val MAX_IMPORT_BYTES = 50 * 1024 * 1024L
    }

    private var pendingFileResult: MethodChannel.Result? = null

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

                val coverImage = call.argument<Boolean>("coverImage") == true
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (coverImage) "image/*" else "*/*"
                    if (!coverImage) {
                        putExtra(
                            Intent.EXTRA_MIME_TYPES,
                            arrayOf("application/epub+zip", "text/plain", "application/pdf")
                        )
                    }
                }
                pendingFileResult = result
                startActivityForResult(intent, PICK_FILE_REQUEST)
            }
    }

    @Deprecated("Deprecated in Android; retained for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_FILE_REQUEST) return

        val result = pendingFileResult ?: return
        pendingFileResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val uri = data.data!!
        try {
            val metadata = queryMetadata(uri)
            if (metadata.second != null && metadata.second!! > MAX_IMPORT_BYTES) {
                result.error("file_too_large", "The selected file is larger than 50 MB", null)
                return
            }
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalStateException("Could not open selected file")
            if (bytes.size.toLong() > MAX_IMPORT_BYTES) {
                result.error("file_too_large", "The selected file is larger than 50 MB", null)
                return
            }
            result.success(
                mapOf(
                    "name" to (metadata.first ?: uri.lastPathSegment ?: "未命名书籍"),
                    "bytes" to bytes,
                    "coverBytes" to if ((metadata.first ?: "").lowercase().endsWith(".pdf")) {
                        renderPdfCover(bytes)
                    } else null
                )
            )
        } catch (error: Throwable) {
            result.error("file_read_failed", error.message, null)
        }
    }

    private fun renderPdfCover(bytes: ByteArray): ByteArray? {
        val file = File.createTempFile("reading-cover", ".pdf", cacheDir)
        return try {
            file.writeBytes(bytes)
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    if (renderer.pageCount == 0) return null
                    renderer.openPage(0).use { page ->
                        val width = 900
                        val height = (width * page.height.toFloat() / page.width).toInt()
                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                        bitmap.eraseColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        ByteArrayOutputStream().use { output ->
                            bitmap.compress(Bitmap.CompressFormat.PNG, 92, output)
                            bitmap.recycle()
                            output.toByteArray()
                        }
                    }
                }
            }
        } catch (_: Throwable) {
            null
        } finally {
            file.delete()
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
