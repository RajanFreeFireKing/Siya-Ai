package com.siya.ai.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings

/** Feature 8: voice se system settings. Jo cheez Android programmatically allow nahi karta wahan seedha panel kholta hai. */
object SystemControl {
    private fun go(ctx: Context, i: Intent) = try { ctx.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true } catch (_: Exception) { false }

    fun brightness(ctx: Context, level: String): String {
        if (!Settings.System.canWrite(ctx)) {
            go(ctx, Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${ctx.packageName}")))
            return "ERROR: 'Modify system settings' permission chahiye, settings khol di hai - ON karo"
        }
        val cur = Settings.System.getInt(ctx.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128)
        val v = when (level.lowercase()) {
            "up" -> cur + 40
            "down" -> cur - 40
            "max" -> 255
            "min" -> 10
            else -> ((level.toIntOrNull() ?: return "ERROR: up, down, max, min ya 0-100 do") * 255 / 100)
        }.coerceIn(5, 255)
        Settings.System.putInt(ctx.contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
        Settings.System.putInt(ctx.contentResolver, Settings.System.SCREEN_BRIGHTNESS, v)
        return "OK: brightness ${v * 100 / 255}%"
    }

    /** Android 10+ par app wifi / bluetooth / hotspot seedha ON-OFF nahi kar sakta -> panel kholta hai. */
    fun toggle(ctx: Context, what: String): String {
        val ok = when (what.lowercase()) {
            "wifi" -> go(ctx, Intent(Settings.Panel.ACTION_WIFI))
            "internet", "data" -> go(ctx, Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY))
            "bluetooth" -> go(ctx, Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            "hotspot" -> go(ctx, Intent().setClassName("com.android.settings", "com.android.settings.TetherSettings"))
                || go(ctx, Intent(Settings.ACTION_WIRELESS_SETTINGS))
            "airplane" -> go(ctx, Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS))
            "location" -> go(ctx, Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            "dnd" -> go(ctx, Intent(Settings.ACTION_ZEN_MODE_PRIORITY_SETTINGS))
            else -> return "ERROR: wifi, bluetooth, hotspot, airplane, location, dnd, internet"
        }
        return if (ok) "OK: $what ka panel khol diya - ek tap se ON/OFF ho jayega" else "ERROR: $what panel nahi khula"
    }
}
