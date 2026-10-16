package com.siya.ai.core

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.provider.Settings
import android.view.Display
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import com.siya.ai.data.ImageUtil
import com.siya.ai.service.AccessibilityHelperService
import com.siya.ai.service.GameVisionOverlay
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Feature 1 + 2: Game controller (tap / swipe / hold / drag), voice macros aur AI auto-play.
 * Sab coordinates PERCENT (0-100) mein hain, isliye har phone par same chalte hain.
 * Ye sirf user ke apne phone ke games / offline practice ke liye hai; online multiplayer mein auto-play se
 * account ban ho sakta hai - ye jokhim user ka hai.
 */
object GameControl {
    private val ui = Handler(Looper.getMainLooper())
    @Volatile private var autoOn = false
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)
    private fun svc() = AccessibilityHelperService.instance
    private fun metrics(ctx: Context): android.util.DisplayMetrics = android.util.DisplayMetrics().also { dm ->
        @Suppress("DEPRECATION")
        (ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(dm)
    }

    // ── gestures ────────────────────────────────────────────
    private fun gesture(path: Path, ms: Long): Boolean {
        val s = svc() ?: return false
        val latch = CountDownLatch(1)
        val g = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, ms.coerceIn(1, 8000))).build()
        val ok = s.dispatchGesture(g, object : AccessibilityService.GestureResultCallback() {
            override fun onCompleted(d: GestureDescription?) { latch.countDown() }
            override fun onCancelled(d: GestureDescription?) { latch.countDown() }
        }, null)
        if (ok) latch.await(ms + 600, TimeUnit.MILLISECONDS)
        return ok
    }

    private fun px(ctx: Context, pctX: Double, pctY: Double): Pair<Float, Float> {
        val m = metrics(ctx)
        return (pctX.coerceIn(0.0, 100.0) / 100 * m.widthPixels).toFloat() to (pctY.coerceIn(0.0, 100.0) / 100 * m.heightPixels).toFloat()
    }

    fun tap(ctx: Context, x: Double, y: Double, holdMs: Long = 50): String {
        if (svc() == null) return "ERROR: Accessibility ON nahi hai"
        val (a, b) = px(ctx, x, y)
        return if (gesture(Path().apply { moveTo(a, b); lineTo(a + 1, b + 1) }, holdMs)) "OK: tap ($x%, $y%)" else "ERROR: gesture nahi chala"
    }

    fun swipe(ctx: Context, x1: Double, y1: Double, x2: Double, y2: Double, ms: Long = 300): String {
        if (svc() == null) return "ERROR: Accessibility ON nahi hai"
        val (a, b) = px(ctx, x1, y1); val (c, d) = px(ctx, x2, y2)
        return if (gesture(Path().apply { moveTo(a, b); lineTo(c, d) }, ms)) "OK: swipe/drag" else "ERROR: gesture nahi chala"
    }


    /** Fast, non-blocking mapped action. Gloo wall uses two short strokes in one gesture. */
    fun action(ctx: Context, actionName: String): String {
        val service=svc() ?: return "ERROR: Accessibility ON nahi hai"
        if(Build.VERSION.SDK_INT<Build.VERSION_CODES.N) return "ERROR: Gesture control ke liye Android 7+ chahiye"
        val action=GameTouchMapping.Button.from(actionName) ?: return "ERROR: fire, jump, crouch, gloo_wall, sprint ya joystick use karo."
        val dm=metrics(ctx); val width=dm.widthPixels.coerceAtLeast(1); val height=dm.heightPixels.coerceAtLeast(1)
        if(action==GameTouchMapping.Button.JOYSTICK) {
            val start=GameTouchMapping.get(ctx,GameTouchMapping.Button.JOYSTICK)
            val end=GameTouchMapping.Point((start.xPercent-5f).coerceIn(0f,100f),(start.yPercent-12f).coerceIn(0f,100f))
            val (sx,sy)=start.toPixels(width,height); val (ex,ey)=end.toPixels(width,height)
            val path=Path().apply { moveTo(sx,sy); lineTo(ex,ey) }
            val ok=service.dispatchGesture(GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path,0,90)).build(),null,null)
            return if(ok) "OK: joystick gesture queued" else "ERROR: gesture dispatch rejected"
        }
        val strokes=if(action==GameTouchMapping.Button.GLOO_WALL) listOf(
            Triple(GameTouchMapping.get(ctx,GameTouchMapping.Button.GLOO_WALL),0L,38L),
            Triple(GameTouchMapping.get(ctx,GameTouchMapping.Button.FIRE),38L,38L)
        ) else listOf(Triple(GameTouchMapping.get(ctx,action),0L,45L))
        val builder=GestureDescription.Builder()
        strokes.forEach { (point,start,duration) ->
            val (x,y)=point.toPixels(width,height)
            val path=Path().apply { moveTo(x,y); lineTo(x+0.1f,y+0.1f) }
            builder.addStroke(GestureDescription.StrokeDescription(path,start,duration))
        }
        val accepted=service.dispatchGesture(builder.build(),object:AccessibilityService.GestureResultCallback() {
            override fun onCompleted(gestureDescription:GestureDescription?) { Log.i("GameControl","mapped action completed: "+action.key) }
            override fun onCancelled(gestureDescription:GestureDescription?) { Log.w("GameControl","mapped action cancelled: "+action.key) }
        },null)
        Log.i("GameControl","mapped action="+action.key+" accepted="+accepted+" display="+width+"x"+height)
        return if(accepted) "OK: "+action.key+" gesture queued ("+(strokes.last().second+strokes.last().third)+"ms plan)" else "ERROR: gesture dispatch rejected"
    }
    fun setMapping(ctx:Context,actionName:String,x:Float,y:Float):String {
        val button=GameTouchMapping.Button.from(actionName) ?: return "ERROR: unknown game button"
        val p=GameTouchMapping.set(ctx,button,x,y)
        return "OK: "+button.label+" mapped to "+"%.1f".format(java.util.Locale.ROOT,p.xPercent)+"%, "+"%.1f".format(java.util.Locale.ROOT,p.yPercent)+"%"
    }
    fun mappingSummary(ctx:Context):String=GameTouchMapping.summary(ctx)
    fun calibrate(ctx:Context):String=GameVisionOverlay.show(ctx)

    // ── macros (Feature 2) ──────────────────────────────────
    private fun macros(ctx: Context) = try { JSONObject(prefs(ctx).getString("game_macros", "{}")) } catch (_: Exception) { JSONObject() }
    fun macroNames(ctx: Context): List<String> = macros(ctx).keys().asSequence().toList()

    fun run(ctx: Context, name: String): String {
        val all = macros(ctx)
        val q = name.trim().lowercase()
        val key = all.keys().asSequence().firstOrNull { it == q } ?: all.keys().asSequence().firstOrNull { it.contains(q) || q.contains(it) }
            ?: return "NOT_FOUND: '$name' macro nahi hai. Saved: ${macroNames(ctx).joinToString()}"
        val m = all.getJSONObject(key)
        val p = m.getJSONArray("pts")
        val ms = m.optLong("ms", 60)
        val a = p.getJSONArray(0)
        return if (p.length() > 1) { val b = p.getJSONArray(1); swipe(ctx, a.getDouble(0), a.getDouble(1), b.getDouble(0), b.getDouble(1), ms) }
        else tap(ctx, a.getDouble(0), a.getDouble(1), ms)
    }

    fun delete(ctx: Context, name: String): String {
        val all = macros(ctx); all.remove(name.trim().lowercase()); prefs(ctx).edit().putString("game_macros", all.toString()).apply(); return "OK: macro hata diya"
    }

    /** Full-screen transparent overlay: user game ka button dabata hai, uska jagah (tap / hold / drag) macro ban jaata hai. */
    fun learn(ctx: Context, name: String): String {
        if (!Settings.canDrawOverlays(ctx)) return "ERROR: Display over other apps ON karo"
        val app = ctx.applicationContext
        val key = name.trim().lowercase().ifBlank { return "ERROR: macro ka naam do" }
        ui.post {
            val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val m = metrics(app)
            val tv = object : TextView(app) {
                var sx = 0f; var sy = 0f; var t0 = 0L
                override fun onTouchEvent(e: MotionEvent): Boolean {
                    when (e.action) {
                        MotionEvent.ACTION_DOWN -> { sx = e.rawX; sy = e.rawY; t0 = System.currentTimeMillis() }
                        MotionEvent.ACTION_UP -> {
                            val dur = System.currentTimeMillis() - t0
                            val moved = Math.hypot((e.rawX - sx).toDouble(), (e.rawY - sy).toDouble()) > 60 * m.density
                            val pts = JSONArray().put(JSONArray().put(sx * 100.0 / m.widthPixels).put(sy * 100.0 / m.heightPixels))
                            if (moved) pts.put(JSONArray().put(e.rawX * 100.0 / m.widthPixels).put(e.rawY * 100.0 / m.heightPixels))
                            val all = macros(app)
                            all.put(key, JSONObject().put("pts", pts).put("ms", dur.coerceIn(40, 4000)).put("kind", if (moved) "drag" else if (dur > 400) "hold" else "tap"))
                            prefs(app).edit().putString("game_macros", all.toString()).apply()
                            try { wm.removeView(this) } catch (_: Exception) {}
                            android.widget.Toast.makeText(app, "Macro '$key' save ho gaya", android.widget.Toast.LENGTH_SHORT).show()
                        }
                    }
                    return true
                }
            }.apply {
                text = "'$key' ke liye game ka button dabao\n(tap / dabaye rakho / drag - jaisa chalana hai)"
                setTextColor(Color.WHITE); textSize = 16f; gravity = Gravity.CENTER_HORIZONTAL or Gravity.TOP
                setPadding(40, (80 * m.density).toInt(), 40, 0); setBackgroundColor(0x66000000)
            }
            @Suppress("DEPRECATION")
            val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
            try {
                wm.addView(tv, WindowManager.LayoutParams(-1, -1, type, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT))
            } catch (_: Exception) {}
        }
        return "OK: ab game mein jo button save karna hai wo dabao (screen par instruction dikh rahi hai)"
    }

    // ── screen frame + auto-play (Feature 1) ────────────────
    fun screenshot(ctx: Context): Bitmap? {
        if (Build.VERSION.SDK_INT < 30) return null
        val s = svc() ?: return null
        val latch = CountDownLatch(1); var out: Bitmap? = null
        try {
            s.takeScreenshot(Display.DEFAULT_DISPLAY, ctx.mainExecutor, object : AccessibilityService.TakeScreenshotCallback {
                override fun onSuccess(r: AccessibilityService.ScreenshotResult) {
                    try { out = Bitmap.wrapHardwareBuffer(r.hardwareBuffer, r.colorSpace)?.copy(Bitmap.Config.ARGB_8888, false); r.hardwareBuffer.close() } catch (_: Exception) {}
                    latch.countDown()
                }
                override fun onFailure(errorCode: Int) { latch.countDown() }
            })
            latch.await(4, TimeUnit.SECONDS)
        } catch (_: Exception) {}
        return out
    }

    fun autoplay(ctx: Context, on: Boolean, goal: String): String {
        if (!on) { autoOn = false; return "OK: auto-play band" }
        if (autoOn) return "OK: auto-play pehle se chal raha hai"
        if (svc() == null) return "ERROR: Accessibility ON nahi hai"
        if (Build.VERSION.SDK_INT < 30) return "ERROR: auto-play ke liye Android 11+ chahiye (screenshot)"
        autoOn = true
        val start = System.currentTimeMillis()
        Thread {
            while (autoOn && System.currentTimeMillis() - start < 10 * 60_000) {
                val s = SiyaSession.current
                if (s == null) { autoOn = false; break }
                val bmp = screenshot(ctx)
                if (bmp != null) {
                    s.sendText("AUTO-PLAY goal: $goal. Ye game ka abhi ka frame hai. Sirf ek agla move game_tap / game_swipe / macro_run se chalao (coordinates percent 0-100). Bolna mat, bas tool chalao.")
                    s.sendImage(ImageUtil.jpeg(ImageUtil.scale(bmp, 640), 60))
                }
                Thread.sleep(1800)
            }
            autoOn = false
        }.start()
        return "OK: auto-play shuru (goal: $goal). Maximum 10 minute. Band karne ke liye 'auto-play band karo' bolo."
    }
}
