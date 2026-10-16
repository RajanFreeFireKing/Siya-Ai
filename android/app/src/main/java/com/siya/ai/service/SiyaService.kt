package com.siya.ai.service

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.siya.ai.R
import com.siya.ai.core.SiyaSession
import com.siya.ai.ui.main.MainActivity

/**
 * Siya ka background ghar. Yahin live session, "Hello Siya" listener aur floating orb chalte hain,
 * isliye app band hone ya doosre app ke upar hone par bhi Siya kaam karti hai.
 */
class SiyaService : Service() {

    companion object {
        private const val TAG = "SIYA_SERVICE"
        const val ACTION_START = "com.siya.ai.action.START"
        const val ACTION_STOP = "com.siya.ai.action.STOP"
        const val ACTION_SYNC = "com.siya.ai.action.SYNC"
        const val ACTION_SHUTDOWN = "com.siya.ai.action.SHUTDOWN"
        const val ACTION_WAKE_DETECTED = "com.siya.ai.action.WAKE_DETECTED"
        /** Notification ka "Mic off" button: sirf mic / session band, Siya taiyaar rehti hai. */
        const val ACTION_MIC_OFF = "com.siya.ai.action.MIC_OFF"
        const val EXTRA_SOURCE = "source"
        private const val CHANNEL = "siya_background_v2"   // naya channel: IMPORTANCE_LOW (purana MIN hone se buttons chhup jaate the)
        private const val NOTIF_ID = 1001

        @Volatile var instance: SiyaService? = null
        @Volatile var eventSink: ((Map<String, Any?>) -> Unit)? = null
        @Volatile var lastState: String = "idle"
        /** App screen par khula hai ya nahi (khula ho to "Hello Siya" listener band rehta hai - mic baar-baar nahi khulta). */
        @Volatile var appVisible: Boolean = false
        /** MainActivity ko state badalne par batane ke liye (screen-on flag ke liye). */
        @Volatile var stateHook: ((String) -> Unit)? = null

        fun hasMic(ctx: Context) =
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

        /** Service ko action bhejo. Mic permission ke bina nahi chalti (Android 14 ki shart). */
        fun send(ctx: Context, action: String, source: String = "app"): Boolean {
            if (!hasMic(ctx)) return false
            return try {
                ContextCompat.startForegroundService(ctx,
                    Intent(ctx, SiyaService::class.java).setAction(action).putExtra(EXTRA_SOURCE, source))
                true
            } catch (e: Exception) { Log.e(TAG, "send: ${e.message}"); false }
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private var session: SiyaSession? = null
    private var wake: WakeEngine? = null
    private var wakeKind = ""
    private var overlay: OrbOverlayView? = null
    private var foregroundOn = false
    private var inCall = false
    private var cpuLock: PowerManager.WakeLock? = null
    private var screenLock: PowerManager.WakeLock? = null

    private val prefs by lazy { getSharedPreferences("siya_prefs", Context.MODE_PRIVATE) }
    private val wakeEnabled get() = prefs.getBoolean("wake_word_enabled", false)

    private val callReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.action) {
                CallMonitorService.ACTION_CALL_ACTIVE -> if (!prefs.getBoolean("screener_active", false)) { inCall = true; session?.pauseForCall(); wake?.stop() }
                ACTION_WAKE_DETECTED -> onWakeWord()
                CallMonitorService.ACTION_CALL_ENDED -> {
                    if (prefs.getBoolean("screener_active", false)) { prefs.edit().putBoolean("screener_active", false).apply(); session?.stop() }
                    inCall = false; session?.resumeAfterCall(); syncWake()
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        val f = IntentFilter().apply {
            addAction(CallMonitorService.ACTION_CALL_ACTIVE)
            addAction(CallMonitorService.ACTION_CALL_ENDED)
            addAction(ACTION_WAKE_DETECTED)
        }
        ContextCompat.registerReceiver(this, callReceiver, f, ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (!hasMic(this) || action == null) { stopSelfSafely(); return START_NOT_STICKY }
        ensureForeground()
        when (action) {
            ACTION_START -> startSession(intent?.getStringExtra(EXTRA_SOURCE) ?: "app")
            ACTION_STOP, ACTION_MIC_OFF -> session?.stop() ?: afterSession()
            ACTION_SYNC -> { syncWake(); if (session?.active != true && wake?.isRunning != true) stopSelfSafely() }
            ACTION_SHUTDOWN -> { session?.stop(); wake?.stop(); stopSelfSafely() }
        }
        return START_NOT_STICKY
    }

    // ── session ───────────────────────────────────────────────
    private fun startSession(source: String) {
        if (inCall) return
        wake?.stop()
        val s = session ?: SiyaSession(this, { m -> emit(m) }, { afterSession() }).also { session = it }
        if (s.active) return
        if (source != "app") showOverlay()
        try { com.siya.ai.core.HabitTracker.onSession(this) } catch (_: Exception) {}
        if (s.start()) {
            holdAwake(true)
            if (source == "screener") {
                main.postDelayed({ overlay?.expand(); session?.sendText("Call screening shuru karo: caller se poochho wo kis kaam se call kar raha hai.") }, 2500)
                // zyada se zyada 2 minute, phir apne aap band
                main.postDelayed({ if (prefs.getBoolean("screener_active", false)) { prefs.edit().putBoolean("screener_active", false).apply(); session?.stop() } }, 120_000)
            }
        } else {
            hideOverlay()
            if (source != "app") android.widget.Toast.makeText(this, "Siya: Settings mein Gemini API Key daalo / mic permission do", android.widget.Toast.LENGTH_LONG).show()
            // API key / permission ki problem: thodi der status dikhne do, phir chhod do
            main.postDelayed({ afterSession() }, 2500)
        }
    }

    /** AI chal rahi ho to CPU + (setting ON ho to) screen band na ho. */
    private fun holdAwake(on: Boolean) {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (on) {
                if (cpuLock?.isHeld != true)
                    cpuLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "siya:session").apply { setReferenceCounted(false); acquire(2 * 60 * 60 * 1000L) }
                if (prefs.getBoolean("keep_screen_on", true) && screenLock?.isHeld != true) {
                    @Suppress("DEPRECATION")
                    screenLock = pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ON_AFTER_RELEASE, "siya:screen")
                        .apply { setReferenceCounted(false); acquire(2 * 60 * 60 * 1000L) }
                }
            } else {
                if (cpuLock?.isHeld == true) cpuLock?.release()
                if (screenLock?.isHeld == true) screenLock?.release()
                cpuLock = null; screenLock = null
            }
        } catch (e: Exception) { Log.e(TAG, "wakelock: ${e.message}") }
    }

