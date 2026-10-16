package com.siya.ai.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Local relationship graph for people and their contextual notes.
 * Existing people.json files remain readable; notes and phone numbers are optional fields.
 */
object PeopleStore {
    data class Person(
        val id: String,
        val name: String,
        val relation: String,
        val photo: String,
        val phoneNumber: String = "",
        val notes: List<String> = emptyList()
    )

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
                val notesJson = o.optJSONArray("notes") ?: JSONArray()
                Person(
                    o.optString("id"), o.optString("name"), o.optString("relation", "family"), o.optString("photo"),
                    o.optString("phoneNumber"), (0 until notesJson.length()).mapNotNull { n -> notesJson.optString(n).takeIf { it.isNotBlank() } }
                )
            }
        } catch (_: Exception) { emptyList() }
    }

    private fun write(ctx: Context, people: List<Person>) {
        val a = JSONArray()
        people.forEach { p ->
            val notes = JSONArray()
            p.notes.forEach { notes.put(it) }
            a.put(JSONObject().put("id", p.id).put("name", p.name).put("relation", p.relation).put("photo", p.photo)
                .put("phoneNumber", p.phoneNumber).put("notes", notes))
        }
        val target = file(ctx)
        val temp = File(ctx.filesDir, "people.json.tmp")
        temp.writeText(a.toString())
        if (!temp.renameTo(target)) { target.writeText(a.toString()); temp.delete() }
    }

    /** photoSrc=null keeps the old photo. The optional phone number helps match calls/messages. */
    fun save(ctx: Context, id: String?, name: String, relation: String, photoSrc: String?, phoneNumber: String = ""): Person = synchronized(lock) {
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
        val p = Person(pid, name.trim().ifBlank { "Unknown" }, relation.ifBlank { "family" }, photo,
            phoneNumber.trim().ifBlank { old?.phoneNumber.orEmpty() }, old?.notes.orEmpty())
        all.removeAll { it.id == pid }
        all.add(p)
        write(ctx, all)
        p
    }

    /** Add a durable relationship note, for example "Isne ₹500 dene hain" or a birthday date. */
    fun addNote(ctx: Context, name: String, phoneNumber: String = "", note: String, category: String = "note"): Person? = synchronized(lock) {
        val cleanName = name.trim().ifBlank { "Unknown contact" }
        val cleanNote = note.trim()
        if (cleanNote.isBlank()) return null
        val all = list(ctx).toMutableList()
        val normalizedPhone = normalizePhone(phoneNumber)
        val found = all.indexOfFirst {
            (normalizedPhone.isNotBlank() && normalizePhone(it.phoneNumber) == normalizedPhone) ||
                it.name.equals(cleanName, ignoreCase = true)
        }
        val old = if (found >= 0) all[found] else null
        val tagged = "[$category] $cleanNote"
        val notes = old?.notes.orEmpty().toMutableList()
        val existing = notes.indexOfFirst { it.equals(tagged, true) || it.substringAfter("] ").equals(cleanNote, true) }
        if (existing >= 0) notes[existing] = tagged else notes.add(tagged)
        val p = Person(old?.id ?: UUID.randomUUID().toString().take(8), old?.name ?: cleanName,
            old?.relation ?: "contact", old?.photo.orEmpty(), phoneNumber.trim().ifBlank { old?.phoneNumber.orEmpty() }, notes)
        if (found >= 0) all.removeAt(found)
        all.add(p)
        write(ctx, all)
        p
    }

    /** Fast lookup for an incoming call or message; returns notes suitable for immediate display/speech. */
    fun contextForContact(ctx: Context, name: String = "", phoneNumber: String = ""): String {
        val normalizedPhone = normalizePhone(phoneNumber)
        val cleanName = name.trim()
        val person = list(ctx).firstOrNull {
            (normalizedPhone.isNotBlank() && normalizePhone(it.phoneNumber) == normalizedPhone) ||
                (cleanName.isNotBlank() && it.name.equals(cleanName, ignoreCase = true))
        } ?: return ""
        if (person.notes.isEmpty()) return ""
        return buildString {
            append("Context for ").append(person.name)
            if (person.relation.isNotBlank()) append(" (").append(person.relation).append(')')
            append(": ")
            append(person.notes.takeLast(8).joinToString("; ") { it.removePrefix("[note] ").removePrefix("[financial_debts] ").removePrefix("[important_dates] ") })
        }
    }

    private fun normalizePhone(value: String): String = value.filter { it.isDigit() }.takeLast(10)

    fun delete(ctx: Context, id: String) = synchronized(lock) {
        val all = list(ctx).toMutableList()
        all.firstOrNull { it.id == id }?.let { try { File(it.photo).delete() } catch (_: Exception) { } }
        all.removeAll { it.id == id }
        write(ctx, all)
    }

    fun toUi(ctx: Context): List<Map<String, Any?>> =
        list(ctx).map { mapOf("id" to it.id, "name" to it.name, "relation" to it.relation, "photo" to it.photo, "phoneNumber" to it.phoneNumber, "notes" to it.notes) }

    /** System prompt ke liye: saved people and their useful context. */
    fun promptLine(ctx: Context): String {
        val people = list(ctx)
        if (people.isEmpty()) return ""
        return "Saved people: " + people.joinToString("; ") { p ->
            buildString {
                append(p.name).append(" (").append(p.relation).append(')')
                if (p.notes.isNotEmpty()) append(" — ").append(p.notes.takeLast(4).joinToString(", "))
            }
        } + "."
    }
}
