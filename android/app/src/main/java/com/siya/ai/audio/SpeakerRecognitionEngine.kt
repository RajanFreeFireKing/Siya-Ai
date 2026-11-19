package com.siya.ai.audio

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.nio.FloatBuffer
import kotlin.math.*

/**
 * Biometric Voiceprint Lock & Speaker Recognition Engine ("AI Boss").
 *
 * Uses WeSpeaker ResNet34 INT8 ONNX model (~6.38 MB) to extract 256-D speaker embeddings
 * and verifies whether the speaker is the verified Boss (Malik) or an Unknown Stranger
 * using cosine similarity in < 0.2s.
 */
class SpeakerRecognitionEngine private constructor(private val context: Context) {

    companion object {
        private const val TAG = "SiyaSpeakerBoss"
        private const val MODEL_NAME = "speaker_embedding.onnx"
        private const val PREFS_NAME = "siya_boss_voiceprint"
        private const val KEY_ENROLLED = "is_boss_enrolled"
        private const val KEY_EMBEDDING = "boss_embedding_vector"
        private const val KEY_SAMPLE_COUNT = "enrolled_sample_count"

        const val SAMPLE_RATE = 16000
        const val NUM_MEL_BINS = 80
        const val FFT_SIZE = 512
        const val WINDOW_SIZE = 400 // 25ms @ 16kHz
        const val HOP_SIZE = 160    // 10ms @ 16kHz
        const val EMBEDDING_DIM = 256

        const val BOSS_MATCH_THRESHOLD = 0.75f     // >= 75% -> BOSS (Verified Malik)
        const val STRANGER_THRESHOLD = 0.50f       // < 50%  -> UNKNOWN STRANGER

        @Volatile
        private var instance: SpeakerRecognitionEngine? = null

        fun getInstance(ctx: Context): SpeakerRecognitionEngine {
            return instance ?: synchronized(this) {
                instance ?: SpeakerRecognitionEngine(ctx.applicationContext).also { instance = it }
            }
        }
    }

    enum class SpeakerIdentity(val label: String, val tag: String) {
        BOSS("BOSS", "[Speaker: BOSS (Verified Malik)]"),
        STRANGER("STRANGER", "[Speaker: UNKNOWN STRANGER (Not Boss)]"),
        UNVERIFIED("UNVERIFIED", "[Speaker: UNVERIFIED]"),
        NOT_CONFIGURED("OPEN", "[Speaker: GUEST (No Boss Enrolled)]")
    }

    data class VerificationResult(
        val identity: SpeakerIdentity,
        val similarity: Float,
        val isBoss: Boolean
    )

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private var ortEnv: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var initialized = false

    // Stored Boss embedding vector
    private var bossEmbedding: FloatArray? = null

    // In-memory buffer for multi-sample enrollment (3-4 samples)
    private val enrollmentBuffer = mutableListOf<FloatArray>()

    // Hanning window precomputed
    private val hanningWindow = FloatArray(WINDOW_SIZE) { i ->
        (0.5f * (1f - cos(2.0 * Math.PI * i / (WINDOW_SIZE - 1)))).toFloat()
    }

    // Mel filterbank weights [NUM_MEL_BINS][FFT_SIZE / 2 + 1]
    private val melFilterBank = createMelFilterBank(SAMPLE_RATE, FFT_SIZE, NUM_MEL_BINS, 50f, 7600f)

    init {
        loadStoredBossProfile()
        initSession()
    }

