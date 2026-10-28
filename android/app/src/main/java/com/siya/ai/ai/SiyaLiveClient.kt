package com.siya.ai.ai

import android.util.Base64
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Gemini Live (real-time voice). Mic ka PCM seedha stream hota hai, jawab bhi audio mein aata hai,
 * beech mein bolne par (barge-in) Gemini khud ruk jaata hai - bilkul live call jaisa.
 */
class SiyaLiveClient(
    private val apiKey: String,
    private val model: String,
    private val voiceName: String,
    private val systemPrompt: String,
    private val tools: JSONArray,
    private val callback: Listener,
    private val temperature: Double = 0.88
) {
    interface Listener {
        fun onReady()
        fun onAudio(pcm24k: ByteArray)
        fun onUserText(text: String)
        fun onSiyaText(text: String)
        fun onInterrupted()
        fun onTurnComplete()
        fun onToolCall(id: String, name: String, args: JSONObject)
        fun onGoAway()
        fun onClosed(reason: String)
    }

    private val tag = "SIYA_LIVE"
    @Volatile private var ready = false
    @Volatile private var closedByUs = false
    private var ws: WebSocket? = null

    private val http = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .connectTimeout(15, TimeUnit.SECONDS)
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    val isReady get() = ready

    fun connect() {
        closedByUs = false
        ready = false
        val url = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=$apiKey"
        ws = http.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) { sendSetup(webSocket) }
            override fun onMessage(webSocket: WebSocket, text: String) { handle(text) }
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) { handle(bytes.utf8()) }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                ready = false
                if (!closedByUs) callback.onClosed(t.message ?: "connection failed")
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                ready = false
                if (!closedByUs) callback.onClosed(if (reason.isNotEmpty()) reason else "closed $code")
            }
        })
    }

    private fun sendSetup(w: WebSocket) {
        try {
            val setup = JSONObject().apply {
                put("model", if (model.startsWith("models/")) model else "models/$model")
                put("generationConfig", JSONObject().apply {
                    put("responseModalities", JSONArray().put("AUDIO"))
                    put("temperature", temperature)
                    put("speechConfig", JSONObject().put("voiceConfig",
                        JSONObject().put("prebuiltVoiceConfig", JSONObject().put("voiceName", voiceName))))
                })
                put("systemInstruction", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", systemPrompt))))
                put("tools", tools)
                put("realtimeInputConfig", JSONObject().put("automaticActivityDetection", JSONObject().apply {
                    put("startOfSpeechSensitivity", "START_SENSITIVITY_HIGH")
                    put("endOfSpeechSensitivity", "END_SENSITIVITY_HIGH")
                    put("prefixPaddingMs", 60)
                    put("silenceDurationMs", 220)
                }))
                put("inputAudioTranscription", JSONObject())
                put("outputAudioTranscription", JSONObject())
                put("contextWindowCompression", JSONObject().put("slidingWindow", JSONObject()))
            }
            w.send(JSONObject().put("setup", setup).toString())
        } catch (e: Exception) { Log.e(tag, "setup: ${e.message}") }
    }

    /** Mic ka 16kHz 16-bit mono PCM chunk. */
    fun sendAudio(pcm16k: ByteArray, length: Int) {
        if (!ready) return
        try {
            val b64 = Base64.encodeToString(pcm16k, 0, length, Base64.NO_WRAP)
            ws?.send(JSONObject().put("realtimeInput", JSONObject().put("audio",
                JSONObject().put("data", b64).put("mimeType", "audio/pcm;rate=16000"))).toString())
        } catch (_: Exception) {}
    }

    /** Camera / screen ki photo (JPEG) live session ko bhejo. */
    fun sendImage(jpeg: ByteArray) {
        if (!ready) return
        try {
            val b64 = Base64.encodeToString(jpeg, Base64.NO_WRAP)
            ws?.send(JSONObject().put("realtimeInput", JSONObject().put("video",
                JSONObject().put("data", b64).put("mimeType", "image/jpeg"))).toString())
        } catch (_: Exception) {}
    }

    fun sendText(text: String) {
        if (!ready) return
        try { ws?.send(JSONObject().put("realtimeInput", JSONObject().put("text", text)).toString()) } catch (_: Exception) {}
    }

    fun sendAudioStreamEnd() {
        if (!ready) return
        try { ws?.send(JSONObject().put("realtimeInput", JSONObject().put("audioStreamEnd", true)).toString()) } catch (_: Exception) {}
    }

    fun sendToolResult(id: String, name: String, result: String) {
        try {
            val fr = JSONObject().put("id", id).put("name", name).put("response", JSONObject().put("result", result))
            ws?.send(JSONObject().put("toolResponse", JSONObject().put("functionResponses", JSONArray().put(fr))).toString())
        } catch (_: Exception) {}
    }

    private fun handle(raw: String) {
        try {
            val json = JSONObject(raw)
            if (json.has("setupComplete")) { ready = true; callback.onReady(); return }

            json.optJSONObject("toolCall")?.optJSONArray("functionCalls")?.let { calls ->
                for (i in 0 until calls.length()) {
                    val c = calls.getJSONObject(i)
                    callback.onToolCall(c.optString("id"), c.optString("name"), c.optJSONObject("args") ?: JSONObject())
                }
                return
            }
            if (json.has("goAway")) { callback.onGoAway(); return }

            val sc = json.optJSONObject("serverContent") ?: return
            if (sc.optBoolean("interrupted", false)) callback.onInterrupted()

            sc.optJSONObject("modelTurn")?.optJSONArray("parts")?.let { parts ->
                for (i in 0 until parts.length()) {
                    val p = parts.getJSONObject(i)
                    p.optJSONObject("inlineData")?.optString("data")?.takeIf { it.isNotEmpty() }?.let {
                        callback.onAudio(Base64.decode(it, Base64.DEFAULT))
                    }
                }
            }
            sc.optJSONObject("inputTranscription")?.optString("text")?.takeIf { it.isNotEmpty() }?.let { callback.onUserText(it) }
            sc.optJSONObject("outputTranscription")?.optString("text")?.takeIf { it.isNotEmpty() }?.let { callback.onSiyaText(it) }
            if (sc.optBoolean("turnComplete", false)) callback.onTurnComplete()
        } catch (e: Exception) { Log.e(tag, "parse: ${e.message}") }
    }

    fun close() {
        closedByUs = true
        ready = false
        try { ws?.close(1000, "bye") } catch (_: Exception) {}
        ws = null
    }
}
