package com.siya.ai.service

import android.content.Context
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import org.vosk.android.StorageService

/**
 * Feature 7: bina paid key / internet ke offline "Hey Siya" (Vosk).
 * Model: android/app/src/main/assets/model/ ke andar chhota Vosk model (vosk-model-small-en-in ya small-hi) rakho.
 */
class VoskWakeEngine(private val ctx: Context, private val onWake: () -> Unit) : WakeEngine {
    companion object {
        fun available(ctx: Context) = try { ctx.assets.list("model")?.isNotEmpty() == true } catch (_: Exception) { false }
        private var model: Model? = null
    }

    private var svc: SpeechService? = null
    @Volatile override var isRunning = false
        private set

    private val phrases = """["hey siya", "hello siya", "hi siya", "hey sia", "hey siyaa", "[unk]"]"""

    override fun start() {
        if (isRunning) return
        isRunning = true
        val m = model
        if (m != null) listen(m) else StorageService.unpack(ctx, "model", "vosk_model",
            { mod -> model = mod; if (isRunning) listen(mod) }, { isRunning = false })
    }

    private fun listen(m: Model) {
        try {
            svc = SpeechService(Recognizer(m, 16000f, phrases), 16000f).also {
                it.startListening(object : RecognitionListener {
                    private fun check(h: String?) {
                        if (h != null && h.contains("siya", true) || h?.contains("sia", true) == true) { onWake() }
                    }
                    override fun onPartialResult(h: String?) = check(h)
                    override fun onResult(h: String?) = check(h)
                    override fun onFinalResult(h: String?) {}
                    override fun onError(e: Exception?) { isRunning = false }
                    override fun onTimeout() {}
                })
            }
        } catch (_: Exception) { isRunning = false }
    }

    override fun stop() {
        isRunning = false
        try { svc?.stop(); svc?.shutdown() } catch (_: Exception) {}
        svc = null
    }
}
