package com.siya.ai.service

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.siya.ai.R
import com.siya.ai.data.PeopleStore
import java.util.concurrent.Executors

/**
 * FIXED CallMonitorService:
 * - Uses TelephonyCallback (API 31+) with PhoneStateListener fallback
 * - Proper call detect + launch CallAssistantActivity
 * - Contact name lookup
 * - Double-launch prevention via timer
 */
class CallMonitorService : Service() {

    private var telephonyManager: TelephonyManager? = null
    private var legacyListener: PhoneStateListener? = null
    private var modernCallback: Any? = null  // TelephonyCallback for API 31+
    private var lastRingTime = 0L
    private var lastCallState = TelephonyManager.CALL_STATE_IDLE

    companion object {
        var isRunning = false
        const val ACTION_CALL_ACTIVE  = "com.siya.ai.CALL_ACTIVE"
        const val ACTION_CALL_ENDED   = "com.siya.ai.CALL_ENDED"
        const val ACTION_CALL_RINGING = "com.siya.ai.CALL_RINGING"
        private const val TAG = "SIYA_CALL"
        private const val DEBOUNCE_MS = 4000L
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        startForegroundCompat()
        // Call detect user ne ON nahi kiya to kuch bhi track nahi karte: turant band.
        if (!getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getBoolean("call_detect_enabled", false)) {
            stopForeground(true); stopSelf(); return
        }
        setupPhoneListener()
        Log.d(TAG, "CallMonitorService started (API ${Build.VERSION.SDK_INT})")
    }

    @SuppressLint("MissingPermission")
    private fun setupPhoneListener() {
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Modern API 31+ TelephonyCallback
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    handleCallState(state, null)
                }
            }
            modernCallback = callback
            try {
                telephonyManager?.registerTelephonyCallback(
                    Executors.newSingleThreadExecutor(), callback
                )
                Log.d(TAG, "Using modern TelephonyCallback")
            } catch (e: Exception) {
                Log.e(TAG, "TelephonyCallback failed: ${e.message}")
                setupLegacyListener()
            }
        } else {
            setupLegacyListener()
        }
    }

    @Suppress("DEPRECATION")
    private fun setupLegacyListener() {
        Log.d(TAG, "Using legacy PhoneStateListener")
        legacyListener = object : PhoneStateListener() {
            @Deprecated("Deprecated in Java")
            override fun onCallStateChanged(state: Int, incomingNumber: String?) {
                handleCallState(state, incomingNumber)
            }
        }
        telephonyManager?.listen(legacyListener, PhoneStateListener.LISTEN_CALL_STATE)
    }

    private fun handleCallState(state: Int, rawNumber: String?) {
        Log.d(TAG, "Call state: $state (prev: $lastCallState), number: $rawNumber")

        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                if (lastCallState != TelephonyManager.CALL_STATE_RINGING) {
                    val now = System.currentTimeMillis()
                    if (now - lastRingTime > DEBOUNCE_MS) {
                        lastRingTime = now
                        lastCallState = state
                        Log.d(TAG, "RINGING → launching SIYA call UI")
                        handleIncomingCall(rawNumber, false)
                    }
                }
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                lastCallState = state
                val intent = Intent(ACTION_CALL_ACTIVE).apply { setPackage(packageName) }
                sendBroadcast(intent)
                Log.d(TAG, "OFFHOOK → SIYA paused")
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                lastCallState = state
                val intent = Intent(ACTION_CALL_ENDED).apply { setPackage(packageName) }
                sendBroadcast(intent)
                Log.d(TAG, "IDLE → SIYA resuming")
            }
        }
    }

    private fun handleIncomingCall(rawNumber: String?, isWhatsAppCall: Boolean) {
        val prefs = getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("call_detect_enabled", false)) return

        if (checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "READ_PHONE_STATE not granted")
            return
        }

        val callerName = resolveCallerName(rawNumber)
        val contactContext = try { PeopleStore.contextForContact(this, callerName, rawNumber.orEmpty()) } catch (_: Exception) { "" }
        val userName   = prefs.getString("user_name", "Sir") ?: "Sir"
        val personality= prefs.getString("personality_mode", "gf") ?: "gf"

        Log.d(TAG, "Caller: '$callerName' (raw: $rawNumber)")

        val intent = Intent(this, com.siya.ai.ui.main.CallAssistantActivity::class.java).apply {
            putExtra("CALLER_NAME", callerName)
            putExtra("PHONE_NUMBER", rawNumber ?: "")
            putExtra("USER_NAME", userName)
            putExtra("PERSONALITY", personality)
            putExtra("CONTACT_CONTEXT", contactContext)
            putExtra("IS_WHATSAPP_CALL", isWhatsAppCall)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        try { startActivity(intent) } catch (e: Exception) { Log.e(TAG, "Launch failed: ${e.message}") }
    }

    private fun resolveCallerName(number: String?): String {
        if (number.isNullOrEmpty()) return "Unknown Caller"
        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return "Unknown Caller"
        val clean = number.replace(" ","").replace("-","").replace("(","").replace(")","")
        return try {
            val uri = android.net.Uri.withAppendedPath(
                android.provider.ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                android.net.Uri.encode(clean)
            )
            contentResolver.query(uri, arrayOf(android.provider.ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0).ifBlank { "Unknown Caller" } else "Unknown Caller"
            } ?: "Unknown Caller"
        } catch (e: Exception) { "Unknown Caller" }
    }

    // ── Foreground ─────────────────────────────────────────────
    private fun startForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("call_monitor_channel", "SIYA Call Monitor", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(ch)
        }
        val notif = NotificationCompat.Builder(this, "call_monitor_channel")
            .setContentTitle("SIYA Call Monitor")
            .setContentText("Incoming calls detect ho rahe hain")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= 34)
            startForeground(1002, notif, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else
            startForeground(1002, notif)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()   // startForegroundService ke baad 5 sec mein zaroori
        if (!getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getBoolean("call_detect_enabled", false)) {
            stopForeground(true); stopSelf(); return START_NOT_STICKY
        }
        return START_STICKY
    }
    override fun onBind(intent: Intent?): IBinder? = null

    @Suppress("DEPRECATION")
    override fun onDestroy() {
        isRunning = false
        if (telephonyManager == null) { super.onDestroy(); return }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (modernCallback as? TelephonyCallback)?.let {
                try { telephonyManager?.unregisterTelephonyCallback(it) } catch (_: Exception) {}
            }
        } else {
            telephonyManager?.listen(legacyListener, PhoneStateListener.LISTEN_NONE)
        }
        Log.d(TAG, "CallMonitorService destroyed")
        super.onDestroy()
    }
}