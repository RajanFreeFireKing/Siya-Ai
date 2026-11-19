package com.siya.ai.browser

import android.content.Context
import android.util.Log
import com.siya.ai.service.SiyaService
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/**
 * 100% Free OSINT Photo & Name Lookup Feature.
 * Uses OkHttp & ObscuraMobileEngine (Headless Browser) with Zero API cost.
 */
object OsintEngine {
    private const val TAG = "SIYA_OSINT"
    private val client = OkHttpClient.Builder()
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .writeTimeout(25, TimeUnit.SECONDS)
        .build()

    /**
     * Uploads image to Catbox.moe (100% free temporary host) and conducts Yandex Reverse Image search.
     */
    fun imageLookup(ctx: Context, imagePath: String): String {
        Log.i(TAG, "Starting OSINT Image Lookup for: $imagePath")
        val file = File(imagePath)
        if (!file.exists() || !file.isFile) {
            return "ERROR: File not found at path '$imagePath'. Please check if photo exists."
        }

        // Step 1: Upload to Catbox.moe
        val publicUrl: String = try {
            val fileBody = file.asRequestBody("image/*".toMediaType())
            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("reqtype", "fileupload")
                .addFormDataPart("fileToUpload", file.name, fileBody)
                .build()

            val req = Request.Builder()
                .url("https://catbox.moe/user/api.php")
                .post(requestBody)
                .header("User-Agent", "Mozilla/5.0 (Linux; Android 14)")
                .build()

            client.newCall(req).execute().use { resp ->
                val body = resp.body?.string()?.trim().orEmpty()
                if (resp.isSuccessful && body.startsWith("http")) {
                    body
                } else {
                    return "ERROR: Catbox image upload failed (${resp.code}): $body"
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Catbox upload error: ${e.message}", e)
            return "ERROR: Failed to upload image for reverse search: ${e.message}"
        }

        Log.i(TAG, "Image uploaded to Catbox: $publicUrl")

        // Step 2: Query Yandex Reverse Image Search via ObscuraMobileEngine (Headless)
        val yandexUrl = "https://yandex.com/images/search?rpt=imageview&url=" + URLEncoder.encode(publicUrl, "UTF-8")
        val browserResult = ObscuraMobileEngine.open(ctx, yandexUrl)

        // Parse matching links from browser result
        val links = mutableListOf<String>()
        val linkRegex = Regex("""\[\d+\]\s+\[Link\]\s+"([^"]+)"\s+->\s+(https?://[^\s]+)""")
        for (m in linkRegex.findAll(browserResult)) {
            val title = m.groupValues[1]
            val url = m.groupValues[2]
            if (!url.contains("yandex.") && !url.contains("catbox.moe")) {
                links.add("$title: $url")
            }
        }

        val summary = "Yandex Reverse Image Search completed for '$publicUrl'. Found ${links.size} relevant sources."

        // Step 3: Emit to Flutter UI for Dark Glassmorphic Popup
        try {
            SiyaService.eventSink?.invoke(mapOf(
                "type" to "osint_result",
                "mode" to "image",
                "query" to file.name,
                "imageUrl" to publicUrl,
                "summary" to summary,
                "links" to links.take(10)
            ))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to emit osint_result to Flutter: ${e.message}")
        }

        return """
            OSINT Reverse Image Search Results:
            Public Image URL: $publicUrl
            Yandex Analysis:
            ${browserResult.take(1500)}
            Found Sources:
            ${if (links.isEmpty()) "No direct public links found on page." else links.take(8).joinToString("\n")}
        """.trimIndent()
    }

    /**
     * Searches for public footprints (Instagram, YouTube, GitHub, Reddit, Facebook)
     */
    fun nameLookup(ctx: Context, nameOrUsername: String): String {
        val target = nameOrUsername.trim().removePrefix("@")
        Log.i(TAG, "Starting OSINT Name Lookup for: $target")

        val discoveredLinks = mutableListOf<String>()

        // Step 1: Direct public profile probe using OkHttp
        val directPlatforms = listOf(
            "GitHub" to "https://github.com/$target",
            "Reddit" to "https://www.reddit.com/user/$target/about.json",
            "Telegram" to "https://t.me/$target",
            "Instagram" to "https://www.instagram.com/$target/"
        )

        for ((platform, url) in directPlatforms) {
            try {
                val req = Request.Builder()
                    .url(url)
                    .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                    .get()
                    .build()

                client.newCall(req).execute().use { resp ->
                    if (resp.isSuccessful) {
                        if (platform == "Reddit") {
                            val body = resp.body?.string().orEmpty()
                            if (body.contains("\"name\"") && !body.contains("\"error\"")) {
                                discoveredLinks.add("Reddit: https://www.reddit.com/user/$target")
                            }
                        } else {
                            val directUrl = if (platform == "Telegram") "https://t.me/$target" else url
                            discoveredLinks.add("$platform: $directUrl")
                        }
                    }
                }
            } catch (_: Exception) {}
        }

        // Step 2: Obscura headless search for cross-platform mentions
        val searchQuery = "\"$target\" site:instagram.com OR site:youtube.com OR site:facebook.com OR site:github.com OR site:linkedin.com"
        val searchResult = ObscuraMobileEngine.search(ctx, searchQuery)

        val linkRegex = Regex("""\[\d+\]\s+\[Link\]\s+"([^"]+)"\s+->\s+(https?://[^\s]+)""")
        for (m in linkRegex.findAll(searchResult)) {
            val title = m.groupValues[1]
            val url = m.groupValues[2]
            if (!url.contains("duckduckgo.com") && !url.contains("bing.com")) {
                discoveredLinks.add("$title: $url")
            }
        }

        val distinctLinks = discoveredLinks.distinct().take(12)
        val summary = "OSINT Profile Lookup for '$target': Found ${distinctLinks.size} public mentions and profiles."

        // Step 3: Emit to Flutter UI
        try {
            SiyaService.eventSink?.invoke(mapOf(
                "type" to "osint_result",
                "mode" to "name",
                "query" to target,
                "summary" to summary,
                "links" to distinctLinks
            ))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to emit osint_result to Flutter: ${e.message}")
        }

        return """
            OSINT Name Lookup Results for '$target':
            Verified Profiles & Web Mentions:
            ${if (distinctLinks.isEmpty()) "No direct public profiles found." else distinctLinks.joinToString("\n")}
            
            Web Excerpt:
            ${searchResult.take(1200)}
        """.trimIndent()
    }
}
