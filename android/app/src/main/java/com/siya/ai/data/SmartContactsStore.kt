package com.siya.ai.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Storage for custom smart contacts and their voice call nicknames / aliases.
 * Persisted locally in smart_contacts.json.
 */
object SmartContactsStore {

    data class Contact(
        val id: String,
        val name: String,
        val number: String,
        val aliases: List<String>
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "id" to id,
            "name" to name,
            "number" to number,
            "aliases" to aliases
        )
    }

    private val lock = Any()
    private fun file(ctx: Context) = File(ctx.filesDir, "smart_contacts.json")

    fun list(ctx: Context): List<Map<String, Any>> = synchronized(lock) {
        try {
            val f = file(ctx)
            if (!f.exists()) return emptyList()
            val arr = JSONArray(f.readText())
            val out = ArrayList<Map<String, Any>>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val aliasesJson = o.optJSONArray("aliases") ?: JSONArray()
                val aliases = ArrayList<String>()
                for (j in 0 until aliasesJson.length()) {
                    val a = aliasesJson.optString(j, "").trim()
                    if (a.isNotEmpty()) aliases.add(a)
                }
                out.add(mapOf(
                    "id" to o.optString("id", UUID.randomUUID().toString()),
                    "name" to o.optString("name", ""),
                    "number" to o.optString("number", ""),
                    "aliases" to aliases
                ))
            }
            out
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun save(ctx: Context, id: String?, name: String, number: String, aliases: List<String>): Map<String, Any> = synchronized(lock) {
        val current = list(ctx).toMutableList()
        val cid = if (!id.isNullOrBlank()) id else UUID.randomUUID().toString().take(8)

        val cleanAliases = aliases.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        val newContact = mapOf(
            "id" to cid,
            "name" to name.trim(),
            "number" to number.trim(),
            "aliases" to cleanAliases
        )

        val idx = current.indexOfFirst { (it["id"] as? String) == cid }
        if (idx >= 0) {
            current[idx] = newContact
        } else {
            current.add(0, newContact)
        }

        write(ctx, current)
        newContact
    }

    fun delete(ctx: Context, id: String) = synchronized(lock) {
        val current = list(ctx).filter { (it["id"] as? String) != id }
        write(ctx, current)
    }

    private fun write(ctx: Context, contacts: List<Map<String, Any>>) {
        val arr = JSONArray()
        for (c in contacts) {
            val o = JSONObject()
            o.put("id", c["id"])
            o.put("name", c["name"])
            o.put("number", c["number"])
            val aArr = JSONArray()
            @Suppress("UNCHECKED_CAST")
            val aliases = (c["aliases"] as? List<String>) ?: emptyList()
            for (a in aliases) aArr.put(a)
            o.put("aliases", aArr)
            arr.put(o)
        }
        val target = file(ctx)
        val temp = File(ctx.filesDir, "smart_contacts.json.tmp")
        temp.writeText(arr.toString())
        if (!temp.renameTo(target)) {
            target.writeText(arr.toString())
            temp.delete()
        }
    }

    /**
     * Resolves voice command query ("papa", "mera dost", "ramesh") against:
     * 1. Any alias (exact or contained)
     * 2. Primary name
     * Returns Pair(number, contact_name) or null.
     */
    fun find(ctx: Context, query: String): Pair<String, String>? {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return null

        val contacts = list(ctx)
        // 1. Exact alias match
        for (c in contacts) {
            val num = (c["number"] as? String).orEmpty()
            val name = (c["name"] as? String).orEmpty()
            @Suppress("UNCHECKED_CAST")
            val aliases = (c["aliases"] as? List<String>) ?: emptyList()
            for (a in aliases) {
                val al = a.trim().lowercase()
                if (al == q || q == al.replace(" ", "") || q.contains(al)) {
                    if (num.isNotEmpty()) return num to (if (name.isNotEmpty()) name else a)
                }
            }
        }

        // 2. Exact or partial primary name match
        for (c in contacts) {
            val num = (c["number"] as? String).orEmpty()
            val name = (c["name"] as? String).orEmpty()
            val nl = name.trim().lowercase()
            if (nl.isNotEmpty() && (nl == q || q.contains(nl) || nl.contains(q))) {
                if (num.isNotEmpty()) return num to name
            }
        }

        return null
    }
}
