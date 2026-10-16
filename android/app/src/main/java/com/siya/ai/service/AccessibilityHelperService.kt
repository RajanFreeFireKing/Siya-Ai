package com.siya.ai.service

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.provider.Settings
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import com.siya.ai.security.SosManager
import com.siya.ai.automation.BrowserAutomationEngine

class AccessibilityHelperService : AccessibilityService() {

    companion object {
        var instance: AccessibilityHelperService? = null
            private set

        // Ye check karta hai ki kya user ne Accessibility permission on ki hai
        fun isEnabled(context: Context): Boolean {
            var accessibilityEnabled = 0
            val service = "${context.packageName}/${AccessibilityHelperService::class.java.canonicalName}"
            try {
                accessibilityEnabled = Settings.Secure.getInt(
                    context.applicationContext.contentResolver,
                    Settings.Secure.ACCESSIBILITY_ENABLED
                )
            } catch (e: Settings.SettingNotFoundException) {
                e.printStackTrace()
            }
            if (accessibilityEnabled == 1) {
                val settingValue = Settings.Secure.getString(
                    context.applicationContext.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                )
                if (settingValue != null) {
                    return settingValue.contains(service)
                }
            }
            return false
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Feed the bounded image-generation workflow; it ignores events while idle.
        BrowserAutomationEngine.onAccessibilityEvent(event)
        SmartAccessibilityEngine.onStoryAccessibilityEvent(event)
    }

    // Feature 15: Volume DOWN 3 baar (2 second ke andar) = SOS
    private val volPresses = ArrayList<Long>()
    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN &&
            getSharedPreferences("siya_prefs", MODE_PRIVATE).getBoolean("sos_volume_enabled", false)) {
            val now = System.currentTimeMillis()
            volPresses.removeAll { now - it > 2000 }
            volPresses.add(now)
            if (volPresses.size >= 3) { volPresses.clear(); Thread { SosManager.trigger(applicationContext) }.start() }
        }
        return false   // volume normal kaam karta rahe
    }

    override fun onInterrupt() {
        // Service interrupt hone par handle karna
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }
}
