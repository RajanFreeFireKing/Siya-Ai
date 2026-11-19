package com.siya.ai.ui.widget

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.io.File

/**
 * Universal Floating Window: Displays image, web browser, or OSINT research
 * directly over other apps without opening MainActivity or disturbing the user.
 */
object UniversalFloatingWindow {
    private var win: FloatingWindow? = null
    private val ui = Handler(Looper.getMainLooper())

    @SuppressLint("SetJavaScriptEnabled")
    fun show(
        ctx: Context,
        type: String,
        title: String,
        content: String,
        mediaUrl: String,
        url: String
    ): Boolean {
        val app = ctx.applicationContext
        if (!android.provider.Settings.canDrawOverlays(app)) return false

        ui.post {
            try {
                win?.close()
                win = null

                val d = app.resources.displayMetrics.density
                val mode = type.lowercase().trim()

                val contentView: View = when {
                    mode == "image" || mode == "gallery" || (mediaUrl.isNotBlank() && (mediaUrl.endsWith(".jpg") || mediaUrl.endsWith(".png") || mediaUrl.endsWith(".jpeg") || mediaUrl.startsWith("content://"))) -> {
                        buildImageView(app, mediaUrl, content, d)
                    }
                    mode == "web" || mode == "browser" || url.isNotBlank() -> {
                        buildWebView(app, if (url.isNotBlank()) url else "https://www.google.com", d)
                    }
                    else -> {
                        buildTextView(app, title, content, d)
                    }
                }

                win = FloatingWindow(
                    app,
                    title.ifBlank { "Siya Smart Popup" },
                    contentView,
                    widthFrac = 0.94f,
                    heightFrac = if (mode == "image" || mode == "gallery") 0.55f else 0.50f,
                    onClose = { win = null }
                )
                win?.show()
            } catch (e: Exception) {
                android.util.Log.e("UniversalFloatingWindow", "Error showing floating window: ${e.message}")
            }
        }
        return true
    }

    private fun buildImageView(app: Context, pathOrUri: String, caption: String, d: Float): View {
        val root = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFF0F111D.toInt())
            setPadding((12 * d).toInt(), (8 * d).toInt(), (12 * d).toInt(), (12 * d).toInt())
        }

        val cleanPath = pathOrUri.removePrefix("file://")
        val bmp = try {
            if (cleanPath.startsWith("content://")) {
                app.contentResolver.openInputStream(Uri.parse(cleanPath))?.use {
                    BitmapFactory.decodeStream(it)
                }
            } else if (File(cleanPath).exists()) {
                BitmapFactory.decodeFile(cleanPath)
            } else null
        } catch (_: Exception) { null }

        val iv = ImageView(app).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            adjustViewBounds = true
            if (bmp != null) {
                setImageBitmap(bmp)
            } else {
                setImageResource(android.R.drawable.ic_menu_gallery)
                setColorFilter(0xFF3EE6FF.toInt())
            }
        }

        root.addView(iv, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        if (caption.isNotBlank()) {
            val tv = TextView(app).apply {
                text = caption
                setTextColor(0xEEFFFFFF.toInt())
                textSize = 12.5f
                setPadding(0, (6 * d).toInt(), 0, 0)
                maxLines = 2
            }
            root.addView(tv)
        }

        return root
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun buildWebView(app: Context, targetUrl: String, d: Float): View {
        val wv = WebView(app).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                    url?.let { view?.loadUrl(it) }
                    return true
                }
            }
            loadUrl(targetUrl)
        }
        return wv
    }

    private fun buildTextView(app: Context, title: String, content: String, d: Float): View {
        val scroll = ScrollView(app).apply {
            setBackgroundColor(0xFF0F111D.toInt())
            setPadding((14 * d).toInt(), (12 * d).toInt(), (14 * d).toInt(), (14 * d).toInt())
        }

        val col = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
        }

        val tvTitle = TextView(app).apply {
            text = title
            setTextColor(0xFF3EE6FF.toInt())
            textSize = 15f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
        col.addView(tvTitle)

        val divider = View(app).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, (1 * d).toInt()).apply {
                setMargins(0, (8 * d).toInt(), 0, (8 * d).toInt())
            }
            setBackgroundColor(0x333EE6FF.toInt())
        }
        col.addView(divider)

        val tvContent = TextView(app).apply {
            text = content.ifBlank { "Details available." }
            setTextColor(0xDDFFFFFF.toInt())
            textSize = 13.5f
            setLineSpacing(0f, 1.25f)
        }
        col.addView(tvContent)

        scroll.addView(col)
        return scroll
    }

    fun close() {
        ui.post {
            win?.close()
            win = null
        }
    }

    fun isShowing(): Boolean = win?.shown == true
}
