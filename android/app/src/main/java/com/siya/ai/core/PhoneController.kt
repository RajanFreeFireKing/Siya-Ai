package com.siya.ai.core

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.provider.ContactsContract
import android.provider.MediaStore
import android.telephony.SmsManager
import android.util.Log
import android.view.Display
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.content.ContextCompat
import com.siya.ai.service.AccessibilityHelperService
import com.siya.ai.service.SmartAccessibilityEngine
import com.siya.ai.utils.HindiTransliterator
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Phone ko control karne ka saara kaam: app kholna, call, WhatsApp, screen tap/scroll/type/screenshot...
 * Har function ek text result lautata hai jo Gemini ko tool-response ke roop mein jaata hai.
 */
object PhoneController {

    private const val TAG = "SIYA_PHONE"

    data class AppInfo(val label: String, val pkg: String) {
        val norm = normalize(label)
    }

    private var appCache: List<AppInfo>? = null
    private var appCacheAt = 0L

    // ── Apps ──────────────────────────────────────────────────
    fun apps(ctx: Context, force: Boolean = false): List<AppInfo> {
        val now = System.currentTimeMillis()
        appCache?.let { if (!force && now - appCacheAt < 90_000) return it }
        val pm = ctx.packageManager
        val q = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val list = try {
            pm.queryIntentActivities(q, 0)
                .map { AppInfo(it.loadLabel(pm).toString(), it.activityInfo.packageName) }
                .distinctBy { it.pkg }
                .sortedBy { it.label.lowercase() }
        } catch (e: Exception) { emptyList() }
        appCache = list; appCacheAt = now
        return list
    }

    fun appNames(ctx: Context, max: Int = 160): String =
        apps(ctx).filter { it.pkg != ctx.packageName }.take(max).joinToString(", ") { it.label }

    private val aliases: Map<String, List<String>> = mapOf(
        "whatsapp" to listOf("whatsapp", "watsapp", "whatsap", "whats app", "wa", "व्हाट्सएप", "वॉट्सऐप", "वाट्सएप", "व्हाट्सऐप", "व्हॉट्सअॅप"),
        "youtube" to listOf("youtube", "you tube", "ytube", "yt", "यूट्यूब", "यूटूब", "यूट्यब"),
        "instagram" to listOf("instagram", "insta", "इंस्टाग्राम", "इंस्टा"),
        "facebook" to listOf("facebook", "fb", "फेसबुक"),
        "chrome" to listOf("chrome", "browser", "क्रोम", "ब्राउज़र"),
        "camera" to listOf("camera", "कैमरा"),
        "gallery" to listOf("gallery", "photos", "गैलरी", "फोटो", "फ़ोटो"),
        "settings" to listOf("settings", "setting", "सेटिंग", "सेटिंग्स"),
        "phone" to listOf("phone", "dialer", "call", "फोन", "डायलर"),
        "contacts" to listOf("contacts", "contact", "कॉन्टैक्ट", "संपर्क"),
        "messages" to listOf("messages", "message", "sms", "मैसेज", "मैसेजेस"),
        "maps" to listOf("maps", "google maps", "gmaps", "map", "मैप", "मैप्स"),
        "spotify" to listOf("spotify", "sportify", "स्पॉटिफाई", "स्पोटिफाई"),
        "telegram" to listOf("telegram", "टेलीग्राम"),
        "snapchat" to listOf("snapchat", "snap", "स्नैपचैट"),
        "play store" to listOf("play store", "playstore", "प्ले स्टोर"),
        "gmail" to listOf("gmail", "mail", "email", "जीमेल"),
        "calculator" to listOf("calculator", "calc", "कैलकुलेटर"),
        "clock" to listOf("clock", "alarm", "घड़ी", "अलार्म"),
        "phonepe" to listOf("phonepe", "phone pe", "फोनपे"),
        "paytm" to listOf("paytm", "पेटीएम"),
        "google pay" to listOf("google pay", "gpay", "g pay", "गूगल पे"),
        "files" to listOf("files", "file manager", "फाइल्स"),
        "x" to listOf("twitter", "ट्विटर")
    )

    fun normalize(s: String): String =
        s.lowercase(Locale.ROOT).replace(Regex("[^\\p{L}\\p{N} ]"), " ").replace(Regex("\\s+"), " ").trim()

    private fun resolveAlias(q: String): String {
        for ((canon, vars) in aliases) if (vars.any { normalize(it) == q }) return canon
        return q
    }

