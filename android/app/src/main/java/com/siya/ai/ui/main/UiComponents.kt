package com.siya.ai.ui.main

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.sin
import kotlin.math.abs

// ─── WaveformView ────────────────────────────────────────────────────────────
class WaveformView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private var amplitude = 0f
    private var phase = 0f
    private var isAnimating = false

    private val waveAnimator = ValueAnimator.ofFloat(0f, (2 * Math.PI).toFloat()).apply {
        duration = 800
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            phase = it.animatedValue as Float
            invalidate()
        }
    }

    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FF1744")
        style = Paint.Style.FILL
    }

    private val barCount = 20
    private val barHeights = FloatArray(barCount) { 0.1f }
    private var targetHeights = FloatArray(barCount) { 0.1f }

    fun startAnimation() {
        isAnimating = true
        waveAnimator.start()
    }

    fun stopAnimation() {
        isAnimating = false
        waveAnimator.cancel()
        amplitude = 0f
        invalidate()
    }

    fun setAmplitude(rms: Float) {
        amplitude = ((rms + 10f) / 20f).coerceIn(0f, 1f)
        updateBarHeights()
    }

    private fun updateBarHeights() {
        for (i in 0 until barCount) {
            val wave = sin(i * 0.5f + phase)
            targetHeights[i] = (0.1f + amplitude * 0.9f * abs(wave.toFloat()))
                .coerceIn(0.05f, 1f)
        }
    }

    override fun onDraw(canvas: Canvas) {
        if (!isAnimating) return
        val w = width.toFloat()
        val h = height.toFloat()
        val barWidth = w / (barCount * 2f)
        val spacing = barWidth

        for (i in 0 until barCount) {
            barHeights[i] += (targetHeights[i] - barHeights[i]) * 0.3f
            val barH = h * barHeights[i]
            val left = i * (barWidth + spacing) + spacing / 2
            val top = (h - barH) / 2
            val right = left + barWidth
            val bottom = top + barH

            val alpha = (180 + (75 * barHeights[i])).toInt().coerceIn(0, 255)
            barPaint.color = Color.argb(alpha, 255, 23, 68)
            canvas.drawRoundRect(left, top, right, bottom, 4f, 4f, barPaint)
        }
    }
}
