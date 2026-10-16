package com.siya.ai.memory

import android.content.Context
import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Durable on-device memory with categorized facts and migration from the previous JSON format. */
object MemoryStore {
    data class Msg(val time: Long, val role: String, val text: String)
    data class Fact(val id: String, val text: String, val category: String, val entity: String, val createdAt: Long, val source: String)

    private const val FILE_MSGS = "siya_memory.jsonl"
    private const val FILE_FACTS = "siya_facts.json"
    private const val MAX_MSGS = 20000
    private val lock = Any()
    private var cache: MutableList<Msg>? = null
    private var facts: MutableList<Fact>? = null
    private val factExecutor = Executors.newSingleThreadExecutor()
    private val http = OkHttpClient.Builder().connectTimeout(12, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS).writeTimeout(12, TimeUnit.SECONDS).build()
    private val dayFmt get() = SimpleDateFormat("EEE, dd MMM yyyy", Locale.getDefault())
    private val fullFmt get() = SimpleDateFormat("dd MMM yyyy, hh:mm a", Locale.getDefault())
    private val timeFmt get() = SimpleDateFormat("hh:mm a", Locale.getDefault())
    private val categories = setOf("preferences", "promises", "daily_routine", "financial_debts", "relationships", "important_dates", "other")

    fun isEnabled(ctx: Context) = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getBoolean("memory_enabled", true)
    private fun apiKey(ctx: Context) = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getString("api_key", "").orEmpty()

    private fun ensure(ctx: Context): MutableList<Msg> {
        cache?.let { return it }
        val list = ArrayList<Msg>()
        try {
            val f = File(ctx.filesDir, FILE_MSGS)
            if (f.exists()) f.forEachLine { line ->
                if (line.isBlank()) return@forEachLine
                try { val o = JSONObject(line); list.add(Msg(o.getLong("t"), o.getString("r"), o.getString("x"))) } catch (_: Exception) { }
            }
        } catch (_: Exception) { }
        cache = list
        return list
    }

    private fun inferCategory(text: String): String {
        val s = text.lowercase(Locale.ROOT)
        return when {
            listOf("dene hain", "udhaar", "karz", "loan", "owe", "₹", "rupaye", "paise dene").any { s.contains(it) } -> "financial_debts"
            listOf("birthday", "janamdin", "anniversary", "barsi").any { s.contains(it) } -> "important_dates"
            listOf("promise", "vaada", "vachan", "karunga", "karungi", "yaad dilana").any { s.contains(it) } -> "promises"
            listOf("roz", "daily", "har subah", "har shaam", "routine", "uthata", "sota").any { s.contains(it) } -> "daily_routine"
            listOf("favourite", "favorite", "pasand", "napasand", "like", "dislike", "rang", "color", "colour", "shirt", "khana").any { s.contains(it) } -> "preferences"
            listOf("dost", "bhai", "behen", "papa", "mummy", "wife", "husband", "rishta").any { s.contains(it) } -> "relationships"
            else -> "other"
        }
    }

    private fun ensureFacts(ctx: Context): MutableList<Fact> {
        facts?.let { return it }
        val list = ArrayList<Fact>()
        try {
            val f = File(ctx.filesDir, FILE_FACTS)
            if (f.exists()) {
                val a = JSONArray(f.readText())
                for (i in 0 until a.length()) {
                    val value = a.opt(i)
                    if (value is String) {
                        val text = value.substringAfter("] ", value).trim()
                        if (text.isNotBlank()) list.add(Fact("legacy-$i", text, inferCategory(text), "user", System.currentTimeMillis(), "legacy"))
                    } else if (value is JSONObject) {
                        val text = value.optString("text").trim()
                        if (text.isNotBlank()) list.add(Fact(
                            value.optString("id", "fact-$i"), text,
                            value.optString("category", inferCategory(text)).let { if (it in categories) it else "other" },
                            value.optString("entity", "user"), value.optLong("createdAt", System.currentTimeMillis()), value.optString("source", "memory")
                        ))
                    }
                }
            }
        } catch (e: Exception) { Log.w("SIYA_MEMORY", "Could not read facts: ${e.message}") }
        facts = list
        saveFactsLocked(ctx)
        return list
    }

    private fun saveFactsLocked(ctx: Context) {
        try {
            val a = JSONArray()
            (facts ?: emptyList()).forEach { f -> a.put(JSONObject().put("id", f.id).put("text", f.text).put("category", f.category).put("entity", f.entity).put("createdAt", f.createdAt).put("source", f.source)) }
            val target = File(ctx.filesDir, FILE_FACTS)
            val temp = File(ctx.filesDir, "$FILE_FACTS.tmp")
            temp.writeText(a.toString())
            if (!temp.renameTo(target)) { target.writeText(a.toString()); temp.delete() }
        } catch (e: Exception) { Log.w("SIYA_MEMORY", "Could not save facts: ${e.message}") }
    }

