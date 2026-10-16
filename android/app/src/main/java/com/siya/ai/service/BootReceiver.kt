package com.siya.ai.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.siya.ai.R
import com.siya.ai.ui.main.MainActivity

/**
 * Phone restart ke baad "Hey Siya" wapas chalu.
 * Android 14/15 boot receiver se microphone foreground service start hone nahi deta, isliye:
 *  - jahan allowed hai wahan seedha start,
 *  - warna ek shaant (IMPORTANCE_MIN) notification: ek tap par Siya jaag jaati hai.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("wake_word_enabled", false)) return
        if (Build.VERSION.SDK_INT < 34) {
            try { SiyaService.send(context, SiyaService.ACTION_SYNC); return } catch (_: Exception) {}
        }
        // Android 14+: tap-to-start notification
        val nm = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(
            NotificationChannel("siya_boot", "Siya start", NotificationManager.IMPORTANCE_MIN).apply { setShowBadge(false); setSound(null, null); enableVibration(false) })
        val open = PendingIntent.getActivity(context, 7, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), PendingIntent.FLAG_IMMUTABLE)
        nm.notify(7001, NotificationCompat.Builder(context, "siya_boot")
            .setSmallIcon(R.drawable.ic_siya_notif).setContentTitle("Siya").setContentText("\"Hey Siya\" chalu karne ke liye tap karo")
            .setPriority(NotificationCompat.PRIORITY_MIN).setContentIntent(open).setAutoCancel(true).build())
    }
}
