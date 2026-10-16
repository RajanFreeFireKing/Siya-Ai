package com.siya.ai.ui.widget

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Dusre apps ke upar tairne wali window: header pakad kar kahin bhi khiskao, neeche-right ke grip se
 * chhota / bada karo, (–) se chhota karo, (⛶) se poori screen. Browser, map aur call popup sab yahi use karte hain.
 */
class FloatingWindow(
    private val ctx: Context,
    titleText: String,
    private val content: View,
    private val widthFrac: Float = 0.94f,
    private val heightFrac: Float = 0.5f,
    private val onClose: () -> Unit = {},
    private val onFull: (() -> Unit)? = null,
    private val headerExtra: List<View> = emptyList(),
) {
    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val dm = ctx.resources.displayMetrics
    private val d = dm.density
    private val ui = Handler(Looper.getMainLooper())

    private lateinit var root: FocusFrame
    private lateinit var lp: WindowManager.LayoutParams
    private var body: FrameLayout? = null
    val title = TextView(ctx).apply {
        setTextColor(0xFFFFFFFF.toInt()); textSize = 13f; maxLines = 1; text = titleText
        ellipsize = android.text.TextUtils.TruncateAt.END
    }
    var shown = false
        private set
    private var minimized = false
    private var savedH = 0
    private val minW = (170 * d).toInt()
    private val minH = (130 * d).toInt()

    /** Touch hone par keyboard ke liye focus lo, bahar touch hone par wapas chhod do. */
    private inner class FocusFrame(c: Context) : LinearLayout(c) {
        override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
            if (ev.action == MotionEvent.ACTION_DOWN) requestImeFocus(true)
            else if (ev.action == MotionEvent.ACTION_OUTSIDE) requestImeFocus(false)
            return super.dispatchTouchEvent(ev)
        }
    }

    private fun requestImeFocus(on: Boolean) {
        if (!shown) return
        val has = lp.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE != 0
        if (on == !has) return
        lp.flags = if (on) lp.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
        else lp.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        try { wm.updateViewLayout(root, lp) } catch (_: Exception) {}
    }

    private fun tv(res: Int, onClick: () -> Unit) = android.widget.ImageView(ctx).apply {
        setImageResource(res); setColorFilter(0xFF3EE6FF.toInt())
        setPadding((8 * d).toInt(), (7 * d).toInt(), (8 * d).toInt(), (7 * d).toInt())
        layoutParams = LinearLayout.LayoutParams((36 * d).toInt(), (34 * d).toInt())
        setOnClickListener { onClick() }
    }

    fun show(): Boolean {
        if (shown) return true
        if (!Settings.canDrawOverlays(ctx)) return false
        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(0xFF0B2338.toInt(), 0xFF140F33.toInt()))
            setPadding((14 * d).toInt(), (3 * d).toInt(), (2 * d).toInt(), (3 * d).toInt())
            addView(title, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            headerExtra.forEach { addView(it) }
            addView(tv(com.siya.ai.R.drawable.ic_br_min) { toggleMinimize() })
            if (onFull != null) addView(tv(com.siya.ai.R.drawable.ic_br_expand) { onFull.invoke() })
            addView(tv(com.siya.ai.R.drawable.ic_br_close) { close() })
        }
        val grip = TextView(ctx).apply {
            text = "\u25E2"; setTextColor(0xFF3EE6FF.toInt()); textSize = 22f; gravity = Gravity.CENTER
            setBackgroundColor(0x00000000)
        }
        val b = FrameLayout(ctx)
        (content.parent as? ViewGroup)?.removeView(content)
        b.addView(content, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        b.addView(grip, FrameLayout.LayoutParams((40 * d).toInt(), (40 * d).toInt(), Gravity.BOTTOM or Gravity.END))
        body = b

        root = FocusFrame(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(0xFF071826.toInt()); cornerRadius = 18 * d; setStroke((1.5f * d).toInt(), 0xAA22D3EE.toInt())
            }
            clipToOutline = true
            addView(header, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(b, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        }
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
        lp = WindowManager.LayoutParams(
            (dm.widthPixels * widthFrac).toInt(), (dm.heightPixels * heightFrac).toInt(), type,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (dm.widthPixels - width) / 2
            y = (80 * d).toInt()
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }

        // header pakad kar khiskao
        var sx = 0f; var sy = 0f; var ox = 0; var oy = 0
        header.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { sx = e.rawX; sy = e.rawY; ox = lp.x; oy = lp.y }
                MotionEvent.ACTION_MOVE -> {
                    lp.x = (ox + (e.rawX - sx)).toInt().coerceIn(-lp.width + (80 * d).toInt(), dm.widthPixels - (80 * d).toInt())
                    lp.y = (oy + (e.rawY - sy)).toInt().coerceIn(0, dm.heightPixels - (60 * d).toInt())
                    try { wm.updateViewLayout(root, lp) } catch (_: Exception) {}
                }
            }
            true
        }
        // grip se chhota / bada
        var gx = 0f; var gy = 0f; var ow = 0; var oh = 0
        grip.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { gx = e.rawX; gy = e.rawY; ow = lp.width; oh = lp.height }
                MotionEvent.ACTION_MOVE -> {
                    lp.width = (ow + (e.rawX - gx)).toInt().coerceIn(minW, dm.widthPixels - lp.x.coerceAtLeast(0) + (40 * d).toInt())
                    lp.height = (oh + (e.rawY - gy)).toInt().coerceIn(minH, dm.heightPixels)
                    minimized = false
                    try { wm.updateViewLayout(root, lp) } catch (_: Exception) {}
                }
            }
            true
        }
        return try {
            wm.addView(root, lp); shown = true; true
        } catch (_: Exception) { false }
    }

    private fun toggleMinimize() {
        if (!shown) return
        if (!minimized) { savedH = lp.height; lp.height = (44 * d).toInt(); minimized = true }
        else { lp.height = savedH.coerceAtLeast(minH); minimized = false }
        try { wm.updateViewLayout(root, lp) } catch (_: Exception) {}
    }

    /** "small", "big", "full", "min", "restore" */
    fun resize(mode: String) {
        if (!shown) return
        minimized = false
        when (mode) {
            "small" -> { lp.width = (dm.widthPixels * 0.6f).toInt(); lp.height = (dm.heightPixels * 0.28f).toInt() }
            "big" -> { lp.width = (dm.widthPixels * 0.98f).toInt(); lp.height = (dm.heightPixels * 0.8f).toInt(); lp.x = (dm.widthPixels - lp.width) / 2; lp.y = (40 * d).toInt() }
            "min" -> { savedH = lp.height; lp.height = (44 * d).toInt(); minimized = true }
            else -> { lp.width = (dm.widthPixels * widthFrac).toInt(); lp.height = (dm.heightPixels * heightFrac).toInt() }
        }
        try { wm.updateViewLayout(root, lp) } catch (_: Exception) {}
    }

    /** Window ko screen par kisi jagah le jao: top / bottom / left / right / center. */
    fun moveTo(where: String) {
        if (!shown) return
        when (where) {
            "top" -> lp.y = (40 * d).toInt()
            "bottom" -> lp.y = (dm.heightPixels - lp.height - 60 * d).toInt().coerceAtLeast(0)
            "left" -> lp.x = 0
            "right" -> lp.x = (dm.widthPixels - lp.width).coerceAtLeast(0)
            else -> { lp.x = (dm.widthPixels - lp.width) / 2; lp.y = (dm.heightPixels - lp.height) / 2 }
        }
        try { wm.updateViewLayout(root, lp) } catch (_: Exception) {}
    }

    fun setTitle(t: String) { title.text = t }

    /** Content view wapas do (full screen par jaate waqt). */
    fun detachContent(): View {
        body?.removeView(content)
        return content
    }

    fun hide() {
        if (!shown) return
        try { wm.removeView(root) } catch (_: Exception) {}
        shown = false
    }

    fun close() { hide(); onClose() }

    companion object {
        private var candidates: FloatingWindow? = null

        /** Numbers ki list, tap karne par callback. */
        fun showCandidates(ctx: Context, title: String, items: List<Pair<String, String>>, onPick: (String) -> Unit) {
            val app = ctx.applicationContext
            Handler(Looper.getMainLooper()).post {
                candidates?.hide()
                val d = app.resources.displayMetrics.density
                val list = LinearLayout(app).apply { orientation = LinearLayout.VERTICAL }
                items.forEachIndexed { i, (name, number) ->
                    list.addView(TextView(app).apply {
                        text = "${i + 1}.  $name\n      $number"
                        setTextColor(0xFFFFFFFF.toInt()); textSize = 16f
                        setPadding((16 * d).toInt(), (12 * d).toInt(), (16 * d).toInt(), (12 * d).toInt())
                        setBackgroundColor(if (i % 2 == 0) 0xFF0B2236.toInt() else 0xFF08192A.toInt())
                        setOnClickListener { candidates?.close(); onPick(number) }
                    })
                }
                val sv = ScrollView(app).apply { addView(list) }
                val w = FloatingWindow(app, title, sv, 0.92f, 0.4f, onClose = { candidates = null })
                candidates = w
                w.show()
            }
        }
    }
}
