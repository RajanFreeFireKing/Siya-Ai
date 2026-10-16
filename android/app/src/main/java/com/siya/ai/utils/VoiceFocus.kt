package com.siya.ai.utils

/**
 * User ki awaaz par focus: background ki awaaz (TV, bheed, door ke log) mein jo dheemi hai wo Gemini tak nahi jaati.
 * Idea: noise floor lagatar seekhte rehna; awaaz tabhi "user ki" maani jaati hai jab floor se kaafi upar
 * (aur ek minimum level se upar) ho. Bolne ke baad thodi der gate khula rehta hai (hangover) aur
 * bolna shuru hone se pehle ki ~240 ms audio bhi saath jaati hai, taaki shabd kate nahi.
 */
class VoiceFocus(private val mode: String) {
    // mode: off | normal | strict
    private val margin = when (mode) { "strict" -> 2.8f; "normal" -> 1.9f; else -> 0f }
    private val minLevel = when (mode) { "strict" -> 0.012f; "normal" -> 0.006f; else -> 0f }
    private val hangoverMs = if (mode == "strict") 450L else 650L

    private var floor = 0.006f
    private var openUntil = 0L
    private val pre = ArrayDeque<ByteArray>()      // pre-roll (6 x 40ms)

    /** Ek 40 ms chunk do. Wapas: bhejne wali audio chunks ki list (khaali = gate band, silence bhejo). */
    fun process(buf: ByteArray, n: Int, level: Float, now: Long): List<ByteArray> {
        if (margin == 0f) return listOf(buf.copyOf(n))
        // Floor = lagatar "sabse shaant" level (minimum-tracking): bolne se upar nahi chadhta,
        // isliye dheemi mic wale phone par bhi gate kabhi hamesha band nahi rehta.
        floor = if (level < floor) floor * 0.8f + level * 0.2f else floor * 1.0015f
        floor = floor.coerceIn(0.0015f, 0.02f)
        val loud = level > maxOf(minLevel, floor * margin)
        val chunk = buf.copyOf(n)
        if (loud) {
            val wasClosed = now > openUntil
            openUntil = now + hangoverMs
            if (wasClosed && pre.isNotEmpty()) {
                val out = ArrayList<ByteArray>(pre)
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

    fun reset() { openUntil = 0L; pre.clear() }
}
