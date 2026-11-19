package com.siya.ai.audio

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Real-Time Audio & Emotion Detection Pipeline.
 *
 * Implements a 2-Tier Gatekeeper Cascade:
 * Tier 1: 24/7 Silero VAD v5 runs continuously on 512-sample (32ms) frames with near-zero CPU/battery impact.
 * Tier 2: When speech, deep sigh, or emotional vocalization is detected by Tier 1,
 *         AST Audio Classifier and Emotion2Vec Plus are triggered to extract acoustic events
 *         (sigh, laughter, crying, gasp) and emotional state (weary, sad, angry, happy, calm).
 */
class AudioEmotionPipeline private constructor(private val context: Context) {

    companion object {
        private const val TAG_DETECTION = "SiyaAudioDetection"
        private const val TAG_EMOTION = "SiyaAudioEmotion"

        private const val VAD_THRESHOLD = 0.40f
        private const val INFERENCE_COOLDOWN_MS = 1500L // 1.5 seconds cooldown
        private const val BUFFER_SIZE = 48000           // 3 seconds @ 16kHz
        private const val CHUNK_SIZE = 512              // 32ms @ 16kHz

        @Volatile
        private var instance: AudioEmotionPipeline? = null

        fun getInstance(ctx: Context): AudioEmotionPipeline {
            return instance ?: synchronized(this) {
                instance ?: AudioEmotionPipeline(ctx.applicationContext).also { instance = it }
            }
        }
    }

    data class DetectionResult(
        val vadProbability: Float,
        val mood: String,
        val moodConfidence: Float,
        val acousticEvent: String?,
        val eventConfidence: Float,
        val timestamp: Long = System.currentTimeMillis()
    )

    private val isRunning = AtomicBoolean(false)
    private var vadDetector: SileroVadDetector? = null
    private var emotionDetector: Emotion2VecDetector? = null
    private var astClassifier: AstAudioClassifier? = null

    // Rolling circular buffer of 16kHz float samples
    private val ringBuffer = FloatArray(BUFFER_SIZE)
    private var ringPos = 0
    private var totalSamplesAdded = 0L

    // Frame buffer for Silero VAD (512 samples)
    private val vadFrame = FloatArray(CHUNK_SIZE)
    private var vadFramePos = 0

    // Background processing worker thread
    private var workerThread: HandlerThread? = null
    private var workerHandler: Handler? = null

    private var lastInferenceTime = 0L
    private var lastReportedMood = ""
    private var lastReportedEvent = ""

    private var detectionListener: ((DetectionResult) -> Unit)? = null

    fun setListener(listener: ((DetectionResult) -> Unit)?) {
        this.detectionListener = listener
    }

    @Synchronized
    fun start() {
        if (isRunning.get()) return
        Log.i(TAG_DETECTION, "Starting Audio & Emotion Pipeline (Gatekeeper Cascade)...")

        workerThread = HandlerThread("siya-audio-pipeline").apply { start() }
        workerHandler = Handler(workerThread!!.looper)

        workerHandler?.post {
            try {
                vadDetector = SileroVadDetector(context)
                emotionDetector = Emotion2VecDetector(context)
                astClassifier = AstAudioClassifier(context)
                Log.i(TAG_DETECTION, "All 3 ONNX models loaded successfully into AudioEmotionPipeline.")
            } catch (e: Exception) {
                Log.e(TAG_DETECTION, "Error initializing ONNX models in pipeline: ${e.message}", e)
            }
        }

        ringPos = 0
        totalSamplesAdded = 0L
        vadFramePos = 0
        lastInferenceTime = 0L
        isRunning.set(true)
    }

    /**
     * Feed incoming 16kHz 16-bit PCM byte audio from microphone.
     */
    fun feedPcm(bytes: ByteArray, length: Int) {
        if (!isRunning.get() || length <= 0) return

        val sampleCount = length / 2
        val floatSamples = FloatArray(sampleCount)
        var i = 0
        var s = 0
        while (i + 1 < length && s < sampleCount) {
            val pcm16 = ((bytes[i + 1].toInt() shl 8) or (bytes[i].toInt() and 0xFF)).toShort()
            floatSamples[s] = pcm16 / 32768.0f
            i += 2
            s++
        }

        feedFloat(floatSamples, sampleCount)
    }