    private fun afterSession() {
        holdAwake(false)
        hideOverlay()
        lastState = "idle"
        if (wakeEnabled && !inCall) { syncWake(); updateNotification() }
        else stopSelfSafely()
    }

    private fun syncWake() {
        if (wakeEnabled && session?.active != true && !inCall && !appVisible && hasMic(this)) {
            // 1) Porcupine (key + hey_siya.ppn) 2) Android 13+: ek hi continuous mic stream 3) purana SpeechRecognizer loop
            val kind = when {
                VoskWakeEngine.available(this) -> "vosk"          // free offline (assets/model mila to pehle yahi)
                PorcupineWakeEngine.available(this) -> "ppn"
                StreamingWakeListener.supported(this) && !prefs.getBoolean("wake_stream_broken", false) -> "stream"
                else -> "legacy"
            }
            if (wake != null && wakeKind != kind) { wake?.stop(); wake = null }
            if (wake == null) {
                wakeKind = kind
                wake = when (kind) {
                    "vosk" -> VoskWakeEngine(this) { main.post { onWakeWord() } }
                    "ppn" -> PorcupineWakeEngine(this) { main.post { onWakeWord() } }
                    "stream" -> StreamingWakeListener(this, { main.post { onWakeWord() } }, {
                        prefs.edit().putBoolean("wake_stream_broken", true).apply()
                        main.post { wake = null; syncWake() }
                    })
                    else -> WakeWordListener(this) { onWakeWord() }
                }
            }
            wake?.start()
        } else {
            wake?.stop()
        }
        updateNotification()
    }