    fun add(ctx: Context, role: String, text: String) {
        val t = text.trim()
        if (t.isEmpty() || !isEnabled(ctx)) return
        synchronized(lock) {
            val list = ensure(ctx)
            val m = Msg(System.currentTimeMillis(), role, t)
            list.add(m)
            try { File(ctx.filesDir, FILE_MSGS).appendText(JSONObject().put("t", m.time).put("r", m.role).put("x", m.text).toString() + "\n") }
            catch (e: Exception) { Log.w("SIYA_MEMORY", "Could not save conversation: ${e.message}") }
            try { VectorMemory.index(ctx.applicationContext, role, t) } catch (_: Exception) { }
            if (list.size > MAX_MSGS) {
                val keep = list.takeLast(MAX_MSGS - 2000).toMutableList()
                list.clear(); list.addAll(keep); rewrite(ctx)
            }
        }
        if (role.equals("user", true) && t.length >= 3) {
            val app = ctx.applicationContext
            factExecutor.execute { extractFactsWithGemini(app, t) }
        }
    }

    private fun extractFactsWithGemini(ctx: Context, utterance: String) {
        val key = apiKey(ctx)
        if (key.isBlank() || !isEnabled(ctx)) return
        try {
            val prompt = """Extract only durable, useful personal facts from this Hindi/Hinglish/English user utterance.
Return strict JSON only: {"facts":[{"text":"short standalone fact","category":"preferences|promises|daily_routine|financial_debts|relationships|important_dates|other","entity":"user or person's name"}]}.
Keep exact amounts, names, dates and obligations. Do not invent facts. Ignore greetings, questions without a personal fact, temporary requests and assistant statements. Use "user" for facts about the speaker. If nothing durable is present, return {"facts":[]} .
Utterance: ${JSONObject.quote(utterance.take(2500))}"""
            val body = JSONObject().put("contents", JSONArray().put(JSONObject().put("role", "user").put("parts", JSONArray().put(JSONObject().put("text", prompt)))))
                .put("generationConfig", JSONObject().put("temperature", 0.1).put("responseMimeType", "application/json"))
            val req = Request.Builder().url("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
                .header("x-goog-api-key", key).post(body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())).build()
            http.newCall(req).execute().use { response ->
                if (!response.isSuccessful) { Log.w("SIYA_MEMORY", "Fact extraction HTTP ${response.code}"); return }
                val root = JSONObject(response.body?.string().orEmpty())
                val text = root.optJSONArray("candidates")?.optJSONObject(0)?.optJSONObject("content")?.optJSONArray("parts")?.optJSONObject(0)?.optString("text").orEmpty()
                val clean = text.replace(Regex("^\\s*\\x60{3}json?\\s*"), "").replace(Regex("\\s*\\x60{3}\\s*$"), "").trim()
                val arr = JSONObject(clean).optJSONArray("facts") ?: return
                for (i in 0 until arr.length()) {
                    val item = arr.optJSONObject(i) ?: continue
                    val factText = item.optString("text").trim()
                    if (factText.isBlank()) continue
                    val requestedCategory = item.optString("category", inferCategory(factText))
                    addCategorizedFact(ctx, factText, requestedCategory, item.optString("entity", "user"), "gemini")
                }
            }
        } catch (e: Exception) { Log.w("SIYA_MEMORY", "Gemini fact extraction failed: ${e.message}") }
    }

    private fun rewrite(ctx: Context) {
        try {
            val sb = StringBuilder()
            ensure(ctx).forEach { sb.append(JSONObject().put("t", it.time).put("r", it.role).put("x", it.text)).append('\n') }
            File(ctx.filesDir, FILE_MSGS).writeText(sb.toString())
        } catch (_: Exception) { }
    }

    fun addFact(ctx: Context, fact: String): Boolean = addCategorizedFact(ctx, fact, inferCategory(fact), "user", "manual")

    fun addCategorizedFact(ctx: Context, fact: String, category: String, entity: String = "user", source: String = "manual"): Boolean {
        val text = fact.trim().removePrefix("-").trim()
        if (text.isEmpty()) return false
        val cat = category.takeIf { it in categories } ?: inferCategory(text)
        synchronized(lock) {
            val list = ensureFacts(ctx)
            val existing = list.indexOfFirst { it.text.equals(text, true) }
            val now = System.currentTimeMillis()
            val item = Fact(if (existing >= 0) list[existing].id else "fact-${now}-${text.hashCode()}", text, cat, entity.trim().ifBlank { "user" }, if (existing >= 0) list[existing].createdAt else now, source)
            if (existing >= 0) list[existing] = item else list.add(item)
            saveFactsLocked(ctx)
        }
        return true
    }