    private fun loadStoredBossProfile() {
        val enrolled = prefs.getBoolean(KEY_ENROLLED, false)
        val rawVector = prefs.getString(KEY_EMBEDDING, null)
        if (enrolled && !rawVector.isNullOrBlank()) {
            try {
                val parts = rawVector.split(",")
                if (parts.size == EMBEDDING_DIM) {
                    val vec = FloatArray(EMBEDDING_DIM) { idx -> parts[idx].toFloat() }
                    bossEmbedding = normalizeL2(vec)
                    Log.i(TAG, "Loaded verified AI Boss voiceprint (${parts.size} dimensions).")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to parse stored boss embedding: ${e.message}")
            }
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
            Log.i(TAG, "WeSpeaker INT8 speaker embedding model initialized ($MODEL_NAME).")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize WeSpeaker model: ${e.message}", e)
        }
    }

    fun isBossEnrolled(): Boolean = prefs.getBoolean(KEY_ENROLLED, false) && bossEmbedding != null

    fun getEnrolledSampleCount(): Int = prefs.getInt(KEY_SAMPLE_COUNT, 0)

    /**
     * Extracts 256-D normalized speaker embedding from raw 16kHz PCM float samples.
     */
    @Synchronized
    fun extractEmbedding(samples: FloatArray): FloatArray? {
        if (!initialized || session == null || ortEnv == null) return null
        val env = ortEnv ?: return null
        val sess = session ?: return null

        if (samples.size < WINDOW_SIZE) return null

        val features = computeLogMelSpectrogram(samples) ?: return null
        val numFrames = features.size / NUM_MEL_BINS
        if (numFrames < 9) return null // WeSpeaker min_num_frames = 9

        var inputTensor: OnnxTensor? = null
        var results: OrtSession.Result? = null

        return try {
            val buffer = FloatBuffer.wrap(features)
            val shape = longArrayOf(1, numFrames.toLong(), NUM_MEL_BINS.toLong())
            inputTensor = OnnxTensor.createTensor(env, buffer, shape)

            results = sess.run(mapOf("input_features" to inputTensor))
            val outputTensor = results.get(0) as? OnnxTensor ?: return null
            val rawOutput = outputTensor.floatBuffer

            val embedding = FloatArray(EMBEDDING_DIM)
            rawOutput.get(embedding, 0, minOf(EMBEDDING_DIM, rawOutput.remaining()))
            normalizeL2(embedding)
        } catch (e: Exception) {
            Log.e(TAG, "Embedding extraction failed: ${e.message}", e)
            null
        } finally {
            inputTensor?.close()
            results?.close()
        }
    }

    /**
     * Real-time speaker verification against enrolled Boss voiceprint.
     * Takes < 0.2s.
     */
    fun verifySpeaker(samples: FloatArray): VerificationResult {
        val boss = bossEmbedding
        if (!isBossEnrolled() || boss == null) {
            return VerificationResult(SpeakerIdentity.NOT_CONFIGURED, 0f, isBoss = true)
        }

        val liveEmbedding = extractEmbedding(samples)
            ?: return VerificationResult(SpeakerIdentity.UNVERIFIED, 0f, isBoss = false)

        val similarity = cosineSimilarity(liveEmbedding, boss)
        Log.d(TAG, "Speaker Verification Cosine Similarity: ${"%.3f".format(similarity)}")

        val identity = when {
            similarity >= BOSS_MATCH_THRESHOLD -> SpeakerIdentity.BOSS
            similarity < STRANGER_THRESHOLD -> SpeakerIdentity.STRANGER
            else -> SpeakerIdentity.UNVERIFIED
        }

        return VerificationResult(identity, similarity, isBoss = identity == SpeakerIdentity.BOSS)
    }

    /**
     * Enrollment Step: Add one recorded voice sample (e.g. 1.5 - 3 seconds).
     * Returns current sample count (1..4) or -1 on error.
     */
    @Synchronized
    fun addEnrollmentSample(samples: FloatArray): Int {
        val emb = extractEmbedding(samples) ?: return -1
        enrollmentBuffer.add(emb)
        Log.i(TAG, "Added enrollment sample ${enrollmentBuffer.size}/4")
        return enrollmentBuffer.size
    }

    /**
     * Enrollment Step: Finalize and average all collected enrollment samples,
     * persist to SharedPreferences as the active Boss voiceprint.
     */
    @Synchronized
    fun finalizeEnrollment(): Boolean {
        if (enrollmentBuffer.isEmpty()) return false

        val avg = FloatArray(EMBEDDING_DIM)
        for (vec in enrollmentBuffer) {
            for (i in 0 until EMBEDDING_DIM) {
                avg[i] += vec[i]
            }
        }
        for (i in 0 until EMBEDDING_DIM) {
            avg[i] /= enrollmentBuffer.size.toFloat()
        }
        val normalized = normalizeL2(avg)
        bossEmbedding = normalized

        val serialized = normalized.joinToString(",") { it.toString() }
        prefs.edit()
            .putBoolean(KEY_ENROLLED, true)
            .putString(KEY_EMBEDDING, serialized)
            .putInt(KEY_SAMPLE_COUNT, enrollmentBuffer.size)
            .apply()

        Log.i(TAG, "Successfully enrolled AI Boss with ${enrollmentBuffer.size} voice samples!")
        enrollmentBuffer.clear()
        return true
    }

    /**
     * Reset / Delete enrolled Boss voiceprint.
     */
    @Synchronized
    fun clearBossProfile() {
        enrollmentBuffer.clear()
        bossEmbedding = null
        prefs.edit()
            .remove(KEY_ENROLLED)
            .remove(KEY_EMBEDDING)
            .remove(KEY_SAMPLE_COUNT)
            .apply()
        Log.i(TAG, "Cleared AI Boss voice profile.")
    }

    private fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        var dot = 0f
        var normA = 0f
        var normB = 0f
        for (i in a.indices) {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        val denom = (sqrt(normA) * sqrt(normB))
        return if (denom > 1e-8f) (dot / denom).coerceIn(-1.0f, 1.0f) else 0f
    }

    private fun normalizeL2(vec: FloatArray): FloatArray {
        var sumSq = 0f
        for (v in vec) sumSq += v * v
        val norm = sqrt(sumSq)
        if (norm > 1e-8f) {
            for (i in vec.indices) vec[i] /= norm
        }
        return vec
    }

    /**
     * Computes 80-bin Log-Mel Spectrogram features for WeSpeaker.
     */
    private fun computeLogMelSpectrogram(samples: FloatArray): FloatArray? {
        val numFrames = (samples.size - WINDOW_SIZE) / HOP_SIZE + 1
        if (numFrames <= 0) return null

        val out = FloatArray(numFrames * NUM_MEL_BINS)
        val frameBuffer = FloatArray(WINDOW_SIZE)
        val real = FloatArray(FFT_SIZE)
        val imag = FloatArray(FFT_SIZE)
        val powerSpec = FloatArray(FFT_SIZE / 2 + 1)

        for (f in 0 until numFrames) {
            val start = f * HOP_SIZE
            for (i in 0 until WINDOW_SIZE) {
                frameBuffer[i] = samples[start + i] * hanningWindow[i]
            }

            real.fill(0f)
            imag.fill(0f)
            System.arraycopy(frameBuffer, 0, real, 0, WINDOW_SIZE)
            fft(real, imag)

            for (i in powerSpec.indices) {
                powerSpec[i] = real[i] * real[i] + imag[i] * imag[i]
            }

            val frameOffset = f * NUM_MEL_BINS
            for (m in 0 until NUM_MEL_BINS) {
                var melEnergy = 0f
                val filter = melFilterBank[m]
                for (k in powerSpec.indices) {
                    melEnergy += powerSpec[k] * filter[k]
                }
                out[frameOffset + m] = ln(max(melEnergy, 1e-10f))
            }
        }
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
                    wR = nextWR
                    wI = nextWI
                }
                i += l
            }
            l = l shl 1
        }
    }

    private fun createMelFilterBank(
        sampleRate: Int,
        fftSize: Int,
        numMelBins: Int,
        lowFreq: Float,
        highFreq: Float
    ): Array<FloatArray> {
        fun hzToMel(hz: Float): Float = 2595f * log10(1f + hz / 700f)
        fun melToHz(mel: Float): Float = 700f * (10.0.pow(mel / 2595.0).toFloat() - 1f)

        val lowMel = hzToMel(lowFreq)
        val highMel = hzToMel(highFreq)
        val numPoints = numMelBins + 2
        val melPoints = FloatArray(numPoints) { i ->
            lowMel + i * (highMel - lowMel) / (numPoints - 1)
        }

        val binPoints = IntArray(numPoints) { i ->
            val hz = melToHz(melPoints[i])
            floor((fftSize + 1) * hz / sampleRate).toInt().coerceIn(0, fftSize / 2)
        }

        val filterBank = Array(numMelBins) { FloatArray(fftSize / 2 + 1) }
        for (m in 0 until numMelBins) {
            val left = binPoints[m]
            val center = binPoints[m + 1]
            val right = binPoints[m + 2]

            for (k in left until center) {
                if (center > left) filterBank[m][k] = (k - left).toFloat() / (center - left)
            }
            for (k in center until right) {
                if (right > center) filterBank[m][k] = (right - k).toFloat() / (right - center)
            }
        }
        return filterBank
    }

    @Synchronized
    fun release() {
        try {
            session?.close()
            session = null
            ortEnv = null
            initialized = false
        } catch (_: Exception) {}
    }
}
