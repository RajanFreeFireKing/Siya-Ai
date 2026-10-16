package com.siya.ai.utils

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import java.util.concurrent.LinkedBlockingQueue
import kotlin.math.sqrt

/**
 * Speaker side: Gemini ka 24kHz audio ek hi AudioTrack par gapless chalta hai
 * (writer thread alag hai, isliye awaaz tootti nahi / ghabrati nahi).
 */
class LivePlayer(private val bluetooth: Boolean = false) {
    private val rate = 24000
    private var track: AudioTrack? = null
    private val queue = LinkedBlockingQueue<ByteArray>()
    @Volatile private var running = false
    private var writer: Thread? = null
    @Volatile var lastWriteAt = 0L
        private set

    val isPlaying get() = queue.isNotEmpty() || (System.currentTimeMillis() - lastWriteAt < 350)

    fun start() {
        if (running) return
        val min = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val t = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(if (bluetooth) AudioAttributes.USAGE_VOICE_COMMUNICATION else AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(rate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(maxOf(min * 4, rate / 2 * 2)) // ~0.5s buffer: smooth, no stutter
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track = t
        t.play()
        running = true
        writer = Thread({
            while (running) {
                try {
                    val chunk = queue.take()
                    if (chunk.isEmpty()) continue
                    track?.write(chunk, 0, chunk.size)
                    lastWriteAt = System.currentTimeMillis()
                } catch (_: InterruptedException) { break } catch (_: Exception) {}
            }
        }, "siya-audio-out").also { it.isDaemon = true; it.start() }
    }

    fun play(pcm: ByteArray) { if (running) queue.offer(pcm) }

    /** Barge-in: turant chup. */
    fun flush() {
        queue.clear()
        try { track?.pause(); track?.flush(); track?.play() } catch (_: Exception) {}
        lastWriteAt = 0L
    }

    fun release() {
        running = false
        queue.clear()
        writer?.interrupt(); writer = null
        try { track?.stop() } catch (_: Exception) {}
        try { track?.release() } catch (_: Exception) {}
        track = null
    }
}

/**
 * Mic side: ek hi AudioRecord pura session chalta hai (on/off blink nahi hota).
 * Echo cancel + noise suppress ON.
 */
class MicStreamer(
    private val btDevice: android.media.AudioDeviceInfo? = null,
    private val onChunk: (ByteArray, Int, Float) -> Unit   // pcm, length, level 0..1
) {
    private val rate = 16000
    private var rec: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var running = false
    private val fx = ArrayList<android.media.audiofx.AudioEffect>()

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        if (running) return true
        val min = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (min <= 0) return false
        val r = try {
            AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, rate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min * 2, 4096))
        } catch (_: Exception) { return false }
        if (r.state != AudioRecord.STATE_INITIALIZED) { r.release(); return false }
        if (btDevice != null) try { r.setPreferredDevice(btDevice) } catch (_: Exception) {}
        rec = r
        try { if (AcousticEchoCanceler.isAvailable()) AcousticEchoCanceler.create(r.audioSessionId)?.also { it.enabled = true; fx.add(it) } } catch (_: Exception) {}
        try { if (NoiseSuppressor.isAvailable()) NoiseSuppressor.create(r.audioSessionId)?.also { it.enabled = true; fx.add(it) } } catch (_: Exception) {}
        try { if (AutomaticGainControl.isAvailable()) AutomaticGainControl.create(r.audioSessionId)?.also { it.enabled = true; fx.add(it) } } catch (_: Exception) {}
        r.startRecording()
        running = true
        thread = Thread({
            val buf = ByteArray(1280) // 40 ms
            while (running) {
                val n = try { r.read(buf, 0, buf.size) } catch (_: Exception) { -1 }
                if (n <= 0) continue
                var sum = 0.0
                var i = 0
                while (i + 1 < n) {
                    val s = ((buf[i + 1].toInt() shl 8) or (buf[i].toInt() and 0xFF)).toShort().toInt()
                    sum += s.toDouble() * s
                    i += 2
                }
                val rms = sqrt(sum / (n / 2).coerceAtLeast(1)) / 32768.0
                onChunk(buf, n, rms.toFloat().coerceIn(0f, 1f))
            }
        }, "siya-mic").also { it.isDaemon = true; it.start() }
        return true
    }

    /** Aas-paas ki awaaz (gaana / video) sunne ke liye echo-cancel / noise-suppress / AGC temporarily band. */
    fun setEffects(on: Boolean) {
        fx.forEach { try { it.enabled = on } catch (_: Exception) {} }
    }

    fun stop() {
        running = false
        thread?.interrupt(); thread = null
        fx.forEach { try { it.release() } catch (_: Exception) {} }; fx.clear()
        try { rec?.stop() } catch (_: Exception) {}
        try { rec?.release() } catch (_: Exception) {}
        rec = null
    }
}
