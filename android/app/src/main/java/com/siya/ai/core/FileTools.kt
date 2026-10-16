package com.siya.ai.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * "All files access" milne par Siya user ki files dekh, padh, likh, move/copy aur share kar sakti hai.
 * delete asli delete nahi hai: file Siya_Trash folder mein chali jaati hai (wapas mil sakti hai).
 */
object FileTools {

    private val root: File get() = Environment.getExternalStorageDirectory()
    private val trash: File get() = File(root, "Siya_Trash")

    fun hasAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= 30) Environment.isExternalStorageManager() else true

    private fun need(): String? =
        if (!hasAccess()) "ERROR: All files access ON nahi hai (Siya Settings > All files access)" else null

    /** "Download/abc.pdf", "/storage/emulated/0/DCIM", "~/Music" sab chalega. */
    private fun resolve(p: String): File {
        val t = p.trim().removePrefix("~").trim()
        if (t.isEmpty() || t == "/") return root
        return if (t.startsWith("/")) File(t) else File(root, t)
    }

    private fun size(n: Long) = when {
        n > 1_000_000_000 -> "%.1fGB".format(n / 1e9)
        n > 1_000_000 -> "%.1fMB".format(n / 1e6)
        n > 1_000 -> "%.0fKB".format(n / 1e3)
        else -> "${n}B"
    }

    private fun date(ms: Long) = SimpleDateFormat("dd MMM yyyy HH:mm", Locale.getDefault()).format(Date(ms))

    fun list(path: String): String {
        need()?.let { return it }
        val d = resolve(path)
        if (!d.exists()) return "NOT_FOUND: ${d.path}"
        if (!d.isDirectory) return "ERROR: ye folder nahi, file hai: ${d.path}"
        val items = d.listFiles()?.sortedWith(compareBy({ !it.isDirectory }, { it.name.lowercase() })) ?: return "ERROR: folder khul nahi raha"
        if (items.isEmpty()) return "Folder khaali hai: ${d.path}"
        return "Folder: ${d.path} (${items.size} items)\n" + items.take(80).joinToString("\n") {
            if (it.isDirectory) "[folder] ${it.name}" else "${it.name} (${size(it.length())}, ${date(it.lastModified())})"
        } + if (items.size > 80) "\n... aur ${items.size - 80} items" else ""
    }

    fun find(query: String, path: String): String {
        need()?.let { return it }
        val q = query.trim().lowercase()
        if (q.isEmpty()) return "ERROR: kya dhundna hai?"
        val start = resolve(path)
        val hits = ArrayList<File>()
        fun walk(d: File, depth: Int) {
            if (hits.size >= 40 || depth > 7) return
            val kids = d.listFiles() ?: return
            for (f in kids) {
                if (f.name.startsWith(".") || f.absolutePath.startsWith(trash.absolutePath)) continue
                if (f.name.lowercase().contains(q)) hits.add(f)
                if (f.isDirectory && !f.absolutePath.contains("/Android/")) walk(f, depth + 1)
                if (hits.size >= 40) return
            }
        }
        walk(start, 0)
        if (hits.isEmpty()) return "NOT_FOUND: '$query' naam ki koi file/folder nahi mili"
        return hits.joinToString("\n") { (if (it.isDirectory) "[folder] " else "") + it.path + if (it.isFile) " (${size(it.length())})" else "" }
    }

    fun read(path: String): String {
        need()?.let { return it }
        val f = resolve(path)
        if (!f.isFile) return "NOT_FOUND: ${f.path}"
        if (f.length() > 5_000_000) return "ERROR: file bahut badi hai (${size(f.length())})"
        return try {
            val t = f.readText()
            if (t.contains('\u0000')) "ERROR: yeh text file nahi lagti (binary)" else t.take(8000) + if (t.length > 8000) "\n...[baaki ${t.length - 8000} characters kaat diye]" else ""
        } catch (e: Exception) { "ERROR: ${e.message}" }
    }

    fun write(path: String, content: String, mode: String): String {
        need()?.let { return it }
        val f = resolve(path)
        return try {
            f.parentFile?.mkdirs()
            when (mode.lowercase()) {
                "append" -> f.appendText(content)
                "create" -> { if (f.exists()) return "ERROR: file pehle se hai: ${f.path} (overwrite ya append bolo)"; f.writeText(content) }
                else -> {
                    if (f.exists()) backup(f)
                    f.writeText(content)
                }
            }
            "OK: ${f.path} mein likh diya"
        } catch (e: Exception) { "ERROR: ${e.message}" }
    }

    /** Overwrite se pehle purani copy Siya_Trash mein rakh do. */
    private fun backup(f: File) {
        try {
            trash.mkdirs()
            f.copyTo(File(trash, "${stamp()}_${f.name}"), overwrite = true)
        } catch (_: Exception) {}
    }

    private fun stamp() = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())

    fun mkdir(path: String): String {
        need()?.let { return it }
        val d = resolve(path)
        return if (d.exists() || d.mkdirs()) "OK: folder taiyaar: ${d.path}" else "ERROR: folder nahi bana"
    }

    fun move(from: String, to: String): String {
        need()?.let { return it }
        val a = resolve(from)
        if (!a.exists()) return "NOT_FOUND: ${a.path}"
        var b = resolve(to)
        if (b.isDirectory) b = File(b, a.name)
        if (b.exists()) return "ERROR: destination par pehle se hai: ${b.path}"
        b.parentFile?.mkdirs()
        return if (a.renameTo(b)) "OK: ${a.name} -> ${b.path}" else try {
            a.copyRecursively(b); a.deleteRecursively(); "OK: ${a.name} -> ${b.path}"
        } catch (e: Exception) { "ERROR: ${e.message}" }
    }

    fun copy(from: String, to: String): String {
        need()?.let { return it }
        val a = resolve(from)
        if (!a.exists()) return "NOT_FOUND: ${a.path}"
        var b = resolve(to)
        if (b.isDirectory) b = File(b, a.name)
        if (b.exists()) return "ERROR: destination par pehle se hai: ${b.path}"
        return try { b.parentFile?.mkdirs(); a.copyRecursively(b); "OK: copy ho gayi: ${b.path}" } catch (e: Exception) { "ERROR: ${e.message}" }
    }

    fun delete(path: String): String {
        need()?.let { return it }
        val f = resolve(path)
        if (!f.exists()) return "NOT_FOUND: ${f.path}"
        if (f == root) return "ERROR: poora storage delete nahi kar sakti"
        trash.mkdirs()
        val dest = File(trash, "${stamp()}_${f.name}")
        return if (f.renameTo(dest)) "OK: ${f.name} ko Siya_Trash mein daal diya (wapas mil sakti hai)" else try {
            f.copyRecursively(dest); f.deleteRecursively(); "OK: ${f.name} ko Siya_Trash mein daal diya"
        } catch (e: Exception) { "ERROR: ${e.message}" }
    }

    /** Koi bhi file kisi bhi app mein share karo. app = "WhatsApp" jaisa naam (khaali = chooser). */
    fun share(ctx: Context, path: String, app: String): String {
        need()?.let { return it }
        val f = resolve(path)
        if (!f.isFile) return "NOT_FOUND: ${f.path}"
        return try {
            val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", f)
            val ext = f.extension.lowercase()
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
            val send = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            launchShare(ctx, send, app, f.name)
        } catch (e: Exception) { "ERROR: ${e.message}" }
    }

    fun shareText(ctx: Context, text: String, app: String): String {
        val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
        return launchShare(ctx, send, app, "text")
    }

    private fun launchShare(ctx: Context, send: Intent, app: String, what: String): String {
        val pkg = if (app.isNotBlank()) PhoneController.findApp(ctx, app)?.pkg else null
        if (app.isNotBlank() && pkg == null) return "NOT_FOUND: '$app' app phone mein nahi mila"
        val intent = if (pkg != null) send.setPackage(pkg) else Intent.createChooser(send, "Share")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(intent)
        return if (pkg != null) "OK: $what ${app} mein share screen par khul gaya. Ab read_screen karke contact chuno (tap_on_screen) aur Send dabao."
        else "OK: $what ke liye share menu khul gaya. User ya tum app chuno (tap_on_screen)."
    }
}
