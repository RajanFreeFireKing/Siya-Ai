package com.siya.ai.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import com.siya.ai.R
import com.siya.ai.data.SmsLedger

/** Feature 11: SMS aate hi paisa wala SMS ledger mein jodta hai aur chhoti notification deta hai. */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getBoolean("ledger_enabled", true)) return
        val msgs = Telephony.Sms.Intents.getMessagesFromIntent(i) ?: return
        val from = msgs.firstOrNull()?.originatingAddress ?: return
        val text = msgs.joinToString("") { it.messageBody ?: "" }
        val line = SmsLedger.ingest(ctx, from, text) ?: return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel("siya_ledger", "Siya kharcha", NotificationManager.IMPORTANCE_DEFAULT))
        nm.notify(7100 + (System.currentTimeMillis() % 100).toInt(), NotificationCompat.Builder(ctx, "siya_ledger")
            .setSmallIcon(R.drawable.ic_siya_notif).setContentTitle("Siya kharcha").setContentText("$line - kharche mein add ho gaya").setAutoCancel(true).build())
    }
}
