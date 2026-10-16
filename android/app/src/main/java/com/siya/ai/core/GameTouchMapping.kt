package com.siya.ai.core

import android.content.Context
import android.util.DisplayMetrics
import android.view.WindowManager
import org.json.JSONObject
import java.util.Locale

/** User-configurable OpenGL-game touch coordinates stored as screen percentages. */
object GameTouchMapping {
    enum class Button(val key: String, val label: String) {
        FIRE("fire", "FIRE"), JUMP("jump", "JUMP"), CROUCH("crouch", "CROUCH"),
        GLOO_WALL("gloo_wall", "GLOO WALL"), SPRINT("sprint", "SPRINT"), JOYSTICK("joystick", "JOYSTICK");
        companion object {
            fun from(value: String): Button? {
                val q = value.trim().lowercase(Locale.ROOT).replace("-", "_").replace(" ", "_")
                return values().firstOrNull { it.key == q || it.name.lowercase(Locale.ROOT) == q ||
                    (it == GLOO_WALL && q in setOf("gloo", "wall", "gloo_wall_button")) ||
                    (it == FIRE && q in setOf("shoot", "fire_button")) }
            }
        }
    }
    data class Point(val xPercent: Float, val yPercent: Float) {
        fun toPixels(width: Int, height: Int): Pair<Float, Float> =
            (xPercent.coerceIn(0f, 100f) * width / 100f) to (yPercent.coerceIn(0f, 100f) * height / 100f)
    }
    fun screenSize(context: Context): Pair<Int, Int> {
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(dm)
        return dm.widthPixels.coerceAtLeast(1) to dm.heightPixels.coerceAtLeast(1)
    }
    fun isLandscape(context: Context): Boolean { val (w,h)=screenSize(context); return w >= h }
    private fun key(context: Context) = if (isLandscape(context)) "game_touch_mapping_landscape" else "game_touch_mapping_portrait"
    private fun defaults(context: Context): Map<Button, Point> = if (isLandscape(context)) mapOf(
        Button.FIRE to Point(92f,64f), Button.JUMP to Point(82f,46f), Button.CROUCH to Point(85f,73f),
        Button.GLOO_WALL to Point(75f,63f), Button.SPRINT to Point(25f,73f), Button.JOYSTICK to Point(14f,73f)
    ) else mapOf(
        Button.FIRE to Point(88f,66f), Button.JUMP to Point(78f,51f), Button.CROUCH to Point(84f,75f),
        Button.GLOO_WALL to Point(71f,66f), Button.SPRINT to Point(24f,78f), Button.JOYSTICK to Point(15f,78f)
    )
    fun get(context: Context, button: Button): Point {
        val fallback=defaults(context).getValue(button)
        return try {
            val j=JSONObject(context.getSharedPreferences("siya_prefs",Context.MODE_PRIVATE).getString(key(context),"{}") ?: "{}")
            val p=j.optJSONObject(button.key) ?: return fallback
            Point(p.optDouble("x",fallback.xPercent.toDouble()).toFloat().coerceIn(0f,100f),
                p.optDouble("y",fallback.yPercent.toDouble()).toFloat().coerceIn(0f,100f))
        } catch (_:Exception) { fallback }
    }
    fun set(context: Context, button: Button, x: Float, y: Float): Point {
        val p=Point(x.coerceIn(0f,100f),y.coerceIn(0f,100f))
        val prefs=context.getSharedPreferences("siya_prefs",Context.MODE_PRIVATE)
        val j=try { JSONObject(prefs.getString(key(context),"{}") ?: "{}") } catch (_:Exception) { JSONObject() }
        j.put(button.key,JSONObject().put("x",p.xPercent.toDouble()).put("y",p.yPercent.toDouble()))
        prefs.edit().putString(key(context),j.toString()).apply()
        return p
    }
    fun all(context: Context): Map<Button,Point> = Button.values().associateWith { get(context,it) }
    fun summary(context: Context): String = "Touch map ("+(if(isLandscape(context)) "landscape" else "portrait")+"): "+
        all(context).entries.joinToString("; ") { it.key.label+"="+"%.1f".format(Locale.ROOT,it.value.xPercent)+"%,"+"%.1f".format(Locale.ROOT,it.value.yPercent)+"%" }
}
