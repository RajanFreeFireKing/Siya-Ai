package com.siya.ai.memory

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Siya ki yaaddaasht: poori chat history (date + time ke saath) aur important facts.
 * Phone ki internal storage mein save hota hai (filesDir), kahin upload nahi hota.
 */
object MemoryStore {

    data class Msg(val time: Long, val role: String, val text: String)

    private const val FILE_MSGS = "siya_memory.jsonl"
    private const val FILE_FACTS = "siya_facts.json"
    private const val MAX_MSGS = 20000

    private val lock = Any()
    private var cache: MutableList<Msg>? = null
    private var facts: MutableList<String>? = null

    private val dayFmt get() = SimpleDateFormat("EEE, dd MMM yyyy", Locale.getDefault())
    private val fullFmt get() = SimpleDateFormat("dd MMM yyyy, hh:mm a", Locale.getDefault())
    private val timeFmt get() = SimpleDateFormat("hh:mm a", Locale.getDefault())

    fun isEnabled(ctx: Context) =
        ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getBoolean("memory_enabled", true)

    // ── load / save ──────────────────────────────────────────
    private fun ensure(ctx: Context): MutableList<Msg> {
        cache?.let { return it }
        val list = ArrayList<Msg>()
        try {
            val f = File(ctx.filesDir, FILE_MSGS)
            if (f.exists()) f.forEachLine { line ->
                if (line.isBlank()) return@forEachLine
                try {
                    val o = JSONObject(line)
                    list.add(Msg(o.getLong("t"), o.getString("r"), o.getString("x")))
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        cache = list
        return list
    }

    private fun ensureFacts(ctx: Context): MutableList<String> {
        facts?.let { return it }
        val list = ArrayList<String>()
        try {
            val f = File(ctx.filesDir, FILE_FACTS)
            if (f.exists()) {
                val a = JSONArray(f.readText())
                for (i in 0 until a.length()) list.add(a.getString(i))
            }
        } catch (_: Exception) {}
        facts = list
        return list
    }

    private fun saveFacts(ctx: Context) {
        try {
            val a = JSONArray(); ensureFacts(ctx).forEach { a.put(it) }
            File(ctx.filesDir, FILE_FACTS).writeText(a.toString())
        } catch (_: Exception) {}
    }

    // ── write ────────────────────────────────────────────────
    fun add(ctx: Context, role: String, text: String) {
        val t = text.trim()
        if (t.isEmpty() || !isEnabled(ctx)) return
        synchronized(lock) {
            val list = ensure(ctx)
            val m = Msg(System.currentTimeMillis(), role, t)
            list.add(m)
            try {
                File(ctx.filesDir, FILE_MSGS).appendText(
                    JSONObject().put("t", m.time).put("r", m.role).put("x", m.text).toString() + "\n"
                )
            } catch (_: Exception) {}
            try { VectorMemory.index(ctx, role, t) } catch (_: Exception) {}
            if (list.size > MAX_MSGS) {
                val keep = list.takeLast(MAX_MSGS - 2000).toMutableList()
                list.clear(); list.addAll(keep)
                rewrite(ctx)
            }
        }
    }

    private fun rewrite(ctx: Context) {
        try {
            val sb = StringBuilder()
            ensure(ctx).forEach {
                sb.append(JSONObject().put("t", it.time).put("r", it.role).put("x", it.text)).append('\n')
            }
            File(ctx.filesDir, FILE_MSGS).writeText(sb.toString())
        } catch (_: Exception) {}
    }

    fun addFact(ctx: Context, fact: String): Boolean {
        val f = fact.trim()
        if (f.isEmpty()) return false
        synchronized(lock) {
            val l = ensureFacts(ctx)
            if (l.any { it.equals(f, true) }) return true
            l.add("[${dayFmt.format(Date())}] $f")
            if (l.size > 200) l.removeAt(0)
            saveFacts(ctx)
        }
        return true
    }

    fun clearAll(ctx: Context) {
        synchronized(lock) {
            cache = ArrayList(); facts = ArrayList()
            try { File(ctx.filesDir, FILE_MSGS).delete(); File(ctx.filesDir, FILE_FACTS).delete() } catch (_: Exception) {}
        }
    }

    // ── read ─────────────────────────────────────────────────
    fun count(ctx: Context) = synchronized(lock) { ensure(ctx).size }

    fun recent(ctx: Context, n: Int): List<Msg> = synchronized(lock) { ensure(ctx).takeLast(n) }

    fun factList(ctx: Context): List<String> = synchronized(lock) { ensureFacts(ctx).toList() }

    fun search(ctx: Context, query: String, limit: Int = 12): List<Msg> {
        val words = query.lowercase().split(Regex("\\s+")).filter { it.length > 1 }
        if (words.isEmpty()) return emptyList()
        synchronized(lock) {
            return ensure(ctx).asReversed()
                .map { m -> m to words.count { m.text.lowercase().contains(it) } }
                .filter { it.second > 0 }
                .sortedWith(compareByDescending<Pair<Msg, Int>> { it.second }.thenByDescending { it.first.time })
                .take(limit)
                .map { it.first }
        }
    }

    fun format(m: Msg): String =
        "[${fullFmt.format(Date(m.time))}] ${if (m.role == "user") "User" else "Siya"}: ${m.text}"

    /** Live session ke system prompt mein jaane wala compact context. */
    fun buildContext(ctx: Context, recentCount: Int = 40): String {
        val sb = StringBuilder()
        val fl = factList(ctx)
        if (fl.isNotEmpty()) {
            sb.append("=== REMEMBERED FACTS ===\n")
            fl.takeLast(60).forEach { sb.append("- ").append(it).append('\n') }
        }
        val total = count(ctx)
        if (total > 0) {
            sb.append("\n=== PAST CONVERSATION (latest $recentCount of $total messages, oldest first) ===\n")
            recent(ctx, recentCount).forEach { sb.append(format(it).take(400)).append('\n') }
            sb.append("Older chat: use the search_memory tool.\n")
        }
        return sb.toString()
    }

    // ── for Flutter UI ───────────────────────────────────────
    fun toUiList(ctx: Context, limit: Int = 600): List<Map<String, Any?>> = synchronized(lock) {
        ensure(ctx).takeLast(limit).map {
            mapOf(
                "time" to it.time,
                "role" to it.role,
                "text" to it.text,
                "day" to dayFmt.format(Date(it.time)),
                "clock" to timeFmt.format(Date(it.time))
            )
        }
    }

    fun exportText(ctx: Context): String = synchronized(lock) {
        val sb = StringBuilder("Siya chat history\n\n")
        val fl = ensureFacts(ctx)
        if (fl.isNotEmpty()) { sb.append("Facts:\n"); fl.forEach { sb.append("- $it\n") }; sb.append('\n') }
        ensure(ctx).forEach { sb.append(format(it)).append('\n') }
        sb.toString()
    }
}
