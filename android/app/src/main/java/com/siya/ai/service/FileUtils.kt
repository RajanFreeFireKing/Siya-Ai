package com.siya.ai.service

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileNotFoundException

/** Copies a nested APK assets directory to app-private storage for native libraries. */
object FileUtils {
    private const val TAG = "SIYA_ASSET_UNPACK"

    @Synchronized
    fun unpackAssetDirectory(context: Context, assetPath: String, destination: File): File {
        val marker = File(destination, "am/final.mdl")
        if (marker.isFile && marker.length() > 0L &&
            File(destination, "conf/model.conf").isFile &&
            File(destination, "graph/HCLr.fst").isFile) return destination

        if (destination.exists()) destination.deleteRecursively()
        if (!destination.mkdirs() && !destination.isDirectory) {
            throw IllegalStateException("Cannot create model directory: ${destination.absolutePath}")
        }
        copyRecursively(context, assetPath.trim('/'), destination)
        if (!marker.isFile || marker.length() == 0L) {
            destination.deleteRecursively()
            throw FileNotFoundException("Vosk model assets incomplete at assets/$assetPath")
        }
        Log.i(TAG, "Unpacked Vosk model to ${destination.absolutePath}")
        return destination
    }

    private fun copyRecursively(context: Context, assetPath: String, destination: File) {
        val children = context.assets.list(assetPath)
            ?: throw FileNotFoundException("Missing asset directory: $assetPath")
        if (children.isNotEmpty()) {
            if (!destination.exists() && !destination.mkdirs()) {
                throw IllegalStateException("Cannot create directory: ${destination.absolutePath}")
            }
            children.forEach { child ->
                copyRecursively(context, "$assetPath/$child", File(destination, child))
            }
            return
        }
        try {
            context.assets.open(assetPath).use { input ->
                destination.parentFile?.let {
                    if (!it.exists() && !it.mkdirs()) throw IllegalStateException("Cannot create ${it.absolutePath}")
                }
                destination.outputStream().use { output -> input.copyTo(output) }
            }
        } catch (e: FileNotFoundException) {
            // Empty directories have no stream; preserve them. Required model files are checked after copy.
            if (!destination.exists() && !destination.mkdirs()) throw e
        }
    }
}
