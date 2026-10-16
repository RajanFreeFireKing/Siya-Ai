package com.siya.ai.core

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CallLog
import android.provider.ContactsContract
import com.siya.ai.ui.widget.FloatingWindow

/**
 * "Jiska number ... 47 par khatam hota hai": contacts + call log mein last digits se milte numbers dhundo,
 * popup mein dikhao (tap = call) aur Siya ko list do taaki wo zor se pooch sake.
 */
object CallFinder {
    data class Hit(val name: String, val number: String, val source: String)

    private fun digits(s: String) = s.filter { it.isDigit() }

    fun find(ctx: Context, suffix: String): List<Hit> {
        val d = digits(suffix)
        if (d.length < 2) return emptyList()
        val seen = LinkedHashMap<String, Hit>()   // normalized (last 10 digits) -> hit
        fun add(h: Hit) {
            val key = digits(h.number).takeLast(10)
            val old = seen[key]
            if (old == null || (old.name.isBlank() && h.name.isNotBlank())) seen[key] = h
        }
        if (ctx.checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
            try {
                ctx.contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
                    null, null, null)?.use { c ->
                    while (c.moveToNext()) {
                        val num = c.getString(1) ?: continue
                        if (digits(num).endsWith(d)) add(Hit(c.getString(0).orEmpty(), num, "contact"))
                    }
                }
            } catch (_: Exception) {}
        }
        if (ctx.checkSelfPermission(Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED) {
            try {
                ctx.contentResolver.query(CallLog.Calls.CONTENT_URI,
                    arrayOf(CallLog.Calls.CACHED_NAME, CallLog.Calls.NUMBER), null, null, "${CallLog.Calls.DATE} DESC LIMIT 400")?.use { c ->
                    while (c.moveToNext()) {
                        val num = c.getString(1) ?: continue
                        if (digits(num).endsWith(d)) add(Hit(c.getString(0).orEmpty(), num, "recent call"))
                    }
                }
            } catch (_: Exception) {}
        }
        return seen.values.take(8)
    }

    fun call(ctx: Context, number: String): Boolean = try {
        ctx.startActivity(Intent(Intent.ACTION_CALL, Uri.parse("tel:" + Uri.encode(number))).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Exception) { false }

    /** Tool: popup dikhao + text list lautao. */
    fun run(ctx: Context, suffix: String): String {
        if (ctx.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED &&
            ctx.checkSelfPermission(Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED)
            return "ERROR: Contacts / Call log permission nahi hai (Settings > Permissions)"
        val hits = find(ctx, suffix)
        if (hits.isEmpty()) return "NOT_FOUND: '$suffix' par khatam hone wala koi number nahi mila"
        FloatingWindow.showCandidates(ctx, "Kise call karna hai? (…${digits(suffix)})",
            hits.map { (it.name.ifBlank { "Naam save nahi" }) to it.number }) { number -> call(ctx, number) }
        val list = hits.mapIndexed { i, h -> "${i + 1}. ${h.name.ifBlank { "naam save nahi" }} - ${h.number} (${h.source})" }.joinToString("\n")
        return if (hits.size == 1) "Ek hi number mila:\n$list\nUser se pooch kar call_contact(number) se call karo."
        else "${hits.size} numbers mile (popup mein bhi dikh rahe hain, tap karke call hoga):\n$list\nUser se zor se pucho kaun sa call karna hai, phir call_contact(number) karo."
    }
}
