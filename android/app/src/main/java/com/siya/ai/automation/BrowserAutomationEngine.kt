package com.siya.ai.automation

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.app.NotificationCompat
import com.siya.ai.R
import com.siya.ai.service.AccessibilityHelperService
import java.io.IOException
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Best-effort UI automation for ChatGPT/Gemini web image generation.
 * All waiting is bounded; each accessibility event advances the same single state machine.
 */
object BrowserAutomationEngine {
    private const val TAG = "SiyaImageAutomation"
    private const val MAX_WAIT_MS = 180_000L
    private const val POLL_MS = 1_500L
    private const val CHANNEL_ID = "siya_image_generation"
    private val main = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)

    private enum class Stage { OPENING, ATTACH_PICKER, WAIT_ATTACH_RETURN, ENTER_PROMPT, SUBMIT, WAIT_RESULT, WAIT_DOWNLOAD, DONE }
    @Volatile private var stage = Stage.DONE
    @Volatile private var provider = "chatgpt"
    @Volatile private var prompt = ""
    @Volatile private var editImage = false
    @Volatile private var startedAt = 0L
    @Volatile private var downloadClickedAt = 0L
    @Volatile private var polls = 0
    @Volatile private var lastAdvanceAt = 0L
    @Volatile private var lastStatus = ""
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var tick: Runnable? = null

    fun start(context: Context, providerName: String, imagePrompt: String, attachImage: Boolean = false): String {
        val cleanPrompt = imagePrompt.trim()
        if (cleanPrompt.isBlank()) return "ERROR: image prompt khaali hai"
        if (!busy.compareAndSet(false, true)) return "ERROR: image generation pehle se chal rahi hai"
        val service = AccessibilityHelperService.instance
        if (service == null || !AccessibilityHelperService.isEnabled(context)) {
            busy.set(false)
            return "ERROR: Siya Accessibility Service ON karo, phir dobara bolo"
        }
        provider = if (providerName.contains("gemini", true)) "gemini" else "chatgpt"
        prompt = cleanPrompt.take(2500)
        editImage = attachImage
        startedAt = SystemClock.elapsedRealtime()
        downloadClickedAt = 0L
        polls = 0
        lastAdvanceAt = 0L
        lastStatus = ""
        stage = Stage.OPENING
        val url = if (provider == "gemini") "https://gemini.google.com/app" else "https://chatgpt.com/"
        try {
            context.applicationContext.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: Exception) {
            finish(context, false, "Browser nahi khul saka: ${e.message ?: "unknown error"}")
            return "ERROR: browser nahi khula"
        }
        schedule(context.applicationContext, 900L)
        return "OK: ${provider.uppercase(Locale.ROOT)} image workflow shuru kiya. Screen par login maange to login karo; agar edit photo chuni hai to picker mein photo select karo. Workflow maximum 3 minute chalega."
    }

    fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!busy.get() || stage == Stage.DONE) return
        val service = AccessibilityHelperService.instance ?: return
        advance(service.applicationContext, service.rootInActiveWindow)
    }

    private fun schedule(context: Context, delay: Long = POLL_MS) {
        tick?.let { main.removeCallbacks(it) }
        val r = Runnable {
            if (!busy.get() || stage == Stage.DONE) return@Runnable
            val service = AccessibilityHelperService.instance
            if (service == null) {
                finish(context, false, "Accessibility service disconnect ho gayi.")
                return@Runnable
            }
            advance(context, service.rootInActiveWindow)
        }
        tick = r
        main.postDelayed(r, delay)
    }

    private fun advance(context: Context, root: AccessibilityNodeInfo?) {
        if (!busy.get() || stage == Stage.DONE) return
        val nowElapsed = SystemClock.elapsedRealtime()
        // Accessibility events can arrive in bursts; throttle them so they cannot exhaust the poll budget.
        if (nowElapsed - lastAdvanceAt < 800L) return
        lastAdvanceAt = nowElapsed
        if (nowElapsed - startedAt > MAX_WAIT_MS || polls++ > 130) {
            finish(context, false, "Image workflow timeout ho gaya. Page/login/network check karke dobara try karo.")
            return
        }
        if (root == null) { schedule(context); return }
        val screen = readTree(root).lowercase(Locale.ROOT)

        // If a login or CAPTCHA is present, do not attempt to bypass it.
        if (screen.contains("sign in") || screen.contains("log in") || screen.contains("continue with google") ||
            screen.contains("verify you are human") || screen.contains("captcha")) {
            setStatus(context, "Login/verification required; please complete it on screen.")
            schedule(context, 2500L)
            return
        }

        when (stage) {
            Stage.OPENING -> {
                if (editImage) {
                    if (clickByLabels(root, listOf("attach files", "add photos", "upload image", "attach image", "add image", "add attachment"))) {
                        stage = Stage.WAIT_ATTACH_RETURN
                        setStatus(context, "Photo picker khul raha hai. Apni edit wali photo select karo.")
                    } else {
                        // Keep waiting for the page's input/attachment control to appear.
                        val input = findEditable(root)
                        if (input != null) {
                            if (clickByLabels(root, listOf("attach files", "add photos", "upload image", "attach image", "add image"))) {
                                stage = Stage.WAIT_ATTACH_RETURN
                            }
                        }
                    }
                } else if (findEditable(root) != null) {
                    stage = Stage.ENTER_PROMPT
                }
            }
            Stage.ATTACH_PICKER -> stage = Stage.WAIT_ATTACH_RETURN
            Stage.WAIT_ATTACH_RETURN -> {
                // The user selects the intended source image; continue only after returning to the web app.
                if (isBrowserSurface(root.packageName?.toString().orEmpty()) && findEditable(root) != null) {
                    stage = Stage.ENTER_PROMPT
                }
            }
            Stage.ENTER_PROMPT -> {
                val field = findEditable(root)
                if (field != null && setText(field, prompt, context)) {
                    stage = Stage.SUBMIT
                    schedule(context, 600L)
                    return
                }
            }
            Stage.SUBMIT -> {
                val sent = clickByLabels(root, listOf("create image", "generate image", "generate", "send prompt", "send message", "submit", "create", "send"))
                if (sent || submitFocused(root)) {
                    stage = Stage.WAIT_RESULT
                    setStatus(context, "Image generate ho rahi hai…")
                }
            }
            Stage.WAIT_RESULT -> {
                val generating = screen.contains("stop generating") || screen.contains("generating") ||
                    screen.contains("creating image") || screen.contains("working on it") || screen.contains("making your image")
                val downloadVisible = hasLabel(root, listOf("download image", "download"))
                val imageVisible = hasImageNode(root)
                val imageReady = imageVisible || screen.contains("generated image") ||
                    screen.contains("image created") || screen.contains("your image is ready")
                if (!generating && imageReady && polls > 3) {
                    if (clickByLabels(root, listOf("download image", "download"))) {
                        downloadClickedAt = System.currentTimeMillis() / 1000L
                        stage = Stage.WAIT_DOWNLOAD
                        setStatus(context, "Image ready hai; download ko gallery mein save kar rahi hoon.")
                    } else if (imageVisible) {
                        // Some web layouts expose the image but not a download button; try the image context menu.
                        val image = findImageNode(root)
                        if (image != null && image.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)) {
                            if (clickByLabels(root, listOf("download image", "download image as", "save image"))) {
                                downloadClickedAt = System.currentTimeMillis() / 1000L
                                stage = Stage.WAIT_DOWNLOAD
                            }
                        }
                    }
                }
            }
            Stage.WAIT_DOWNLOAD -> {
                val saved = copyLatestDownloadToGallery(context, downloadClickedAt)
                if (saved != null) finish(context, true, "Jaan, aapki photo ready ho gayi hai aur gallery me save kar di hai!", saved)
                else if (System.currentTimeMillis() / 1000L - downloadClickedAt > 35L) {
                    finish(context, false, "Image generate ho gayi ho sakti hai, lekin Downloads se gallery mein save confirm nahi hua. Download folder check karo.")
                    return
                }
            }
            Stage.DONE -> return
        }
        schedule(context)
    }

    private fun readTree(root: AccessibilityNodeInfo): String {
        val out = StringBuilder()
        fun walk(node: AccessibilityNodeInfo?) {
            if (node == null) return
            node.text?.toString()?.takeIf { it.isNotBlank() }?.let { out.append(it).append('\n') }
            node.contentDescription?.toString()?.takeIf { it.isNotBlank() }?.let { out.append(it).append('\n') }
            node.hintText?.toString()?.takeIf { it.isNotBlank() }?.let { out.append(it).append('\n') }
            for (i in 0 until node.childCount) walk(node.getChild(i))
        }
        walk(root)
        return out.toString()
    }

    private fun findEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable && node.isEnabled) return node
        for (i in 0 until node.childCount) findEditable(node.getChild(i))?.let { return it }
        return null
    }

    private fun setText(node: AccessibilityNodeInfo, text: String, context: Context): Boolean {
        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        val args = android.os.Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        if (node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) return true
        return try {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Siya image prompt", text))
            node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        } catch (_: Exception) { false }
    }

    private fun clickByLabels(root: AccessibilityNodeInfo, labels: List<String>): Boolean {
        val target = findLabel(root, labels) ?: return false
        var node: AccessibilityNodeInfo? = target
        while (node != null) {
            if (node.isEnabled && node.isClickable && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
            node = node.parent
        }
        return target.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    private fun hasLabel(root: AccessibilityNodeInfo, labels: List<String>) = findLabel(root, labels) != null

    private fun findLabel(node: AccessibilityNodeInfo?, labels: List<String>): AccessibilityNodeInfo? {
        if (node == null) return null
        val text = node.text?.toString().orEmpty().trim().lowercase(Locale.ROOT)
        val desc = node.contentDescription?.toString().orEmpty().trim().lowercase(Locale.ROOT)
        val hint = node.hintText?.toString().orEmpty().trim().lowercase(Locale.ROOT)
        if (labels.any { label -> text.contains(label) || desc.contains(label) || hint.contains(label) }) return node
        for (i in 0 until node.childCount) findLabel(node.getChild(i), labels)?.let { return it }
        return null
    }

    private fun isBrowserSurface(packageName: String): Boolean {
        val p = packageName.lowercase(Locale.ROOT)
        return listOf("chrome", "firefox", "brave", "browser", "microsoft.emmx", "googlequicksearchbox", "webview")
            .any { p.contains(it) }
    }

    private fun hasImageNode(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false
        if (node.className?.toString()?.contains("Image", true) == true &&
            (node.contentDescription?.toString()?.contains("image", true) == true || node.isClickable)) return true
        for (i in 0 until node.childCount) if (hasImageNode(node.getChild(i))) return true
        return false
    }

    private fun findImageNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.className?.toString()?.contains("Image", true) == true && node.isClickable) return node
        for (i in 0 until node.childCount) findImageNode(node.getChild(i))?.let { return it }
        return null
    }

    private fun submitFocused(root: AccessibilityNodeInfo): Boolean {
        val field = findEditable(root) ?: return false
        return field.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
    }

    private fun copyLatestDownloadToGallery(context: Context, afterSeconds: Long): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.MIME_TYPE, MediaStore.MediaColumns.DATE_ADDED)
        val selection = "${MediaStore.MediaColumns.DATE_ADDED} >= ? AND ${MediaStore.MediaColumns.MIME_TYPE} LIKE ?"
        val candidates = ArrayList<Pair<Long, Uri>>()
        try {
            resolver.query(collection, projection, selection, arrayOf(afterSeconds.toString(), "image/%"),
                "${MediaStore.MediaColumns.DATE_ADDED} DESC")?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val date = cursor.getLong(dateCol)
                    candidates.add(date to Uri.withAppendedPath(collection, id.toString()))
                }
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Downloads read permission unavailable", e)
            return null
        } catch (e: Exception) {
            Log.w(TAG, "Downloads query failed", e)
            return null
        }
        val source = candidates.sortedByDescending { it.first }.firstOrNull()?.second ?: return null
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "SiyaAI_${System.currentTimeMillis()}.jpg")
            put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/SiyaAI Gallery")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val destination = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return null
        try {
            resolver.openInputStream(source).use { input ->
                if (input == null) throw IOException("Downloaded image stream unavailable")
                resolver.openOutputStream(destination).use { output ->
                    if (output == null) throw IOException("Gallery output stream unavailable")
                    input.copyTo(output)
                }
            }
            resolver.update(destination, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            return destination
        } catch (e: Exception) {
            Log.e(TAG, "Could not copy downloaded image to gallery", e)
            try { resolver.delete(destination, null, null) } catch (_: Exception) {}
            return null
        }
    }

    private fun setStatus(context: Context, text: String) {
        if (text == lastStatus) return
        lastStatus = text
        Log.i(TAG, text)
        postNotification(context, "Siya image generation", text, 1001)
    }

    private fun finish(context: Context, success: Boolean, message: String, uri: Uri? = null) {
        if (!busy.compareAndSet(true, false)) return
        stage = Stage.DONE
        tick?.let { main.removeCallbacks(it) }; tick = null
        postNotification(context, if (success) "Siya AI — Photo ready" else "Siya AI — Image generation", message, 1002, uri)
        speak(context, message)
        Log.i(TAG, "workflow finished success=$success message=$message")
    }

    private fun postNotification(context: Context, title: String, text: String, id: Int, uri: Uri? = null) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Siya image generation", NotificationManager.IMPORTANCE_DEFAULT)
            )
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
            if (uri != null) {
                val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "image/*").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                val pi = PendingIntent.getActivity(context, 1002, view, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                builder.setContentIntent(pi)
            }
            manager.notify(id, builder.build())
        } catch (e: Exception) { Log.w(TAG, "Notification unavailable", e) }
    }

    private fun speak(context: Context, text: String) {
        main.post {
            if (ttsReady && tts != null) {
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "siya-image-status")
            } else if (tts == null) {
                tts = TextToSpeech(context.applicationContext) { status ->
                    ttsReady = status == TextToSpeech.SUCCESS
                    if (ttsReady) {
                        try { tts?.language = Locale("hi", "IN"); tts?.setPitch(1.08f); tts?.setSpeechRate(0.94f) } catch (_: Exception) {}
                        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "siya-image-status")
                    }
                }
            }
        }
    }
}
