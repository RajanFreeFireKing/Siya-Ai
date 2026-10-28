package com.siya.ai.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Feature 11: UPI / bank SMS se roz ka kharcha. Data sirf phone mein (siya_ledger.json). */
object SmsLedger {
    private val amt = Regex("""(?:rs\.?|inr|₹)\s?([0-9][0-9,]*\.?[0-9]*)""", RegexOption.IGNORE_CASE)
    private val debit = Regex("""debited|paid|sent|spent|withdrawn|purchase|transferred to""", RegexOption.IGNORE_CASE)
    private val credit = Regex("""credited|received|deposited""", RegexOption.IGNORE_CASE)
    private fun file(ctx: Context) = java.io.File(ctx.filesDir, "siya_ledger.json")
    private fun day(t: Long = System.currentTimeMillis()) = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(t))

    private fun load(ctx: Context) = try { JSONArray(file(ctx).readText()) } catch (_: Exception) { JSONArray() }

    /** SMS parse karke ledger mein add. Return: add hui entry ka text (ya null agar paisa wala SMS nahi). */
    fun ingest(ctx: Context, sender: String, body: String): String? {
        val m = amt.find(body) ?: return null
        val kind = when { debit.containsMatchIn(body) -> "debit"; credit.containsMatchIn(body) -> "credit"; else -> return null }
        val a = m.groupValues[1].replace(",", "").toDoubleOrNull() ?: return null
        val arr = load(ctx)
        arr.put(JSONObject().put("t", System.currentTimeMillis()).put("day", day()).put("kind", kind).put("amount", a).put("from", sender).put("note", body.take(120)).put("counted", false))
        file(ctx).writeText(arr.toString())
        return "${if (kind == "debit") "₹${a.toInt()} cut gaye" else "₹${a.toInt()} aaye"} ($sender)"
    }

    fun summary(ctx: Context, which: String): String {
        val arr = load(ctx)
        val today = day()
        val month = today.take(7)
        var out = 0.0; var inn = 0.0; val lines = ArrayList<String>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val d = o.getString("day")
            if (if (which == "month") !d.startsWith(month) else d != today) continue
            val a = o.getDouble("amount")
            if (o.getString("kind") == "debit") out += a else inn += a
            lines.add("${if (o.getString("kind") == "debit") "-" else "+"}₹${a.toInt()} ${o.getString("from")}")
        }
        if (lines.isEmpty()) return "Is ${if (which == "month") "mahine" else "din"} koi UPI / bank SMS nahi mila"
        return "Kharcha ₹${out.toInt()}, aaya ₹${inn.toInt()}.\n" + lines.takeLast(15).joinToString("\n")
    }

    fun getEntries(ctx: Context): List<Map<String, Any>> {
        val arr = load(ctx)
        val list = ArrayList<Map<String, Any>>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            list.add(mapOf(
                "t" to o.optLong("t", 0L),
                "day" to o.optString("day", ""),
                "kind" to o.optString("kind", "debit"),
                "amount" to o.optDouble("amount", 0.0),
                "from" to o.optString("from", ""),
                "note" to o.optString("note", "")
            ))
        }
        return list.reversed()
    }
}
