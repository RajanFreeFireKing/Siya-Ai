package com.siya.ai.core

import android.content.Context
import android.util.Base64
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** Gemini REST (user ki apni API key se): text / photo -> text. WhatsApp reply, summary, bill OCR sab yahi use karte hain. */
object AiText {
    private val http = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build()
    private val models = listOf("gemini-2.5-flash", "gemini-2.0-flash")

    fun key(ctx: Context) = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getString("api_key", "").orEmpty()

    fun generate(ctx: Context, prompt: String, jpeg: ByteArray? = null): String? {
        val k = key(ctx); if (k.isBlank()) return null
        val parts = JSONArray().put(JSONObject().put("text", prompt))
        if (jpeg != null) parts.put(JSONObject().put("inline_data", JSONObject().put("mime_type", "image/jpeg").put("data", Base64.encodeToString(jpeg, Base64.NO_WRAP))))
        val body = JSONObject().put("contents", JSONArray().put(JSONObject().put("parts", parts))).toString().toRequestBody("application/json".toMediaType())
        for (m in models) {
            try {
                val req = Request.Builder().url("https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent")
                    .header("x-goog-api-key", k).post(body).build()
                http.newCall(req).execute().use { r ->
                    if (!r.isSuccessful) return@use
                    val ps = JSONObject(r.body?.string().orEmpty()).getJSONArray("candidates").getJSONObject(0).getJSONObject("content").getJSONArray("parts")
                    val sb = StringBuilder(); for (i in 0 until ps.length()) sb.append(ps.getJSONObject(i).optString("text"))
                    if (sb.isNotBlank()) return sb.toString().trim()
                }
            } catch (_: Exception) {}
        }
        return null
    }
}