    fun clearAll(ctx: Context) {
        synchronized(lock) {
            cache = ArrayList(); facts = ArrayList()
            try { File(ctx.filesDir, FILE_MSGS).delete(); File(ctx.filesDir, FILE_FACTS).delete() } catch (_: Exception) { }
        }
    }

    fun count(ctx: Context) = synchronized(lock) { ensure(ctx).size }
    fun recent(ctx: Context, n: Int): List<Msg> = synchronized(lock) { ensure(ctx).takeLast(n) }
    fun factList(ctx: Context): List<String> = synchronized(lock) { ensureFacts(ctx).map { "[${dayFmt.format(Date(it.createdAt))}] [${it.category}] ${it.text}" } }

    fun searchFacts(ctx: Context, query: String, limit: Int = 12): List<Fact> {
        val normalized = query.lowercase(Locale.ROOT)
        val words = normalized.split(Regex("[^\\p{L}\\p{N}₹]+")).filter { it.length > 1 }.toMutableSet()
        val clothingQuery = listOf("shirt", "kapde", "pehnu", "wear", "outfit").any { normalized.contains(it) }
        if (clothingQuery) words.addAll(listOf("color", "colour", "rang", "black", "white", "blue", "shirt"))
        return synchronized(lock) {
            ensureFacts(ctx).map { fact ->
                val hay = (fact.text + " " + fact.category + " " + fact.entity).lowercase(Locale.ROOT)
                val score = words.count { hay.contains(it) } + if (fact.category == "preferences" && (clothingQuery || words.any { it in setOf("color", "colour", "rang") })) 3 else 0
                fact to score
            }.filter { it.second > 0 }.sortedWith(compareByDescending<Pair<Fact, Int>> { it.second }.thenByDescending { it.first.createdAt }).take(limit).map { it.first }
        }
    }

    fun search(ctx: Context, query: String, limit: Int = 12): List<Msg> {
        val words = query.lowercase(Locale.ROOT).split(Regex("\\s+")).filter { it.length > 1 }
        if (words.isEmpty()) return emptyList()
        synchronized(lock) {
            return ensure(ctx).asReversed().map { m -> m to words.count { m.text.lowercase(Locale.ROOT).contains(it) } }
                .filter { it.second > 0 }.sortedWith(compareByDescending<Pair<Msg, Int>> { it.second }.thenByDescending { it.first.time }).take(limit).map { it.first }
        }
    }

    fun format(m: Msg): String = "[${fullFmt.format(Date(m.time))}] ${if (m.role == "user") "User" else "Siya"}: ${m.text}"

    fun buildContext(ctx: Context, recentCount: Int = 40): String {
        val sb = StringBuilder()
        val allFacts = synchronized(lock) { ensureFacts(ctx).toList() }
        if (allFacts.isNotEmpty()) {
            sb.append("=== PERMANENT REMEMBERED FACTS (categorized) ===\n")
            allFacts.filter { it.category in setOf("preferences", "promises", "financial_debts", "important_dates") }.take(100)
                .forEach { sb.append("- [").append(it.category).append("] ").append(it.text).append('\n') }
            allFacts.filter { it.category !in setOf("preferences", "promises", "financial_debts", "important_dates") }.takeLast(60)
                .forEach { sb.append("- [").append(it.category).append("] ").append(it.text).append('\n') }
        }
        val total = count(ctx)
        if (total > 0) {
            sb.append("\n=== PAST CONVERSATION (latest $recentCount of $total messages, oldest first) ===\n")
            recent(ctx, recentCount).forEach { sb.append(format(it).take(400)).append('\n') }
            sb.append("Older chat: use the search_memory tool.\n")
        }
        return sb.toString()
    }

    fun toUiList(ctx: Context, limit: Int = 600): List<Map<String, Any?>> = synchronized(lock) {
        ensure(ctx).takeLast(limit).map { mapOf("time" to it.time, "role" to it.role, "text" to it.text, "day" to dayFmt.format(Date(it.time)), "clock" to timeFmt.format(Date(it.time))) }
    }

    fun exportText(ctx: Context): String = synchronized(lock) {
        val sb = StringBuilder("Siya chat history\n\n")
        val fl = ensureFacts(ctx)
        if (fl.isNotEmpty()) { sb.append("Permanent facts:\n"); fl.forEach { sb.append("- [${it.category}] ${it.text}\n") }; sb.append('\n') }
        ensure(ctx).forEach { sb.append(format(it)).append('\n') }
        sb.toString()
    }
}
