package com.siya.ai.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * "User Data": Siya ko pehchanne ke liye logon ki photo + naam (khud user, ghar wale, dost).
 * Sab kuch sirf phone ke andar (filesDir) save hota hai.
 */
object PeopleStore {
    data class Person(val id: String, val name: String, val relation: String, val photo: String)

    private val lock = Any()
    private fun file(ctx: Context) = File(ctx.filesDir, "people.json")
    private fun photoDir(ctx: Context) = File(ctx.filesDir, "people").also { it.mkdirs() }

    fun list(ctx: Context): List<Person> = synchronized(lock) {
        try {
            val f = file(ctx)
            if (!f.exists()) return emptyList()
            val a = JSONArray(f.readText())
            (0 until a.length()).map {
                val o = a.getJSONObject(it)
                Person(o.optString("id"), o.optString("name"), o.optString("relation", "family"), o.optString("photo"))
            }
        } catch (_: Exception) { emptyList() }
    }

    private fun write(ctx: Context, l: List<Person>) {
        val a = JSONArray()
        l.forEach { a.put(JSONObject().put("id", it.id).put("name", it.name).put("relation", it.relation).put("photo", it.photo)) }
        file(ctx).writeText(a.toString())
    }

    /** id null = naya. photoSrc = naye photo ka path (gallery se copy hua), null = purani photo rakho. */
    fun save(ctx: Context, id: String?, name: String, relation: String, photoSrc: String?): Person = synchronized(lock) {
        val all = list(ctx).toMutableList()
        val pid = id?.takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString().take(8)
        val old = all.firstOrNull { it.id == pid }
        var photo = old?.photo.orEmpty()
        if (!photoSrc.isNullOrBlank()) {
            val bmp = ImageUtil.decodeScaled(photoSrc, 768)
            if (bmp != null) {
                val out = File(photoDir(ctx), "$pid.jpg")
                out.writeBytes(ImageUtil.jpeg(bmp, 88))
                photo = out.absolutePath
            }
        }
        val p = Person(pid, name.trim().ifBlank { "Unknown" }, relation.ifBlank { "family" }, photo)
        all.removeAll { it.id == pid }
        all.add(p)
        write(ctx, all)
        p
    }

    fun delete(ctx: Context, id: String) = synchronized(lock) {
        val all = list(ctx).toMutableList()
        all.firstOrNull { it.id == id }?.let { try { File(it.photo).delete() } catch (_: Exception) {} }
        all.removeAll { it.id == id }
        write(ctx, all)
    }

    fun toUi(ctx: Context): List<Map<String, Any?>> =
        list(ctx).map { mapOf("id" to it.id, "name" to it.name, "relation" to it.relation, "photo" to it.photo) }

    /** System prompt ke liye: kin logon ko pehchanna hai. */
    fun promptLine(ctx: Context): String {
        val l = list(ctx).filter { it.photo.isNotBlank() }
        if (l.isEmpty()) return ""
        return "Pehchaan ke liye saved log: " + l.joinToString("; ") { "${it.name} (${it.relation})" } + "."
    }
}
