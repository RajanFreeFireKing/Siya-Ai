package com.siya.ai.core

import android.app.usage.UsageStatsManager
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Calendar

/**
 * Feature 5: aadatein + mood + pending kaam. Sab phone ke andar (siya_habits.json).
 * Mood sirf user ke bole shabdon se (keyword) - andaaza hai, pakka nahi.
 */
object HabitTracker {
    private val happy = listOf("khush", "mast", "badhiya", "maza", "happy", "great", "awesome", "love")
    private val sad = listOf("udaas", "dukhi", "rona", "sad", "akela", "lonely", "bura lag")
    private val stress = listOf("tension", "pareshan", "stress", "thak", "gussa", "angry", "irritat")
    private val games = listOf("com.dts.freefireth", "com.dts.freefiremax", "com.pubg.imobile", "com.tencent.ig", "com.activision.callofduty.shooter", "com.supercell.", "com.mojang.minecraftpe", "com.kiloo.subwaysurf")

    private fun f(ctx: Context) = File(ctx.filesDir, "siya_habits.json")
    private fun load(ctx: Context) = try { JSONObject(f(ctx).readText()) } catch (_: Exception) { JSONObject() }
    private fun save(ctx: Context, o: JSONObject) { try { f(ctx).writeText(o.toString()) } catch (_: Exception) {} }

    fun onSession(ctx: Context) {
        val o = load(ctx)
        val h = o.optJSONArray("hours") ?: JSONArray().also { a -> repeat(24) { a.put(0) } }
        val hr = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        h.put(hr, h.optInt(hr) + 1)
        save(ctx, o.put("hours", h))
    }

    fun onUserText(ctx: Context, text: String) {
        val t = text.lowercase()
        val mood = when { sad.any { t.contains(it) } -> "udaas"; stress.any { t.contains(it) } -> "tension mein"; happy.any { t.contains(it) } -> "khush"; else -> return }
        save(ctx, load(ctx).put("mood", mood).put("mood_t", System.currentTimeMillis()))
    }

    // ── tasks ──
    private fun tasks(o: JSONObject) = o.optJSONArray("tasks") ?: JSONArray()
    fun addTask(ctx: Context, text: String): String { val o = load(ctx); save(ctx, o.put("tasks", tasks(o).put(JSONObject().put("x", text.trim()).put("done", false)))); return "OK: kaam add: ${text.trim()}" }
    fun pending(ctx: Context): List<String> { val a = tasks(load(ctx)); return (0 until a.length()).map { a.getJSONObject(it) }.filter { !it.optBoolean("done") }.map { it.getString("x") } }
    fun listTasks(ctx: Context): String = pending(ctx).let { if (it.isEmpty()) "Koi pending kaam nahi" else it.mapIndexed { i, s -> "${i + 1}. $s" }.joinToString("\n") }
    fun doneTask(ctx: Context, text: String): String {
        val o = load(ctx); val a = tasks(o); val q = text.trim().lowercase()
        for (i in 0 until a.length()) { val t = a.getJSONObject(i); if (!t.optBoolean("done") && t.getString("x").lowercase().contains(q)) { t.put("done", true); save(ctx, o); return "OK: ho gaya: ${t.getString("x")}" } }
        return "NOT_FOUND: aisa kaam nahi mila"
    }

    private fun gameMinutes(ctx: Context): Int = try {
        val um = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        (um.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, now - 24 * 3600_000L, now).filter { s -> games.any { s.packageName.startsWith(it) } }.sumOf { it.totalTimeInForeground } / 60000).toInt()
    } catch (_: Exception) { 0 }

    private fun peak(o: JSONObject): Int? {
        val h = o.optJSONArray("hours") ?: return null
        val best = (0 until 24).maxByOrNull { h.optInt(it) } ?: return null
        return if (h.optInt(best) >= 3) best else null
    }

    fun summary(ctx: Context): String {
        val o = load(ctx)
        val sb = StringBuilder()
        peak(o)?.let { sb.append("Aap aam taur par $it baje ke aas-paas sabse zyada baat karte ho.\n") }
        o.optString("mood").takeIf { it.isNotBlank() }?.let { sb.append("Aakhri baar baat se lagta hai ki aap $it the.\n") }
        val gm = gameMinutes(ctx)
        if (gm > 0) sb.append("Pichhle 24 ghante mein games mein $gm minute.\n") else sb.append("(Game time ke liye Usage access ON karo.)\n")
        val p = pending(ctx); if (p.isNotEmpty()) sb.append("Pending kaam: ${p.joinToString("; ")}")
        return sb.toString().ifBlank { "Abhi itna data nahi hai, kuch din baat karne ke baad batati hoon." }
    }

    /** System prompt mein jaata hai: subah pending kaam yaad dilana, mood ke hisaab se baat. */
    fun promptLine(ctx: Context): String {
        val o = load(ctx); val p = pending(ctx)
        val parts = ArrayList<String>()
        o.optString("mood").takeIf { it.isNotBlank() && System.currentTimeMillis() - o.optLong("mood_t") < 12 * 3600_000L }?.let { parts.add("User ka pichhla mood: $it (andaaza hai) - usi hisaab se naram / mazaakiya raho.") }
        if (p.isNotEmpty()) parts.add("User ke pending kaam: ${p.joinToString("; ")}. Agar subah (5-11 baje) ka time ho to baat ke beech ek baar pyaar se yaad dila do.")
        peak(o)?.let { parts.add("User aam taur par $it baje active rehta hai.") }
        return parts.joinToString(" ")
    }
}
