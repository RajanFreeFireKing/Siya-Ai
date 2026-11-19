package com.siya.ai.audio

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.util.Log
import java.nio.FloatBuffer
import java.nio.LongBuffer

/**
 * Silero VAD v5 ultra-low-latency voice activity detector.
 * Runs 24/7 as gatekeeper to detect human voice / breathing / speech.
 */
class SileroVadDetector(private val context: Context) {

    companion object {
        private const val TAG = "SiyaAudioDetection"
        private const val MODEL_NAME = "silero_vad.onnx"
        const val FRAME_SIZE = 512 // 32ms at 16kHz
        const val SAMPLE_RATE = 16000L
    }

    private var ortEnv: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var state: Array<Array<FloatArray>> = Array(2) { Array(1) { FloatArray(128) } }
    private var initialized = false

    init {
        initSession()
    }

    @Synchronized
    private fun initSession() {
        if (initialized) return
        try {
            ortEnv = OrtEnvironment.getEnvironment()
            val modelBytes = context.assets.open(MODEL_NAME).use { it.readBytes() }
            val options = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(1)
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            }
            session = ortEnv?.createSession(modelBytes, options)
            initialized = true
            Log.d(TAG, "Silero VAD v5 initialized successfully from assets ($MODEL_NAME)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load Silero VAD model: ${e.message}", e)
        }
    }

    /**
     * Process 512 samples (32ms of 16kHz audio) and return speech probability (0.0 to 1.0).
     */
    @Synchronized
    fun process(samples: FloatArray): Float {
        if (!initialized || session == null || ortEnv == null) return 0f
        val env = ortEnv ?: return 0f
        val sess = session ?: return 0f

        val inputAudio = if (samples.size == FRAME_SIZE) samples else {
            val padded = FloatArray(FRAME_SIZE)
            System.arraycopy(samples, 0, padded, 0, minOf(samples.size, FRAME_SIZE))
            padded
        }

        var inputTensor: OnnxTensor? = null
        var stateTensor: OnnxTensor? = null
        var srTensor: OnnxTensor? = null
        var results: OrtSession.Result? = null

        return try {
            val audioBuffer = FloatBuffer.wrap(inputAudio)
            inputTensor = OnnxTensor.createTensor(env, audioBuffer, longArrayOf(1, FRAME_SIZE.toLong()))
            stateTensor = OnnxTensor.createTensor(env, state)
            srTensor = OnnxTensor.createTensor(env, LongBuffer.wrap(longArrayOf(SAMPLE_RATE)), longArrayOf())

            val inputs = mapOf(
                "input" to inputTensor,
                "state" to stateTensor,
                "sr" to srTensor
            )

            results = sess.run(inputs)
            val outputTensor = results.get(0) as? OnnxTensor
            val stateOutputTensor = results.get(1) as? OnnxTensor

            val prob = when (val value = outputTensor?.value) {
                is Array<*> -> {
                    val row = value[0]
                    when (row) {
                        is FloatArray -> row[0]
                        is Array<*> -> (row[0] as? Number)?.toFloat() ?: 0f
                        else -> 0f
                    }
                }
                is FloatArray -> value[0]
                else -> 0f
            }

            // Update recurrent state for next chunk
            val newState = stateOutputTensor?.value as? Array<Array<FloatArray>>
            if (newState != null) {
                state = newState
            }

            prob
        } catch (e: Exception) {
            Log.e(TAG, "Silero VAD inference error: ${e.message}")
            0f
        } finally {
            try { inputTensor?.close() } catch (_: Exception) {}
            try { stateTensor?.close() } catch (_: Exception) {}
            try { srTensor?.close() } catch (_: Exception) {}
            try { results?.close() } catch (_: Exception) {}
        }
    }

    @Synchronized
    fun reset() {
        state = Array(2) { Array(1) { FloatArray(128) } }
    }

    @Synchronized
    fun release() {
        try {
            session?.close()
            session = null
            initialized = false
            Log.d(TAG, "Silero VAD session closed.")
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing Silero VAD: ${e.message}")
        }
    }
}
