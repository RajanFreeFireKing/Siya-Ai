package com.siya.ai.utils

object HindiTransliterator {
    // Agar STT engine galat english likhta hai, toh ye usey sudharta hai
    fun transliterate(text: String): String {
        var correctedText = text
        val corrections = mapOf(
            "watsp" to "WhatsApp",
            "winod" to "Vinod",
            "sportify" to "Spotify",
            "ytube" to "YouTube"
        )
        
        for ((wrong, right) in corrections) {
            correctedText = correctedText.replace(wrong, right, ignoreCase = true)
        }
        return correctedText
    }
}
