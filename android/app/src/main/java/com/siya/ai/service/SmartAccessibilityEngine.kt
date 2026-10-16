package com.siya.ai.service

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.Locale

object SmartAccessibilityEngine {

    /**
     * True only for explicit cancellation phrases. This parser is used by WhatsApp
     * announce-and-confirm mode; silence/errors are handled as cancellation separately.
     */
    fun isCancelReplyCommand(spoken: String): Boolean {
        val normalized = spoken.trim().lowercase(Locale.ROOT)
            .replace(Regex("[^\\p{L}\\p{N}\\s]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        if (normalized.isBlank()) return true
        val exact = setOf(
            "chhod do", "chhod de", "chod do", "chod de", "rehne do", "rahne do",
            "aise hi chhod dein", "aise hi chhod do", "mat bhejo", "reply mat bhejo",
            "cancel", "cancel karo", "nahi", "nahin", "no", "leave it", "ignore it",
            "dont reply", "don't reply", "do not reply"
        )
        return normalized in exact
    }


    private const val TAG = "SmartAccessibility"

    // ── Click ──────────────────────────────────────────────────
    fun click(text: String? = null, contentDesc: String? = null, id: String? = null): Boolean {
        val service = AccessibilityHelperService.instance ?: run {
            Log.e(TAG, "Accessibility Service not running!")
            return false
        }
        val rootNode = service.rootInActiveWindow ?: run {
            Log.e(TAG, "rootInActiveWindow is null!")
            return false
        }
        Log.d(TAG, "click → text=$text, desc=$contentDesc, id=$id")

        if (id != null) {
            rootNode.findAccessibilityNodeInfosByViewId(id).forEach { if (performClick(it)) return true }
        }
        if (text != null) {
            rootNode.findAccessibilityNodeInfosByText(text).forEach { node ->
                if (node.text?.toString()?.equals(text, ignoreCase = true) == true && performClick(node)) return true
            }
        }
        return searchAndClick(rootNode, text, contentDesc)
    }

    // ── Long Click ─────────────────────────────────────────────
    fun longClick(text: String? = null, contentDesc: String? = null): Boolean {
        val rootNode = AccessibilityHelperService.instance?.rootInActiveWindow ?: return false
        return searchAndLongClick(rootNode, text, contentDesc)
    }

    // ── Scroll ─────────────────────────────────────────────────
    fun scrollDown(id: String? = null): Boolean {
        val service = AccessibilityHelperService.instance ?: return false
        val rootNode = service.rootInActiveWindow ?: return false

        // Try by ID first
        if (id != null) {
            rootNode.findAccessibilityNodeInfosByViewId(id).forEach { node ->
                if (node.isScrollable) {
                    node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                    return true
                }
            }
        }
        // Find any scrollable
        return findScrollableAndScroll(rootNode, forward = true)
    }

    fun scrollUp(id: String? = null): Boolean {
        val service = AccessibilityHelperService.instance ?: return false
        val rootNode = service.rootInActiveWindow ?: return false
        if (id != null) {
            rootNode.findAccessibilityNodeInfosByViewId(id).forEach { node ->
                if (node.isScrollable) {
                    node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
                    return true
                }
            }
        }
        return findScrollableAndScroll(rootNode, forward = false)
    }

    private fun findScrollableAndScroll(node: AccessibilityNodeInfo?, forward: Boolean): Boolean {
        if (node == null) return false
        if (node.isScrollable) {
            val action = if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            node.performAction(action)
            return true
        }
        for (i in 0 until node.childCount) {
            if (findScrollableAndScroll(node.getChild(i), forward)) return true
        }
        return false
    }

    // ── Type Text ──────────────────────────────────────────────
    fun typeText(text: String, fieldId: String? = null, fieldHint: String? = null): Boolean {
        val rootNode = AccessibilityHelperService.instance?.rootInActiveWindow ?: return false
        val target = when {
            fieldId != null -> rootNode.findAccessibilityNodeInfosByViewId(fieldId).firstOrNull()
            fieldHint != null -> findByHint(rootNode, fieldHint)
            else -> findFocusedEditText(rootNode) ?: findAnyEditText(rootNode)
        } ?: return false

        target.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        val args = Bundle().apply { putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }
        target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        Log.d(TAG, "Typed: '$text'")
        return true
    }

    // ── Clear Text ─────────────────────────────────────────────
    fun clearText(fieldId: String? = null): Boolean {
        return typeText("", fieldId)
    }

    // ── Press Back ─────────────────────────────────────────────
    fun pressBack(): Boolean {
        val service = AccessibilityHelperService.instance ?: return false
        service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
        return true
    }

    // ── Press Home ─────────────────────────────────────────────
    fun pressHome(): Boolean {
        val service = AccessibilityHelperService.instance ?: return false
        service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
        return true
    }

    // ── Recents ────────────────────────────────────────────────
    fun openRecents(): Boolean {
        val service = AccessibilityHelperService.instance ?: return false
        service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)
        return true
    }

    // ── Notifications ──────────────────────────────────────────
    fun openNotifications(): Boolean {
        val service = AccessibilityHelperService.instance ?: return false
        service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)
        return true
    }

