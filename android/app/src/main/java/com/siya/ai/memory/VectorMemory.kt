package com.siya.ai.memory

import android.content.Context
import android.util.Base64
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.sqrt

/**
 * Feature 4: Vector semantic memory. Har baat ka embedding (256 numbers) Gemini embedding API se banta hai
 * (user ki apni API key) aur phone mein save hota hai. Purani baat "matlab" se milti hai, sirf shabd se nahi.
 */
object VectorMemory {
    private class Item(val t: Long, val role: String, val text: String, val v: FloatArray)
    private val io = Executors.newSingleThreadExecutor()
    private val http = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS).build()
    private const val DIM = 256
    private val lock = Any()
    private var items: MutableList<Item>? = null

    private fun key(ctx: Context) = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getString("api_key", "").orEmpty()
    private fun model(ctx: Context) = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getString("embed_model", "gemini-embedding-001").orEmpty()
    private fun file(ctx: Context) = File(ctx.filesDir, "siya_vectors.jsonl")

    private fun embed(ctx: Context, text: String, query: Boolean): FloatArray? {
        val k = key(ctx); if (k.isBlank()) return null
        val m = model(ctx)
        val body = JSONObject().put("model", "models/$m")
            .put("content", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", text.take(1500)))))
            .put("taskType", if (query) "RETRIEVAL_QUERY" else "RETRIEVAL_DOCUMENT").put("outputDimensionality", DIM)
        return try {
            val req = Request.Builder().url("https://generativelanguage.googleapis.com/v1beta/models/$m:embedContent")
                .header("x-goog-api-key", k).post(body.toString().toRequestBody("application/json".toMediaType())).build()
            http.newCall(req).execute().use { r ->
                if (!r.isSuccessful) return null
                val a = JSONObject(r.body?.string().orEmpty()).getJSONObject("embedding").getJSONArray("values")
                val v = FloatArray(a.length()) { a.getDouble(it).toFloat() }
                val n = sqrt(v.sumOf { (it * it).toDouble() }).toFloat().coerceAtLeast(1e-6f)
                for (i in v.indices) v[i] /= n
                v
            }
        } catch (_: Exception) { null }
    }

    private fun enc(v: FloatArray): String { val b = ByteBuffer.allocate(v.size * 4); v.forEach { b.putFloat(it) }; return Base64.encodeToString(b.array(), Base64.NO_WRAP) }
    private fun dec(s: String): FloatArray { val b = ByteBuffer.wrap(Base64.decode(s, Base64.NO_WRAP)); return FloatArray(b.remaining() / 4) { b.float } }

    private fun load(ctx: Context): MutableList<Item> = synchronized(lock) {
        items?.let { return it }
        val l = ArrayList<Item>()
        try { file(ctx).forEachLine { line -> try { val o = JSONObject(line); l.add(Item(o.getLong("t"), o.getString("r"), o.getString("x"), dec(o.getString("v")))) } catch (_: Exception) {} } } catch (_: Exception) {}
        items = l; l
    }

    /** MemoryStore.add se bulaya jaata hai. Background mein, chat ko rokta nahi. */
    fun index(ctx: Context, role: String, text: String) {
        if (text.length < 20 || key(ctx).isBlank()) return
        val app = ctx.applicationContext
        io.execute {
            val v = embed(app, text, false) ?: return@execute
            val now = System.currentTimeMillis()
            synchronized(lock) {
                load(app).add(Item(now, role, text, v))
                try { file(app).appendText(JSONObject().put("t", now).put("r", role).put("x", text).put("v", enc(v)).toString() + "\n") } catch (_: Exception) {}
            }
        }
    }

    fun search(ctx: Context, query: String, k: Int = 5): String {
        if (query.isBlank()) return ""
        val q = embed(ctx, query, true) ?: return ""
        val all = synchronized(lock) { ArrayList(load(ctx)) }
        if (all.isEmpty()) return ""
        val fmt = SimpleDateFormat("dd MMM yyyy, hh:mm a", Locale.getDefault())
        return all.map { it to it.v.indices.sumOf { i -> (it.v[i] * q[i]).toDouble() } }
            .filter { it.second > 0.55 }.sortedByDescending { it.second }.take(k)
            .joinToString("\n") { "[${fmt.format(Date(it.first.t))}] ${if (it.first.role == "user") "User" else "Siya"}: ${it.first.text.take(300)}" }
    }
}
