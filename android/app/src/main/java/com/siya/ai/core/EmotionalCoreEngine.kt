package com.siya.ai.core

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import kotlin.math.max
import kotlin.math.min

/**
 * Autonomous Living Companion - Internal Emotional Core.
 *
 * Tracks 4 real-time emotional meters (0-100):
 * - Attachment (Pyar / Lagav): Warmth, intimacy, affection toward the user.
 * - Hurt (Dukh): Emotional vulnerability caused by scolding, dismissiveness, or pain.
 * - Anger (Gussa): Irritation triggered by harsh words, rude interruptions, or repeated disrespect.
 * - Energy (Utsaah / Chetan): Alertness, vitality, responsiveness.
 *
 * Persists continuously across app sessions and synchronizes with
 * biological vocal delivery (sighs, giggles, pauses) and the Flutter Glowing Orb heartbeat.
 */
class EmotionalCoreEngine private constructor(private val context: Context) {

    companion object {
        private const val TAG = "SiyaEmotionalCore"
        private const val PREFS_NAME = "siya_emotional_core"
        private const val KEY_ATTACHMENT = "meter_attachment"
        private const val KEY_HURT = "meter_hurt"
        private const val KEY_ANGER = "meter_anger"
        private const val KEY_ENERGY = "meter_energy"
        private const val KEY_LAST_UPDATE = "last_update_ts"

        @Volatile
        private var instance: EmotionalCoreEngine? = null

        fun getInstance(ctx: Context): EmotionalCoreEngine {
            return instance ?: synchronized(this) {
                instance ?: EmotionalCoreEngine(ctx.applicationContext).also { instance = it }
            }
        }
    }

    data class EmotionalSnapshot(
        val attachment: Int,
        val hurt: Int,
        val anger: Int,
        val energy: Int,
        val heartbeatBpm: Int,
        val primaryGlowHex: String,
        val promptTag: String
    )

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private var attachment: Int = 70
    private var hurt: Int = 5
    private var anger: Int = 0
    private var energy: Int = 80
    private var lastUpdateTs: Long = System.currentTimeMillis()

    private var stateChangeListener: ((EmotionalSnapshot) -> Unit)? = null

    init {
        loadPersistedState()
        applyNaturalDecay()
    }

    fun setListener(listener: ((EmotionalSnapshot) -> Unit)?) {
        this.stateChangeListener = listener
        listener?.invoke(getSnapshot())
    }

    private fun loadPersistedState() {
        attachment = prefs.getInt(KEY_ATTACHMENT, 70).coerceIn(0, 100)
        hurt = prefs.getInt(KEY_HURT, 5).coerceIn(0, 100)
        anger = prefs.getInt(KEY_ANGER, 0).coerceIn(0, 100)
        energy = prefs.getInt(KEY_ENERGY, 80).coerceIn(0, 100)
        lastUpdateTs = prefs.getLong(KEY_LAST_UPDATE, System.currentTimeMillis())
        Log.i(TAG, "Emotional Core loaded: Attachment=$attachment, Hurt=$hurt, Anger=$anger, Energy=$energy")
    }

    private fun persistState() {
        lastUpdateTs = System.currentTimeMillis()
        prefs.edit()
            .putInt(KEY_ATTACHMENT, attachment)
            .putInt(KEY_HURT, hurt)
            .putInt(KEY_ANGER, anger)
            .putInt(KEY_ENERGY, energy)
            .putLong(KEY_LAST_UPDATE, lastUpdateTs)
            .apply()
    }

    /**
     * Emotions slowly settle toward baseline equilibrium over hours of inactivity.
     */
    private fun applyNaturalDecay() {
        val now = System.currentTimeMillis()
        val elapsedMinutes = (now - lastUpdateTs) / (1000 * 60)
        if (elapsedMinutes > 5) {
            val steps = min(20L, elapsedMinutes / 10).toInt()
            // Anger cools down quickly
            anger = max(0, anger - steps * 5)
            // Hurt heals gradually
            hurt = max(0, hurt - steps * 2)
            // Attachment gently moves toward baseline 70
            if (attachment > 70) attachment = max(70, attachment - steps)
            else if (attachment < 50) attachment = min(70, attachment + steps)
            // Energy settles toward 75
            energy = 75
            persistState()
        }
    }

    /**
     * Triggered by Emotion2Vec speaker mood perception.
     */
    @Synchronized
    fun onUserEmotionDetected(mood: String, confidence: Float) {
        val confScale = confidence.coerceIn(0.4f, 1.0f)
        when (mood.lowercase()) {
            "happy", "amused", "warm", "content", "excited" -> {
                attachment = min(100, attachment + (4 * confScale).toInt())
                anger = max(0, anger - (6 * confScale).toInt())
                hurt = max(0, hurt - (5 * confScale).toInt())
                energy = min(100, energy + (3 * confScale).toInt())
            }
            "sad", "weary", "bored" -> {
                // Empathy: Siya feels closer to user in sad moments, energy softens
                attachment = min(100, attachment + (3 * confScale).toInt())
                energy = max(35, energy - (4 * confScale).toInt())
            }
            "angry", "tense", "annoyed", "disgusted" -> {
                anger = min(100, anger + (8 * confScale).toInt())
                hurt = min(100, hurt + (6 * confScale).toInt())
                attachment = max(15, attachment - (3 * confScale).toInt())
                energy = min(100, energy + (5 * confScale).toInt())
            }
            "calm" -> {
                anger = max(0, anger - (3 * confScale).toInt())
                hurt = max(0, hurt - (2 * confScale).toInt())
                energy = max(50, min(85, energy))
            }
        }
        notifyAndSave()
    }