    fun findApp(ctx: Context, query: String): AppInfo? {
        var q = normalize(query)
            .replace(Regex("\\b(open|kholo|khol|start|chalu|launch|app|application|please|karo|kar do|do|ko|ka|ki)\\b"), " ")
            .replace(Regex("\\s+"), " ").trim()
        if (q.isEmpty()) return null
        val candidates = linkedSetOf(resolveAlias(q))
        val latin = normalize(HindiTransliterator.transliterate(query))
        if (latin.isNotEmpty()) candidates.add(resolveAlias(latin))
        q = candidates.first()

        val list = apps(ctx).filter { it.pkg != ctx.packageName }
        var best: AppInfo? = null
        var bestScore = 0
        for (app in list) {
            for (c in candidates) {
                val s = score(c, app)
                if (s > bestScore) { bestScore = s; best = app }
            }
        }
        return if (bestScore >= 55) best else null
    }

    private fun score(q: String, app: AppInfo): Int {
        val l = app.norm
        val lc = l.replace(" ", "")
        val qc = q.replace(" ", "")
        if (l == q || lc == qc) return 100
        if (l.startsWith(q) || q.startsWith(l)) return 88
        if (qc.length >= 3 && lc.contains(qc)) return 78
        if (lc.length >= 3 && qc.contains(lc)) return 72
        val words = l.split(" ")
        if (words.any { it == q }) return 80
        if (qc.length >= 4 && app.pkg.lowercase().contains(qc)) return 62
        val d = levenshtein(qc, lc.take(maxOf(qc.length + 2, 4)))
        val ratio = 1.0 - d.toDouble() / maxOf(qc.length, 1)
        if (qc.length >= 4 && ratio >= 0.72) return (50 + ratio * 20).toInt()
        return 0
    }

