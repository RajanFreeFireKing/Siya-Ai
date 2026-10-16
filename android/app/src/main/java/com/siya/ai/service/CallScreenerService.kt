package com.siya.ai.service

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.telecom.Call
import android.telecom.CallScreeningService
import android.telecom.TelecomManager
import com.siya.ai.data.PersonNotes

/**
 * Feature 10 + 6: Call Screening role se aaya number hamesha milta hai.
 *  - spam list wale number turant reject
 *  - save kiye note wale insaan ka alert ("Ramesh calling (isne paise dene hain)")
 *  - "call_screener" ON ho aur number contact mein na ho to: Siya call utha ke caller se poochhti hai "Aap kis kaam se call kar rahe hain?"
 *    aur jawab live text mein bubble ke pill mein dikhta hai.
 *
 * SACH: Android third-party app ko call ki awaaz mein seedha bolne nahi deta. Isliye Siya SPEAKERPHONE par bolti hai aur
 * mic se caller ki awaaz sunti hai - kuch phones par mic call ke time block hota hai, wahan ye kaam nahi karega.
 */
class CallScreenerService : CallScreeningService() {
    override fun onScreenCall(details: Call.Details) {
        val ctx = applicationContext
        val prefs = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)
        val b = CallResponse.Builder()
        if (details.callDirection != Call.Details.DIRECTION_INCOMING) { respondToCall(details, b.build()); return }
        val number = details.handle?.schemeSpecificPart.orEmpty()
        val spam = prefs.getString("spam_numbers", "").orEmpty().split(",").map { it.trim() }.filter { it.length >= 5 }
        if (spam.any { number.endsWith(it) || number.startsWith(it) }) {
            respondToCall(details, b.setDisallowCall(true).setRejectCall(true).build()); return
        }
        val name = contactName(ctx, number)
        try { PersonNotes.alertForCall(ctx, number, name) } catch (_: Exception) {}
        respondToCall(details, b.build())
        if (prefs.getBoolean("call_screener", false) && name.isBlank() && number.isNotBlank()) {
            Handler(Looper.getMainLooper()).postDelayed({ startScreening(ctx) }, 1500)
        }
    }

    private fun contactName(ctx: Context, number: String): String {
        if (number.isBlank()) return ""
        return try {
            val uri = android.net.Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, android.net.Uri.encode(number))
            ctx.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0).orEmpty() else "" }.orEmpty()
        } catch (_: Exception) { "" }
    }

    @Suppress("MissingPermission")
    private fun startScreening(ctx: Context) {
        try {
            ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).edit().putBoolean("screener_active", true).apply()
            (ctx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).acceptRingingCall()
            val am = ctx.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            am.mode = android.media.AudioManager.MODE_IN_CALL
            am.isSpeakerphoneOn = true
            SiyaService.send(ctx, SiyaService.ACTION_START, "screener")
        } catch (_: Exception) {
            ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).edit().putBoolean("screener_active", false).apply()
        }
    }
}
