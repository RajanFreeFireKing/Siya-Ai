package com.siya.ai.audio

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import com.siya.ai.core.EmotionalCoreEngine
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Real-Time Audio, Speaker Verification & Emotion Pipeline.
 *
 * Implements:
 * 1. Tier 1: Silero VAD v5 (0.65f threshold) on 512-sample (32ms) frames with near-zero battery.
 * 2. Speaker Verification: WeSpeaker INT8 (<0.2s) verifies [Speaker: BOSS (Verified Malik)] vs [Speaker: UNKNOWN STRANGER].
 * 3. Lazy AST Classifier: 0% CPU on normal ambient noise. Triggers AST ONLY on:
 *    (a) Sudden loud decibel spike (>70 dB SPL)
 *    (b) User explicitly asking ("Peeche kaisi aawaz aa rahi hai?")
 * 4. Thermal Guard: If phone temp > 39°C or PowerManager thermal status severe, pauses heavy AST/Emotion inference.
 * 5. 5-Second Cooldown & 2-thread limit for zero lag and cold, smooth operation.
 */
class AudioEmotionPipeline private constructor(private val context: Context) {

    companion object {
        private const val TAG_DETECTION = "SiyaAudioDetection"
        private const val TAG_EMOTION = "SiyaAudioEmotion"

        private const val VAD_THRESHOLD = 0.65f
        private const val INFERENCE_COOLDOWN_MS = 5000L // 5.0 seconds cooldown
        private const val BUFFER_SIZE = 48000           // 3 seconds @ 16kHz
        private const val CHUNK_SIZE = 512              // 32ms @ 16kHz
        private const val LOUD_DECIBEL_THRESHOLD = 70.0f // > 70 dB SPL spike

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
        val speakerTag: String = "",
        val timestamp: Long = System.currentTimeMillis()
    )

    private val isRunning = AtomicBoolean(false)
    private var vadDetector: SileroVadDetector? = null
    private var emotionDetector: Emotion2VecDetector? = null
    private var astClassifier: AstAudioClassifier? = null
    private var speakerEngine: SpeakerRecognitionEngine? = null

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
    private var lastAstTime = 0L
    private var lastReportedMood = ""
    private var lastReportedEvent = ""
    private var lastReportedSpeaker = ""

    private var detectionListener: ((DetectionResult) -> Unit)? = null

    fun setListener(listener: ((DetectionResult) -> Unit)?) {
        this.detectionListener = listener
    }

    @Synchronized
    fun start() {
        if (isRunning.get()) return
        Log.i(TAG_DETECTION, "Starting Audio & Emotion Pipeline (Gatekeeper Cascade + Thermal Guard)...")

        workerThread = HandlerThread("siya-audio-pipeline").apply { start() }
        workerHandler = Handler(workerThread!!.looper)

        workerHandler?.post {
            try {
                vadDetector = SileroVadDetector(context)
                emotionDetector = Emotion2VecDetector(context)
                astClassifier = AstAudioClassifier(context)
                speakerEngine = SpeakerRecognitionEngine.getInstance(context)
                Log.i(TAG_DETECTION, "All Audio ONNX models loaded successfully into AudioEmotionPipeline.")
            } catch (e: Exception) {
                Log.e(TAG_DETECTION, "Error initializing ONNX models in pipeline: ${e.message}", e)
            }
        }

        ringPos = 0
        totalSamplesAdded = 0L
        vadFramePos = 0
        lastInferenceTime = 0L
        lastAstTime = 0L
        isRunning.set(true)
    }