    private fun onWakeWord() {
        Log.d(TAG, "Hey Siya detected; opening orb")
        try {
            val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 65)
            tone.startTone(ToneGenerator.TONE_PROP_ACK, 180)
            main.postDelayed({ try { tone.release() } catch (_: Exception) {} }, 300)
        } catch (_: Exception) {}
        startSession("wake")
    }

    private fun emit(m: Map<String, Any?>) {
        if (m["type"] == "state") {
            lastState = m["state"] as? String ?: "idle"
            stateHook?.invoke(lastState)
            if (lastState != "idle" && session?.active == true) holdAwake(true)   // lock ki 2 ghante ki limit refresh
        }
        main.post {
            eventSink?.invoke(m)
            overlay?.update(m)
            if (m["type"] == "state") updateNotification()
        }
    }

    // ── overlay ───────────────────────────────────────────────
    private fun showOverlay() {
        if (overlay != null || !Settings.canDrawOverlays(this)) return
        main.post {
            try {
                val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                val dm = resources.displayMetrics
                lateinit var lp: WindowManager.LayoutParams
                val v = OrbOverlayView(this,
                    onClose = { session?.stop() },     // bubble ka tap Siya band NAHI karta; sirf [X] karta hai
                    onDrag = { dx, dy ->
                        lp.x = (lp.x + dx).toInt().coerceIn(0, dm.widthPixels - (60 * dm.density).toInt())
                        lp.y = (lp.y + dy).toInt().coerceIn(0, dm.heightPixels - (120 * dm.density).toInt())
                        try { overlay?.let { wm.updateViewLayout(it, lp) } } catch (_: Exception) {}
                    })
                @Suppress("DEPRECATION")
                val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else WindowManager.LayoutParams.TYPE_PHONE
                lp = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
                    type,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.START
                    x = dm.widthPixels - (110 * dm.density).toInt()
                    y = (dm.heightPixels * 0.62f).toInt()
                }
                wm.addView(v, lp)
                overlay = v
            } catch (e: Exception) { Log.e(TAG, "overlay: ${e.message}") }
        }
    }

    private fun hideOverlay() {
        main.post {
            overlay?.let {
                try { (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it) } catch (_: Exception) {}
            }
            overlay = null
        }
    }

    // ── foreground notification ───────────────────────────────
    private fun ensureForeground() {
        if (foregroundOn) return
        val n = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= 30)
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            else startForeground(NOTIF_ID, n)
            foregroundOn = true
        } catch (e: Exception) {
            Log.e(TAG, "startForeground: ${e.message}")
            stopSelf()
        }
    }

    private fun updateNotification() {
        if (!foregroundOn) return
        (getSystemService(NotificationManager::class.java)).notify(NOTIF_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "Siya background", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false); setSound(null, null); enableVibration(false) })
        }
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), flags)
        val micOff = PendingIntent.getService(this, 2, Intent(this, SiyaService::class.java).setAction(ACTION_MIC_OFF), flags)
        val micOn = PendingIntent.getService(this, 3,
            Intent(this, SiyaService::class.java).setAction(ACTION_START).putExtra(EXTRA_SOURCE, "app"), flags)
        val cancel = PendingIntent.getService(this, 1, Intent(this, SiyaService::class.java).setAction(ACTION_SHUTDOWN), flags)
        val active = session?.active == true
        val text = when {
            active -> "Siya sun rahi hai"
            wake?.isRunning == true -> "\"Hey Siya\" bolo, main jaag jaungi"
            else -> "Siya taiyaar hai"
        }
        val b = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_siya_notif)
            .setContentTitle(if (com.siya.ai.core.GhostMode.isOn(this)) "Calculator" else "Siya Ai")
            .setContentText(if (com.siya.ai.core.GhostMode.isOn(this)) "Running" else text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        // Mic off / Mic on  +  Cancel: dono buttons notification ke andar hi
        if (active) b.addAction(R.drawable.ic_mic_off, "Mic off", micOff)
        else b.addAction(R.drawable.ic_mic_on, "Mic on", micOn)
        b.addAction(R.drawable.ic_close, "Cancel", cancel)
        return b.build()
    }

    /** User ne app recents se hata di: "Hello Siya" always-on band hai to mic bilkul chhod do. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        if (!wakeEnabled && session?.active != true) { wake?.stop(); stopSelfSafely() }
        super.onTaskRemoved(rootIntent)
    }

    private fun stopSelfSafely() {
        holdAwake(false)
        hideOverlay()
        if (foregroundOn) { stopForeground(STOP_FOREGROUND_REMOVE); foregroundOn = false }
        stopSelf()
    }

    override fun onDestroy() {
        try { unregisterReceiver(callReceiver) } catch (_: Exception) {}
        wake?.stop(); wake = null
        session?.stop(); session = null
        holdAwake(false)
        hideOverlay()
        lastState = "idle"
        instance = null
        super.onDestroy()
    }

    /** MainActivity ke liye */
    fun isSessionActive() = session?.active == true

    /** Settings (API key / awaaz / personality) badalne par naya connection. */
    fun reloadSession() { session?.reload() }
}
