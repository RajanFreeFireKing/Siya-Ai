package com.siya.ai.service

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale

/**
 * WhatsApp announce-and-confirm mode. No generated or automatic replies.
 * A reply is sent only when the user dictates it in response to the spoken prompt.
 */
class SiyaNotificationListener : NotificationListenerService() {
    companion object {
        private const val TAG = "SiyaWaConfirm"
        private const val LISTEN_TIMEOUT_MS = 12_000L
    }

    private val main = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var recognizer: SpeechRecognizer? = null
    private var pendingAction: Notification.Action? = null
    private var pendingInputs: Array<RemoteInput>? = null
    private var pendingSender = ""
    private var timeout: Runnable? = null
    private var lastNotificationKey: String? = null
    private var lastNotificationAt = 0L

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName != "com.whatsapp" && sbn.packageName != "com.whatsapp.w4b") return
        val n = sbn.notification
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val ex = n.extras
        val sender = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val message = ex.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: ex.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        if (sender.isBlank() || message.isBlank() || sender.equals("WhatsApp", true)) return
        if (message.contains("new messages", true) || message.contains("checking for new messages", true)) return
        if (ex.getBoolean("android.isGroupConversation", false)) return

        val now = SystemClock.elapsedRealtime()
        if (sbn.key == lastNotificationKey && now - lastNotificationAt < 3_000L) return
        lastNotificationKey = sbn.key
        lastNotificationAt = now

        val action = (n.actions?.toList().orEmpty() + Notification.WearableExtender(n).actions)
            .firstOrNull { it.remoteInputs?.isNotEmpty() == true }

        cancelPending()
        pendingSender = sender
        pendingAction = action
        pendingInputs = action?.remoteInputs

        val prompt = if (action != null) {
            "$sender ne message kiya hai: '$message'. Kya reply dena hai ya aise hi chhod dein?"
        } else {
            "$sender ne message kiya hai: '$message'. Is notification mein direct reply ka option nahi mila."
        }
        speakPrompt(prompt, action != null)
    }

    private fun speakPrompt(prompt: String, listenAfter: Boolean) {
        main.post {
            if (ttsReady && tts != null) {
                speakWithCurrentEngine(prompt, listenAfter)
                return@post
            }
            if (tts == null) {
                tts = TextToSpeech(applicationContext) { status ->
                    main.post {
                        val engine = tts
                        ttsReady = status == TextToSpeech.SUCCESS && engine != null
                        if (!ttsReady) {
                            Log.w(TAG, "TTS unavailable; canceling pending reply")
                            cancelPending()
                            return@post
                        }
                        try {
                            engine!!.language = Locale("hi", "IN")
                            engine.setSpeechRate(0.92f)
                            engine.setPitch(1.08f)
                        } catch (e: Exception) {
                            Log.w(TAG, "Hindi TTS configuration failed", e)
                        }
                        speakWithCurrentEngine(prompt, listenAfter)
                    }
                }
            }
        }
    }

    private fun speakWithCurrentEngine(prompt: String, listenAfter: Boolean) {
        val engine = tts ?: run { cancelPending(); return }
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) {
                if (utteranceId == "wa-confirm-prompt" && listenAfter) main.post { startReplyRecognition() }
            }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                if (utteranceId == "wa-confirm-prompt" && listenAfter) main.post { startReplyRecognition() }
            }
        })
        engine.speak(prompt, TextToSpeech.QUEUE_FLUSH, null, "wa-confirm-prompt")
    }

    private fun startReplyRecognition() {
        if (pendingAction == null || pendingInputs.isNullOrEmpty()) {
            cancelPending()
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.w(TAG, "Speech recognition unavailable; no reply sent")
            cancelPending()
            return
        }
        try {
            recognizer?.destroy()
            val sr = SpeechRecognizer.createSpeechRecognizer(applicationContext)
            recognizer = sr
            sr.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onError(error: Int) {
                    Log.d(TAG, "Voice reply cancelled/error=$error; no message sent")
                    cancelPending()
                }
                override fun onResults(results: Bundle?) {
                    timeout?.let { main.removeCallbacks(it) }; timeout = null
                    val spoken = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()?.trim().orEmpty()
                    if (spoken.isBlank() || SmartAccessibilityEngine.isCancelReplyCommand(spoken)) {
                        cancelPending()
                        return
                    }
                    sendApprovedReply(spoken)
                }
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "hi-IN")
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "hi-IN")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Reply boliye, ya Chhod do kahiye")
            }
            timeout?.let { main.removeCallbacks(it) }
            timeout = Runnable { cancelPending() }.also { main.postDelayed(it, LISTEN_TIMEOUT_MS) }
            sr.startListening(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Could not start voice recognition", e)
            cancelPending()
        }
    }

    private fun sendApprovedReply(spokenReply: String) {
        val action = pendingAction
        val inputs = pendingInputs
        val input = inputs?.firstOrNull()
        if (action == null || inputs.isNullOrEmpty() || input == null) {
            cancelPending()
            return
        }
        try {
            val fillIn = Intent()
            val results = Bundle().apply { putCharSequence(input.resultKey, spokenReply.take(2_000)) }
            RemoteInput.addResultsToIntent(inputs, fillIn, results)
            action.actionIntent.send(this, 0, fillIn)
            Log.i(TAG, "Explicit user-dictated WhatsApp reply sent; sender=$pendingSender")
        } catch (e: Exception) {
            Log.e(TAG, "RemoteInput reply failed; no UI fallback attempted", e)
        } finally {
            cancelPending()
        }
    }

    private fun cancelPending() {
        timeout?.let { main.removeCallbacks(it) }; timeout = null
        try { recognizer?.cancel(); recognizer?.destroy() } catch (_: Exception) {}
        recognizer = null
        pendingAction = null
        pendingInputs = null
        pendingSender = ""
    }

    override fun onDestroy() {
        cancelPending()
        try { tts?.stop(); tts?.shutdown() } catch (_: Exception) {}
        tts = null
        ttsReady = false
        main.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