    /**
     * Thermal Guard: Checks battery temperature and thermal throttling status.
     * Pauses heavy AST and Emotion inference if phone exceeds 39°C.
     */
    fun isThermalGuardActive(): Boolean {
        try {
            val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val intent = context.registerReceiver(null, filter)
            val tempTenths = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
            val tempCelsius = tempTenths / 10.0f
            if (tempCelsius >= 39.0f) {
                Log.w(TAG_DETECTION, "Thermal Guard Active: Phone temp ${tempCelsius}°C >= 39°C. Pausing heavy inference.")
                return true
            }
        } catch (_: Exception) {}

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                val thermalStatus = powerManager?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE
                if (thermalStatus >= PowerManager.THERMAL_STATUS_SEVERE) {
                    Log.w(TAG_DETECTION, "Thermal Guard Active: System thermal status severe ($thermalStatus).")
                    return true
                }
            } catch (_: Exception) {}
        }
        return false
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
     * Tier 1: Silero VAD gatekeeper processing (0.65 threshold) + Decibel spike detector.
     */
    private fun processVadFrame() {
        val vad = vadDetector ?: return
        val vadProb = vad.process(vadFrame)
        val now = System.currentTimeMillis()

        // Calculate RMS and Decibels SPL approximation
        var sumSquares = 0.0
        for (sample in vadFrame) {
            sumSquares += sample * sample
        }
        val rms = sqrt(sumSquares / CHUNK_SIZE).toFloat()
        val decibels = (20.0 * log10(maxOf(rms, 0.00001f)) + 90.0).toFloat().coerceIn(20f, 120f)

        // Condition A for AST: Sudden high decibel spike (>70 dB)
        if (decibels >= LOUD_DECIBEL_THRESHOLD && (now - lastAstTime >= INFERENCE_COOLDOWN_MS) && !isThermalGuardActive()) {
            lastAstTime = now
            Log.w(TAG_DETECTION, "[Decibel Spike] Loud acoustic spike detected: ${decibels.toInt()} dB SPL!")
            triggerAstSpikeInference(decibels)
        }

        // Voice Activity Gatekeeper
        if (vadProb >= VAD_THRESHOLD) {
            Log.d(TAG_DETECTION, "[Silero VAD] Voice Detected: prob=${"%.3f".format(vadProb)} (Gatekeeper OPEN)")

            // Check 5-second cooldown and Thermal Guard before heavy emotion inference
            if (now - lastInferenceTime >= INFERENCE_COOLDOWN_MS && totalSamplesAdded >= BUFFER_SIZE / 2) {
                if (isThermalGuardActive()) {
                    Log.i(TAG_DETECTION, "Thermal Guard active; skipping heavy inference to keep phone cool.")
                    return
                }
                lastInferenceTime = now
                runTier2Inference(vadProb)
            }
        }
    }

    /**
     * Tier 2: Speaker Verification & Emotion2Vec Inference.
     */
    private fun runTier2Inference(vadProb: Float) {
        val audioSnapshot = FloatArray(BUFFER_SIZE)
        val startPos = ringPos
        val len1 = BUFFER_SIZE - startPos
        System.arraycopy(ringBuffer, startPos, audioSnapshot, 0, len1)
        if (startPos > 0) {
            System.arraycopy(ringBuffer, 0, audioSnapshot, len1, startPos)
        }

        // 1. Speaker Verification (Boss vs Stranger) in < 0.2s
        val speakerVerif = speakerEngine?.verifySpeaker(audioSnapshot)
        val speakerTag = speakerVerif?.identity?.tag ?: ""

        // 2. Emotion2Vec
        val emotionRes = emotionDetector?.detect(audioSnapshot)
        val mood = emotionRes?.topEmotion ?: "neutral"
        val moodConf = emotionRes?.confidence ?: 0f

        // Feed user mood to Autonomous Living Emotional Core
        EmotionalCoreEngine.getInstance(context).onUserEmotionDetected(mood, moodConf)

        Log.i(TAG_EMOTION, "================ [Siya Real-Time Audio Context] ================")
        Log.i(TAG_EMOTION, ">> Silero VAD Prob : ${"%.3f".format(vadProb)}")
        Log.i(TAG_EMOTION, ">> Speaker ID      : ${speakerVerif?.identity?.label} (${"%.1f".format((speakerVerif?.similarity ?: 0f) * 100)}%)")
        Log.i(TAG_EMOTION, ">> Speaker Mood    : $mood (${"%.2f".format(moodConf * 100)}%)")
        Log.i(TAG_EMOTION, "================================================================")

        val result = DetectionResult(
            vadProbability = vadProb,
            mood = mood,
            moodConfidence = moodConf,
            acousticEvent = null,
            eventConfidence = 0f,
            speakerTag = speakerTag
        )

        if (mood != lastReportedMood || speakerTag != lastReportedSpeaker) {
            lastReportedMood = mood
            lastReportedSpeaker = speakerTag
            Handler(Looper.getMainLooper()).post {
                detectionListener?.invoke(result)
            }
        }
    }

    /**
     * Triggers AST inference on sudden loud noise spikes (>70 dB).
     */
    private fun triggerAstSpikeInference(decibels: Float) {
        val audioSnapshot = FloatArray(BUFFER_SIZE)
        val startPos = ringPos
        val len1 = BUFFER_SIZE - startPos
        System.arraycopy(ringBuffer, startPos, audioSnapshot, 0, len1)
        if (startPos > 0) {
            System.arraycopy(ringBuffer, 0, audioSnapshot, len1, startPos)
        }

        val astRes = astClassifier?.classify(audioSnapshot)
        val topEvent = astRes?.topEvent ?: "Loud noise"
        val conf = astRes?.confidence ?: 0f

        Log.i(TAG_DETECTION, "[AST Noise Spike] Event: $topEvent (${"%.1f".format(conf * 100)}%) at ${decibels.toInt()} dB")

        val alertTag = "Achanak tez aawaz hui ($topEvent, ~${decibels.toInt()} dB)"
        val result = DetectionResult(
            vadProbability = 0f,
            mood = lastReportedMood,
            moodConfidence = 0f,
            acousticEvent = alertTag,
            eventConfidence = conf,
            speakerTag = lastReportedSpeaker
        )
        Handler(Looper.getMainLooper()).post {
            detectionListener?.invoke(result)
        }
    }

    /**
     * Condition B: On-demand AST background sound check (e.g. user asks "Peeche kaisi aawaz aa rahi hai?").
     */
    fun checkAcousticEnvironment(callback: (String) -> Unit) {
        workerHandler?.post {
            val audioSnapshot = FloatArray(BUFFER_SIZE)
            val startPos = ringPos
            val len1 = BUFFER_SIZE - startPos
            System.arraycopy(ringBuffer, startPos, audioSnapshot, 0, len1)
            if (startPos > 0) {
                System.arraycopy(ringBuffer, 0, audioSnapshot, len1, startPos)
            }

            val astRes = astClassifier?.classify(audioSnapshot)
            val topEvent = astRes?.topEvent ?: "ambient silence"
            val conf = astRes?.confidence ?: 0f

            val details = when {
                astRes?.isSighOrBreathing == true -> "Gehri saans ya halki saans lene ki aawaz"
                astRes?.isLaughter == true -> "Hansi ya khilkhilane ki aawaz"
                astRes?.isCrying == true -> "Rone ya siskariyan lene ki aawaz"
                conf >= 0.20f && !topEvent.equals("Silence", ignoreCase = true) -> topEvent
                else -> "Aas-paas shaant mahaul hai, koi ajeeb shor nahi hai."
            }
            Handler(Looper.getMainLooper()).post {
                callback(details)
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
                speakerEngine?.release()
                vadDetector = null
                emotionDetector = null
                astClassifier = null
                speakerEngine = null
            } catch (e: Exception) {
                Log.e(TAG_DETECTION, "Error closing detectors: ${e.message}")
            }
        }

        workerThread?.quitSafely()
        workerThread = null
        workerHandler = null
    }
}
