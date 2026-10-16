package com.siya.ai.service

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Process
import android.util.Log
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File

/** Free on-device "Hey Siya" detector using a filesystem-backed Vosk model. */
class VoskWakeEngine(private val ctx: Context, @Suppress("UNUSED_PARAMETER") onWake: () -> Unit) : WakeEngine {
    companion object {
        private const val TAG = "SIYA_VOSK_WAKE"
        private const val RATE = 16_000
        private const val FRAME_SAMPLES = 4_000
        private const val GRAMMAR = """["hey siya", "siya", "[unk]"]"""
        @Volatile private var sharedModel: Model? = null
        @Volatile private var modelPath: String? = null

        fun available(ctx: Context): Boolean = try {
            ctx.assets.list("model/vosk-model-small-en-in-0.4")?.isNotEmpty() == true
        } catch (_: Exception) { false }
    }

    @Volatile private var running = false
    override val isRunning: Boolean get() = running
    private var worker: Thread? = null

    override fun start() {
        if (running) return
        running = true
        worker = Thread({ listenLoop() }, "siya-vosk-wake").also {
            it.isDaemon = true
            it.start()
        }
    }

    override fun stop() {
        running = false
        worker?.interrupt()
        worker = null
    }

    @SuppressLint("MissingPermission")
    private fun listenLoop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
        var recorder: AudioRecord? = null
        var recognizer: Recognizer? = null
        try {
            val path = FileUtils.unpackAssetDirectory(
                ctx,
                "model/vosk-model-small-en-in-0.4",
                File(ctx.filesDir, "vosk-model")
            ).absolutePath
            val model = synchronized(VoskWakeEngine::class.java) {
                if (sharedModel == null || modelPath != path) {
                    try { sharedModel?.close() } catch (_: Exception) {}
                    sharedModel = Model(path)
                    modelPath = path
                }
                sharedModel!!
            }
            recognizer = Recognizer(model, RATE.toFloat(), GRAMMAR)
            recognizer.setWords(true)

            val minBytes = AudioRecord.getMinBufferSize(
                RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            require(minBytes > 0) { "AudioRecord buffer size unavailable: $minBytes" }
            recorder = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minBytes, FRAME_SAMPLES * 2 * 2)
            )
            check(recorder.state == AudioRecord.STATE_INITIALIZED) { "AudioRecord initialization failed" }
            recorder.startRecording()
            Log.i(TAG, "Vosk model loaded from $path; listening at 16 kHz mono PCM")

            val buffer = ShortArray(FRAME_SAMPLES)
            while (running && !Thread.currentThread().isInterrupted) {
                val count = recorder.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                if (count < 0) {
                    Log.w(TAG, "AudioRecord read failed: $count")
                    break
                }
                if (count == 0) continue
                if (recognizer.acceptWaveForm(buffer, count) && isConfidentWake(recognizer.result)) {
                    Log.i(TAG, "Wake phrase accepted")
                    running = false
                    ctx.sendBroadcast(
                        Intent(SiyaService.ACTION_WAKE_DETECTED).setPackage(ctx.packageName)
                    )
                    break
                }
            }
        } catch (e: InterruptedException) {
            // Normal stop path.
        } catch (e: Exception) {
            Log.e(TAG, "Vosk wake listener stopped safely: ${e.message}", e)
        } finally {
            running = false
            try { recorder?.stop() } catch (_: Exception) {}
            try { recorder?.release() } catch (_: Exception) {}
            try { recognizer?.close() } catch (_: Exception) {}
        }
    }

    private fun isConfidentWake(json: String): Boolean {
        return try {
            val root = JSONObject(json)
            val text = root.optString("text").lowercase().trim()
            if (text != "hey siya" && text != "siya") {
                false
            } else {
                val words = root.optJSONArray("result")
                var siyaConfidence = 0.0
                var sawSiya = false
                if (words != null) {
                    for (i in 0 until words.length()) {
                        val word = words.optJSONObject(i) ?: continue
                        if (word.optString("word").equals("siya", ignoreCase = true)) {
                            sawSiya = true
                            siyaConfidence = word.optDouble("conf", 0.0)
                        }
                    }
                }
                sawSiya && siyaConfidence >= 0.55
            }
        } catch (_: Exception) { false }
    }
}
