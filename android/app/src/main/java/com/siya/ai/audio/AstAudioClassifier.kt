package com.siya.ai.audio

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.nio.FloatBuffer
import kotlin.math.*

/**
 * AST (Audio Spectrogram Transformer) INT8 Audio Event Classifier.
 * Identifies deep sighs, gasps, breathing, laughter, crying, whispering, and room atmosphere.
 */
class AstAudioClassifier(private val context: Context) {

    companion object {
        private const val TAG = "SiyaAudioDetection"
        private const val MODEL_NAME = "ast_int8.onnx"
        private const val LABELS_NAME = "ast_labels.json"

        const val NUM_MEL_BINS = 128
        const val TARGET_FRAMES = 1024
        const val FFT_SIZE = 512
        const val WINDOW_SIZE = 400   // 25ms @ 16kHz
        const val HOP_SIZE = 160      // 10ms @ 16kHz
        const val SAMPLE_RATE = 16000

        // AST normalization constants (AudioSet mean & std)
        private const val AST_MEAN = -4.2677393f
        private const val AST_STD = 4.5689974f
    }

    data class AstEventResult(
        val topEvent: String,
        val confidence: Float,
        val isSighOrBreathing: Boolean,
        val isLaughter: Boolean,
        val isCrying: Boolean,
        val topEvents: List<Pair<String, Float>>
    )

    private var ortEnv: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var labelMap = HashMap<Int, String>()
    private var initialized = false

    // Precomputed Hanning window
    private val hanningWindow = FloatArray(WINDOW_SIZE) { i ->
        (0.5f * (1f - cos(2.0 * Math.PI * i / (WINDOW_SIZE - 1)))).toFloat()
    }

    // Mel filterbank weights [NUM_MEL_BINS][FFT_SIZE / 2 + 1]
    private val melFilterBank = createMelFilterBank(SAMPLE_RATE, FFT_SIZE, NUM_MEL_BINS, 50f, 7600f)

    init {
        loadLabels()
        initSession()
    }

