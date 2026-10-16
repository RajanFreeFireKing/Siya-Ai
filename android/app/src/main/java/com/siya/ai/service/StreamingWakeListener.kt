package com.siya.ai.service

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import java.io.OutputStream
import java.util.concurrent.LinkedBlockingQueue
import kotlin.math.sqrt

/**
 * "Hey Siya" bina mic baar-baar kholay band kiye (Android 13+).
 *
 * Purana tareeka SpeechRecognizer ko har kuch second mein start / stop karta tha, isliye mic icon jhapakta tha.
 * Yahan mic ek hi AudioRecord se lagatar khula rehta hai (icon steady), aur recognizer ko audio
 * hum khud pipe se dete hain (EXTRA_AUDIO_SOURCE). Recognizer tabhi chalta hai jab koi bolna shuru kare
 * (energy VAD), isliye CPU / battery bhi kam lagti hai aur mic ka on-off nahi hota.
 * Agar phone ka recognizer pipe se audio lena support na kare to onUnsupported() bulata hai aur service purane listener par chali jaati hai.
 */
class StreamingWakeListener(
    private val ctx: Context,
    private val onWake: () -> Unit,
    private val onUnsupported: () -> Unit,
) : WakeEngine {

    companion object {
        private const val TAG = "SIYA_STREAM_WAKE"
        private const val RATE = 16000
        private const val FRAME = 640            // 20 ms, 16-bit mono
        private val EMPTY = ByteArray(0)
        private val pattern = Regex("""(hello|helo|hallo|hey|hay|हेलो|हैलो|हलो|हे)\s+(siya|sya|sia|सिया|सीया)""", RegexOption.IGNORE_CASE)

        fun supported(ctx: Context) = Build.VERSION.SDK_INT >= 33 && SpeechRecognizer.isRecognitionAvailable(ctx)
    }

    private class Sess(val read: ParcelFileDescriptor, val out: OutputStream) {
        val q = LinkedBlockingQueue<ByteArray>()
        @Volatile var dead = false
    }

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var running = false
    private var micThread: Thread? = null
    private var recognizer: SpeechRecognizer? = null
    @Volatile private var cur: Sess? = null            // jis session ko abhi audio mil raha hai
    private var live: Sess? = null                      // recognizer ke paas jo pipe hai (main thread)
    @Volatile private var waitingResult = false
    @Volatile private var cooldownUntil = 0L
    private var hardFails = 0
    private var everWorked = false
    private var muted = false

    override val isRunning get() = running

    override fun start() {
        if (running) return
        running = true
        hardFails = 0
        micThread = Thread({ micLoop() }, "siya-wake-mic").also { it.isDaemon = true; it.start() }
    }

    override fun stop() {
        running = false
        micThread?.interrupt(); micThread = null
        main.removeCallbacksAndMessages(null)
        main.post { teardown() }
    }

    // ── mic: ek hi AudioRecord, lagatar ───────────────────────
    @SuppressLint("MissingPermission")
    private fun micLoop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        var rec: AudioRecord? = null
        var backoff = 1000L
        val pre = ArrayDeque<ByteArray>()               // 400 ms pre-roll
        var floor = 0.004f
        var voiced = 0
        var lastVoice = 0L
        var streamStart = 0L
        val buf = ByteArray(FRAME)
        try {
            while (running) {
                if (rec == null) {
                    val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                    val r = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, RATE, AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT, maxOf(min, FRAME * 16))
                    if (r.state != AudioRecord.STATE_INITIALIZED) {
                        r.release(); Thread.sleep(backoff); backoff = (backoff * 2).coerceAtMost(8000L); continue
                    }
                    r.startRecording(); rec = r; backoff = 1000L
                }
                var got = 0
                while (got < FRAME && running) {
                    val n = rec.read(buf, got, FRAME - got)
                    if (n < 0) { got = -1; break }
                    got += n
                }
                if (got < 0) {                              // mic kisi aur ne le liya: chupchap chhodo, baad mein wapas
                    try { rec.stop() } catch (_: Exception) {}; rec.release(); rec = null
                    Thread.sleep(backoff); backoff = (backoff * 2).coerceAtMost(8000L); continue
                }
                if (got < FRAME) continue

                var sum = 0.0; var i = 0
                while (i + 1 < FRAME) {
                    val s = ((buf[i + 1].toInt() shl 8) or (buf[i].toInt() and 0xFF)).toShort().toInt()
                    sum += s.toDouble() * s; i += 2
                }
                val level = (sqrt(sum / (FRAME / 2)) / 32768.0).toFloat()
                floor = if (level < floor) floor * 0.8f + level * 0.2f else floor * 1.002f
                floor = floor.coerceIn(0.001f, 0.03f)
                val voice = level > maxOf(0.012f, floor * 3f)
                val now = System.currentTimeMillis()
                val frame = buf.copyOf()

                val s = cur
                if (s != null) {                            // session chal rahi hai: audio pipe mein bhejo
                    s.q.offer(frame)
                    if (voice) lastVoice = now
                    if (now - lastVoice > 900 || now - streamStart > 6500) {   // bolna khatam: pipe band (EOF)
                        s.q.offer(EMPTY); cur = null; waitingResult = true
                        main.postDelayed({ if (waitingResult) sessionEnded(hard = false) }, 4500)
                    }
                    continue
                }
                pre.addLast(frame); while (pre.size > 20) pre.removeFirst()
                if (waitingResult || now < cooldownUntil) { voiced = 0; continue }
                voiced = if (voice) voiced + 1 else 0
                if (voiced >= 4) {                          // bolna shuru: session kholo
                    voiced = 0
                    val pipe = ParcelFileDescriptor.createPipe()
                    val sess = Sess(pipe[0], ParcelFileDescriptor.AutoCloseOutputStream(pipe[1]))
                    pre.forEach { sess.q.offer(it) }; pre.clear()
                    startWriter(sess)
                    lastVoice = now; streamStart = now
                    cur = sess
                    main.post { beginRecognition(sess) }
                }
            }
        } catch (_: InterruptedException) {
        } catch (e: Exception) {
            Log.e(TAG, "mic loop: ${e.message}")
        } finally {
            try { rec?.stop() } catch (_: Exception) {}
            try { rec?.release() } catch (_: Exception) {}
            cur?.let { it.q.offer(EMPTY) }; cur = null
        }
    }

    private fun startWriter(s: Sess) {
        Thread({
            try {
                while (true) {
                    val b = s.q.take()
                    if (b.isEmpty()) break
                    s.out.write(b)
                }
            } catch (_: Exception) { s.dead = true }
            finally { try { s.out.close() } catch (_: Exception) {} }
        }, "siya-wake-pipe").also { it.isDaemon = true; it.start() }
    }

    // ── recognizer (main thread) ──────────────────────────────
    private fun createRecognizer(): SpeechRecognizer? = try {
        if (Build.VERSION.SDK_INT >= 33 && SpeechRecognizer.isOnDeviceRecognitionAvailable(ctx)) SpeechRecognizer.createOnDeviceSpeechRecognizer(ctx)
        else SpeechRecognizer.createSpeechRecognizer(ctx)
    } catch (_: Exception) { null }

    private fun beginRecognition(s: Sess) {
        if (!running) { closeSess(s); return }
        try {
            if (recognizer == null) recognizer = createRecognizer()
            val r = recognizer ?: run { markUnsupported(); return }
            r.setRecognitionListener(listener)
            live = s
            val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-IN")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, ctx.packageName)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, s.read)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, RATE)
            }
            mute(true)
            main.postDelayed({ mute(false) }, 1400)       // sirf start ki beep ke liye, phir awaaz wapas
            r.startListening(i)
        } catch (e: Exception) {
            Log.e(TAG, "begin: ${e.message}")
            sessionEnded(hard = true)
        }
    }

    private fun matches(text: String): Boolean {
        val n = text.lowercase().replace(Regex("[^\\p{L}\\p{M}\\s]"), " ").replace(Regex("\\s+"), " ").trim()
        return pattern.containsMatchIn(n)
    }

    private fun check(b: Bundle?): Boolean =
        b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.any(::matches) == true

    private fun woke() {
        running = false
        main.removeCallbacksAndMessages(null)
        micThread?.interrupt(); micThread = null
        teardown()
        onWake()
    }

    private fun sessionEnded(hard: Boolean) {
        waitingResult = false
        cooldownUntil = System.currentTimeMillis() + 400
        cur?.let { it.q.offer(EMPTY) }; cur = null
        try { recognizer?.cancel() } catch (_: Exception) {}
        live?.let { closeSess(it) }; live = null
        if (hard) {
            hardFails++
            if (hardFails >= 3 && !everWorked) markUnsupported()
        }
    }

    private fun closeSess(s: Sess) {
        try { s.out.close() } catch (_: Exception) {}
        try { s.read.close() } catch (_: Exception) {}
    }

    private fun markUnsupported() {
        Log.w(TAG, "recognizer pipe audio support nahi karta; purane listener par ja rahe hain")
        running = false
        micThread?.interrupt(); micThread = null
        teardown()
        onUnsupported()
    }

    private fun teardown() {
        waitingResult = false
        cur?.let { it.q.offer(EMPTY) }; cur = null
        live?.let { closeSess(it) }; live = null
        try { recognizer?.cancel() } catch (_: Exception) {}
        try { recognizer?.destroy() } catch (_: Exception) {}
        recognizer = null
        mute(false)
    }

    private fun mute(on: Boolean) {
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
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() { everWorked = true }
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
        override fun onPartialResults(partialResults: Bundle?) { if (running && check(partialResults)) woke() }
        override fun onResults(results: Bundle?) {
            if (!running) return
            everWorked = true; hardFails = 0
            if (check(results)) woke() else sessionEnded(hard = false)
        }
        override fun onError(error: Int) {
            if (!running) return
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> { everWorked = true; sessionEnded(hard = false) }
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> { try { recognizer?.destroy() } catch (_: Exception) {}; recognizer = null; sessionEnded(hard = false) }
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> { running = false; teardown() }
                else -> sessionEnded(hard = true)
            }
        }
    }
}
