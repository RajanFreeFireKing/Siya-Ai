package com.siya.ai.service

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.animation.LinearInterpolator
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * Siya ka chhota gol hologram bubble (power button / assistant se aane par dusre app ke upar).
 *
 *  - Sirf ek chhota gol bubble dikhta hai (card / text nahi).
 *  - TAP  -> caption pill khulti / band hoti hai (Siya BAND NAHI hoti).
 *  - DRAG -> bubble kahin bhi khiska sakte ho.
 *  - Siya ko band karna ho to pill ka [X] dabao (ya notification se Mic off / Cancel).
 *
 * Smooth rakhne ke liye: shaders sirf state badalne par bante hain (har frame nahi),
 * bubble ka size canvas.scale se badalta hai, aur animation tabhi chalti hai jab view screen par ho.
 */
class OrbOverlayView(
    context: Context,
    private val onClose: () -> Unit,
    private val onDrag: (dx: Float, dy: Float) -> Unit,
    private val onMicToggle: () -> Boolean = { false },
) : View(context) {

    private val d = resources.displayMetrics.density
    private val bubble = 84 * d                 // bubble ka square size
    private val pillW = 210 * d
    private val slop = ViewConfiguration.get(context).scaledTouchSlop

    private val glow = Paint(Paint.ANTI_ALIAS_FLAG)
    private val orb = Paint(Paint.ANTI_ALIAS_FLAG)
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val pill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val pillBorder = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 1.2f * d }
    private val capUser = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xAAB8E8FF.toInt(); textSize = 11.5f * d }
    private val capSiya = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFFFFFF.toInt(); textSize = 13f * d }
    private val chip = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 9.5f * d; isFakeBoldText = true; letterSpacing = 0.12f }
    private val rect = RectF()
    private val path = Path()
    private val closeRect = RectF()
    private val micRect = RectF()
    private var micOn = true

    private var t = 0f
    private var level = 0.1f
    private var shown = 0.1f
    private var stateName = "waiting"
    private var userCap = ""
    private var siyaCap = ""
    private var expanded = false

    // shader cache (state badalne par hi dobara bante hain)
    private var shaderFor = ""
    private var pa = 0
    private var pb = 0
    private var pdeep = 0

    private fun pal() {
        if (shaderFor == stateName) return
        shaderFor = stateName
        val (a, b, deep) = when (stateName) {
            "listening" -> Triple(0xFFB58CFF.toInt(), 0xFF8B5CF6.toInt(), 0xFF6D35D4.toInt())
            "processing", "thinking", "waiting" -> Triple(0xFFC7A7FF.toInt(), 0xFF9B6BFF.toInt(), 0xFF6D35D4.toInt())
            "speaking" -> Triple(0xFFE0C9FF.toInt(), 0xFF9A65FF.toInt(), 0xFF6D35D4.toInt())
            else -> Triple(0xFF8FB3D9.toInt(), 0xFF3D6A99.toInt(), 0xFF5B5F97.toInt())
        }
        pa = a; pb = b; pdeep = deep
        // unit-circle (radius = 1) par shaders; draw ke waqt canvas.scale lagta hai
        glow.shader = RadialGradient(0f, 0f, 3.1f, intArrayOf((a and 0x00FFFFFF) or 0xA0000000.toInt(), (deep and 0x00FFFFFF) or 0x22000000, 0x00000000), floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP)
        orb.shader = RadialGradient(-0.35f, -0.45f, 1.9f, intArrayOf(a, b, (deep and 0x00FFFFFF) or 0xFF000000.toInt()), floatArrayOf(0f, 0.52f, 1f), Shader.TileMode.CLAMP)
        pill.shader = LinearGradient(0f, 0f, 0f, 120 * d, intArrayOf(0xF0071626.toInt(), 0xF2030A14.toInt()), null, Shader.TileMode.CLAMP)
        pillBorder.color = (a and 0x00FFFFFF) or 0x99000000.toInt()
    }

    private val anim = ValueAnimator.ofFloat(0f, 16f).apply {
        duration = 16000; repeatCount = ValueAnimator.INFINITE; interpolator = LinearInterpolator()
        addUpdateListener { t = it.animatedValue as Float; shown += (level - shown) * 0.25f; invalidate() }
    }

    fun expand() { expanded = true; requestLayout(); invalidate() }

    fun update(event: Map<String, Any?>) {
        when (event["type"]) {
            "state" -> { stateName = event["state"] as? String ?: "idle"; invalidate() }
            "amp" -> level = ((event["v"] as? Double) ?: 0.0).toFloat().coerceIn(0f, 1f)
            "micMuted" -> { micOn = (event["muted"] as? Boolean) != true; invalidate() }
            "caption" -> {
                val who = event["who"] as? String
                val text = (event["text"] as? String).orEmpty()
                if (who == "user") { userCap = text; siyaCap = "" } else siyaCap = text
                if (expanded) invalidate()
            }
        }
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); anim.start() }
    override fun onDetachedFromWindow() { anim.cancel(); super.onDetachedFromWindow() }
    override fun onWindowVisibilityChanged(v: Int) {
        super.onWindowVisibilityChanged(v)
        if (v == VISIBLE) { if (!anim.isStarted) anim.start() else anim.resume() } else anim.pause()
    }

    private fun pillHeight() = 112 * d

    override fun onMeasure(wSpec: Int, hSpec: Int) {
        if (expanded) setMeasuredDimension((bubble + pillW + 6 * d).toInt(), max(bubble, pillHeight()).toInt())
        else setMeasuredDimension(bubble.toInt(), bubble.toInt())
    }

    private fun wrap(text: String, p: TextPaint, width: Int, maxLines: Int): StaticLayout =
        StaticLayout.Builder.obtain(text, 0, text.length, p, width)
            .setMaxLines(maxLines).setEllipsize(android.text.TextUtils.TruncateAt.END).setAlignment(Layout.Alignment.ALIGN_NORMAL).build()

    override fun onDraw(c: Canvas) {
        pal()
        val e = if (stateName == "idle") 0.25f else 1f
        val cx = bubble / 2
        val cy = height / 2f
        val breathe = 0.5f + 0.5f * sin(t * 2 * PI.toFloat() * (0.06f + 0.05f * e))
        val r = (17f + 2.5f * breathe + 6f * shown * e) * d

        // soft glow
        c.save(); c.translate(cx, cy); c.scale(r, r); c.drawCircle(0f, 0f, 3.1f, glow); c.restore()

        // dashed ring
        line.shader = null
        line.strokeWidth = 1.2f * d
        line.color = (pdeep and 0x00FFFFFF) or ((80 + 120 * e).toInt() shl 24)
        val dr = r * 1.7f
        val rot = t * (14f + 40f * e)
        rect.set(cx - dr, cy - dr, cx + dr, cy + dr)
        for (i in 0 until 24) c.drawArc(rect, rot + i * 15f, 8f, false, line)

        when (stateName) {
            "listening" -> for (i in 0 until 2) {
                val ph = (t * 0.8f + i / 2f) % 1f
                line.strokeWidth = (1.8f * (1 - ph) + 0.4f) * d
                line.color = (pa and 0x00FFFFFF) or (((1 - ph) * 0.7f * 255).toInt() shl 24)
                c.drawCircle(cx, cy, r * (1.1f + ph * 0.55f), line)
            }
            "processing", "thinking", "waiting" -> for (i in 0 until 2) {
                val rad = r * (1.3f + i * 0.2f)
                val dir = if (i % 2 == 0) 1f else -1f
                line.strokeWidth = (2.2f - i * 0.6f) * d
                line.color = ((if (i == 1) pdeep else pa) and 0x00FFFFFF) or 0xE6000000.toInt()
                rect.set(cx - rad, cy - rad, cx + rad, cy + rad)
                c.drawArc(rect, dir * t * (110f + i * 60f) + i * 110f, 90f + 30f * i, false, line)
            }
            "speaking" -> {
                line.strokeWidth = 1.8f * d
                line.color = (pa and 0x00FFFFFF) or 0xE6000000.toInt()
                for (i in 0 until 28) {
                    val ang = i * 2 * PI.toFloat() / 28
                    val wob = (sin(i * 0.9f + t * 9f) * 0.5f + 0.5f) * abs(sin(i * 0.37f - t * 5f))
                    val len = r * (0.06f + (0.08f + 0.40f * shown) * wob)
                    c.drawLine(cx + cos(ang) * r * 1.22f, cy + sin(ang) * r * 1.22f, cx + cos(ang) * (r * 1.22f + len), cy + sin(ang) * (r * 1.22f + len), line)
                }
            }
        }

        // core orb
        c.save(); c.translate(cx, cy); c.scale(r, r); c.drawCircle(0f, 0f, 1f, orb); c.restore()
        c.save()
        path.reset(); path.addCircle(cx, cy, r, Path.Direction.CW); c.clipPath(path)
        val sy = cy - r + ((t * (0.35f + 0.5f * e)) % 1f) * r * 2
        fill.shader = LinearGradient(0f, sy - r * 0.12f, 0f, sy + r * 0.12f, intArrayOf(0x00FFFFFF, 0x55FFFFFF, 0x00FFFFFF), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
        c.drawRect(cx - r, sy - r * 0.12f, cx + r, sy + r * 0.12f, fill)
        c.restore()

        // mic glyph
        line.shader = null
        line.strokeWidth = max(1.4f, r * 0.12f); line.color = 0xE6FFFFFF.toInt()
        c.drawLine(cx, cy - r * 0.46f, cx, cy + r * 0.16f, line)
        rect.set(cx - r * 0.59f, cy - r * 0.76f, cx + r * 0.59f, cy + r * 0.69f)
        c.drawArc(rect, 0f, 180f, false, line)
        c.drawLine(cx, cy + r * 0.20f, cx, cy + r * 0.47f, line)
        c.drawLine(cx - r * 0.28f, cy + r * 0.47f, cx + r * 0.28f, cy + r * 0.47f, line)

        if (expanded) drawPill(c)
    }

    private fun drawPill(c: Canvas) {
        val left = bubble + 2 * d
        val top = (height - pillHeight()) / 2
        rect.set(left, top, left + pillW, top + pillHeight())
        c.save(); c.translate(0f, top); c.drawRoundRect(RectF(left, 0f, left + pillW, pillHeight()), 22 * d, 22 * d, pill); c.restore()
        c.drawRoundRect(rect, 22 * d, 22 * d, pillBorder)

        chip.color = (pa and 0x00FFFFFF) or 0xFF000000.toInt()
        c.drawText(when (stateName) { "listening" -> "LISTENING"; "speaking" -> "SPEAKING"; "idle" -> "STANDBY"; else -> "THINKING" }, left + 14 * d, top + 22 * d, chip)
        micRect.set(left + 91 * d, top + 5 * d, left + 151 * d, top + 29 * d)
        fill.shader = null; fill.color = if (micOn) 0xAA087F5B.toInt() else 0xAA475569.toInt()
        c.drawRoundRect(micRect, 8 * d, 8 * d, fill)
        chip.textSize = 8.5f * d
        c.drawText(if (micOn) "MIC ON" else "MIC OFF", micRect.left + 7 * d, micRect.centerY() + 3 * d, chip)
        chip.textSize = 9.5f * d

        // [X] - sirf yahi Siya ko band karta hai
        val cs = 26 * d
        closeRect.set(left + pillW - cs - 6 * d, top + 6 * d, left + pillW - 6 * d, top + 6 * d + cs)
        fill.shader = null; fill.color = 0x33FFFFFF
        c.drawCircle(closeRect.centerX(), closeRect.centerY(), cs / 2, fill)
        line.shader = null; line.strokeWidth = 1.6f * d; line.color = 0xFFFFFFFF.toInt()
        val k = cs * 0.2f
        c.drawLine(closeRect.centerX() - k, closeRect.centerY() - k, closeRect.centerX() + k, closeRect.centerY() + k, line)
        c.drawLine(closeRect.centerX() + k, closeRect.centerY() - k, closeRect.centerX() - k, closeRect.centerY() + k, line)

        val tw = (pillW - 28 * d).toInt()
        var ty = top + 30 * d
        if (userCap.isNotBlank()) {
            val l = wrap(userCap, capUser, tw, 2)
            c.save(); c.translate(left + 14 * d, ty); l.draw(c); c.restore(); ty += l.height + 3 * d
        }
        if (siyaCap.isNotBlank()) {
            val l = wrap(siyaCap, capSiya, tw, 3)
            c.save(); c.translate(left + 14 * d, ty); l.draw(c); c.restore()
        } else if (userCap.isBlank()) {
            c.drawText("Bolo, main sun rahi hoon", left + 14 * d, ty + 12 * d, capUser)
        }
    }

    // ── touch: tap = pill khol/band, drag = khiskao, [X] = Siya band ──
    private var downX = 0f
    private var downY = 0f
    private var lastX = 0f
    private var lastY = 0f
    private var dragging = false

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { downX = e.rawX; downY = e.rawY; lastX = downX; lastY = downY; dragging = false }
            MotionEvent.ACTION_MOVE -> {
                if (!dragging && (abs(e.rawX - downX) > slop || abs(e.rawY - downY) > slop)) dragging = true
                if (dragging) { onDrag(e.rawX - lastX, e.rawY - lastY); lastX = e.rawX; lastY = e.rawY }
            }
            MotionEvent.ACTION_UP -> if (!dragging) {
                if (expanded && closeRect.contains(e.x, e.y)) onClose()
                else if (expanded && micRect.contains(e.x, e.y)) { micOn = onMicToggle(); invalidate() }
                else { expanded = !expanded; requestLayout(); invalidate() }
                performClick()
            }
        }
        return true
    }

    override fun performClick(): Boolean { super.performClick(); return true }
}
