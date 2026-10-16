package com.siya.ai.service

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Process
import android.util.Log
import ai.picovoice.porcupine.Porcupine
import java.io.File

/**
 * Offline, kam-power "Hey Siya" detector (Picovoice Porcupine).
 *  - Ek hi AudioRecord (16 kHz, mono, 16-bit) lagatar chalta hai: mic baar-baar on/off nahi hota, koi click / pop nahi.
 *  - Sirf chhote frames Porcupine ko jaate hain: CPU bahut kam; koi STT / LLM nahi chalta.
 *  - Wake word milte hi mic chhod deta hai (stop) aur onWake() bulata hai; Siya session ke baad service dobara start() karti hai.
 * Zaroori: assets mein "hey_siya.ppn" + Settings mein Picovoice AccessKey.
 */
class PorcupineWakeEngine(private val ctx: Context, private val onWake: () -> Unit) : WakeEngine {
    @Volatile private var running = false
    private var thread: Thread? = null

    override val isRunning get() = running

    companion object {
        private const val TAG = "SIYA_PPN"
        const val ASSET = "hey_siya.ppn"

        fun accessKey(ctx: Context) = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getString("picovoice_key", "").orEmpty().trim()

        fun hasModel(ctx: Context) = try { ctx.assets.open(ASSET).close(); true } catch (_: Exception) { false }

        /** Key + .ppn dono ho to hi Porcupine use hoga, warna purana SpeechRecognizer wala listener. */
        fun available(ctx: Context) = accessKey(ctx).isNotEmpty() && hasModel(ctx)

        private fun modelFile(ctx: Context): File {
            val f = File(ctx.filesDir, ASSET)
            if (!f.exists() || f.length() == 0L) ctx.assets.open(ASSET).use { i -> f.outputStream().use { o -> i.copyTo(o) } }
            return f
        }
    }

    @SuppressLint("MissingPermission")
    override fun start() {
        if (running) return
        running = true
        thread = Thread({ loop() }, "siya-porcupine").also { it.isDaemon = true; it.start() }
    }

    override fun stop() {
        running = false
        thread?.interrupt()
        thread = null
    }

    @SuppressLint("MissingPermission")
    private fun loop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        var porcupine: Porcupine? = null
        var rec: AudioRecord? = null
        var backoff = 1000L
        try {
            porcupine = Porcupine.Builder()
                .setAccessKey(accessKey(ctx))
                .setKeywordPath(modelFile(ctx).absolutePath)
                .setSensitivity(0.65f)
                .build(ctx)
            val frame = porcupine.frameLength
            val pcm = ShortArray(frame)
            while (running) {
                if (rec == null) {
                    val min = AudioRecord.getMinBufferSize(porcupine.sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                    val r = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, porcupine.sampleRate,
                        AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, frame * 2 * 4))
                    if (r.state != AudioRecord.STATE_INITIALIZED) {
                        r.release()
                        Log.w(TAG, "AudioRecord init fail, retry in ${backoff}ms")
                        Thread.sleep(backoff); backoff = (backoff * 2).coerceAtMost(8000L); continue
                    }
                    r.startRecording()
                    rec = r; backoff = 1000L
                }
                val n = rec.read(pcm, 0, frame)
                if (n < 0) {   // mic kisi aur ne le liya / error: chupchap chhodo aur baad mein dobara lo
                    try { rec.stop() } catch (_: Exception) {}; rec.release(); rec = null
                    Thread.sleep(backoff); backoff = (backoff * 2).coerceAtMost(8000L)
                    continue
                }
                if (n < frame) continue
                if (porcupine.process(pcm) >= 0) {
                    running = false
                    try { rec.stop() } catch (_: Exception) {}; rec.release(); rec = null
                    onWake()
                    break
                }
            }
        } catch (e: InterruptedException) {
            // stop() ne roka
        } catch (e: Exception) {
            Log.e(TAG, "porcupine: ${e.message}")
        } finally {
            try { rec?.stop() } catch (_: Exception) {}
            try { rec?.release() } catch (_: Exception) {}
            try { porcupine?.delete() } catch (_: Exception) {}
            running = false
        }
    }
}
