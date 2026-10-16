package com.siya.ai.service

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.siya.ai.core.AiText

/**
 * Notification access: (1) gaana / video control (MediaSession), (2) Feature 9: WhatsApp auto-reply.
 *
 * WhatsApp auto-reply DEFAULT BAND hai ("wa_autoreply"). ON karne par sirf naye personal message (group nahi) ka text
 * Gemini ko bheja jaata hai (aapki API key se) aur reply WhatsApp ke apne "Reply" button se jaata hai.
 * Har sender ko 90 second mein sirf ek reply. Reply ke aakhir mein "(Siya auto-reply)" likha aata hai.
 */
class SiyaNotificationListener : NotificationListenerService() {
    private val lastReply = HashMap<String, Long>()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName != "com.whatsapp" && sbn.packageName != "com.whatsapp.w4b") return
        val prefs = getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("wa_autoreply", false)) return
        val n = sbn.notification
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val ex = n.extras
        if (ex.getBoolean("android.isGroupConversation", false)) return
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty().trim()
        val text = ex.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty().trim()
        if (title.isBlank() || text.isBlank() || title.equals("WhatsApp", true) || text.contains("new messages", true) || text.startsWith("\uD83D\uDCF7") ) return
        val allow = prefs.getString("wa_reply_names", "").orEmpty().split(",").map { it.trim().lowercase() }.filter { it.isNotEmpty() }
        if (allow.isNotEmpty() && allow.none { title.lowercase().contains(it) }) return
        val now = System.currentTimeMillis()
        if (now - (lastReply[title] ?: 0L) < 90_000) return
        val action = (n.actions?.toList().orEmpty() + Notification.WearableExtender(n).actions)
            .firstOrNull { it.remoteInputs?.isNotEmpty() == true } ?: return
        lastReply[title] = now
        val user = prefs.getString("user_name", "Sir").orEmpty()
        Thread {
            val r = AiText.generate(this, "Tum $user ki assistant Siya ho aur unki taraf se WhatsApp par jawab likh rahi ho. " +
                "$title ne message bheja: \"$text\". Chhota (1-2 line), sahi, shaleen jawab likho, usi bhasha mein jisme message hai. " +
                "Koi paisa dene, kisi cheez ka waada karne ya personal jaankari dene ki baat mat likho; zaroorat ho to bolo ki $user thodi der mein khud dekhenge. Sirf reply text do.") ?: return@Thread
            val ri = action.remoteInputs[0]
            val i = Intent(); val b = Bundle()
            b.putCharSequence(ri.resultKey, r.take(300) + " (Siya auto-reply)")
            RemoteInput.addResultsToIntent(action.remoteInputs, i, b)
            try { action.actionIntent.send(this, 0, i) } catch (_: Exception) {}
        }.start()
    }
}