    /**
     * Process normalized float samples [-1.0, 1.0] at 16kHz.
     */
    fun feedFloat(samples: FloatArray, count: Int) {
        if (!isRunning.get() || count <= 0) return

        workerHandler?.post {
            for (idx in 0 until count) {
                val sample = samples[idx]

                // Add to 3-second rolling ring buffer
                ringBuffer[ringPos] = sample
                ringPos = (ringPos + 1) % BUFFER_SIZE
                totalSamplesAdded++

                // Fill VAD chunk
                vadFrame[vadFramePos] = sample
                vadFramePos++

                if (vadFramePos >= CHUNK_SIZE) {
                    processVadFrame()
                    vadFramePos = 0
                }
            }
        }
    }

    /**
     * Tier 1: Silero VAD gatekeeper processing.
     */
    private fun processVadFrame() {
        val vad = vadDetector ?: return
        val vadProb = vad.process(vadFrame)
        val now = System.currentTimeMillis()

        if (vadProb >= VAD_THRESHOLD) {
            Log.d(TAG_DETECTION, "[Silero VAD] Voice/Breathing Activity Detected: prob=${"%.3f".format(vadProb)} (Gatekeeper OPEN)")

            // Check cooldown before running Tier 2 models
            if (now - lastInferenceTime >= INFERENCE_COOLDOWN_MS && totalSamplesAdded >= BUFFER_SIZE / 2) {
                lastInferenceTime = now
                runTier2Inference(vadProb)
            }
        }
    }

    /**
     * Tier 2: AST Audio Classifier & Emotion2Vec Inference.
     */
    private fun runTier2Inference(vadProb: Float) {
        // Snapshot last 3 seconds from ring buffer in chronological order
        val audioSnapshot = FloatArray(BUFFER_SIZE)
        val startPos = ringPos
        val len1 = BUFFER_SIZE - startPos
        System.arraycopy(ringBuffer, startPos, audioSnapshot, 0, len1)
        if (startPos > 0) {
            System.arraycopy(ringBuffer, 0, audioSnapshot, len1, startPos)
        }

        // Run Emotion2Vec
        val emotionRes = emotionDetector?.detect(audioSnapshot)
        val mood = emotionRes?.topEmotion ?: "neutral"
        val moodConf = emotionRes?.confidence ?: 0f

        // Run AST Classifier
        val astRes = astClassifier?.classify(audioSnapshot)
        val topEvent = astRes?.topEvent ?: "ambient"
        val eventConf = astRes?.confidence ?: 0f

        // Determine critical acoustic event
        var significantEvent: String? = null
        if (astRes?.isSighOrBreathing == true) {
            significantEvent = "Deep Sigh / Breathing"
        } else if (astRes?.isLaughter == true) {
            significantEvent = "Laughter"
        } else if (astRes?.isCrying == true) {
            significantEvent = "Crying / Sobbing"
        } else if (eventConf >= 0.25f && !topEvent.equals("Speech", ignoreCase = true) && !topEvent.equals("Silence", ignoreCase = true)) {
            significantEvent = topEvent
        }

        // Live Debug Logging
        Log.i(TAG_EMOTION, "================ [Siya Real-Time Audio Context] ================")
        Log.i(TAG_EMOTION, ">> Silero VAD Prob : ${"%.3f".format(vadProb)}")
        Log.i(TAG_EMOTION, ">> Speaker Mood    : $mood (${"%.2f".format(moodConf * 100)}%)")
        Log.i(TAG_EMOTION, ">> Acoustic Event  : ${significantEvent ?: "Normal Voice"} (${"%.2f".format(eventConf * 100)}%)")
        Log.i(TAG_EMOTION, "================================================================")

        val result = DetectionResult(
            vadProbability = vadProb,
            mood = mood,
            moodConfidence = moodConf,
            acousticEvent = significantEvent,
            eventConfidence = eventConf
        )

        // Avoid re-emitting identical consecutive states
        if (mood != lastReportedMood || significantEvent != lastReportedEvent) {
            lastReportedMood = mood
            lastReportedEvent = significantEvent ?: ""
            Handler(Looper.getMainLooper()).post {
                detectionListener?.invoke(result)
            }
        }
    }

    @Synchronized
    fun stop() {
        if (!isRunning.get()) return
        Log.i(TAG_DETECTION, "Stopping AudioEmotionPipeline...")
        isRunning.set(false)

        workerHandler?.post {
            try {
                vadDetector?.release()
                emotionDetector?.release()
                astClassifier?.release()
                vadDetector = null
                emotionDetector = null
                astClassifier = null
            } catch (e: Exception) {
                Log.e(TAG_DETECTION, "Error closing detectors: ${e.message}")
            }
        }

        workerThread?.quitSafely()
        workerThread = null
        workerHandler = null
    }
}
