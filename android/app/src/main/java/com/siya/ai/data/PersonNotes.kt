package com.siya.ai.data

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import com.siya.ai.R
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Feature 6: kisi insaan ke baare mein notes ("Ramesh ne ₹500 liye the") + uska call aate hi alert. */
object PersonNotes {
    private fun f(ctx: Context) = File(ctx.filesDir, "people_notes.json")
    private fun load(ctx: Context) = try { JSONObject(f(ctx).readText()) } catch (_: Exception) { JSONObject() }
    private fun last10(n: String) = n.filter { it.isDigit() }.takeLast(10)

    fun add(ctx: Context, name: String, note: String, number: String): String {
        val o = load(ctx); val k = name.trim().lowercase()
        val p = o.optJSONObject(k) ?: JSONObject().put("name", name.trim()).put("notes", JSONArray())
        p.getJSONArray("notes").put(note.trim())
        if (number.isNotBlank()) p.put("number", last10(number))
        o.put(k, p); f(ctx).writeText(o.toString())
        return "OK: ${name.trim()} ke baare mein note save"
    }

    fun get(ctx: Context, name: String): String {
        val o = load(ctx); val q = name.trim().lowercase()
        val k = o.keys().asSequence().firstOrNull { it == q || it.contains(q) } ?: return "Is naam ka koi note nahi"
        val p = o.getJSONObject(k)
        return "${p.getString("name")}: " + (0 until p.getJSONArray("notes").length()).joinToString("; ") { p.getJSONArray("notes").getString(it) }
    }

    fun clear(ctx: Context, name: String): String { val o = load(ctx); o.remove(name.trim().lowercase()); f(ctx).writeText(o.toString()); return "OK: notes hata diye" }

    /** Number ya contact ke naam se notes dhundo; mile to heads-up notification: "Ramesh calling (Isne paise dene hain)". */
    fun alertForCall(ctx: Context, number: String, contactName: String) {
        val o = load(ctx); val n10 = last10(number)
        val k = o.keys().asSequence().firstOrNull { key ->
            val p = o.getJSONObject(key)
            (n10.length >= 7 && p.optString("number") == n10) || (contactName.isNotBlank() && contactName != "Unknown Caller" && contactName.lowercase().contains(key))
        } ?: return
        val p = o.getJSONObject(k); val notes = p.getJSONArray("notes")
        val text = (0 until notes.length()).joinToString("; ") { notes.getString(it) }
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel("siya_callnote", "Siya call note", NotificationManager.IMPORTANCE_HIGH))
        nm.notify(7300, NotificationCompat.Builder(ctx, "siya_callnote").setSmallIcon(R.drawable.ic_siya_notif)
            .setContentTitle("${p.getString("name")} calling").setContentText("($text)")
            .setStyle(NotificationCompat.BigTextStyle().bigText(text)).setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL).setTimeoutAfter(30_000).build())
    }
}
