package com.siya.ai.ui.main

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.ContactsContract
import android.provider.Settings
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.siya.ai.browser.AiBrowser
import com.siya.ai.core.FileTools
import com.siya.ai.core.MediaTools
import com.siya.ai.core.PhoneController
import com.siya.ai.data.FaceSearch
import com.siya.ai.data.LocationHelper
import com.siya.ai.data.MediaHelper
import com.siya.ai.data.PeopleStore
import com.siya.ai.memory.MemoryStore
import com.siya.ai.service.PorcupineWakeEngine
import com.siya.ai.security.BiometricManager
import com.siya.ai.security.SecuritySettingsActivity
import com.siya.ai.service.AccessibilityHelperService
import com.siya.ai.service.CallMonitorService
import com.siya.ai.service.SiyaDeviceAdminReceiver
import com.siya.ai.service.SiyaService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter UI host. Yahan sirf bridge hai: logic SiyaService / SiyaSession / PhoneController / MemoryStore mein hai.
 * MethodChannel "siya/engine", EventChannel "siya/events".
 */
class MainActivity : FlutterFragmentActivity() {

    private val ui = Handler(Looper.getMainLooper())
    private var pendingContact: MethodChannel.Result? = null
    private var pendingPermissions: MethodChannel.Result? = null

    private val prefs by lazy { getSharedPreferences("siya_prefs", Context.MODE_PRIVATE) }
    private val adminComponent by lazy { ComponentName(this, SiyaDeviceAdminReceiver::class.java) }
    private val dpm by lazy { getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager }

    private val contactPicker = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val pending = pendingContact
        pendingContact = null
        val uri = result.data?.data
        if (result.resultCode != Activity.RESULT_OK || uri == null) { pending?.success(null); return@registerForActivityResult }
        var out: Map<String, String>? = null
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val n = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val p = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                out = mapOf(
                    "name" to (if (n >= 0) c.getString(n) ?: "" else ""),
                    "number" to (if (p >= 0) (c.getString(p) ?: "").replace(" ", "") else "")
                )
            }
        }
        pending?.success(out)
    }

    private var pendingPick: MethodChannel.Result? = null
    private val mediaPicker = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        val r = pendingPick
        pendingPick = null
        if (uri == null) { r?.success(null); return@registerForActivityResult }
        Thread {
            val path = MediaHelper.copyIn(this, uri.toString(), "picked", "pick_${System.currentTimeMillis()}")
            ui.post { r?.success(path) }
        }.start()
    }

    private val allPermissions: Array<String> by lazy {
        val l = arrayListOf(
            Manifest.permission.RECORD_AUDIO, Manifest.permission.READ_CONTACTS,
            Manifest.permission.WRITE_CONTACTS, Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG, Manifest.permission.CALL_PHONE,
            Manifest.permission.SEND_SMS, Manifest.permission.ANSWER_PHONE_CALLS,
            Manifest.permission.CAMERA, Manifest.permission.MODIFY_AUDIO_SETTINGS
        )
        l.add(Manifest.permission.ACCESS_FINE_LOCATION); l.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        l.add(Manifest.permission.RECEIVE_SMS); l.add(Manifest.permission.READ_SMS)   // UPI kharcha ledger
        if (Build.VERSION.SDK_INT >= 31) l.add(Manifest.permission.BLUETOOTH_CONNECT)   // Bluetooth headset se command ke liye
        if (Build.VERSION.SDK_INT >= 33) {
            l.add(0, Manifest.permission.POST_NOTIFICATIONS)
            l.add(Manifest.permission.READ_MEDIA_IMAGES); l.add(Manifest.permission.READ_MEDIA_VIDEO)
        } else l.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        l.toTypedArray()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true); setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
    }

    /** Screen tabhi on rakho jab AI chal rahi ho (aur setting ON ho); AI band to normal screen timeout. */
    private fun applyKeepAwake(state: String) {
        val on = state != "idle" && prefs.getBoolean("keep_screen_on", true)
        runOnUiThread {
            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onResume() {
        super.onResume()
        SiyaService.appVisible = true
        SiyaService.stateHook = { applyKeepAwake(it) }
        applyKeepAwake(SiyaService.lastState)
        // App khula hai: background "Hello Siya" mic chhod de (baar-baar khulna-band hona band)
        if (SiyaService.instance != null) SiyaService.send(this, SiyaService.ACTION_SYNC)
    }

    override fun onPause() {
        SiyaService.appVisible = false
        SiyaService.stateHook = null
        if (prefs.getBoolean("wake_word_enabled", false) || SiyaService.instance != null)
            SiyaService.send(this, SiyaService.ACTION_SYNC)
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "siya/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                SiyaService.eventSink = { m -> events?.success(m) }
                events?.success(mapOf("type" to "state", "state" to SiyaService.lastState))
                events?.success(mapOf("type" to "micMuted", "muted" to (SiyaService.instance?.isMicMuted() ?: false)))
            }
            override fun onCancel(arguments: Any?) { SiyaService.eventSink = null }
        })

        MethodChannel(messenger, "siya/engine").setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> initApp(result)
                "consumeFirstRun" -> {
                    val first = !prefs.getBoolean("first_run_done", false)
                    if (first) prefs.edit().putBoolean("first_run_done", true).apply()
                    result.success(first)
                }
                "toggleMic" -> { toggleMic(); result.success(null) }
                "toggleMicMute" -> {
                    if (SiyaService.instance?.isSessionActive() == true) {
                        SiyaService.send(this, SiyaService.ACTION_TOGGLE_MIC_MUTE)
                    } else {
                        SiyaService.send(this, SiyaService.ACTION_START, "app")
                    }
                    result.success(null)
                }
                "minimizeApp" -> {
                    if (Settings.canDrawOverlays(this)) {
                        SiyaService.send(this, SiyaService.ACTION_SHOW_OVERLAY, "app")
                    }
                    moveTaskToBack(true)
                    result.success(null)
                }
                "getSettings" -> result.success(readSettings())
                "saveSettings" -> {
                    @Suppress("UNCHECKED_CAST")
                    val m = call.arguments as Map<String, Any?>
                    saveSettings(m)
                    if (m.keys.any { it in reloadKeys }) SiyaService.instance?.reloadSession()
                    if (("wake_word_enabled" in m || "picovoice_key" in m) && (prefs.getBoolean("wake_word_enabled", false) || SiyaService.instance != null))
                        SiyaService.send(this, SiyaService.ACTION_SYNC)
                    if ("call_detect_enabled" in m) applyCallDetect()
                    if ("ghost_mode" in m) com.siya.ai.core.GhostMode.apply(this)
                    if ("game_hud" in m) { if (prefs.getBoolean("game_hud", false)) com.siya.ai.service.GameHud.show(this) else com.siya.ai.service.GameHud.hide() }
                    if (m["call_screener"] == true) requestCallScreeningRole()
                    result.success(null)
                }
                "faceSearchStart" -> {
                    FaceSearch.start(this, call.argument<String>("id") ?: "", call.argument<Int>("limit") ?: 300)
                    result.success(null)
                }
                "faceSearchStatus" -> result.success(FaceSearch.status(this, call.argument<String>("id") ?: ""))
                "faceSearchCancel" -> { FaceSearch.cancel(); result.success(null) }
                "mediaFull" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    Thread { val b = MediaHelper.full(this, uri); ui.post { result.success(b) } }.start()
                }
                "openNotificationAccess" -> {
                    try { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
                    result.success(null)
                }
                "openAllFilesSettings" -> { openAllFiles(); result.success(null) }
                "pickMedia" -> {
                    pendingPick = result
                    mediaPicker.launch(if (call.argument<String>("kind") == "video") "video/*" else "image/*")
                }
                "listMedia" -> {
                    val kind = call.argument<String>("kind") ?: "image"
                    Thread { val l = MediaHelper.list(this, kind); ui.post { result.success(l) } }.start()
                }
                "mediaThumb" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    val kind = call.argument<String>("kind") ?: "image"
                    val size = call.argument<Int>("size") ?: 256
                    Thread { val b = MediaHelper.thumbnail(this, uri, kind, size); ui.post { result.success(b) } }.start()
                }
                "setWallpaper" -> {
                    val uri = call.argument<String>("uri")
                    val path = call.argument<String>("path")
                    val kind = call.argument<String>("kind") ?: "image"
                    Thread {
                        val out = when {
                            uri != null -> MediaHelper.copyIn(this, uri, "wallpaper", "wall_${System.currentTimeMillis()}")
                            path != null -> MediaHelper.copyIn(this, Uri.fromFile(java.io.File(path)).toString(), "wallpaper", "wall_${System.currentTimeMillis()}")
                            else -> null
                        }
                        if (out != null) {
                            // purani wallpaper files hata do
                            java.io.File(filesDir, "wallpaper").listFiles()?.filter { it.absolutePath != out }?.forEach { it.delete() }
                            prefs.edit().putString("wallpaper_type", kind).putString("wallpaper_path", out).apply()
                        }
                        ui.post { result.success(out) }
                    }.start()
                }
                "clearWallpaper" -> {
                    java.io.File(filesDir, "wallpaper").listFiles()?.forEach { it.delete() }
                    prefs.edit().putString("wallpaper_type", "none").putString("wallpaper_path", "").apply()
                    result.success(null)
                }
                "getPeople" -> result.success(PeopleStore.toUi(this))
                "savePerson" -> {
                    val photo = call.argument<String>("photo")
                    val p = PeopleStore.save(this, call.argument<String>("id"), call.argument<String>("name") ?: "",
                        call.argument<String>("relation") ?: "family", photo)
                    if (!photo.isNullOrBlank() && photo.startsWith(java.io.File(filesDir, "picked").absolutePath)) java.io.File(photo).delete()
                    SiyaService.instance?.reloadSession()
                    result.success(mapOf("id" to p.id, "name" to p.name, "relation" to p.relation, "photo" to p.photo))
                }
                "deletePerson" -> { PeopleStore.delete(this, call.argument<String>("id") ?: ""); SiyaService.instance?.reloadSession(); result.success(null) }
                "getLocation" -> Thread {
                    val l = LocationHelper.device(this)
                    val m: Map<String, Any?>? = l?.let {
                        mapOf("lat" to it.latitude, "lng" to it.longitude, "name" to LocationHelper.placeName(this, it.latitude, it.longitude))
                    }
                    ui.post { result.success(m) }
                }.start()
                "searchPlace" -> {
                    val q = call.argument<String>("q") ?: ""
                    Thread { val m = LocationHelper.search(this, q); ui.post { result.success(m) } }.start()
                }
                "openBrowser" -> {
                    val url = call.argument<String>("url") ?: "https://www.google.com"
                    prefs.edit().putBoolean("ai_browser_enabled", true).apply()
                    Thread { AiBrowser.open(this, url, "full"); ui.post { result.success(true) } }.start()
                }
                "getSmsLedger" -> Thread {
                    val entries = com.siya.ai.data.SmsLedger.getEntries(this)
                    val daySummary = com.siya.ai.data.SmsLedger.summary(this, "day")
                    val monthSummary = com.siya.ai.data.SmsLedger.summary(this, "month")
                    ui.post {
                        result.success(mapOf(
                            "entries" to entries,
                            "daySummary" to daySummary,
                            "monthSummary" to monthSummary
                        ))
                    }
                }.start()
                "getCallLogs" -> Thread {
                    val list = ArrayList<Map<String, Any>>()
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED) {
                        try {
                            contentResolver.query(
                                android.provider.CallLog.Calls.CONTENT_URI,
                                arrayOf(
                                    android.provider.CallLog.Calls.CACHED_NAME,
                                    android.provider.CallLog.Calls.NUMBER,
                                    android.provider.CallLog.Calls.DATE,
                                    android.provider.CallLog.Calls.DURATION,
                                    android.provider.CallLog.Calls.TYPE
                                ),
                                null, null, "${android.provider.CallLog.Calls.DATE} DESC LIMIT 40"
                            )?.use { c ->
                                while (c.moveToNext()) {
                                    list.add(mapOf(
                                        "name" to (c.getString(0) ?: ""),
                                        "number" to (c.getString(1) ?: ""),
                                        "date" to c.getLong(2),
                                        "duration" to c.getLong(3),
                                        "type" to c.getInt(4)
                                    ))
                                }
                            }
                        } catch (_: Exception) {}
                    }
                    ui.post { result.success(list) }
                }.start()
                "getStatus" -> result.success(readStatus())
                "requestPermissions" -> requestAllPermissions(result)
                "openAccessibility" -> { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)); result.success(null) }
                "openOverlaySettings" -> {
                    startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                    result.success(null)
                }
                "requestBatteryExemption" -> { requestBatteryExemption(); result.success(null) }
                "toggleAdmin" -> { toggleAdmin(); result.success(null) }
                "requestCallScreening" -> { requestCallScreeningRole(); result.success(null) }
                "openUsageAccess" -> { try { startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)) } catch (_: Exception) {}; result.success(null) }
                "openSecurity" -> { startActivity(Intent(this, SecuritySettingsActivity::class.java)); result.success(null) }
                "setDefaultAssistant" -> { openAssistantSettings(); result.success(null) }
                "pickContact" -> {
                    pendingContact = result
                    contactPicker.launch(Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI))
                }
                // ── Smart Contacts & Nickname Caller ──
                "getSmartContacts" -> Thread {
                    val list = com.siya.ai.data.SmartContactsStore.list(this)
                    ui.post { result.success(list) }
                }.start()
                "saveSmartContact" -> Thread {
                    val id = call.argument<String>("id")
                    val name = call.argument<String>("name") ?: ""
                    val number = call.argument<String>("number") ?: ""
                    val aliases = call.argument<List<String>>("aliases") ?: emptyList()
                    val saved = com.siya.ai.data.SmartContactsStore.save(this, id, name, number, aliases)
                    ui.post { result.success(saved) }
                }.start()
                "deleteSmartContact" -> Thread {
                    val id = call.argument<String>("id") ?: ""
                    com.siya.ai.data.SmartContactsStore.delete(this, id)
                    ui.post { result.success(null) }
                }.start()
                "directCall" -> {
                    val number = call.argument<String>("number") ?: ""
                    val ok = PhoneController.directCall(this, number)
                    result.success(ok)
                }
                // ── AI Data / Memory ──
                "getMemory" -> Thread {
                    val l = MemoryStore.toUiList(this)
                    val f = MemoryStore.factList(this)
                    ui.post { result.success(mapOf("messages" to l, "facts" to f, "total" to MemoryStore.count(this))) }
                }.start()
                "clearMemory" -> { MemoryStore.clearAll(this); result.success(null) }
                "copyMemory" -> {
                    val cm = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("Siya chat", MemoryStore.exportText(this)))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── App start (halka - UI pehle dikhta hai) ──────────────────────────
    private fun initApp(result: MethodChannel.Result) {
        var answered = false
        fun begin() {
            if (answered) return
            answered = true
            // Bhari cheezein UI ke baad, alag thread par
            Thread {
                // Call detect hamesha user ki marzi se: purane update se ON reh gaya ho to ek baar OFF kar do
                try {
                    if (!prefs.getBoolean("call_detect_reset_v3", false)) {
                        prefs.edit().putBoolean("call_detect_enabled", false).putBoolean("call_detect_reset_v3", true).apply()
                    }
                    if (!prefs.getBoolean("call_detect_enabled", false)) stopService(Intent(this, CallMonitorService::class.java))
                } catch (_: Exception) {}
                try {
                    if (prefs.getBoolean("call_detect_enabled", false) &&
                        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED)
                        ContextCompat.startForegroundService(this, Intent(this, CallMonitorService::class.java))
                } catch (_: Exception) {}
                if (prefs.getBoolean("wake_word_enabled", false)) SiyaService.send(this, SiyaService.ACTION_SYNC)
            }.start()
            result.success(true)
        }
        BiometricManager.authenticate(this,
            onSuccess = { begin() },
            onError = { msg: String ->
                Toast.makeText(this, "Auth failed: $msg", Toast.LENGTH_LONG).show()
                if (!answered) { answered = true; result.success(false) }
            },
            onFallback = { begin() }
        )
    }

    private fun toggleMic() {
        if (!SiyaService.hasMic(this)) { requestAllPermissions(null); return }
        val svc = SiyaService.instance
        if (svc != null && svc.isSessionActive()) SiyaService.send(this, SiyaService.ACTION_STOP)
        else SiyaService.send(this, SiyaService.ACTION_START, "app")
    }

    // ── Permissions ─────────────────────────────────────────────────────
    private fun missingCount() = allPermissions.count {
        ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
    }

    private fun requestAllPermissions(result: MethodChannel.Result?) {
        val missing = allPermissions.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) { result?.success(0); return }
        pendingPermissions = result
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), 200)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 200) {
            pendingPermissions?.success(missingCount())
            pendingPermissions = null
            applyCallDetect()
        }
    }

    private fun requestBatteryExemption() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) {
            Toast.makeText(this, "Battery optimization pehle se off hai", Toast.LENGTH_SHORT).show(); return
        }
        try {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    // ── Settings ────────────────────────────────────────────────────────
    private val defaults: Map<String, Any> = mapOf(
        "api_key" to "", "user_name" to "Sir", "prime_name" to "", "prime_number" to "",
        "personality_mode" to "love", "selected_personality" to "love", "live_voice" to "Aoede",
        "memory_enabled" to true, "wake_word_enabled" to false,
        "call_detect_enabled" to false,          // call detect default BAND (privacy)
        "keep_screen_on" to true, "ai_browser_enabled" to false,
        "voice_focus" to "normal", "picovoice_key" to "",
        "wallpaper_type" to "none", "wallpaper_path" to "", "wallpaper_sound" to false, "wallpaper_dim" to 0.35,
        "loc_mode" to "device", "loc_name" to "", "loc_lat" to 0.0, "loc_lng" to 0.0,
        // naye features
        "wa_autoreply" to false, "wa_reply_names" to "", "call_screener" to false, "ledger_enabled" to true,
        "sos_volume_enabled" to false, "sos_contacts" to "", "ghost_mode" to false, "ghost_code" to "2580",
        "game_hud" to false, "spam_numbers" to ""
    )

    /** In keys ke badalne par live session dobara connect hota hai. */
    private val reloadKeys = setOf("api_key", "user_name", "prime_name", "prime_number", "personality_mode",
        "selected_personality", "live_voice", "memory_enabled", "ai_browser_enabled", "loc_mode", "loc_name", "voice_focus")

    private fun readSettings(): Map<String, Any?> {
        val out = HashMap<String, Any?>(defaults)
        prefs.all.forEach { (k, v) -> if (k in defaults) out[k] = if (v is Float) v.toDouble() else v }
        return out
    }

    /** Sirf bheje gaye keys save hote hain (Profile / Wallpaper / Location alag screens se aate hain). */
    private fun saveSettings(m: Map<String, Any?>) {
        prefs.edit().apply {
            for ((k, v) in m) {
                when (val d = defaults[k]) {
                    null -> {}
                    is Boolean -> putBoolean(k, v as? Boolean ?: d)
                    is String -> putString(k, (v?.toString() ?: d).trim())
                    is Double -> putFloat(k, (v as? Number)?.toFloat() ?: d.toFloat())
                }
            }
        }.apply()
    }

    private fun applyCallDetect() {
        if (prefs.getBoolean("call_detect_enabled", false)) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED)
                try { ContextCompat.startForegroundService(this, Intent(this, CallMonitorService::class.java)) } catch (_: Exception) {}
        } else {
            try { stopService(Intent(this, CallMonitorService::class.java)) } catch (_: Exception) {}
        }
    }

    private fun openAllFiles() {
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName")))
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE), 201)
        }
    }

    private fun readStatus(): Map<String, Any?> {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return mapOf(
            "accessibility" to AccessibilityHelperService.isEnabled(this),
            "admin" to dpm.isAdminActive(adminComponent),
            "missing_permissions" to missingCount(),
            "overlay" to Settings.canDrawOverlays(this),
            "battery_ok" to pm.isIgnoringBatteryOptimizations(packageName),
            "notifications" to nm.areNotificationsEnabled(),
            "memory_count" to MemoryStore.count(this),
            "all_files" to FileTools.hasAccess(),
            "media_access" to MediaTools.hasAccess(this),
            "ppn_model" to PorcupineWakeEngine.hasModel(this),
            "location_perm" to LocationHelper.hasPermission(this),
            "mic_perm" to (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED),
            "phone_perm" to (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED),
            "call_log_perm" to (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED),
            "sms_perm" to (ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED),
            "call_screener_role" to if (Build.VERSION.SDK_INT >= 29) {
                try {
                    val rm = getSystemService(android.app.role.RoleManager::class.java)
                    rm.isRoleHeld(android.app.role.RoleManager.ROLE_CALL_SCREENING)
                } catch (_: Exception) { false }
            } else false
        )
    }

    private fun toggleAdmin() {
        if (!dpm.isAdminActive(adminComponent)) {
            startActivity(Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Siya needs admin to control system.")
            })
        } else {
            Toast.makeText(this, "Admin is already active", Toast.LENGTH_SHORT).show()
        }
    }

    /** Call Screening role: AI call screener + spam block + "Ramesh calling" alert ke liye zaroori. */
    @Suppress("DEPRECATION")
    private fun requestCallScreeningRole() {
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                val rm = getSystemService(android.app.role.RoleManager::class.java)
                if (rm.isRoleAvailable(android.app.role.RoleManager.ROLE_CALL_SCREENING) && !rm.isRoleHeld(android.app.role.RoleManager.ROLE_CALL_SCREENING))
                    startActivityForResult(rm.createRequestRoleIntent(android.app.role.RoleManager.ROLE_CALL_SCREENING), 311)
            }
        } catch (_: Exception) {}
    }

    private fun openAssistantSettings() {
        try {
            startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
            Toast.makeText(this, "Siya ko Default Assistant chuno", Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Toast.makeText(this, "Settings > Apps > Default Apps > Assistant > Siya", Toast.LENGTH_LONG).show()
        }
    }
}
