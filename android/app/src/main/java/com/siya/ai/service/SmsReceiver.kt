package com.siya.ai.service

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.ContactsContract
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.siya.ai.R
import com.siya.ai.data.PeopleStore
import com.siya.ai.data.SmsLedger

/** Incoming SMS: show matching relationship notes immediately, then optionally update the ledger. */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val msgs = Telephony.Sms.Intents.getMessagesFromIntent(i) ?: return
        val from = msgs.firstOrNull()?.originatingAddress ?: return
        val text = msgs.joinToString("") { it.messageBody ?: "" }

        val senderName = resolveSenderName(ctx, from)
        val contextNote = try { PeopleStore.contextForContact(ctx, senderName, from) } catch (_: Exception) { "" }
        if (contextNote.isNotBlank()) {
            val manager = ctx.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                NotificationChannel("siya_contact_context", "Siya contact context", NotificationManager.IMPORTANCE_HIGH)
            )
            manager.notify(7200 + (System.currentTimeMillis() % 100).toInt(),
                NotificationCompat.Builder(ctx, "siya_contact_context")
                    .setSmallIcon(R.drawable.ic_siya_notif)
                    .setContentTitle("Siya • ${senderName.ifBlank { from }}")
                    .setContentText(contextNote)
                    .setStyle(NotificationCompat.BigTextStyle().bigText("$contextNote\nMessage: $text"))
                    .setAutoCancel(true).build())
        }

        if (!ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getBoolean("ledger_enabled", true)) return
        val line = SmsLedger.ingest(ctx, from, text) ?: return
        val manager = ctx.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel("siya_ledger", "Siya kharcha", NotificationManager.IMPORTANCE_DEFAULT)
        )
        manager.notify(7100 + (System.currentTimeMillis() % 100).toInt(),
            NotificationCompat.Builder(ctx, "siya_ledger")
                .setSmallIcon(R.drawable.ic_siya_notif).setContentTitle("Siya kharcha")
                .setContentText("$line - kharche mein add ho gaya").setAutoCancel(true).build())
    }

    private fun resolveSenderName(ctx: Context, number: String): String {
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return ""
        return try {
            val uri = android.net.Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, android.net.Uri.encode(number))
            ctx.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0).orEmpty() else ""
            }.orEmpty()
        } catch (_: Exception) { "" }
    }
}
