package com.siya.ai.core

import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.provider.MediaStore
import com.siya.ai.data.FaceSearch
import com.siya.ai.data.PeopleStore
import java.util.Calendar

/** Feature 14: "pichle mahine ka bijli ka bill dikhao" / "Rahul ke sath wali photo dikhao". */
object FileFinder {
    private val synonyms = mapOf("bijli" to listOf("electric", "bijli", "light", "mseb", "bses"), "bill" to listOf("bill", "invoice", "receipt"), "paani" to listOf("water", "paani"),
        "photo" to listOf("img", "photo", "pxl", "dsc"), "aadhar" to listOf("aadhaar", "aadhar", "uid"), "resume" to listOf("resume", "cv"), "fees" to listOf("fee", "fees"))

    private fun range(w: String): Pair<Long, Long> {
        val c = Calendar.getInstance(); val now = c.timeInMillis
        fun startOfDay(): Calendar = (c.clone() as Calendar).apply { set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0) }
        return when (w.lowercase().trim()) {
            "aaj", "today" -> startOfDay().timeInMillis to now
            "kal", "yesterday" -> startOfDay().apply { add(Calendar.DAY_OF_YEAR, -1) }.timeInMillis to startOfDay().timeInMillis
            "is hafte", "this week" -> now - 7 * 86400_000L to now
            "pichle hafte", "last week" -> now - 14 * 86400_000L to now - 7 * 86400_000L
            "is mahine", "this month" -> startOfDay().apply { set(Calendar.DAY_OF_MONTH, 1) }.timeInMillis to now
            "pichle mahine", "last month" -> startOfDay().apply { set(Calendar.DAY_OF_MONTH, 1); add(Calendar.MONTH, -1) }.timeInMillis to startOfDay().apply { set(Calendar.DAY_OF_MONTH, 1) }.timeInMillis
            else -> 0L to now
        }
    }

    fun find(ctx: Context, query: String, whenText: String, open: Boolean): String {
        val (from, to) = range(whenText)
        val words = query.lowercase().split(" ").filter { it.length > 2 }.flatMap { synonyms[it] ?: listOf(it) }.distinct()
        if (words.isEmpty()) return "ERROR: kya dhundna hai batao"
        val sel = "(" + words.joinToString(" OR ") { "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?" } + ") AND ${MediaStore.Files.FileColumns.DATE_MODIFIED} BETWEEN ? AND ?"
        val args = (words.map { "%$it%" } + listOf((from / 1000).toString(), (to / 1000).toString())).toTypedArray()
        val hits = ArrayList<Triple<Long, String, String>>()
        try {
            ctx.contentResolver.query(MediaStore.Files.getContentUri("external"), arrayOf(MediaStore.Files.FileColumns._ID, MediaStore.Files.FileColumns.DISPLAY_NAME, MediaStore.Files.FileColumns.MIME_TYPE),
                sel, args, "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC")?.use { c ->
                while (c.moveToNext() && hits.size < 10) hits.add(Triple(c.getLong(0), c.getString(1).orEmpty(), c.getString(2).orEmpty()))
            }
        } catch (e: SecurityException) { return "ERROR: Files / All-files access ON karo" }
        if (hits.isEmpty()) return "Aisi koi file nahi mili ($query, $whenText). Tip: file ka naam alag ho sakta hai."
        if (open) {
            val h = hits[0]
            try {
                ctx.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(ContentUris.withAppendedId(MediaStore.Files.getContentUri("external"), h.first), h.third.ifBlank { "*/*" })
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION))
            } catch (_: Exception) { return "Mili: ${h.second} lekin khul nahi payi" }
        }
        return (if (open) "Khol di: ${hits[0].second}\n" else "") + "Mili files:\n" + hits.joinToString("\n") { "- ${it.second}" }
    }

    fun photosOf(ctx: Context, person: String): String {
        val p = PeopleStore.list(ctx).firstOrNull { it.name.equals(person.trim(), true) || it.name.lowercase().contains(person.trim().lowercase()) }
            ?: return "ERROR: '$person' User Data mein saved nahi hai (photo ke saath add karo)"
        val st = FaceSearch.status(ctx, p.id)
        @Suppress("UNCHECKED_CAST") val m = st["matches"] as List<Map<String, Any?>>
        if (m.isNotEmpty()) {
            try { ctx.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(m[0]["uri"] as String)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)) } catch (_: Exception) {}
            return "${p.name} ki ${m.size} photo mili, pehli khol di."
        }
        if (st["running"] == true) return "Search chal rahi hai: ${st["done"]}/${st["total"]} photo dekh li. Thodi der baad dobara poochho."
        FaceSearch.start(ctx, p.id, 300)
        return "${p.name} ki photo dhundna shuru kiya (gallery ki 300 photos). Thodi der baad dobara bolo."
    }
}
