package com.siya.ai.ui.main

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.view.WindowManager
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/**
 * Camera se ek photo lene ke liye chhoti, transparent activity (camera sirf visible activity se
 * khulta hai). Photo lekar turant band ho jaati hai. Siya ka "camera se dekho" tool isse chalata hai.
 */
class CameraCaptureActivity : Activity() {

    companion object {
        const val EXTRA_FRONT = "front"
        @Volatile var latch: CountDownLatch? = null
        @Volatile var result: ByteArray? = null
        @Volatile var error: String? = null

        /** Tool thread se bulao. JPEG bytes ya null (error mein `error` dekho). */
        fun capture(ctx: Context, front: Boolean): ByteArray? {
            if (ctx.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                error = "Camera permission nahi hai (Settings > Permissions)"; return null
            }
            result = null; error = null
            val l = CountDownLatch(1)
            latch = l
            try {
                ctx.startActivity(android.content.Intent(ctx, CameraCaptureActivity::class.java)
                    .putExtra(EXTRA_FRONT, front)
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_NO_ANIMATION))
            } catch (e: Exception) { error = "Camera screen khul nahi paayi: ${e.message}"; return null }
            l.await(12, TimeUnit.SECONDS)
            return result
        }
    }

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var jpegReader: ImageReader? = null
    private var yuvReader: ImageReader? = null
    private var done = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        thread = HandlerThread("siya-cam").also { it.start() }
        handler = Handler(thread!!.looper)
        start(intent.getBooleanExtra(EXTRA_FRONT, false))
    }

    private fun finishWith(bytes: ByteArray?, err: String?) {
        if (done) return
        done = true
        result = bytes; if (err != null) error = err
        try { session?.close() } catch (_: Exception) {}
        try { camera?.close() } catch (_: Exception) {}
        try { jpegReader?.close(); yuvReader?.close() } catch (_: Exception) {}
        thread?.quitSafely()
        latch?.countDown()
        runOnUiThread { finish(); overridePendingTransition(0, 0) }
    }

    @android.annotation.SuppressLint("MissingPermission")
    private fun start(front: Boolean) {
        try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val want = if (front) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
            val id = cm.cameraIdList.firstOrNull { cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == want }
                ?: cm.cameraIdList.firstOrNull() ?: return finishWith(null, "Camera nahi mila")
            val ch = cm.getCameraCharacteristics(id)
            val sensor = ch.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            val sizes = ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)?.getOutputSizes(ImageFormat.JPEG)
                ?: return finishWith(null, "Camera size nahi mili")
            val size = sizes.filter { it.width <= 1920 && it.height <= 1920 }.maxByOrNull { it.width * it.height } ?: sizes.first()
            val ySize = sizes.minByOrNull { abs(it.width - 640) } ?: size

            jpegReader = ImageReader.newInstance(size.width, size.height, ImageFormat.JPEG, 2).also { r ->
                r.setOnImageAvailableListener({ rd ->
                    val img = rd.acquireLatestImage() ?: return@setOnImageAvailableListener
                    try {
                        val buf = img.planes[0].buffer
                        val b = ByteArray(buf.remaining()); buf.get(b)
                        finishWith(b, null)
                    } finally { img.close() }
                }, handler)
            }
            // warm-up preview (auto exposure / focus settle ho): chhota YUV stream
            yuvReader = ImageReader.newInstance(ySize.width, ySize.height, ImageFormat.YUV_420_888, 2).also { r ->
                r.setOnImageAvailableListener({ rd -> try { rd.acquireLatestImage()?.close() } catch (_: Exception) {} }, handler)
            }

            cm.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(c: CameraDevice) {
                    camera = c
                    try {
                        @Suppress("DEPRECATION")
                        c.createCaptureSession(listOf(yuvReader!!.surface, jpegReader!!.surface), object : CameraCaptureSession.StateCallback() {
                            override fun onConfigured(s: CameraCaptureSession) {
                                session = s
                                try {
                                    val prev = c.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                                        addTarget(yuvReader!!.surface)
                                        set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                                    }
                                    s.setRepeatingRequest(prev.build(), null, handler)
                                    handler?.postDelayed({
                                        try {
                                            val still = c.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                                                addTarget(jpegReader!!.surface)
                                                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                                                set(CaptureRequest.JPEG_ORIENTATION, sensor)
                                                set(CaptureRequest.JPEG_QUALITY, 85.toByte())
                                            }
                                            s.capture(still.build(), null, handler)
                                        } catch (e: Exception) { finishWith(null, "Photo nahi li: ${e.message}") }
                                    }, 1000)
                                } catch (e: Exception) { finishWith(null, "Camera start nahi hua: ${e.message}") }
                            }
                            override fun onConfigureFailed(s: CameraCaptureSession) { finishWith(null, "Camera configure nahi hua") }
                        }, handler)
                    } catch (e: Exception) { finishWith(null, "Camera session fail: ${e.message}") }
                }
                override fun onDisconnected(c: CameraDevice) { finishWith(null, "Camera disconnect ho gaya (koi aur app use kar rahi hai?)") }
                override fun onError(c: CameraDevice, e: Int) { finishWith(null, "Camera error $e") }
            }, handler)
        } catch (e: Exception) { finishWith(null, "Camera error: ${e.message}") }
        // safety: 11 sec mein kuch na ho to band
        handler?.postDelayed({ finishWith(null, "Camera se photo nahi aayi (time out)") }, 11000)
    }

    override fun onDestroy() {
        if (!done) finishWith(null, "Camera screen band ho gayi")
        super.onDestroy()
    }
}
