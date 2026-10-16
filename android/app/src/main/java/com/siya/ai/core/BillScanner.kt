package com.siya.ai.core

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import com.siya.ai.data.ImageUtil
import com.siya.ai.ui.main.CameraCaptureActivity
import org.json.JSONObject

/** Feature 13: camera (ya screen) se bill / handwritten note -> editable text + khud jodkar total. */
object BillScanner {
    fun scan(ctx: Context, source: String): String {
        val jpeg: ByteArray = if (source.equals("screen", true)) {
            val b = GameControl.screenshot(ctx) ?: return "ERROR: screenshot nahi mila"
            ImageUtil.jpeg(ImageUtil.scale(b, 1600), 80)
        } else {
            val bytes = CameraCaptureActivity.capture(ctx, false) ?: return "ERROR: ${CameraCaptureActivity.error ?: "camera se photo nahi aayi"}"
            val bmp = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return "ERROR: photo samajh nahi aayi"
            ImageUtil.jpeg(ImageUtil.scale(bmp, 1600), 82)
        }
        val raw = AiText.generate(ctx, "Is photo ka poora text jaisa likha hai waisa nikalo. Agar ye bill / rasid hai to har item ka naam aur amount bhi nikalo. " +
            "SIRF JSON do, koi markdown nahi: {\"text\":\"poora text\",\"items\":[{\"name\":\"..\",\"amount\":123.5}],\"printed_total\":null ya number}", jpeg)
            ?: return "ERROR: text nahi nikla (API key / internet check karo)"
        return try {
            val j = JSONObject(raw.removePrefix("```json").removePrefix("```").removeSuffix("```").trim())
            val items = j.optJSONArray("items")
            var sum = 0.0; val lines = ArrayList<String>()
            if (items != null) for (i in 0 until items.length()) { val it = items.getJSONObject(i); val a = it.optDouble("amount", 0.0); sum += a; lines.add("${it.optString("name")}: ${a}") }
            val text = j.optString("text")
            (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Siya scan", text))
            val printed = if (j.isNull("printed_total")) "" else "\nBill par likha total: ${j.optDouble("printed_total")}"
            "Text (clipboard mein copy ho gaya, kahin bhi paste kar sakte ho):\n$text\n" +
                (if (lines.isNotEmpty()) "\nItems:\n${lines.joinToString("\n")}\nMeri jod: ${"%.2f".format(sum)}$printed" else "")
        } catch (_: Exception) { "Text:\n$raw" }
    }
}
