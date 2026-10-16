package com.siya.ai.service

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.util.Log
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
}