    private fun levenshtein(a: String, b: String): Int {
        if (a == b) return 0
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        var prev = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            val cur = IntArray(b.length + 1)
            cur[0] = i
            for (j in 1..b.length) {
                cur[j] = minOf(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + if (a[i - 1] == b[j - 1]) 0 else 1)
            }
            prev = cur
        }
        return prev[b.length]
    }

    private fun launch(ctx: Context, intent: Intent): Boolean {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        // Accessibility service ka context background se bhi activity start kar paata hai.
        val a11y: Context? = AccessibilityHelperService.instance
        return try {
            (a11y ?: ctx).startActivity(intent); true
        } catch (e: Exception) {
            Log.w(TAG, "launch via a11y failed: ${e.message}")
            try { ctx.startActivity(intent); true } catch (e2: Exception) { Log.e(TAG, "launch: ${e2.message}"); false }
        }
    }

    private fun foregroundPackage(): String? = try {
        AccessibilityHelperService.instance?.rootInActiveWindow?.packageName?.toString()
    } catch (_: Exception) { null }

    fun openApp(ctx: Context, query: String): String {
        val app = findApp(ctx, query)
            ?: return "NOT_FOUND: '$query' naam ka koi app nahi mila. Installed apps: ${appNames(ctx, 80)}"
        val intent = ctx.packageManager.getLaunchIntentForPackage(app.pkg)
            ?: return "ERROR: ${app.label} launch nahi ho sakta"
        if (!launch(ctx, intent)) return "ERROR: ${app.label} ko kholne ki permission nahi (Settings mein 'Display over other apps' ON karo)"
        if (AccessibilityHelperService.instance != null) {
            for (i in 0 until 10) {
                Thread.sleep(250)
                if (foregroundPackage() == app.pkg) return "OK: ${app.label} khul gaya"
            }
            // ek baar aur try
            ctx.packageManager.getLaunchIntentForPackage(app.pkg)?.let { launch(ctx, it) }
            Thread.sleep(800)
            return if (foregroundPackage() == app.pkg) "OK: ${app.label} khul gaya" else "OK_UNVERIFIED: ${app.label} kholne ki koshish ki"
        }
        return "OK: ${app.label} khol diya"
    }

    // ── Contacts ──────────────────────────────────────────────
    private fun has(ctx: Context, p: String) = ContextCompat.checkSelfPermission(ctx, p) == PackageManager.PERMISSION_GRANTED

    fun findNumber(ctx: Context, name: String): Pair<String, String>? {
        if (name.matches(Regex("[0-9+ \\-]{6,}"))) return name.replace(" ", "") to name
        if (!has(ctx, Manifest.permission.READ_CONTACTS)) return null
        val variants = linkedSetOf(name.trim(), HindiTransliterator.transliterate(name).trim())
        variants.addAll(name.trim().split(" ").filter { it.length > 2 })
        for (v in variants) {
            if (v.isEmpty()) continue
            try {
                ctx.contentResolver.query(
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER, ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME),
                    "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?", arrayOf("%$v%"),
                    "${ContactsContract.CommonDataKinds.Phone.TIMES_CONTACTED} DESC"
                )?.use { c ->
                    if (c.moveToFirst()) return c.getString(0) to c.getString(1)
                }
            } catch (_: Exception) {}
        }
        return null
    }

    fun call(ctx: Context, name: String): String {
        if (!has(ctx, Manifest.permission.CALL_PHONE)) return "ERROR: Call permission nahi hai"
        val (num, who) = findNumber(ctx, name) ?: return "NOT_FOUND: '$name' contact nahi mila"
        val ok = launch(ctx, Intent(Intent.ACTION_CALL, Uri.parse("tel:" + Uri.encode(num))))
        return if (ok) "OK: $who ko call laga diya" else "ERROR: call shuru nahi hui"
    }

    private fun waNumber(num: String): String {
        var n = num.replace(Regex("[^0-9+]"), "")
        if (!n.startsWith("+") && n.length == 10) n = "+91$n"
        return n.removePrefix("+")
    }

    fun whatsappMessage(ctx: Context, name: String, message: String): String {
        val (num, who) = findNumber(ctx, name) ?: return "NOT_FOUND: '$name' contact nahi mila"
        val uri = Uri.parse("https://api.whatsapp.com/send?phone=${waNumber(num)}&text=${Uri.encode(message)}")
        val i = Intent(Intent.ACTION_VIEW, uri).setPackage("com.whatsapp")
        if (!launch(ctx, i)) {
            val i2 = Intent(Intent.ACTION_VIEW, uri).setPackage("com.whatsapp.w4b")
            if (!launch(ctx, i2)) return "ERROR: WhatsApp khul nahi paya"
        }
        if (AccessibilityHelperService.instance == null) return "OK: $who ka chat khul gaya, message likha hua hai (Send dabana baaki hai - Accessibility ON karo to main khud bhej dungi)"
        for (t in 0 until 8) {
            Thread.sleep(800)
            if (SmartAccessibilityEngine.click(contentDesc = "Send") || SmartAccessibilityEngine.click(text = "Send")) return "OK: $who ko WhatsApp message bhej diya"
        }
        return "OK_UNVERIFIED: $who ka chat khula, Send button nahi mila"
    }

    fun whatsappCall(ctx: Context, name: String, video: Boolean): String {
        if (!has(ctx, Manifest.permission.READ_CONTACTS)) return "ERROR: Contacts permission nahi hai"
        val mime = if (video) "vnd.android.cursor.item/vnd.com.whatsapp.video.call" else "vnd.android.cursor.item/vnd.com.whatsapp.voip.call"
        val variants = linkedSetOf(name.trim(), HindiTransliterator.transliterate(name).trim())
        for (v in variants) {
            if (v.isEmpty()) continue
            try {
                ctx.contentResolver.query(
                    ContactsContract.Data.CONTENT_URI,
                    arrayOf(ContactsContract.Data._ID, ContactsContract.Data.DISPLAY_NAME),
                    "${ContactsContract.Data.MIMETYPE} = ? AND ${ContactsContract.Data.DISPLAY_NAME} LIKE ?",
                    arrayOf(mime, "%$v%"), null
                )?.use { c ->
                    if (c.moveToFirst()) {
                        val id = c.getLong(0); val who = c.getString(1)
                        val i = Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse("content://com.android.contacts/data/$id"), mime).setPackage("com.whatsapp")
                        if (launch(ctx, i)) return "OK: $who ko WhatsApp ${if (video) "video" else "voice"} call laga di"
                    }
                }
            } catch (e: Exception) { Log.w(TAG, "wa call: ${e.message}") }
        }
        return "NOT_FOUND: '$name' WhatsApp contact nahi mila"
    }

    @Suppress("DEPRECATION")
    fun sms(ctx: Context, name: String, message: String): String {
        if (!has(ctx, Manifest.permission.SEND_SMS)) return "ERROR: SMS permission nahi hai"
        val (num, who) = findNumber(ctx, name) ?: return "NOT_FOUND: '$name' contact nahi mila"
        return try {
            val sm = if (Build.VERSION.SDK_INT >= 31) ctx.getSystemService(SmsManager::class.java) else SmsManager.getDefault()
            sm.sendMultipartTextMessage(num, null, sm.divideMessage(message), null, null)
            "OK: $who ko SMS bhej diya"
        } catch (e: Exception) { "ERROR: SMS nahi gaya (${e.message})" }
    }

    // ── Media / Web ───────────────────────────────────────────
    fun youtubePlay(ctx: Context, query: String): String {
        val uri = Uri.parse("https://www.youtube.com/results?search_query=${Uri.encode(query)}")
        val i = Intent(Intent.ACTION_VIEW, uri).setPackage("com.google.android.youtube")
        if (!launch(ctx, i) && !launch(ctx, Intent(Intent.ACTION_VIEW, uri))) return "ERROR: YouTube khul nahi paya"
        if (AccessibilityHelperService.instance != null) {
            for (t in 0 until 6) {
                Thread.sleep(1000)
                if (SmartAccessibilityEngine.click(contentDesc = "play video")) return "OK: YouTube par '$query' chala diya"
            }
        }
        return "OK: YouTube par '$query' ki search khol di"
    }

    fun spotifyPlay(ctx: Context, query: String): String {
        val i = Intent(Intent.ACTION_VIEW, Uri.parse("spotify:search:${Uri.encode(query)}")).setPackage("com.spotify.music")
        if (!launch(ctx, i)) return "ERROR: Spotify khul nahi paya"
        return "OK: Spotify par '$query' search khol di"
    }

    fun mediaKey(ctx: Context, action: String): String {
        val code = when (action.lowercase()) {
            "play", "pause", "play_pause", "toggle" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous", "prev" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            "stop" -> KeyEvent.KEYCODE_MEDIA_STOP
            else -> return "ERROR: unknown media action"
        }
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
        return "OK: media $action"
    }

    fun openUrl(ctx: Context, url: String): String {
        val u = if (url.startsWith("http")) url else "https://$url"
        return if (launch(ctx, Intent(Intent.ACTION_VIEW, Uri.parse(u)))) "OK: $u khul gaya" else "ERROR: link nahi khula"
    }

    // ── System ────────────────────────────────────────────────
    fun flashlight(ctx: Context, on: Boolean): String = try {
        val cm = ctx.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        cm.setTorchMode(cm.cameraIdList[0], on); "OK: flashlight ${if (on) "ON" else "OFF"}"
    } catch (e: Exception) { "ERROR: flashlight (${e.message})" }

    fun volume(ctx: Context, dir: String): String = try {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        when (dir.lowercase()) {
            "up" -> am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
            "down" -> am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
            "mute" -> am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, AudioManager.FLAG_SHOW_UI)
            "max" -> am.setStreamVolume(AudioManager.STREAM_MUSIC, am.getStreamMaxVolume(AudioManager.STREAM_MUSIC), AudioManager.FLAG_SHOW_UI)
        }
        "OK: volume $dir"
    } catch (e: Exception) { "ERROR: volume (${e.message})" }

    fun battery(ctx: Context): String {
        val bm = ctx.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return "Battery ${bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)}%"
    }

    fun dateTime(): String =
        SimpleDateFormat("EEEE, dd MMMM yyyy, hh:mm:ss a zzzz", Locale.getDefault()).format(Date())

    // ── Screen control (Accessibility) ────────────────────────
    private fun needA11y(): String? =
        if (AccessibilityHelperService.instance == null) "ERROR: Accessibility ON nahi hai (Settings > Accessibility > Siya)" else null

    fun readScreen(): String {
        needA11y()?.let { return it }
        val root = AccessibilityHelperService.instance?.rootInActiveWindow ?: return "ERROR: screen read nahi hui"
        val sb = StringBuilder("App: ${root.packageName}\n")
        fun walk(n: AccessibilityNodeInfo?, depth: Int) {
            if (n == null || sb.length > 6500 || depth > 28) return
            val label = (n.text ?: n.contentDescription)?.toString()?.trim().orEmpty()
            val tags = buildString {
                if (n.isClickable) append("[tap]")
                if (n.isEditable) append("[input]")
                if (n.isScrollable) append("[scroll]")
            }
            if (label.isNotEmpty() || tags.isNotEmpty()) {
                if (label.isNotEmpty()) sb.append(label.take(90)).append(' ').append(tags).append('\n')
            }
            for (i in 0 until n.childCount) walk(n.getChild(i), depth + 1)
        }
        walk(root, 0)
        return sb.toString()
    }

    fun tap(text: String): String {
        needA11y()?.let { return it }
        return if (SmartAccessibilityEngine.click(text = text, contentDesc = text)) "OK: '$text' par tap kiya" else "NOT_FOUND: screen par '$text' nahi mila"
    }

    fun longPress(text: String): String {
        needA11y()?.let { return it }
        return if (SmartAccessibilityEngine.longClick(text = text, contentDesc = text)) "OK: '$text' long press" else "NOT_FOUND: '$text' nahi mila"
    }

    fun scroll(direction: String): String {
        needA11y()?.let { return it }
        val d = direction.lowercase()
        val ok = when (d) {
            "down", "next" -> SmartAccessibilityEngine.scrollDown() || SmartAccessibilityEngine.swipe("up")
            "up", "previous", "prev" -> SmartAccessibilityEngine.scrollUp() || SmartAccessibilityEngine.swipe("down")
            else -> false
        }
        return if (ok) "OK: scroll $d" else "ERROR: scroll nahi hua"
    }

    /** Seedha ungli ka swipe (reels/shorts/next video ke liye). direction = ungli ki disha. */
    fun swipe(direction: String): String {
        needA11y()?.let { return it }
        return if (SmartAccessibilityEngine.swipe(direction)) "OK: swipe $direction" else "ERROR: swipe nahi hua"
    }

    fun typeText(text: String): String {
        needA11y()?.let { return it }
        return if (SmartAccessibilityEngine.typeText(text)) "OK: text likh diya" else "ERROR: koi input box nahi mila (pehle input box par tap karo)"
    }

    /** Text likho aur turant bhej do (ChatGPT / WhatsApp / koi bhi chat app). */
    fun typeAndSend(text: String): String {
        needA11y()?.let { return it }
        if (!SmartAccessibilityEngine.typeText(text)) return "ERROR: koi input box nahi mila (pehle input box par tap karo)"
        Thread.sleep(450)
        return if (SmartAccessibilityEngine.submit()) "OK: likh kar bhej diya. Jawab aane tak ruko, phir read_screen karo" else "OK: text likh diya par Send button nahi mila (read_screen karke Send par tap karo)"
    }

    fun submit(): String {
        needA11y()?.let { return it }
        return if (SmartAccessibilityEngine.submit()) "OK: bhej diya" else "ERROR: Send button nahi mila"
    }

    fun press(key: String): String {
        needA11y()?.let { return it }
        val ok = when (key.lowercase()) {
            "back" -> SmartAccessibilityEngine.pressBack()
            "home" -> SmartAccessibilityEngine.pressHome()
            "recents" -> SmartAccessibilityEngine.openRecents()
            "notifications" -> SmartAccessibilityEngine.openNotifications()
            "quick_settings" -> SmartAccessibilityEngine.openQuickSettings()
            else -> false
        }
        return if (ok) "OK: $key" else "ERROR: $key nahi hua"
    }

    fun screenshot(ctx: Context): String {
        needA11y()?.let { return it }
        if (Build.VERSION.SDK_INT < 30) return "ERROR: Screenshot ke liye Android 11+ chahiye"
        val svc = AccessibilityHelperService.instance ?: return "ERROR: accessibility off"
        val latch = CountDownLatch(1)
        var result = "ERROR: screenshot fail"
        try {
            svc.takeScreenshot(Display.DEFAULT_DISPLAY, ctx.mainExecutor, object : AccessibilityService.TakeScreenshotCallback {
                override fun onSuccess(r: AccessibilityService.ScreenshotResult) {
                    try {
                        val hw = Bitmap.wrapHardwareBuffer(r.hardwareBuffer, r.colorSpace)
                        val bmp = hw?.copy(Bitmap.Config.ARGB_8888, false)
                        r.hardwareBuffer.close()
                        if (bmp != null) result = saveBitmap(ctx, bmp)
                    } catch (e: Exception) { result = "ERROR: ${e.message}" }
                    latch.countDown()
                }
                override fun onFailure(errorCode: Int) { result = "ERROR: screenshot code $errorCode"; latch.countDown() }
            })
            latch.await(4, TimeUnit.SECONDS)
        } catch (e: Exception) { result = "ERROR: ${e.message}" }
        return result
    }

    private fun saveBitmap(ctx: Context, bmp: Bitmap): String {
        val name = "Siya_" + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".png"
        val cv = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (Build.VERSION.SDK_INT >= 29) put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Siya")
        }
        val uri = ctx.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv) ?: return "ERROR: gallery mein save nahi hua"
        ctx.contentResolver.openOutputStream(uri)?.use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        return "OK: screenshot gallery (Pictures/Siya) mein save ho gaya"
    }
}
