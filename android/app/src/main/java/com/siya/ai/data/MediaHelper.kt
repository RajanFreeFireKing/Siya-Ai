package com.siya.ai.data

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import android.webkit.MimeTypeMap
import java.io.File

/** Gallery (photos + videos) dikhane aur wallpaper / profile photo ke liye copy karne ka kaam. */
object MediaHelper {

    fun list(ctx: Context, kind: String, limit: Int = 300): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val isVideo = kind == "video"
        val base = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val proj = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.DATE_ADDED)
        try {
            ctx.contentResolver.query(base, proj, null, null, "${MediaStore.MediaColumns.DATE_ADDED} DESC")?.use { c ->
                val idI = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nI = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                while (c.moveToNext() && out.size < limit) {
                    val uri = Uri.withAppendedPath(base, c.getLong(idI).toString())
                    out.add(mapOf("uri" to uri.toString(), "name" to (c.getString(nI) ?: ""), "kind" to kind))
                }
            }
        } catch (_: Exception) {}
        return out
    }

    fun thumbnail(ctx: Context, uriStr: String, kind: String, size: Int): ByteArray? {
        return try {
            val uri = Uri.parse(uriStr)
            val bmp: Bitmap? = if (Build.VERSION.SDK_INT >= 29) {
                ctx.contentResolver.loadThumbnail(uri, Size(size, size), null)
            } else if (kind == "video") {
                MediaMetadataRetriever().let { r ->
                    try { r.setDataSource(ctx, uri); r.frameAtTime } finally { try { r.release() } catch (_: Exception) {} }
                }
            } else {
                ctx.contentResolver.openInputStream(uri)?.use { s ->
                    val o = android.graphics.BitmapFactory.Options().apply { inSampleSize = 8 }
                    android.graphics.BitmapFactory.decodeStream(s, null, o)
                }
            }
            bmp?.let { ImageUtil.jpeg(ImageUtil.scale(it, size), 80) }
        } catch (_: Exception) { null }
    }

    /** Poori photo (2048px tak) JPEG bytes mein, full-screen dekhne ke liye. */
    fun full(ctx: Context, uriStr: String): ByteArray? = try {
        val uri = Uri.parse(uriStr)
        val tmp = File(ctx.cacheDir, "full_view.tmp")
        ctx.contentResolver.openInputStream(uri)?.use { i -> tmp.outputStream().use { o -> i.copyTo(o) } }
        val bmp = ImageUtil.decodeScaled(tmp.absolutePath, 2048)
        bmp?.let { ImageUtil.jpeg(it, 90) }
    } catch (_: Exception) { null }

    /** Kisi bhi content:// URI ko app ke andar copy karo (taaki gallery se delete hone par bhi chale). */
    fun copyIn(ctx: Context, uriStr: String, dir: String, name: String): String? {
        return try {
            val uri = Uri.parse(uriStr)
            val mime = ctx.contentResolver.getType(uri)
            val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
                ?: uri.lastPathSegment?.substringAfterLast('.', "")?.lowercase()?.takeIf { it.length in 2..4 }
                ?: if (mime?.startsWith("video") == true) "mp4" else "jpg"
            val d = File(ctx.filesDir, dir).also { it.mkdirs() }
            d.listFiles()?.filter { it.name.startsWith(name) }?.forEach { it.delete() }
            val out = File(d, "$name.${ext}")
            ctx.contentResolver.openInputStream(uri)?.use { i -> out.outputStream().use { o -> i.copyTo(o) } } ?: return null
            out.absolutePath
        } catch (_: Exception) { null }
    }
}
