package com.siya.ai.ui.widget

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.*
import android.widget.*
import java.io.File
import java.net.URLEncoder

/**
 * Universal Floating Window: Displays interactive browser popup, images,
 * or text cards directly over any app or home screen without closing or
 * disturbing the foreground application.
 */
object UniversalFloatingWindow {
    private var win: FloatingWindow? = null
    private val ui = Handler(Looper.getMainLooper())

    /**
     * Show interactive floating browser popup anywhere on screen.
     * Can be dragged, resized, minimized, or closed.
     * Closing this popup does NOT exit or close the application.
     */
    fun showBrowser(ctx: Context, queryOrUrl: String): Boolean {
        val app = ctx.applicationContext
        if (!android.provider.Settings.canDrawOverlays(app)) return false

        ui.post {
            try {
                win?.close()
                win = null

                val d = app.resources.displayMetrics.density
                val browserLayout = buildBrowserView(app, queryOrUrl, d)

                win = FloatingWindow(
                    app,
                    "Browser Popup",
                    browserLayout,
                    widthFrac = 0.94f,
                    heightFrac = 0.65f,
                    onClose = { win = null }
                )
                win?.show()
            } catch (e: Exception) {
                android.util.Log.e("UniversalFloatingWindow", "Error showing browser popup: ${e.message}")
            }
        }
        return true
    }

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
                        buildBrowserView(app, if (url.isNotBlank()) url else "https://www.google.com", d)
                    }
                    else -> {
                        buildTextView(app, title, content, d)
                    }
                }

                win = FloatingWindow(
                    app,
                    title.ifBlank { if (mode == "web" || mode == "browser") "Browser Popup" else "Siya Smart Popup" },
                    contentView,
                    widthFrac = 0.94f,
                    heightFrac = if (mode == "image" || mode == "gallery") 0.55f else if (mode == "web" || mode == "browser") 0.65f else 0.50f,
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
    private fun buildBrowserView(app: Context, initialInput: String, d: Float): View {
        fun dp(v: Float) = (v * d).toInt()

        val root = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#060B14"))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // Mini Navigation & Search Toolbar
        val toolbar = LinearLayout(app).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6f), dp(4f), dp(6f), dp(4f))
            setBackgroundColor(Color.parseColor("#0C1524"))
        }

        var webView: WebView? = null
        lateinit var urlEdit: EditText
        lateinit var progress: ProgressBar
        lateinit var backBtn: TextView
        lateinit var forwardBtn: TextView

        fun resolveUrl(raw: String): String {
            val q = raw.trim()
            return when {
                q.startsWith("http://") || q.startsWith("https://") -> q
                q.contains(".") && !q.contains(" ") -> "https://$q"
                q.isNotBlank() -> "https://www.google.com/search?q=" + URLEncoder.encode(q, "UTF-8")
                else -> "https://www.google.com"
            }
        }

        // Back button
        backBtn = TextView(app).apply {
            text = "◀"
            textSize = 15f
            setTextColor(Color.parseColor("#64748B"))
            setPadding(dp(8f), dp(4f), dp(8f), dp(4f))
            setOnClickListener { if (webView?.canGoBack() == true) webView?.goBack() }
        }
        toolbar.addView(backBtn)

        // Forward button
        forwardBtn = TextView(app).apply {
            text = "▶"
            textSize = 15f
            setTextColor(Color.parseColor("#64748B"))
            setPadding(dp(8f), dp(4f), dp(8f), dp(4f))
            setOnClickListener { if (webView?.canGoForward() == true) webView?.goForward() }
        }
        toolbar.addView(forwardBtn)

        // URL / Search Input
        urlEdit = EditText(app).apply {
            hint = "Search or type URL..."
            setHintTextColor(Color.parseColor("#475569"))
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setSingleLine(true)
            imeOptions = EditorInfo.IME_ACTION_GO
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#131E32"))
                cornerRadius = dp(14f).toFloat()
                setStroke(dp(1f), Color.parseColor("#25344D"))
            }
            setPadding(dp(10f), dp(5f), dp(10f), dp(5f))
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(4f)
                marginEnd = dp(4f)
            }
            setOnEditorActionListener { _, actionId, event ->
                if (actionId == EditorInfo.IME_ACTION_GO ||
                    (event != null && event.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN)) {
                    val u = resolveUrl(text.toString())
                    setText(u)
                    webView?.loadUrl(u)
                    val imm = app.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                    imm?.hideSoftInputFromWindow(windowToken, 0)
                    true
                } else false
            }
        }
        toolbar.addView(urlEdit)

        // Reload button
        val reloadBtn = TextView(app).apply {
            text = "↻"
            textSize = 18f
            setTextColor(Color.parseColor("#00E5FF"))
            setPadding(dp(6f), dp(2f), dp(6f), dp(2f))
            setOnClickListener { webView?.reload() }
        }
        toolbar.addView(reloadBtn)

        root.addView(toolbar)

        // Progress bar
        progress = ProgressBar(app, null, android.R.attr.progressBarStyleHorizontal).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2.5f))
            max = 100
            visibility = View.GONE
        }
        root.addView(progress)

        // WebView
        val wv = WebView(app).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f)
            setBackgroundColor(Color.parseColor("#060B14"))
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                useWideViewPort = true
                loadWithOverviewMode = true
                builtInZoomControls = true
                displayZoomControls = false
                mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                userAgentString = "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36 SiyaPopup/1.0"
            }
            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                    progress.visibility = View.VISIBLE
                    url?.let { if (!urlEdit.hasFocus()) urlEdit.setText(it) }
                    backBtn.setTextColor(if (canGoBack()) Color.WHITE else Color.parseColor("#64748B"))
                    forwardBtn.setTextColor(if (canGoForward()) Color.WHITE else Color.parseColor("#64748B"))
                }
                override fun onPageFinished(view: WebView?, url: String?) {
                    progress.visibility = View.GONE
                    url?.let { if (!urlEdit.hasFocus()) urlEdit.setText(it) }
                    backBtn.setTextColor(if (canGoBack()) Color.WHITE else Color.parseColor("#64748B"))
                    forwardBtn.setTextColor(if (canGoForward()) Color.WHITE else Color.parseColor("#64748B"))
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onProgressChanged(view: WebView?, newProgress: Int) {
                    progress.progress = newProgress
                    progress.visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
                }
            }
        }
        webView = wv
        root.addView(wv)

        val targetUrl = resolveUrl(initialInput)
        urlEdit.setText(targetUrl)
        wv.loadUrl(targetUrl)

        return root
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