    private fun loadLabels() {
        try {
            val jsonStr = context.assets.open(LABELS_NAME).bufferedReader().use { it.readText() }
            val obj = JSONObject(jsonStr)
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val id = key.toIntOrNull() ?: continue
                labelMap[id] = obj.getString(key)
            }
            Log.d(TAG, "Loaded ${labelMap.size} AST labels.")
        } catch (e: Exception) {
            Log.w(TAG, "Could not load AST labels: ${e.message}")
        }
    }

    @Synchronized
    private fun initSession() {
        if (initialized) return
        try {
            ortEnv = OrtEnvironment.getEnvironment()
            val modelBytes = context.assets.open(MODEL_NAME).use { it.readBytes() }
            val options = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(2)
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            }
            session = ortEnv?.createSession(modelBytes, options)
            initialized = true
            Log.d(TAG, "AST Audio Classifier initialized successfully from assets ($MODEL_NAME)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load AST model: ${e.message}", e)
        }
    }

    /**
     * Extracts spectrogram features and classifies acoustic events.
     */
    @Synchronized
    fun classify(samples: FloatArray): AstEventResult? {
        if (!initialized || session == null || ortEnv == null) return null
        val env = ortEnv ?: return null
        val sess = session ?: return null

        val features = computeSpectrogram(samples) // floatArray of size 1024 * 128
        var inputTensor: OnnxTensor? = null
        var results: OrtSession.Result? = null

        return try {
            val buffer = FloatBuffer.wrap(features)
            inputTensor = OnnxTensor.createTensor(env, buffer, longArrayOf(1, TARGET_FRAMES.toLong(), NUM_MEL_BINS.toLong()))

            val inputName = sess.inputNames.iterator().next()
            results = sess.run(mapOf(inputName to inputTensor))

            val outputTensor = results.get(0) as? OnnxTensor
            val logits = when (val value = outputTensor?.value) {
                is Array<*> -> (value[0] as? FloatArray) ?: FloatArray(0)
                is FloatArray -> value
                else -> FloatArray(0)
            }

            if (logits.isEmpty()) return null

            // Sigmoid probabilities (AudioSet is multi-label)
            val probs = FloatArray(logits.size) { i ->
                1f / (1f + exp(-logits[i]))
            }

            // Find top events
            val sortedIndices = probs.indices.sortedByDescending { probs[it] }
            val topList = mutableListOf<Pair<String, Float>>()
            for (i in 0 until minOf(5, sortedIndices.size)) {
                val idx = sortedIndices[i]
                val name = labelMap[idx] ?: "Event_$idx"
                topList.add(Pair(name, probs[idx]))
            }

            val topIdx = sortedIndices[0]
            val topName = labelMap[topIdx] ?: "Event_$topIdx"
            val topConf = probs[topIdx]

            // Check specifically for breathing, sigh, laughter, crying
            var isSigh = false
            var isLaugh = false
            var isCry = false

            for (pair in topList) {
                val lower = pair.first.lowercase()
                val score = pair.second
                if (score > 0.15f) {
                    if (lower.contains("sigh") || lower.contains("gasp") || lower.contains("pant") || lower.contains("groan")) {
                        isSigh = true
                    }
                    if (lower.contains("laughter") || lower.contains("snicker") || lower.contains("chuckle")) {
                        isLaugh = true
                    }
                    if (lower.contains("crying") || lower.contains("sobbing") || lower.contains("wail") || lower.contains("whimper")) {
                        isCry = true
                    }
                }
            }

            AstEventResult(
                topEvent = topName,
                confidence = topConf,
                isSighOrBreathing = isSigh,
                isLaughter = isLaugh,
                isCrying = isCry,
                topEvents = topList
            )
        } catch (e: Exception) {
            Log.e(TAG, "AST inference error: ${e.message}")
            null
        } finally {
            try { inputTensor?.close() } catch (_: Exception) {}
            try { results?.close() } catch (_: Exception) {}
        }
    }

    /**
     * Computes [1024, 128] normalized log-mel spectrogram.
     */
    private fun computeSpectrogram(audio: FloatArray): FloatArray {
        val totalFrames = ((audio.size - WINDOW_SIZE) / HOP_SIZE).coerceAtLeast(0)
        val framesToTake = minOf(totalFrames, TARGET_FRAMES)
        val out = FloatArray(TARGET_FRAMES * NUM_MEL_BINS)

        val frameBuffer = FloatArray(WINDOW_SIZE)
        val real = FloatArray(FFT_SIZE)
        val imag = FloatArray(FFT_SIZE)
        val powerSpec = FloatArray(FFT_SIZE / 2 + 1)

        for (f in 0 until framesToTake) {
            val start = f * HOP_SIZE
            for (i in 0 until WINDOW_SIZE) {
                frameBuffer[i] = audio[start + i] * hanningWindow[i]
            }
            real.fill(0f)
            imag.fill(0f)
            System.arraycopy(frameBuffer, 0, real, 0, WINDOW_SIZE)
            fft(real, imag)

            for (i in powerSpec.indices) {
                powerSpec[i] = real[i] * real[i] + imag[i] * imag[i]
            }

            // Apply mel filterbank
            val frameOffset = f * NUM_MEL_BINS
            for (m in 0 until NUM_MEL_BINS) {
                var melEnergy = 0f
                val filter = melFilterBank[m]
                for (k in powerSpec.indices) {
                    melEnergy += powerSpec[k] * filter[k]
                }
                val logMel = ln(max(melEnergy, 1e-10f))
                // AST feature normalization
                out[frameOffset + m] = (logMel - AST_MEAN) / (2f * AST_STD)
            }
        }

        // Zero-padding for remaining frames if any
        return out
    }

    private fun fft(real: FloatArray, imag: FloatArray) {
        val n = real.size
        var j = 0
        for (i in 0 until n - 1) {
            if (i < j) {
                val tr = real[i]; real[i] = real[j]; real[j] = tr
                val ti = imag[i]; imag[i] = imag[j]; imag[j] = ti
            }
            var k = n shr 1
            while (k <= j) {
                j -= k
                k = k shr 1
            }
            j += k
        }
        var l = 2
        while (l <= n) {
            val halfL = l shr 1
            val angle = -2.0 * Math.PI / l
            val wStepR = cos(angle).toFloat()
            val wStepI = sin(angle).toFloat()
            var i = 0
            while (i < n) {
                var wR = 1.0f
                var wI = 0.0f
                for (m in 0 until halfL) {
                    val uR = real[i + m]
                    val uI = imag[i + m]
                    val vR = real[i + m + halfL] * wR - imag[i + m + halfL] * wI
                    val vI = real[i + m + halfL] * wI + imag[i + m + halfL] * wR
                    real[i + m] = uR + vR
                    imag[i + m] = uI + vI
                    real[i + m + halfL] = uR - vR
                    imag[i + m + halfL] = uI - vI
                    val nextWR = wR * wStepR - wI * wStepI
                    val nextWI = wR * wStepI + wI * wStepR
                    wR = nextWR; wI = nextWI
                }
                i += l
            }
            l = l shl 1
        }
    }

    private fun createMelFilterBank(sr: Int, nFft: Int, nMels: Int, fMin: Float, fMax: Float): Array<FloatArray> {
        val minMel = hzToMel(fMin)
        val maxMel = hzToMel(fMax)
        val melPoints = FloatArray(nMels + 2) { i ->
            minMel + i * (maxMel - minMel) / (nMels + 1)
        }
        val hzPoints = FloatArray(nMels + 2) { i -> melToHz(melPoints[i]) }
        val binPoints = IntArray(nMels + 2) { i ->
            floor((nFft + 1) * hzPoints[i] / sr).toInt().coerceIn(0, nFft / 2)
        }

        val filters = Array(nMels) { FloatArray(nFft / 2 + 1) }
        for (m in 0 until nMels) {
            val left = binPoints[m]
            val center = binPoints[m + 1]
            val right = binPoints[m + 2]
            for (k in left until center) {
                if (center != left) filters[m][k] = (k - left).toFloat() / (center - left)
            }
            for (k in center until right) {
                if (right != center) filters[m][k] = (right - k).toFloat() / (right - center)
            }
        }
        return filters
    }

    private fun hzToMel(hz: Float): Float = 2595f * log10(1f + hz / 700f)
    private fun melToHz(mel: Float): Float = 700f * (10.0.pow((mel / 2595f).toDouble()).toFloat() - 1f)

    @Synchronized
    fun release() {
        try {
            session?.close()
            session = null
            initialized = false
            Log.d(TAG, "AST session closed.")
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing AST: ${e.message}")
        }
    }
}
