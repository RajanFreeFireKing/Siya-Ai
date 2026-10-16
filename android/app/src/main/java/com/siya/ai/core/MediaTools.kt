package com.siya.ai.core

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.provider.Settings
import com.siya.ai.service.SiyaNotificationListener

/** "Abhi kya chal raha hai?" aur play / pause / next / previous. */
object MediaTools {

    fun hasAccess(ctx: Context): Boolean {
        val flat = Settings.Secure.getString(ctx.contentResolver, "enabled_notification_listeners") ?: return false
        return flat.contains(ctx.packageName)
    }

    private fun sessions(ctx: Context): List<MediaController> = try {
        val msm = ctx.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        msm.getActiveSessions(ComponentName(ctx, SiyaNotificationListener::class.java))
    } catch (_: Exception) { emptyList() }

    private fun best(ctx: Context): MediaController? {
        val l = sessions(ctx)
        return l.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: l.firstOrNull()
    }

    fun nowPlaying(ctx: Context): String {
        if (!hasAccess(ctx)) return "ERROR: Notification access OFF hai (Settings > Access & Security > Media access). Tab tak listen_around tool se awaaz sun lo."
        val all = sessions(ctx)
        if (all.isEmpty()) return "Abhi koi gaana / video chal nahi raha."
        return all.joinToString("\n") { c ->
            val m = c.metadata
            val st = when (c.playbackState?.state) {
                PlaybackState.STATE_PLAYING -> "chal raha hai"
                PlaybackState.STATE_PAUSED -> "pause hai"
                else -> "ruka hua"
            }
            val title = m?.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty().ifBlank { "(naam nahi mila)" }
            val artist = (m?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: m?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)).orEmpty()
            val app = try { ctx.packageManager.getApplicationLabel(ctx.packageManager.getApplicationInfo(c.packageName, 0)).toString() } catch (_: Exception) { c.packageName }
            "$app: $title${if (artist.isNotBlank()) " - $artist" else ""} ($st)"
        }
    }

    fun control(ctx: Context, action: String): String {
        if (!hasAccess(ctx)) return "ERROR: Notification access OFF hai (Settings > Access & Security > Media access)"
        val c = best(ctx) ?: return "ERROR: koi media player nahi mila"
        val t = c.transportControls
        when (action.lowercase()) {
            "play" -> t.play()
            "pause" -> t.pause()
            "next" -> t.skipToNext()
            "previous", "prev" -> t.skipToPrevious()
            "stop" -> t.stop()
            else -> return "ERROR: action play / pause / next / previous / stop mein se do"
        }
        return "OK: $action kar diya"
    }
}
