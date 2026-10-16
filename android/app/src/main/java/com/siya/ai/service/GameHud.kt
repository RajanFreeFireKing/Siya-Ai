package com.siya.ai.service

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.siya.ai.core.GameControl

/**
 * Feature 3: game ke kone mein chhota transparent HUD. Game screen block nahi karta (bahar ka touch game tak jaata hai).
 *  orb -> tap se khulta/band hota hai | timer chip (zone countdown, tap = dobara shuru) | mic chip | macro chips (turant tap, AI ka intezaar nahi)
 */
object GameHud {
    private val ui = Handler(Looper.getMainLooper())
    private var root: LinearLayout? = null
    private var timerView: TextView? = null
    private var left = 0
    private var total = 120
    private val tick = object : Runnable {
        override fun run() {
            if (left > 0) left--
            timerView?.text = "%d:%02d".format(left / 60, left % 60)
            timerView?.setTextColor(if (left in 1..15) Color.parseColor("#FF5252") else Color.WHITE)
            ui.postDelayed(this, 1000)
        }
    }

    fun setTimer(sec: Int) { total = sec.coerceIn(5, 3600); left = total }

    fun show(ctx: Context): String {
        if (root != null) return "OK: HUD pehle se dikh raha hai"
        if (!Settings.canDrawOverlays(ctx)) return "ERROR: Display over other apps ON karo"
        val app = ctx.applicationContext
        ui.post {
            val d = app.resources.displayMetrics.density
            fun chip(t: String, onClick: () -> Unit) = TextView(app).apply {
                text = t; setTextColor(Color.WHITE); textSize = 12f; gravity = Gravity.CENTER
                setPadding((10 * d).toInt(), (6 * d).toInt(), (10 * d).toInt(), (6 * d).toInt())
                background = GradientDrawable().apply { cornerRadius = 20 * d; setColor(0x55000000) }
                setOnClickListener { onClick() }
            }
            val box = LinearLayout(app).apply {
                orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
                background = GradientDrawable().apply { cornerRadius = 26 * d; setColor(0x33000000) }
                setPadding((6 * d).toInt(), (4 * d).toInt(), (6 * d).toInt(), (4 * d).toInt())
            }
            val strip = LinearLayout(app).apply { orientation = LinearLayout.HORIZONTAL; visibility = View.GONE }
            val orb = TextView(app).apply {
                text = "S"; setTextColor(Color.WHITE); textSize = 14f; gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams((38 * d).toInt(), (38 * d).toInt())
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; colors = intArrayOf(0xCCFF5CF2.toInt(), 0xCCFF9A4D.toInt()) }
            }
            val tm = chip("%d:%02d".format(total / 60, total % 60)) { left = total }.also { timerView = it }
            strip.addView(tm)
            strip.addView(chip("\uD83C\uDF99") { SiyaService.send(app, SiyaService.ACTION_START, "hud") })
            GameControl.macroNames(app).take(5).forEach { n -> strip.addView(chip(n) { Thread { GameControl.run(app, n) }.start() }) }
            strip.addView(chip("\u2715") { hide() })
            box.addView(orb); box.addView(strip)
            @Suppress("DEPRECATION")
            val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
            val lp = WindowManager.LayoutParams(-2, -2, type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL, PixelFormat.TRANSLUCENT)
                .apply { gravity = Gravity.TOP or Gravity.START; x = (8 * d).toInt(); y = (90 * d).toInt() }
            val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            var sx = 0f; var sy = 0f; var ox = 0; var oy = 0; var moved = false
            orb.setOnTouchListener { _, e ->
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> { sx = e.rawX; sy = e.rawY; ox = lp.x; oy = lp.y; moved = false }
                    MotionEvent.ACTION_MOVE -> if (Math.abs(e.rawX - sx) > 12 || Math.abs(e.rawY - sy) > 12) {
                        moved = true; lp.x = (ox + e.rawX - sx).toInt(); lp.y = (oy + e.rawY - sy).toInt(); try { wm.updateViewLayout(box, lp) } catch (_: Exception) {}
                    }
                    MotionEvent.ACTION_UP -> if (!moved) strip.visibility = if (strip.visibility == View.GONE) View.VISIBLE else View.GONE
                }
                true
            }
            try { wm.addView(box, lp); root = box; left = total; ui.removeCallbacks(tick); ui.postDelayed(tick, 1000) } catch (_: Exception) {}
        }
        return "OK: gaming HUD chalu. Orb dabao to timer / mic / macro buttons khulenge."
    }

    fun hide(): String {
        ui.post {
            root?.let { try { (it.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it) } catch (_: Exception) {} }
            root = null; timerView = null; ui.removeCallbacks(tick)
        }
        return "OK: HUD band"
    }
}
