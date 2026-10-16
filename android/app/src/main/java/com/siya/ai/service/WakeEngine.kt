package com.siya.ai.service

/** "Hey Siya" sunne wale engines ka common roop (Porcupine ya SpeechRecognizer fallback). */
interface WakeEngine {
    val isRunning: Boolean
    fun start()
    fun stop()
}
