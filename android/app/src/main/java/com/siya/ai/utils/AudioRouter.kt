package com.siya.ai.utils

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build

/**
 * Bluetooth headset / earbuds connected ho to mic aur speaker dono usi se chalte hain.
 * Session shuru hote hi enter(), khatam hone par exit().
 */
object AudioRouter {
    @Volatile var btActive = false
        private set
    private var scoStarted = false
    private var prevMode = AudioManager.MODE_NORMAL

    private fun canBt(ctx: Context) =
        Build.VERSION.SDK_INT < 31 ||
            ctx.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun btInput(am: AudioManager): AudioDeviceInfo? =
        am.getDevices(AudioManager.GET_DEVICES_INPUTS).firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                (Build.VERSION.SDK_INT >= 31 && it.type == AudioDeviceInfo.TYPE_BLE_HEADSET)
        }

    private fun btOutput(am: AudioManager): AudioDeviceInfo? =
        am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                (Build.VERSION.SDK_INT >= 31 && it.type == AudioDeviceInfo.TYPE_BLE_HEADSET)
        }

    /** Bluetooth mic mile to uska AudioDeviceInfo (AudioRecord.setPreferredDevice ke liye), warna null. */
    @Suppress("DEPRECATION")
    fun enter(ctx: Context): AudioDeviceInfo? {
        if (!canBt(ctx)) return null
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val input = btInput(am)
        val hasHeadsetProfile = input != null || (Build.VERSION.SDK_INT < 31 && am.isBluetoothScoAvailableOffCall && am.isBluetoothA2dpOn)
        if (!hasHeadsetProfile) { btActive = false; return null }
        try {
            if (!btActive) prevMode = am.mode
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= 31) {
                val out = btOutput(am)
                if (out != null) am.setCommunicationDevice(out)
            } else if (!scoStarted) {
                am.startBluetoothSco(); am.isBluetoothScoOn = true; scoStarted = true
            }
            btActive = true
            // SCO link ko jud jaane ka thoda waqt
            Thread.sleep(500)
        } catch (_: Exception) { btActive = false }
        return input
    }

    @Suppress("DEPRECATION")
    fun exit(ctx: Context) {
        if (!btActive && !scoStarted) return
        try {
            val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= 31) am.clearCommunicationDevice()
            else if (scoStarted) { am.isBluetoothScoOn = false; am.stopBluetoothSco() }
            am.mode = prevMode
        } catch (_: Exception) {}
        scoStarted = false
        btActive = false
    }
}
