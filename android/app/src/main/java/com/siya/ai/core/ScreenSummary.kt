package com.siya.ai.core

import android.content.Context

/** Feature 12: screen / YouTube video ka 30 second ka nichod (5 bullet). */
object ScreenSummary {
    fun summarize(ctx: Context): String {
        var text = PhoneController.readScreen()
        if (text.startsWith("ERROR")) return text
        if (text.contains("com.google.android.youtube")) {
            // best-effort: description khol ke "Show transcript" dabao taaki poori baat mile
            PhoneController.tap("more"); Thread.sleep(900)
            if (!PhoneController.tap("Show transcript").startsWith("ERROR")) { Thread.sleep(1600); text = PhoneController.readScreen() }
        }
        val bmp = GameControl.screenshot(ctx)
        val jpeg = bmp?.let { com.siya.ai.data.ImageUtil.jpeg(com.siya.ai.data.ImageUtil.scale(it, 900), 70) }
        val out = AiText.generate(ctx, "Neeche phone ki screen ka text hai (aur photo bhi). Isse Hinglish mein 5 chhote bullet points mein summarize karo, itna chhota ki 30 second mein bola jaa sake. " +
            "Agar YouTube video hai aur transcript nahi dikh raha to saaf bolo ki summary sirf title/description par based hai.\n\n" + text.take(6000), jpeg)
        return out ?: "ERROR: summary nahi ban payi (API key / internet check karo)"
    }
}
