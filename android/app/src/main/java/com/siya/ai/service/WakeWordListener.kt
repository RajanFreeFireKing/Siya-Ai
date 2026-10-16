package com.siya.ai.service

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log

class WakeWordListener(private val ctx: Context, private val onWake: () -> Unit) : WakeEngine {
    private val main = Handler(Looper.getMainLooper())
    private val unmuteH = Handler(Looper.getMainLooper())   // alag handler: schedule() ke removeCallbacks se na hate
    private var rec: SpeechRecognizer? = null
    private var running = false
    private var muted = false
    private var failStreak = 0

    private val pattern = Regex(
        """(hello|helo|hallo|hey|hay|हेलो|हैलो|हलो|हे)\s+(siya|sya|सिया|सीया)""",
        RegexOption.IGNORE_CASE
    )

    override val isRunning get() = running

    override fun start() {
        if (running) return
        if (!SpeechRecognizer.isRecognitionAvailable(ctx)) {
            Log.w(TAG, "no recognizer")
            return
        }
        running = true
        failStreak = 0
        listen()
    }

    override fun stop() {
        running = false
        main.removeCallbacksAndMessages(null)
        destroy()
        mute(false)
    }

    private fun destroy() {
        try { rec?.cancel() } catch (_: Exception) {}
        try { rec?.destroy() } catch (_: Exception) {}
        rec = null
    }

    private fun schedule(ms: Long) {
        if (!running) return
        main.removeCallbacksAndMessages(null)
        main.postDelayed({ listen() }, ms)
    }

    private fun listen() {
        if (!running) return
        try {
            destroy()
            val r = SpeechRecognizer.createSpeechRecognizer(ctx)
            r.setRecognitionListener(listener)
            rec = r
            val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-IN")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, ctx.packageName)
            }
            mute(true)
            unmuteH.postDelayed({ mute(false) }, 1200)   // sirf start ki beep ke liye; notification / system awaaz hamesha mute nahi
            r.startListening(i)
        } catch (_: Exception) {
            Log.e(TAG, "speech recognizer start failed")
            failStreak++
            schedule((failStreak * 1000L).coerceAtMost(6000L))
        }
    }

    private fun matches(text: String): Boolean {
        val normalized = text.lowercase()
            .replace(Regex("[^\\p{L}\\p{M}\\s]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        return pattern.containsMatchIn(normalized)
    }

    private fun check(b: Bundle?): Boolean {
        val list = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: return false
        return list.any(::matches)
    }

    private fun woke() {
        running = false
        main.removeCallbacksAndMessages(null)
        destroy()
        mute(false)
        onWake()
    }

    private fun mute(on: Boolean) {
        if (!on) unmuteH.removeCallbacksAndMessages(null)
        if (muted == on) return
        muted = on
        try {
            val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val dir = if (on) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE
            am.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, dir, 0)
            am.adjustStreamVolume(AudioManager.STREAM_SYSTEM, dir, 0)
        } catch (_: Exception) {}
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) { failStreak = 0 }
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
        override fun onPartialResults(partialResults: Bundle?) {
            if (running && check(partialResults)) woke()
        }
        override fun onResults(results: Bundle?) {
            if (!running) return
            if (check(results)) woke() else schedule(350)
        }
        override fun onError(error: Int) {
            if (!running) return
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> schedule(350)
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> schedule(800)
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                    running = false
                    mute(false)
                }
                else -> {
                    failStreak++
                    schedule((failStreak * 900L).coerceAtMost(6000L))
                }
            }
        }
    }

    companion object { private const val TAG = "SIYA_WAKE" }
}
