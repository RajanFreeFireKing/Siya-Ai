package com.siya.ai.core

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.view.Display
import com.siya.ai.data.ImageUtil
import com.siya.ai.data.PeopleStore
import com.siya.ai.service.AccessibilityHelperService
import com.siya.ai.ui.main.CameraCaptureActivity
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Siya ki "aankhein": camera ya screen ki photo Gemini ko bhejna, saved logon ki photo ke saath. */
object VisionTools {

    private fun screenBitmap(ctx: Context): Bitmap? {
        if (Build.VERSION.SDK_INT < 30) return null
        val svc = AccessibilityHelperService.instance ?: return null
        val latch = CountDownLatch(1)
        var out: Bitmap? = null
        try {
            svc.takeScreenshot(Display.DEFAULT_DISPLAY, ctx.mainExecutor, object : AccessibilityService.TakeScreenshotCallback {
                override fun onSuccess(r: AccessibilityService.ScreenshotResult) {
                    try {
                        out = Bitmap.wrapHardwareBuffer(r.hardwareBuffer, r.colorSpace)?.copy(Bitmap.Config.ARGB_8888, false)
                        r.hardwareBuffer.close()
                    } catch (_: Exception) {}
                    latch.countDown()
                }
                override fun onFailure(errorCode: Int) { latch.countDown() }
            })
            latch.await(4, TimeUnit.SECONDS)
        } catch (_: Exception) {}
        return out
    }

    /** Saved logon ki photo pehle bhejo, taaki Gemini naam ke saath pehchan sake. */
    private fun sendReferences(s: SiyaSession): Int {
        var n = 0
        for (p in PeopleStore.list(s.appContext).filter { it.photo.isNotBlank() }.take(6)) {
            val bmp = ImageUtil.decodeScaled(p.photo, 384) ?: continue
            s.sendText("Reference photo: yeh ${p.name} hai (${p.relation}).")
            s.sendImage(ImageUtil.jpeg(bmp, 80))
            Thread.sleep(350)
            n++
        }
        return n
    }

    private fun deliver(ctx: Context, jpeg: ByteArray, what: String, identify: Boolean): String {
        val s = SiyaSession.current ?: return "ERROR: live session chal nahi rahi"
        val refs = if (identify) sendReferences(s) else 0
        s.sendText(if (refs > 0) "Ab yeh asli $what ki photo hai. Isme jo log dikh rahe hain unhe upar di gayi saved logon ki photos se milao aur naam batao; agar pakka na ho to bolo."
                   else "Yeh $what ki photo hai. Dekh kar batao kya hai.")
        s.sendImage(jpeg)
        Thread.sleep(500)
        return "OK: $what ki photo tumhe bhej di hai (${if (refs > 0) "$refs saved logon ki reference photo ke saath" else "reference ke bina"}). Ab dekh kar user ko batao ki kya dikh raha hai."
    }

    fun lookScreen(ctx: Context, identify: Boolean): String {
        if (AccessibilityHelperService.instance == null) return "ERROR: Accessibility ON nahi hai"
        val bmp = screenBitmap(ctx) ?: return "ERROR: screenshot nahi mila (Android 11+ aur Accessibility chahiye)"
        return deliver(ctx, ImageUtil.jpeg(ImageUtil.scale(bmp, 1024), 75), "screen", identify)
    }

    fun lookCamera(ctx: Context, camera: String, identify: Boolean): String {
        val front = camera.equals("front", true) || camera.equals("selfie", true)
        val bytes = CameraCaptureActivity.capture(ctx, front)
            ?: return "ERROR: ${CameraCaptureActivity.error ?: "camera se photo nahi aayi"}"
        val bmp = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: return "ERROR: photo samajh nahi aayi"
        return deliver(ctx, ImageUtil.jpeg(ImageUtil.scale(bmp, 1024), 78), if (front) "front camera" else "back camera", identify)
    }
}
