package com.siya.ai.utils

import kotlin.math.max

/** Adaptive voice gate for the live microphone; ambient mode bypasses this class in SiyaSession. */
class VoiceFocus(private val mode: String) {
    private val margin = when (mode) { "strict" -> 2.5f; "normal" -> 1.75f; else -> 0f }
    private val minLevel = when (mode) { "strict" -> 0.010f; "normal" -> 0.0045f; else -> 0f }
    private val hangoverMs = if (mode == "strict") 520L else 700L
    private var floor = 0.004f
    private var openUntil = 0L
    private val pre = ArrayDeque<ByteArray>()

    /** Input is one PCM chunk. Empty output means background silence is suppressed. */
    fun process(buf: ByteArray, n: Int, level: Float, now: Long): List<ByteArray> {
        if (margin == 0f) return listOf(buf.copyOf(n))
        val bounded = level.coerceIn(0f, 1f)
        floor = if (bounded < floor) floor * 0.72f + bounded * 0.28f
                else floor * 0.9995f + bounded.coerceAtMost(floor * 1.15f) * 0.0005f
        floor = floor.coerceIn(0.0008f, 0.025f)
        val loud = bounded > max(minLevel, floor * margin)
        val chunk = buf.copyOf(n)
        if (loud) {
            val wasClosed = now > openUntil
            openUntil = now + hangoverMs
            if (wasClosed && pre.isNotEmpty()) {
                val out = ArrayList<ByteArray>(pre.size + 1)
                out.addAll(pre)
                out.add(chunk)
                pre.clear()
                return out
            }
            return listOf(chunk)
        }
        if (now <= openUntil) return listOf(chunk)
        pre.addLast(chunk)
        while (pre.size > 6) pre.removeFirst()
        return emptyList()
    }

    fun reset() {
        openUntil = 0L
        pre.clear()
        floor = 0.004f
    }
}
