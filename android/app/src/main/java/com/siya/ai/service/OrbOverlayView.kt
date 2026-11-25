package com.siya.ai.service

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
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
 * 3D Celestial Earth & Galaxy Star Hologram Orb (Default Assistant / Floating Bubble).
 * - Shape: 3D Earth / Celestial Planetary Sphere with spherical lighting & latitude meridians.
 * - Galaxy Star Field: 64 swirling 3D cosmic stars and particles with perspective projection.
 * - Dynamic Color Cycle: Colors smoothly transition across vibrant cosmic hues (Cyan, Blue, Violet, Magenta, Gold).
 * - Sound Reactive: Particles accelerate and atmospheric corona pulses with voice energy.
 * - Interactive: Tap toggles caption pill, drag moves anywhere, [X] closes the bubble.
 */
class OrbOverlayView(
    context: Context,
    private val onClose: () -> Unit,
    private val onDrag: (dx: Float, dy: Float) -> Unit,
    private val onMicToggle: () -> Boolean = { false },
) : View(context) {

    private val d = resources.displayMetrics.density
    private val bubble = 88 * d                 // bubble square dimensions
    private val pillW = 210 * d
    private val slop = ViewConfiguration.get(context).scaledTouchSlop

    // Paints
    private val atmospherePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val globePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val meridianPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val starPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val glintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }
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

    // 64-star pre-generated galaxy star field
    private class GalaxyStar(
        val radiusRatio: Float,
        val baseAngle: Float,
        val tiltRad: Float,
        val speed: Float,
        val sizeDp: Float,
        val isGlint: Boolean,
        val hueOffset: Float
    )

    private val galaxyStars = Array(64) { i ->
        val rnd = java.util.Random(i * 192837L + 77L)
        GalaxyStar(
            radiusRatio = 0.14f + rnd.nextFloat() * 0.74f,
            baseAngle = rnd.nextFloat() * 2f * PI.toFloat(),
            tiltRad = (-35f + rnd.nextFloat() * 70f) * PI.toFloat() / 180f,
            speed = (0.22f + rnd.nextFloat() * 0.48f) * if (rnd.nextBoolean()) 1f else -1f,
            sizeDp = 1.3f + rnd.nextFloat() * 2.5f,
            isGlint = i % 4 == 0,
            hueOffset = -40f + rnd.nextFloat() * 80f
        )
    }

    private val anim = ValueAnimator.ofFloat(0f, 16f).apply {
        duration = 16000; repeatCount = ValueAnimator.INFINITE; interpolator = LinearInterpolator()
        addUpdateListener {
            t = it.animatedValue as Float
            shown += (level - shown) * 0.25f
            invalidate()
        }
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
        val cx = bubble / 2f
        val cy = height / 2f
        val e = if (stateName == "idle") 0.25f else 1f
        val breathe = 0.5f + 0.5f * sin(t * 2 * PI.toFloat() * (0.06f + 0.05f * e))
        val r = (19f + 2.2f * breathe + 6f * shown * e) * d

        // 1. Dynamic Smooth Cosmic Hue Rotation (Cyan -> Blue -> Purple -> Magenta -> Gold)
        val baseHue = (t * 24f) % 360f
        val primaryCosmic = Color.HSVToColor(floatArrayOf(baseHue, 0.85f, 1.0f))
        val atmosphericGlow = Color.HSVToColor(floatArrayOf((baseHue + 25f) % 360f, 0.65f, 1.0f))
        val deepSpaceShade = Color.HSVToColor(floatArrayOf((baseHue + 50f) % 360f, 0.95f, 0.16f))
        val coreHaze = Color.HSVToColor(floatArrayOf((baseHue - 25f + 360f) % 360f, 0.75f, 0.95f))

        // 2. Outer Atmospheric Corona & Sound Reactive Plasma Aura
        val coronaRadius = r * (1.30f + 0.25f * shown * e)
        atmospherePaint.shader = RadialGradient(
            cx, cy, coronaRadius,
            intArrayOf(
                (atmosphericGlow and 0x00FFFFFF) or 0x66000000,
                (primaryCosmic and 0x00FFFFFF) or 0x22000000,
                0x00000000
            ),
            floatArrayOf(0.45f, 0.75f, 1.0f),
            Shader.TileMode.CLAMP
        )
        c.drawCircle(cx, cy, coronaRadius, atmospherePaint)

        // 3. Orbiting Galactic Cosmic Dust Ring (tilted 3D celestial orbit)
        line.shader = null
        line.strokeWidth = 1.0f * d
        val ringCount = 20
        val ringRot = t * 18f
        for (i in 0 until ringCount) {
            val ang = (ringRot + i * (360f / ringCount)) * PI.toFloat() / 180f
            val ringDist = r * (1.45f + 0.08f * sin(i * 1.5f))
            val dotX = cx + cos(ang) * ringDist
            val dotY = cy + sin(ang) * ringDist * 0.42f
            val dotDepth = sin(ang)
            val dotAlpha = ((90 + 130 * ((dotDepth + 1f) / 2f))).toInt().coerceIn(0, 255)
            val dotCol = Color.HSVToColor(dotAlpha, floatArrayOf((baseHue + i * 14f) % 360f, 0.75f, 1.0f))
            line.color = dotCol
            c.drawCircle(dotX, dotY, (0.8f + 0.8f * ((dotDepth + 1f) / 2f)) * d, line)
        }

        // 4. 3D Earth / Planet Sphere Base (Spherical Lighting Depth)
        globePaint.shader = RadialGradient(
            cx - r * 0.35f, cy - r * 0.38f, r * 1.6f,
            intArrayOf(
                Color.WHITE,
                atmosphericGlow,
                primaryCosmic,
                deepSpaceShade,
                0xFF020409.toInt()
            ),
            floatArrayOf(0f, 0.15f, 0.45f, 0.82f, 1.0f),
            Shader.TileMode.CLAMP
        )
        c.drawCircle(cx, cy, r, globePaint)

        // 5. Galaxy Stars & Swirling Particles (Clipped strictly inside the Earth sphere)
        c.save()
        path.reset()
        path.addCircle(cx, cy, r, Path.Direction.CW)
        c.clipPath(path)

        // 3D Earth Latitude / Meridian Rings (tilted 23.5 degrees)
        meridianPaint.strokeWidth = 1.0f * d
        meridianPaint.color = (primaryCosmic and 0x00FFFFFF) or 0x40000000
        val earthTilt = 23.5f * PI.toFloat() / 180f
        c.save()
        c.rotate(-23.5f, cx, cy)
        // Equator & Tropics
        rect.set(cx - r * 0.92f, cy - r * 0.15f, cx + r * 0.92f, cy + r * 0.15f)
        c.drawOval(rect, meridianPaint)
        rect.set(cx - r * 0.80f, cy - r * 0.55f, cx + r * 0.80f, cy - r * 0.25f)
        c.drawOval(rect, meridianPaint)
        rect.set(cx - r * 0.80f, cy + r * 0.25f, cx + r * 0.80f, cy + r * 0.55f)
        c.drawOval(rect, meridianPaint)
        // Polar Meridian arc
        rect.set(cx - r * 0.45f, cy - r * 0.95f, cx + r * 0.45f, cy + r * 0.95f)
        c.drawOval(rect, meridianPaint)
        c.restore()

        // 64 Galaxy Stars with 3D Perspective Projection & Dynamic Color Shifting
        val speedMult = 0.9f + level * 2.2f
        for (star in galaxyStars) {
            val ang = star.baseAngle + t * star.speed * speedMult
            val cosA = cos(ang)
            val sinA = sin(ang)
            val rad = star.radiusRatio * r

            // 3D elliptical orbit projection
            val sx = (cosA * cos(star.tiltRad) - sinA * sin(star.tiltRad) * 0.35f) * rad
            val sy = (cosA * sin(star.tiltRad) * 0.55f + sinA * cos(star.tiltRad)) * rad * 0.65f
            val px = cx + sx
            val py = cy + sy
            val depth = sinA // -1.0 (back) to +1.0 (front)

            val depthFrac = (depth + 1f) / 2f
            val starSize = star.sizeDp * d * (0.75f + 0.55f * depthFrac)
            val starAlpha = ((140 + 115 * depthFrac)).toInt().coerceIn(0, 255)
            val starHue = (baseHue + star.hueOffset + 360f) % 360f
            val starColor = Color.HSVToColor(starAlpha, floatArrayOf(starHue, 0.70f, 1.0f))

            // Star glowing halo
            starPaint.color = (starColor and 0x00FFFFFF) or ((starAlpha * 0.45f).toInt() shl 24)
            c.drawCircle(px, py, starSize * 1.5f, starPaint)

            // Star sharp core
            starPaint.color = if (depth > 0.2f) Color.WHITE else starColor
            c.drawCircle(px, py, starSize, starPaint)

            // Sparkling 4-point cross glint for foreground diamond stars
            if (star.isGlint && depth > 0.15f) {
                glintPaint.color = (starColor and 0x00FFFFFF) or 0xCCFFFFFF.toInt()
                glintPaint.strokeWidth = 0.9f * d
                val arm = starSize * 2.0f
                c.drawLine(px - arm, py, px + arm, py, glintPaint)
                c.drawLine(px, py - arm, px, py + arm, glintPaint)
            }
        }

        // Voice energy nebula ripple
        if (stateName == "listening" || stateName == "speaking") {
            val wavePhase = (t * 1.4f) % 1f
            meridianPaint.strokeWidth = (1.5f * (1f - wavePhase) + 0.5f) * d
            meridianPaint.color = (coreHaze and 0x00FFFFFF) or (((1f - wavePhase) * 180).toInt() shl 24)
            c.drawCircle(cx, cy, r * (0.3f + wavePhase * 0.7f), meridianPaint)
        }

        c.restore()

        // 6. 3D Planet Fresnel Atmospheric Edge Rim Glow
        globePaint.shader = null
        globePaint.style = Paint.Style.STROKE
        globePaint.strokeWidth = 1.4f * d
        globePaint.color = (atmosphericGlow and 0x00FFFFFF) or 0xCCFFFFFF.toInt()
        c.drawCircle(cx, cy, r - 0.7f * d, globePaint)
        globePaint.style = Paint.Style.FILL

        // 7. Subtle Central Voice Core (Clean modern mic icon)
        line.shader = null
        line.strokeWidth = max(1.4f, r * 0.11f)
        line.color = 0xEEFFFFFF.toInt()
        c.drawLine(cx, cy - r * 0.40f, cx, cy + r * 0.14f, line)
        rect.set(cx - r * 0.52f, cy - r * 0.68f, cx + r * 0.52f, cy + r * 0.60f)
        c.drawArc(rect, 0f, 180f, false, line)
        c.drawLine(cx, cy + r * 0.16f, cx, cy + r * 0.40f, line)
        c.drawLine(cx - r * 0.24f, cy + r * 0.40f, cx + r * 0.24f, cy + r * 0.40f, line)

        // Pill Caption Card
        if (expanded) drawPill(c, primaryCosmic)
    }

    private fun drawPill(c: Canvas, accentCol: Int) {
        val left = bubble + 2 * d
        val top = (height - pillHeight()) / 2
        rect.set(left, top, left + pillW, top + pillHeight())
        pill.shader = LinearGradient(0f, 0f, 0f, 120 * d, intArrayOf(0xF0071626.toInt(), 0xF2030A14.toInt()), null, Shader.TileMode.CLAMP)
        c.save(); c.translate(0f, top); c.drawRoundRect(RectF(left, 0f, left + pillW, pillHeight()), 22 * d, 22 * d, pill); c.restore()
        pillBorder.color = (accentCol and 0x00FFFFFF) or 0x99000000.toInt()
        c.drawRoundRect(rect, 22 * d, 22 * d, pillBorder)

        chip.color = (accentCol and 0x00FFFFFF) or 0xFF000000.toInt()
        c.drawText(when (stateName) { "listening" -> "LISTENING"; "speaking" -> "SPEAKING"; "idle" -> "STANDBY"; else -> "THINKING" }, left + 14 * d, top + 22 * d, chip)
        micRect.set(left + 91 * d, top + 5 * d, left + 151 * d, top + 29 * d)
        fill.shader = null; fill.color = if (micOn) 0xAA087F5B.toInt() else 0xAA475569.toInt()
        c.drawRoundRect(micRect, 8 * d, 8 * d, fill)
        chip.textSize = 8.5f * d
        c.drawText(if (micOn) "MIC ON" else "MIC OFF", micRect.left + 7 * d, micRect.centerY() + 3 * d, chip)
        chip.textSize = 9.5f * d

        // [X] - sirf yahi Siya/Kiyon bubble ko band karta hai
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
            c.drawText("Bolo, main sun raha hoon", left + 14 * d, ty + 12 * d, capUser)
        }
    }

    // Touch events: tap = toggle pill, drag = move bubble, [X] = close bubble
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
