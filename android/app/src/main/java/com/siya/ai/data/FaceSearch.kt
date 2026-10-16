package com.siya.ai.data

import android.content.Context
import android.util.Base64
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Gallery mein kisi saved insaan ki photos dhundo.
 * Reference photo + gallery ki chhoti photos (batch mein) Gemini ko bheji jaati hain (user ke apne API key se);
 * Gemini batata hai kin photos mein wahi insaan hai. Koi photo phone par edit / delete nahi hoti.
 */
object FaceSearch {
    data class Match(val uri: String, val name: String)

    @Volatile var running = false
        private set
    @Volatile var done = 0
        private set
    @Volatile var total = 0
        private set
    @Volatile var error = ""
        private set
    @Volatile var personId = ""
        private set
    private val matches = java.util.Collections.synchronizedList(ArrayList<Match>())
    @Volatile private var cancel = false

    private val http = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS).readTimeout(90, TimeUnit.SECONDS).writeTimeout(60, TimeUnit.SECONDS).build()

    private const val BATCH = 6
    private val models = listOf("gemini-2.5-flash", "gemini-2.0-flash")

    private fun cacheFile(ctx: Context, id: String) = File(ctx.filesDir, "people/${id}_matches.json")

    fun status(ctx: Context, id: String): Map<String, Any?> {
        val list: List<Match> = if (personId == id && (running || matches.isNotEmpty())) synchronized(matches) { ArrayList(matches) }
        else loadCache(ctx, id)
        return mapOf(
            "running" to (running && personId == id), "done" to if (personId == id) done else 0,
            "total" to if (personId == id) total else 0, "error" to if (personId == id) error else "",
            "matches" to list.map { mapOf("uri" to it.uri, "name" to it.name) }
        )
    }

    private fun loadCache(ctx: Context, id: String): List<Match> = try {
        val f = cacheFile(ctx, id)
        if (!f.exists()) emptyList() else {
            val a = JSONArray(f.readText())
            (0 until a.length()).map { Match(a.getJSONObject(it).optString("uri"), a.getJSONObject(it).optString("name")) }
        }
    } catch (_: Exception) { emptyList() }

    private fun saveCache(ctx: Context, id: String) {
        try {
            val a = JSONArray()
            synchronized(matches) { matches.forEach { a.put(JSONObject().put("uri", it.uri).put("name", it.name)) } }
            File(ctx.filesDir, "people").mkdirs()
            cacheFile(ctx, id).writeText(a.toString())
        } catch (_: Exception) {}
    }

    fun cancel() { cancel = true }

    fun start(ctx: Context, id: String, limit: Int) {
        if (running) return
        val app = ctx.applicationContext
        val person = PeopleStore.list(app).firstOrNull { it.id == id }
        personId = id; matches.clear(); done = 0; total = 0; error = ""; cancel = false
        if (person == null || person.photo.isBlank()) { error = "Pehle is insaan ki saaf photo save karo"; return }
        val key = app.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getString("api_key", "").orEmpty()
        if (key.isBlank()) { error = "Gemini API key nahi hai (Settings mein daalo)"; return }
        running = true
        Thread({
            try {
                val ref = ImageUtil.decodeScaled(person.photo, 640)
                if (ref == null) { error = "Reference photo khul nahi payi"; return@Thread }
                val refB64 = Base64.encodeToString(ImageUtil.jpeg(ref, 85), Base64.NO_WRAP)
                val items = MediaHelper.list(app, "image", limit)
                total = items.size
                var model = models[0]
                var i = 0
                while (i < items.size && !cancel) {
                    val chunk = items.subList(i, minOf(i + BATCH, items.size))
                    val thumbs = chunk.map { MediaHelper.thumbnail(app, it["uri"] as String, "image", 448) }
                    val idx = ask(key, model, person.name, refB64, thumbs) { m -> model = m }
                    if (idx == null) { if (error.isNotBlank()) break else { done = minOf(i + BATCH, total); i += BATCH; continue } }
                    idx.forEach { n -> if (n in 1..chunk.size) matches.add(Match(chunk[n - 1]["uri"] as String, chunk[n - 1]["name"] as String)) }
                    i += BATCH
                    done = minOf(i, total)
                }
                saveCache(app, id)
            } catch (e: Exception) {
                error = "Search mein dikkat: ${e.message}"
            } finally { running = false }
        }, "siya-facesearch").start()
    }

    /** Wapas: milti hui photos ke number (1..N), ya null (error ya jawab samajh nahi aaya). */
    private fun ask(key: String, model: String, name: String, refB64: String, thumbs: List<ByteArray?>, onModel: (String) -> Unit): List<Int>? {
        val parts = JSONArray()
        parts.put(JSONObject().put("text", "Image 0 ek reference photo hai: yeh $name hai. Neeche Image 1 se ${thumbs.size} tak gallery ki photos hain. " +
            "Batao kin photos mein wahi insaan ($name) clearly dikh raha hai (chehre ka match). Zyada shak ho to shamil mat karo. " +
            "Sirf JSON do: {\"matches\":[numbers]}"))
        parts.put(JSONObject().put("inline_data", JSONObject().put("mime_type", "image/jpeg").put("data", refB64)))
        thumbs.forEachIndexed { n, b ->
            parts.put(JSONObject().put("text", "Image ${n + 1}:"))
            if (b != null) parts.put(JSONObject().put("inline_data", JSONObject().put("mime_type", "image/jpeg").put("data", Base64.encodeToString(b, Base64.NO_WRAP))))
        }
        val body = JSONObject()
            .put("contents", JSONArray().put(JSONObject().put("parts", parts)))
            .put("generationConfig", JSONObject().put("responseMimeType", "application/json").put("temperature", 0.1))
            .toString().toRequestBody("application/json".toMediaType())
        var m = model
        for (attempt in 0 until models.size) {
            val req = Request.Builder().url("https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent?key=$key").post(body).build()
            try {
                http.newCall(req).execute().use { r ->
                    val txt = r.body?.string().orEmpty()
                    if (r.code == 404 && attempt + 1 < models.size) { m = models[attempt + 1]; onModel(m); return@use }
                    if (r.code == 400 && txt.contains("API key", true)) { error = "API key galat hai"; return null }
                    if (r.code == 429) { error = "Gemini limit poori ho gayi, thodi der baad try karo"; return null }
                    if (!r.isSuccessful) { error = "Gemini error ${r.code}"; return null }
                    val out = JSONObject(txt).optJSONArray("candidates")?.optJSONObject(0)
                        ?.optJSONObject("content")?.optJSONArray("parts")?.optJSONObject(0)?.optString("text").orEmpty()
                    val arr = JSONObject(out.trim().removePrefix("```json").removeSuffix("```").trim()).optJSONArray("matches") ?: return emptyList()
                    return (0 until arr.length()).map { arr.optInt(it) }
                }
            } catch (e: Exception) { error = "Network dikkat: ${e.message}"; return null }
        }
        return null
    }
}