    // ── Quick Settings ─────────────────────────────────────────
    fun openQuickSettings(): Boolean {
        val service = AccessibilityHelperService.instance ?: return false
        service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS)
        return true
    }

    // ── Swipe Gesture ──────────────────────────────────────────
    fun swipe(direction: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val service = AccessibilityHelperService.instance ?: return false
        val display = service.resources.displayMetrics
        val w = display.widthPixels.toFloat()
        val h = display.heightPixels.toFloat()

        val path = Path()
        when (direction.lowercase()) {
            "up"    -> { path.moveTo(w/2, h*0.7f); path.lineTo(w/2, h*0.3f) }
            "down"  -> { path.moveTo(w/2, h*0.3f); path.lineTo(w/2, h*0.7f) }
            "left"  -> { path.moveTo(w*0.8f, h/2); path.lineTo(w*0.2f, h/2) }
            "right" -> { path.moveTo(w*0.2f, h/2); path.lineTo(w*0.8f, h/2) }
            else -> return false
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 300))
            .build()
        service.dispatchGesture(gesture, null, null)
        Log.d(TAG, "Swipe: $direction")
        return true
    }

    // ── Get Screen Text ────────────────────────────────────────
    fun getScreenText(): String {
        val rootNode = AccessibilityHelperService.instance?.rootInActiveWindow ?: return ""
        return collectText(rootNode, StringBuilder()).toString().trim()
    }

    private fun collectText(node: AccessibilityNodeInfo?, sb: StringBuilder): StringBuilder {
        if (node == null) return sb
        node.text?.let { if (it.isNotBlank()) sb.appendLine(it.trim()) }
        node.contentDescription?.let { if (it.isNotBlank()) sb.appendLine(it.trim()) }
        for (i in 0 until node.childCount) collectText(node.getChild(i), sb)
        return sb
    }

    // ── Internal helpers ───────────────────────────────────────
    private fun searchAndClick(node: AccessibilityNodeInfo?, text: String?, contentDesc: String?): Boolean {
        if (node == null) return false
        if (text != null && node.text?.toString()?.contains(text, ignoreCase = true) == true && performClick(node)) return true
        if (contentDesc != null && node.contentDescription?.toString()?.contains(contentDesc, ignoreCase = true) == true && performClick(node)) return true
        for (i in 0 until node.childCount) { if (searchAndClick(node.getChild(i), text, contentDesc)) return true }
        return false
    }

    private fun searchAndLongClick(node: AccessibilityNodeInfo?, text: String?, contentDesc: String?): Boolean {
        if (node == null) return false
        if (text != null && node.text?.toString()?.equals(text, ignoreCase = true) == true) {
            if (node.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)) return true
        }
        for (i in 0 until node.childCount) { if (searchAndLongClick(node.getChild(i), text, contentDesc)) return true }
        return false
    }

    private fun performClick(node: AccessibilityNodeInfo): Boolean {
        if (node.isClickable && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
        var parent = node.parent
        while (parent != null) {
            if (parent.isClickable && parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
            parent = parent.parent
        }
        return false
    }

    private fun findFocusedEditText(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isFocused && node.isEditable) return node
        for (i in 0 until node.childCount) {
            findFocusedEditText(node.getChild(i))?.let { return it }
        }
        return null
    }

    /** Focus wala box na mile (ChatGPT jaise apps) to screen ka pehla editable box. */
    private fun findAnyEditText(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable) return node
        for (i in 0 until node.childCount) {
            findAnyEditText(node.getChild(i))?.let { return it }
        }
        return null
    }

    private val sendLabels = setOf("send", "send message", "send prompt", "submit", "भेजें", "भेजो", "सेंड", "सबमिट")

    private fun findSendButton(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        val t = node.text?.toString()?.trim()?.lowercase()
        val d = node.contentDescription?.toString()?.trim()?.lowercase()
        if ((t != null && t in sendLabels) || (d != null && d in sendLabels)) return node
        for (i in 0 until node.childCount) findSendButton(node.getChild(i))?.let { return it }
        return null
    }

    /** Likha hua bhejna: pehle exact "Send" button, nahi mile to keyboard ka Enter. */
    fun submit(): Boolean {
        val service = AccessibilityHelperService.instance ?: return false
        val root = service.rootInActiveWindow ?: return false
        findSendButton(root)?.let { if (performClick(it)) return true }
        val edit = findFocusedEditText(root) ?: findAnyEditText(root)
        if (edit != null && Build.VERSION.SDK_INT >= 30) {
            if (edit.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)) return true
        }
        return false
    }

    private fun findByHint(node: AccessibilityNodeInfo?, hint: String): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.hintText?.toString()?.contains(hint, ignoreCase = true) == true) return node
        for (i in 0 until node.childCount) {
            findByHint(node.getChild(i), hint)?.let { return it }
        }
        return null
    }

    // ── Task 6: bounded story/status automation ──────────────────────────
    private const val STORY_TAG = "SiyaStoryAutomation"
    private const val STORY_TIMEOUT_MS = 120_000L
    private val storyHandler = Handler(Looper.getMainLooper())
    @Volatile private var storyBusy = false
    @Volatile private var storyStage = StoryStage.IDLE
    @Volatile private var storyPlatform = "whatsapp"
    @Volatile private var storyMusic = "Diwali festive instrumental"
    @Volatile private var storyCaption = ""
    @Volatile private var storyStartedAt = 0L
    @Volatile private var storyLastAdvanceAt = 0L
    @Volatile private var storyPolls = 0
    @Volatile private var storyContext: Context? = null
    @Volatile private var storyLastMessage = ""

    private enum class StoryStage {
        IDLE, OPEN_APP, OPEN_STORY, PICK_MEDIA, OPEN_STICKERS, OPEN_MUSIC,
        SEARCH_MUSIC, SELECT_MUSIC, ENTER_CAPTION, POST_STORY, VERIFY_POST, FINISHED
    }

    /** Starts a single bounded workflow. Permission/login dialogs are left for the user. */
    fun startStoryStatus(
        context: Context,
        platformName: String,
        musicQuery: String = "Diwali festive instrumental",
        caption: String = ""
    ): String {
        val platform = if (platformName.contains("insta", true)) "instagram" else "whatsapp"
        if (AccessibilityHelperService.instance == null || !AccessibilityHelperService.isEnabled(context)) {
            return "ERROR: Siya Accessibility Service ON karo, phir story dobara bolo."
        }
        synchronized(this) {
            if (storyBusy) return "ERROR: Story workflow pehle se chal raha hai."
            storyBusy = true
            storyStage = StoryStage.OPEN_APP
            storyPlatform = platform
            storyMusic = musicQuery.trim().ifBlank { "Diwali festive instrumental" }.take(120)
            storyCaption = caption.trim().take(500).ifBlank {
                if (musicQuery.contains("romantic", true)) "✨ Kuch pal, kuch yaadein, aur dil ke kareeb log ❤️"
                else "🪔✨ दीपों की रोशनी, खुशियों की मिठास और अपनों का साथ — शुभ दीपावली! 🪔❤️"
            }
            storyStartedAt = SystemClock.elapsedRealtime()
            storyLastAdvanceAt = 0L
            storyPolls = 0
            storyContext = context.applicationContext
            storyLastMessage = ""
        }
        val packageName = if (platform == "instagram") "com.instagram.android" else "com.whatsapp"
        val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent == null) {
            finishStory(false, if (platform == "instagram") "Instagram install nahi hai." else "WhatsApp install nahi hai.")
            return "ERROR: target app install nahi hai."
        }
        return try {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.applicationContext.startActivity(launchIntent)
            scheduleStory(1200L)
            "OK: " + platform.uppercase(Locale.ROOT) + " story workflow shuru. Recent accessible photo aur music '" +
                storyMusic + "' use hoga. Permission/login aaye to screen par complete karo. Maximum wait 2 minute."
        } catch (e: Exception) {
            finishStory(false, "App launch nahi ho saki: " + (e.message ?: "unknown error"))
            "ERROR: app launch nahi ho saki."
        }
    }

    fun onStoryAccessibilityEvent(event: AccessibilityEvent?) {
        if (!storyBusy || storyStage == StoryStage.IDLE || storyStage == StoryStage.FINISHED) return
        val context = storyContext ?: return
        val service = AccessibilityHelperService.instance ?: return
        advanceStory(context, service.rootInActiveWindow)
    }

    private fun scheduleStory(delayMs: Long = 900L) {
        storyHandler.removeCallbacksAndMessages("siya-story")
        val runnable = object : Runnable {
            override fun run() {
                if (!storyBusy || storyStage == StoryStage.IDLE || storyStage == StoryStage.FINISHED) return
                val context = storyContext
                val service = AccessibilityHelperService.instance
                if (context == null || service == null) {
                    finishStory(false, "Accessibility service disconnect ho gayi.")
                    return
                }
                advanceStory(context, service.rootInActiveWindow)
            }
        }
        storyHandler.postAtTime(runnable, "siya-story", SystemClock.uptimeMillis() + delayMs)
    }

    private fun advanceStory(context: Context, root: AccessibilityNodeInfo?) {
        if (!storyBusy || storyStage == StoryStage.IDLE || storyStage == StoryStage.FINISHED) return
        val now = SystemClock.elapsedRealtime()
        if (now - storyStartedAt > STORY_TIMEOUT_MS || storyPolls++ >= 125) {
            finishStory(false, "Story workflow timeout. Current screen check karo; post hua ya nahi confirm nahi hua.")
            return
        }
        if (now - storyLastAdvanceAt < 450L) return
        storyLastAdvanceAt = now
        if (root == null) { scheduleStory(); return }

        val packageName = root.packageName?.toString().orEmpty()
        val screen = storyTreeText(root).lowercase(Locale.ROOT)
        // Never auto-approve permission dialogs or bypass login / verification.
        val appLabel = if (storyPlatform == "instagram") "instagram" else "whatsapp"
        if (packageName.contains("permissioncontroller") || packageName.contains("packageinstaller") ||
            screen.contains("allow access to photos") || screen.contains("allow " + appLabel)) {
            storyStatus("Permission prompt dikh raha hai. Zaroori permission khud approve karo; phir workflow resume hoga.")
            scheduleStory(1800L)
            return
        }
        if (screen.contains("log in") || screen.contains("login") || screen.contains("two-factor") ||
            screen.contains("verification code") || screen.contains("confirm it's you")) {
            storyStatus("Login/verification required. App mein login complete karo; workflow resume hoga.")
            scheduleStory(2200L)
            return
        }

        when (storyStage) {
            StoryStage.OPEN_APP -> {
                val expected = if (storyPlatform == "instagram") "com.instagram.android" else "com.whatsapp"
                if (packageName == expected || packageName.startsWith(expected + ":")) storyStage = StoryStage.OPEN_STORY
            }
            StoryStage.OPEN_STORY -> {
                val labels = if (storyPlatform == "instagram")
                    listOf("add to your story", "add to story", "create story", "new story", "add story")
                else listOf("updates", "status", "my status", "add status")
                if (clickStoryLabel(root, labels)) {
                    storyStage = StoryStage.PICK_MEDIA
                    storyStatus("Story/Status section khol diya.")
                } else if (storyPlatform == "instagram" && clickStoryLabel(root, listOf("create", "add", "plus"))) {
                    storyStage = StoryStage.PICK_MEDIA
                }
            }
            StoryStage.PICK_MEDIA -> {
                val pickerVisible = isMediaPickerPackage(packageName) ||
                    screen.contains("recent photos") || screen.contains("camera roll") ||
                    screen.contains("select photos") || screen.contains("select an item")
                if (pickerVisible) {
                    if (clickNewestAccessibleThumbnail(root)) {
                        storyStage = StoryStage.OPEN_STICKERS
                        storyStatus("Recent photo select ki; music sticker dhoondh rahi hoon.")
                    }
                } else if (clickStoryLabel(root, listOf("gallery", "recent", "camera roll", "photos", "choose from gallery", "select from gallery"))) {
                    storyStatus("Recent photos khol rahi hoon.")
                } else if (clickStoryLabel(root, listOf("camera", "add status", "new story"))) {
                    storyStatus("Story composer khula; gallery thumbnail ka wait kar rahi hoon.")
                } else if (screen.contains("recent") || screen.contains("photos") || screen.contains("gallery")) {
                    if (clickNewestAccessibleThumbnail(root)) {
                        storyStage = StoryStage.OPEN_STICKERS
                        storyStatus("Recent photo select ki; music sticker dhoondh rahi hoon.")
                    }
                }
            }
            StoryStage.OPEN_STICKERS -> {
                if (clickStoryLabel(root, listOf("music", "add music", "audio", "music sticker"))) {
                    storyStage = StoryStage.SEARCH_MUSIC
                } else if (clickStoryLabel(root, listOf("stickers", "sticker tray", "add sticker"))) {
                    storyStage = StoryStage.OPEN_MUSIC
                }
            }
            StoryStage.OPEN_MUSIC -> {
                if (clickStoryLabel(root, listOf("music", "add music", "audio"))) storyStage = StoryStage.SEARCH_MUSIC
            }
            StoryStage.SEARCH_MUSIC -> {
                val field = findStoryEditable(root, listOf("search music", "search songs", "search audio", "search"))
                if (field != null && setStoryText(field, storyMusic)) {
                    storyStage = StoryStage.SELECT_MUSIC
                    scheduleStory(700L)
                    return
                }
            }
            StoryStage.SELECT_MUSIC -> {
                val terms = storyMusic.split(Regex("\\s+")).filter { it.length >= 3 }.take(4)
                val matching = findStoryNode(root) { node ->
                    val label = storyNodeLabel(node).lowercase(Locale.ROOT)
                    label.isNotBlank() && !node.isEditable && !label.contains("search") &&
                        terms.any { label.contains(it.lowercase(Locale.ROOT)) } &&
                        (node.isClickable || node.parent?.isClickable == true)
                }
                val result = matching ?: if (screen.contains("results") || screen.contains("songs") || screen.contains("tracks")) findFirstMusicResult(root) else null
                if (result != null && clickStoryNode(result)) {
                    storyStage = StoryStage.ENTER_CAPTION
                    storyStatus("Music result select kiya.")
                }
            }
            StoryStage.ENTER_CAPTION -> {
                val field = findStoryEditable(root, listOf("caption", "write a caption", "add a caption", "say something", "describe your status"))
                if (field != null && setStoryText(field, storyCaption)) {
                    storyStage = StoryStage.POST_STORY
                    scheduleStory(600L)
                    return
                }
                if (hasStoryLabel(root, listOf("send", "share", "your story", "my status", "share to story", "post"))) {
                    storyStage = StoryStage.POST_STORY
                }
            }
            StoryStage.POST_STORY -> {
                val labels = if (storyPlatform == "instagram")
                    listOf("share to story", "your story", "share", "post")
                else listOf("my status", "send")
                if (clickStoryLabel(root, labels)) {
                    storyStage = StoryStage.VERIFY_POST
                    storyStatus("Post action press kiya; success verify kar rahi hoon.")
                    scheduleStory(1500L)
                    return
                }
            }
            StoryStage.VERIFY_POST -> {
                val success = screen.contains("shared") || screen.contains("posted") ||
                    screen.contains("added to your story") || screen.contains("added to your status") ||
                    screen.contains("status updated") || screen.contains("your story is live") ||
                    screen.contains("story shared")
                if (success) {
                    finishStory(true, "Story/status post hone ki confirmation mil gayi.")
                    return
                }
                if (storyPlatform == "whatsapp" && (screen.contains("my status") || screen.contains("updates"))) {
                    finishStory(true, "WhatsApp Status screen par wapas aa gayi; status post hua lagta hai.")
                    return
                }
            }
            StoryStage.IDLE, StoryStage.FINISHED -> return
        }
        scheduleStory()
    }

    private fun storyTreeText(root: AccessibilityNodeInfo): String {
        val out = StringBuilder()
        fun visit(node: AccessibilityNodeInfo?) {
            if (node == null) return
            out.append(storyNodeLabel(node)).append('\n')
            for (i in 0 until node.childCount) visit(node.getChild(i))
        }
        visit(root)
        return out.toString()
    }

    private fun storyNodeLabel(node: AccessibilityNodeInfo): String =
        listOfNotNull(node.text?.toString(), node.contentDescription?.toString(), node.hintText?.toString())
            .joinToString(" ").trim()

    private fun findStoryNode(root: AccessibilityNodeInfo, predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        if (predicate(root)) return root
        for (i in 0 until root.childCount) {
            val child = root.getChild(i) ?: continue
            findStoryNode(child, predicate)?.let { return it }
        }
        return null
    }

    private fun findStoryEditable(root: AccessibilityNodeInfo, hints: List<String>): AccessibilityNodeInfo? {
        return findStoryNode(root) { node ->
            node.isEditable && node.isEnabled && hints.any { storyNodeLabel(node).contains(it, true) }
        } ?: findStoryNode(root) { node -> node.isEditable && node.isEnabled }
    }

    private fun setStoryText(node: AccessibilityNodeInfo, value: String): Boolean {
        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value) }
        if (node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) return true
        return try {
            val ctx = storyContext ?: return false
            val clipboard = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Siya story", value))
            node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        } catch (_: Exception) { false }
    }

    private fun clickStoryLabel(root: AccessibilityNodeInfo, labels: List<String>): Boolean {
        val target = findStoryNode(root) { node ->
            val label = storyNodeLabel(node).trim()
            label.isNotEmpty() && labels.any { wanted ->
                label.equals(wanted, true) || (label.length <= 50 && label.contains(wanted, true))
            } && (node.isClickable || node.parent?.isClickable == true)
        } ?: return false
        return clickStoryNode(target)
    }

    private fun hasStoryLabel(root: AccessibilityNodeInfo, labels: List<String>): Boolean =
        findStoryNode(root) { node -> labels.any { storyNodeLabel(node).contains(it, true) } } != null

    private fun clickStoryNode(target: AccessibilityNodeInfo): Boolean {
        if (target.isEnabled && target.isClickable && target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
        var parent = target.parent
        var depth = 0
        while (parent != null && depth++ < 5) {
            if (parent.isEnabled && parent.isClickable && parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
            parent = parent.parent
        }
        return false
    }

    private fun clickNewestAccessibleThumbnail(root: AccessibilityNodeInfo): Boolean {
        val candidates = ArrayList<AccessibilityNodeInfo>()
        fun walk(node: AccessibilityNodeInfo?) {
            if (node == null) return
            val label = storyNodeLabel(node).lowercase(Locale.ROOT)
            val cls = node.className?.toString().orEmpty()
            if (node.isEnabled && (node.isClickable || node.parent?.isClickable == true) &&
                (cls.contains("ImageView", true) || cls.contains("Image", true) ||
                    label.contains("photo") || label.contains("image") || label.contains("thumbnail")) &&
                !label.contains("camera") && !label.contains("close") && !label.contains("back")) {
                candidates.add(node)
            }
            for (i in 0 until node.childCount) walk(node.getChild(i))
        }
        walk(root)
        return candidates.firstOrNull()?.let { clickStoryNode(it) } ?: false
    }

    private fun findFirstMusicResult(root: AccessibilityNodeInfo): AccessibilityNodeInfo? =
        findStoryNode(root) { node ->
            val cls = node.className?.toString().orEmpty()
            val label = storyNodeLabel(node).lowercase(Locale.ROOT)
            node.isEnabled && (node.isClickable || node.parent?.isClickable == true) &&
                label.isNotBlank() && !label.contains("search") &&
                (cls.contains("TextView", true) || cls.contains("ViewGroup", true))
        }

    private fun isMediaPickerPackage(packageName: String): Boolean =
        packageName.contains("documentsui") || packageName.contains("mediaprovider") ||
            packageName.contains("photo") || packageName.contains("gallery")

    private fun storyStatus(message: String) {
        if (message == storyLastMessage) return
        storyLastMessage = message
        Log.i(STORY_TAG, message)
    }

    private fun finishStory(success: Boolean, message: String) {
        storyHandler.removeCallbacksAndMessages("siya-story")
        storyStatus(message)
        storyStage = StoryStage.FINISHED
        storyBusy = false
        storyContext = null
        Log.i(STORY_TAG, "completed success=" + success)
    }

}
