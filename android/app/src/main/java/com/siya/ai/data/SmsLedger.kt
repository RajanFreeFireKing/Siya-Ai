package com.siya.ai.data

import android.content.Context
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Feature 11: UPI / bank SMS se roz ka kharcha. Data sirf phone mein (siya_ledger.json). */
object SmsLedger {
    private val amt1 = Regex("""(?:rs\.?|inr|₹)\s*([0-9][0-9,]*\.?[0-9]*)""", RegexOption.IGNORE_CASE)
    private val amt2 = Regex("""([0-9][0-9,]*\.?[0-9]*)\s*(?:rs\.?|inr|₹)""", RegexOption.IGNORE_CASE)
    private val debit = Regex("""debited|paid|sent|spent|withdrawn|purchase|transferred|deducted|txn|vpa.*debited""", RegexOption.IGNORE_CASE)
    private val credit = Regex("""credited|received|deposited|refund|cashback""", RegexOption.IGNORE_CASE)

    private fun file(ctx: Context) = java.io.File(ctx.filesDir, "siya_ledger.json")
    private fun day(t: Long = System.currentTimeMillis()) = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(t))

    private fun load(ctx: Context): JSONArray = try { JSONArray(file(ctx).readText()) } catch (_: Exception) { JSONArray() }

    /** SMS parse karke ledger mein add. Return: add hui entry ka text (ya null agar paisa wala SMS nahi). */
    fun ingest(ctx: Context, sender: String, body: String, timestamp: Long = System.currentTimeMillis()): String? {
        val m = amt1.find(body) ?: amt2.find(body) ?: return null
        val aStr = m.groupValues[1].replace(",", "").trim()
        val a = aStr.toDoubleOrNull() ?: return null
        if (a <= 0.0) return null

        val isDebit = debit.containsMatchIn(body)
        val isCredit = credit.containsMatchIn(body)
        val kind = when {
            isDebit -> "debit"
            isCredit -> "credit"
            else -> return null
        }

        val arr = load(ctx)
        // Deduplication
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (Math.abs(o.optLong("t", 0L) - timestamp) < 2000L && Math.abs(o.optDouble("amount") - a) < 0.01) {
                return null
            }
        }

        arr.put(JSONObject().apply {
            put("t", timestamp)
            put("day", day(timestamp))
            put("kind", kind)
            put("amount", a)
            put("from", sender)
            put("note", body.take(160))
            put("counted", false)
        })
        file(ctx).writeText(arr.toString())
        return "${if (kind == "debit") "₹${a.toInt()} cut gaye" else "₹${a.toInt()} aaye"} ($sender)"
    }

    fun syncInbox(ctx: Context, limit: Int = 120): Int {
        if (ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.READ_SMS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            return 0
        }
        var added = 0
        try {
            val uri = android.provider.Telephony.Sms.Inbox.CONTENT_URI
            val proj = arrayOf("address", "body", "date")
            ctx.contentResolver.query(uri, proj, null, null, "date DESC LIMIT $limit")?.use { c ->
                val addrIdx = c.getColumnIndexOrThrow("address")
                val bodyIdx = c.getColumnIndexOrThrow("body")
                val dateIdx = c.getColumnIndexOrThrow("date")
                while (c.moveToNext()) {
                    val addr = c.getString(addrIdx) ?: ""
                    val body = c.getString(bodyIdx) ?: ""
                    val date = c.getLong(dateIdx)
                    val res = ingest(ctx, addr, body, date)
                    if (res != null) added++
                }
            }
        } catch (_: Exception) {}
        return added
    }

    fun summaryMap(ctx: Context, which: String): Map<String, Any> {
        val arr = load(ctx)
        val today = day()
        val month = today.take(7)
        var out = 0.0
        var inn = 0.0
        var count = 0
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val d = o.optString("day")
            if (if (which == "month") !d.startsWith(month) else d != today) continue
            val a = o.optDouble("amount", 0.0)
            if (o.optString("kind") == "debit") out += a else inn += a
            count++
        }
        return mapOf(
            "totalDebit" to out,
            "totalCredit" to inn,
            "count" to count
        )
    }

    fun summary(ctx: Context, which: String): String {
        val m = summaryMap(ctx, which)
        val out = (m["totalDebit"] as? Number)?.toDouble() ?: 0.0
        val inn = (m["totalCredit"] as? Number)?.toDouble() ?: 0.0
        return "Kharcha ₹${out.toInt()}, aaya ₹${inn.toInt()}."
    }

    fun getEntries(ctx: Context): List<Map<String, Any>> {
        val arr = load(ctx)
        val list = ArrayList<Map<String, Any>>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val t = o.optLong("t", 0L)
            val dStr = if (t > 0) SimpleDateFormat("dd MMM, hh:mm a", Locale.getDefault()).format(Date(t)) else o.optString("day", "")
            list.add(mapOf(
                "t" to t,
                "day" to o.optString("day", ""),
                "date" to dStr,
                "kind" to o.optString("kind", "debit"),
                "isDebit" to (o.optString("kind", "debit") == "debit"),
                "amount" to o.optDouble("amount", 0.0),
                "from" to o.optString("from", ""),
                "sender" to o.optString("from", ""),
                "note" to o.optString("note", ""),
                "body" to o.optString("note", "")
            ))
        }
        return list.reversed()
    }

    fun getLedgerData(ctx: Context): Map<String, Any> {
        syncInbox(ctx)
        return mapOf(
            "entries" to getEntries(ctx),
            "daySummary" to summaryMap(ctx, "day"),
            "monthSummary" to summaryMap(ctx, "month")
        )
    }
}
