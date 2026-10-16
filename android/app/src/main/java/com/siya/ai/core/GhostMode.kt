package com.siya.ai.core

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/** Feature 15: Ghost Mode. App launcher mein "Calculator" ban jaata hai; secret code + "=" se asli Siya khulti hai. */
object GhostMode {
    fun isOn(ctx: Context) = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getBoolean("ghost_mode", false)

    fun set(ctx: Context, on: Boolean, code: String? = null): String {
        val prefs = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)
        if (!code.isNullOrBlank()) {
            if (code.length < 3 || !code.all { it.isDigit() }) return "ERROR: code sirf ank (kam se kam 3) hona chahiye"
            prefs.edit().putString("ghost_code", code).apply()
        }
        prefs.edit().putBoolean("ghost_mode", on).apply()
        apply(ctx)
        return if (on) "OK: Ghost mode ON. Ab app 'Calculator' dikhega. Code ${prefs.getString("ghost_code", "2580")} dabake = dabao to Siya khulegi. Launcher icon badalne mein kuch second lagte hain."
        else "OK: Ghost mode OFF, normal icon wapas"
    }

    fun apply(ctx: Context) {
        val pm = ctx.packageManager; val on = isOn(ctx)
        fun sw(cls: String, enable: Boolean) = pm.setComponentEnabledSetting(ComponentName(ctx.packageName, "${ctx.packageName}.ui.main.$cls"),
            if (enable) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
        sw("GhostLauncher", on); sw("NormalLauncher", !on)
    }
}
