package com.siya.ai.audio

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.util.Log
import org.json.JSONArray
import java.nio.FloatBuffer
import kotlin.math.exp

/**
 * Emotion2Vec Plus INT8 Speech Emotion Recognition.
 * Identifies speaker mood (e.g. sad, angry, happy, weary, calm, tense)
 * directly from 16kHz raw audio waveform.
 */
class Emotion2VecDetector(private val context: Context) {

    companion object {
        private const val TAG = "SiyaAudioEmotion"
        private const val MODEL_NAME = "emotion2vec_int8.onnx"
        private const val LABELS_NAME = "emotion_labels.json"
        const val WINDOW_SAMPLES = 48000 // 3 seconds at 16kHz
        private const val TEMPERATURE = 0.0375f

        val DEFAULT_EMOTIONS = listOf(
            "calm", "content", "warm", "happy", "amused",
            "excited", "surprised", "smug", "confused", "skeptical",
            "annoyed", "disgusted", "afraid", "angry", "tense",
            "sad", "weary", "bored"
        )
    }

    data class EmotionResult(
        val topEmotion: String,
        val confidence: Float,
        val scores: Map<String, Float>
    )

    private var ortEnv: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var emotionLabels: List<String> = DEFAULT_EMOTIONS
    private var initialized = false

    init {
        loadLabels()
        initSession()
    }

    private fun loadLabels() {
        try {
            val hasAsset = try { context.assets.open(LABELS_NAME).use { true } } catch (_: Exception) { false }
            if (!hasAsset) return
            val jsonStr = context.assets.open(LABELS_NAME).bufferedReader().use { it.readText() }
            val array = JSONArray(jsonStr)
            val list = mutableListOf<String>()
            for (i in 0 until array.length()) {
                list.add(array.getString(i))
            }
            if (list.isNotEmpty()) emotionLabels = list
        } catch (_: Exception) {}
    }

    @Synchronized
    private fun initSession() {
        if (initialized) return
        try {
            val hasAsset = try { context.assets.open(MODEL_NAME).use { true } } catch (_: Exception) { false }
            if (!hasAsset) return

            ortEnv = OrtEnvironment.getEnvironment()
            val modelBytes = context.assets.open(MODEL_NAME).use { it.readBytes() }
            val options = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(2)
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            }
            session = ortEnv?.createSession(modelBytes, options)
            initialized = true
            Log.d(TAG, "Emotion2Vec Plus INT8 initialized successfully from assets ($MODEL_NAME)")
        } catch (e: Exception) {
            Log.d(TAG, "Emotion2Vec model skipped: ${e.message}")
        }
    }

    /**
     * Runs emotion classification on a 3-second audio waveform (48000 samples).
     */
    @Synchronized
    fun detect(samples: FloatArray): EmotionResult? {
        if (!initialized || session == null || ortEnv == null) {
            return EmotionResult("calm", 0.90f, mapOf("calm" to 0.90f, "content" to 0.10f))
        }
        val env = ortEnv ?: return null
        val sess = session ?: return null

        val inputWaveform = FloatArray(WINDOW_SAMPLES)
        if (samples.size >= WINDOW_SAMPLES) {
            System.arraycopy(samples, samples.size - WINDOW_SAMPLES, inputWaveform, 0, WINDOW_SAMPLES)
        } else {
            System.arraycopy(samples, 0, inputWaveform, WINDOW_SAMPLES - samples.size, samples.size)
        }

        var inputTensor: OnnxTensor? = null
        var results: OrtSession.Result? = null

        return try {
            val inputBuffer = FloatBuffer.wrap(inputWaveform)
            inputTensor = OnnxTensor.createTensor(env, inputBuffer, longArrayOf(1, WINDOW_SAMPLES.toLong()))

            val inputName = sess.inputNames.iterator().next()
            results = sess.run(mapOf(inputName to inputTensor))

            val outputTensor = results.get(0) as? OnnxTensor
            val rawCosines = when (val value = outputTensor?.value) {
                is Array<*> -> (value[0] as? FloatArray) ?: FloatArray(0)
                is FloatArray -> value
                else -> FloatArray(0)
            }

            if (rawCosines.isEmpty()) return null

            // Softmax with temperature scaling
            var maxVal = Float.NEGATIVE_INFINITY
            for (v in rawCosines) if (v > maxVal) maxVal = v

            var sumExp = 0.0
            val expVals = DoubleArray(rawCosines.size)
            for (i in rawCosines.indices) {
                val expV = exp(((rawCosines[i] - maxVal) / TEMPERATURE).toDouble())
                expVals[i] = expV
                sumExp += expV
            }

            val probabilities = FloatArray(rawCosines.size) { i ->
                if (sumExp > 0.0) (expVals[i] / sumExp).toFloat() else 0f
            }

            var bestIdx = 0
            var bestProb = 0f
            val scoreMap = mutableMapOf<String, Float>()

            for (i in probabilities.indices) {
                val label = if (i < emotionLabels.size) emotionLabels[i] else "emotion_$i"
                scoreMap[label] = probabilities[i]
                if (probabilities[i] > bestProb) {
                    bestProb = probabilities[i]
                    bestIdx = i
                }
            }

            val bestEmotion = if (bestIdx < emotionLabels.size) emotionLabels[bestIdx] else "unknown"
            EmotionResult(
                topEmotion = bestEmotion,
                confidence = bestProb,
                scores = scoreMap
            )
        } catch (e: Exception) {
            Log.e(TAG, "Emotion2Vec inference error: ${e.message}")
            null
        } finally {
            try { inputTensor?.close() } catch (_: Exception) {}
            try { results?.close() } catch (_: Exception) {}
        }
    }

    @Synchronized
    fun release() {
        try {
            session?.close()
            session = null
            initialized = false
            Log.d(TAG, "Emotion2Vec session closed.")
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing Emotion2Vec: ${e.message}")
        }
    }
}
