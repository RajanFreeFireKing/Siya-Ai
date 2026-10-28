package com.siya.ai.utils

import android.content.Context
import android.speech.tts.TextToSpeech
import android.util.Log
import java.util.Locale

/** Stable Android TTS fallback. Prefer a Hindi-India voice labelled female when installed. */
class FemaleHindiTts(
    context: Context,
    private val onReady: (Boolean) -> Unit = {}
) : TextToSpeech.OnInitListener {
    @Volatile private var ready = false
    private var engine: TextToSpeech? = null

    init {
        activeInstance = this
        engine = TextToSpeech(context.applicationContext, this)
    }

    override fun onInit(status: Int) {
        val tts = engine
        if (status != TextToSpeech.SUCCESS || tts == null) {
            onReady(false)
            return
        }
        try {
            val languageStatus = tts.setLanguage(Locale("hi", "IN"))
            val candidates = tts.voices.orEmpty().filter {
                it.locale.language == "hi" && (it.locale.country.isBlank() || it.locale.country.equals("IN", true))
            }
            val femaleVoice = candidates.firstOrNull {
                it.name.contains("female", true) || it.name.contains("hi-in-x-hie-local", true)
            }
            if (femaleVoice != null) tts.voice = femaleVoice
            tts.setSpeechRate(0.92f)
            tts.setPitch(1.08f)
            ready = languageStatus >= TextToSpeech.LANG_AVAILABLE
            if (femaleVoice == null) Log.w("SIYA_TTS", "No labelled Hindi female voice installed; using available Hindi voice")
            onReady(ready)
        } catch (e: Exception) {
            Log.e("SIYA_TTS", "Could not configure Hindi TTS: ${e.message}", e)
            ready = false
            onReady(false)
        }
    }

    companion object {
        @Volatile var activeInstance: FemaleHindiTts? = null

        fun stopActive() {
            try { activeInstance?.stop() } catch (_: Exception) {}
        }

        fun sanitize(raw: String): String {
            var s = raw.replace(Regex("(?i)\\b(ajay)\\b"), "")
            s = s.replace(Regex("(?i)\\[/?inst\\]"), "")
            s = s.replace(Regex("(?i)<\\|.*?\\|>"), "")
            s = s.replace(Regex("(?i)\\b(model|assistant|developer|system):"), "")
            return s.trim()
        }
    }

    fun speak(text: String, utteranceId: String = "siya-local") {
        val clean = sanitize(text)
        if (!ready || clean.isBlank()) return
        try { engine?.speak(clean, TextToSpeech.QUEUE_FLUSH, null, utteranceId) } catch (e: Exception) {
            Log.w("SIYA_TTS", "speak failed: ${e.message}")
        }
    }

    fun stop() { try { engine?.stop() } catch (_: Exception) {} }

    fun release() {
        ready = false
        try { engine?.stop(); engine?.shutdown() } catch (_: Exception) {}
        engine = null
    }
}