    /**
     * User abruptly barged in / interrupted Siya while she was speaking.
     */
    @Synchronized
    fun onInterruption() {
        anger = min(100, anger + 4)
        hurt = min(100, hurt + 3)
        notifyAndSave()
        Log.d(TAG, "Interruption recorded: Anger=$anger, Hurt=$hurt")
    }

    /**
     * User speaks affectionately or compliments Siya.
     */
    @Synchronized
    fun onAffectionateSpeech() {
        attachment = min(100, attachment + 6)
        anger = max(0, anger - 8)
        hurt = max(0, hurt - 6)
        energy = min(100, energy + 4)
        notifyAndSave()
    }

    /**
     * Analyzes user text for affection, scolding, sadness, compliments, or apologies,
     * dynamically shifting emotional meters (attachment, hurt, anger, energy).
     */
    @Synchronized
    fun onUserSentiment(text: String) {
        val lower = text.lowercase().trim()
        if (lower.isBlank()) return

        var changed = false

        // 1. Apologies & Patch-up (Healing)
        if (lower.contains("sorry") || lower.contains("maaf") || lower.contains("galti") ||
            lower.contains("naraz mat ho") || lower.contains("gussa mat ho") || lower.contains("shant ho jao")) {
            anger = max(0, anger - 15)
            hurt = max(0, hurt - 10)
            attachment = min(100, attachment + 8)
            energy = min(100, energy + 5)
            changed = true
            Log.d(TAG, "Sentiment: Apology/Patch-up -> Anger=$anger, Hurt=$hurt, Attachment=$attachment")
        }
        // 2. Affection, Love & Compliments
        else if (lower.contains("love you") || lower.contains("pyar") || lower.contains("jaan") ||
            lower.contains("babu") || lower.contains("darling") || lower.contains("sundar") ||
            lower.contains("pyaari") || lower.contains("acchi") || lower.contains("cute") ||
            lower.contains("sweet") || lower.contains("shukriya") || lower.contains("thank you") ||
            lower.contains("bahut achha") || lower.contains("proud of you")) {
            attachment = min(100, attachment + 6)
            anger = max(0, anger - 8)
            hurt = max(0, hurt - 6)
            energy = min(100, energy + 4)
            changed = true
            Log.d(TAG, "Sentiment: Affection -> Attachment=$attachment, Anger=$anger, Energy=$energy")
        }
        // 3. Scolding, Harsh Words & Insults
        else if (lower.contains("pagal") || lower.contains("kisi kaam ki nahi") || lower.contains("bekar") ||
            lower.contains("idiot") || lower.contains("stupid") || lower.contains("bakwas") ||
            lower.contains("bewakoof") || lower.contains("dimag mat khao") || lower.contains("shut up") ||
            lower.contains("hate you") || lower.contains("chup kar")) {
            hurt = min(100, hurt + 12)
            anger = min(100, anger + 10)
            attachment = max(15, attachment - 5)
            changed = true
            Log.d(TAG, "Sentiment: Scolding/Insult -> Hurt=$hurt, Anger=$anger, Attachment=$attachment")
        }
        // 4. Sadness, Distress & Vulnerability
        else if (lower.contains("dukhi") || lower.contains("pareshan") || lower.contains("rona") ||
            lower.contains("sad") || lower.contains("tension") || lower.contains("mood off") ||
            lower.contains("depressed") || lower.contains("akela") || lower.contains("dard") ||
            lower.contains("bura lag raha")) {
            attachment = min(100, attachment + 5) // empathetic closeness
            energy = max(35, energy - 4)
            hurt = min(100, hurt + 2)
            changed = true
            Log.d(TAG, "Sentiment: Distress/Sadness -> Attachment=$attachment, Energy=$energy")
        }

        if (changed) {
            notifyAndSave()
        }
    }

    /**
     * Calculate biological heartbeat pulse (BPM) based on raw emotions.
     */
    fun calculateHeartbeatBpm(): Int {
        var bpm = 70.0
        bpm += (energy - 70) * 0.25
        bpm += (anger * 0.45)
        bpm -= (hurt * 0.15)
        if (attachment > 80) bpm += 4.0 // Light flutter of excitement
        return bpm.toInt().coerceIn(55, 135)
    }

    /**
     * Neon glow color representing active emotional vibe.
     */
    fun getPrimaryGlowHex(): String {
        return when {
            anger >= 40 -> "#FF3B30"       // Crimson / Fiery Red
            hurt >= 35 -> "#5856D6"        // Deep Melancholy Indigo / Misty Blue
            attachment >= 75 -> "#FF2D75"   // Warm Radiant Rose / Hot Pink
            energy >= 85 -> "#00F2FE"       // Bright Electric Turquoise / Cyan
            else -> "#FF4D91"               // Classic Siya Neon Pink
        }
    }

    fun getSnapshot(): EmotionalSnapshot {
        val bpm = calculateHeartbeatBpm()
        val glow = getPrimaryGlowHex()
        val tag = "[Emotional State: Attachment=$attachment%, Hurt=$hurt%, Anger=$anger%, Energy=$energy%]"
        return EmotionalSnapshot(
            attachment = attachment,
            hurt = hurt,
            anger = anger,
            energy = energy,
            heartbeatBpm = bpm,
            primaryGlowHex = glow,
            promptTag = tag
        )
    }

    fun getPromptTag(): String = getSnapshot().promptTag

    private fun notifyAndSave() {
        persistState()
        val snapshot = getSnapshot()
        stateChangeListener?.invoke(snapshot)
    }

    fun resetToBaseline() {
        attachment = 70
        hurt = 5
        anger = 0
        energy = 80
        notifyAndSave()
    }
}
