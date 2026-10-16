package com.siya.ai.security

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.telephony.SmsManager
import com.siya.ai.data.LocationHelper
import java.io.File

/** Feature 15 (SOS): emergency contacts ko GPS location SMS + background audio recording. */
object SosManager {
    private var rec: MediaRecorder? = null
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)

    fun setContacts(ctx: Context, numbers: String): String {
        val list = numbers.split(",", ";", " ").map { it.trim() }.filter { it.length >= 6 }
        prefs(ctx).edit().putString("sos_contacts", list.joinToString(",")).apply()
        return "OK: ${list.size} emergency number save"
    }

    fun trigger(ctx: Context): String {
        val nums = prefs(ctx).getString("sos_contacts", "").orEmpty().split(",").filter { it.isNotBlank() }
        if (nums.isEmpty()) return "ERROR: pehle emergency contacts set karo"
        val l = LocationHelper.device(ctx)
        val where = l?.let { "https://maps.google.com/?q=${it.latitude},${it.longitude}" } ?: "location nahi mili"
        val msg = "SOS! Mujhe madad chahiye. Meri location: $where"
        var sent = 0
        val sm = if (Build.VERSION.SDK_INT >= 31) ctx.getSystemService(SmsManager::class.java) else @Suppress("DEPRECATION") SmsManager.getDefault()
        for (n in nums) try { sm.sendMultipartTextMessage(n, null, sm.divideMessage(msg), null, null); sent++ } catch (_: Exception) {}
        startRecording(ctx)
        return "OK: SOS $sent logon ko bheja, recording chalu"
    }

    private fun startRecording(ctx: Context) {
        if (rec != null) return
        try {
            val dir = File(ctx.filesDir, "sos").apply { mkdirs() }
            @Suppress("DEPRECATION")
            rec = (if (Build.VERSION.SDK_INT >= 31) MediaRecorder(ctx) else MediaRecorder()).apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setOutputFile(File(dir, "sos_${System.currentTimeMillis()}.m4a").absolutePath)
                prepare(); start()
            }
        } catch (_: Exception) { rec = null }
    }

    fun stopRecording() { try { rec?.stop(); rec?.release() } catch (_: Exception) {}; rec = null }
}
