package com.siya.ai.browser

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.http.SslError
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.*
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import java.net.URLEncoder

/**
 * Modern In-App Visible Browser UI for Siya AI.
 * Opens when the user requests to see web search or browsing on screen
 * ("Browser mein dikhao", "Browser kholo", "Browser mein search karo").
 */
class BrowserActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var urlEditText: EditText
    private lateinit var progressBar: ProgressBar
    private lateinit var backBtn: TextView
    private lateinit var forwardBtn: TextView
    private lateinit var reloadBtn: TextView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val d = resources.displayMetrics.density
        fun dp(v: Float) = (v * d).toInt()

        val scrimLayout = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#B3000000"))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setOnClickListener { finish() }
        }

        val cardLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#060B14"))
                cornerRadius = dp(20f).toFloat()
                setStroke(dp(1.2f), Color.parseColor("#1E293B"))
            }
            clipToOutline = true
            layoutParams = FrameLayout.LayoutParams(
                (resources.displayMetrics.widthPixels * 0.94f).toInt(),
                (resources.displayMetrics.heightPixels * 0.82f).toInt(),
                Gravity.CENTER
            )
            isClickable = true
        }

        // Top Toolbar
        val toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8f), dp(10f), dp(8f), dp(10f))
            setBackgroundColor(Color.parseColor("#0B132B"))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        // Back button
        backBtn = TextView(this).apply {
            text = "◀"
            textSize = 17f
            setTextColor(Color.parseColor("#94A3B8"))
            setPadding(dp(10f), dp(6f), dp(10f), dp(6f))
            setOnClickListener {
                if (webView.canGoBack()) webView.goBack() else finish()
            }
        }
        toolbar.addView(backBtn)

        // Forward button
        forwardBtn = TextView(this).apply {
            text = "▶"
            textSize = 17f
            setTextColor(Color.parseColor("#94A3B8"))
            setPadding(dp(10f), dp(6f), dp(10f), dp(6f))
            setOnClickListener {
                if (webView.canGoForward()) webView.goForward()
            }
        }
        toolbar.addView(forwardBtn)

        // Address / Search input field
        urlEditText = EditText(this).apply {
            hint = "Search web or type URL..."
            setHintTextColor(Color.parseColor("#64748B"))
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f)
            setSingleLine(true)
            imeOptions = EditorInfo.IME_ACTION_GO
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1C2541"))
                cornerRadius = dp(20f).toFloat()
                setStroke(dp(1f), Color.parseColor("#3A506B"))
            }
            setPadding(dp(14f), dp(8f), dp(14f), dp(8f))
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(6f)
                marginEnd = dp(6f)
            }
            setOnEditorActionListener { _, actionId, event ->
                if (actionId == EditorInfo.IME_ACTION_GO ||
                    (event != null && event.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN)) {
                    loadFromInput(text.toString().trim())
                    val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                    imm?.hideSoftInputFromWindow(windowToken, 0)
                    true
                } else false
            }
        }
        toolbar.addView(urlEditText)

        // Reload button
        reloadBtn = TextView(this).apply {
            text = "↻"
            textSize = 21f
            setTextColor(Color.parseColor("#00E5FF"))
            setPadding(dp(8f), dp(4f), dp(8f), dp(4f))
            setOnClickListener {
                webView.reload()
            }
        }
        toolbar.addView(reloadBtn)

        // Close button
        val closeBtn = TextView(this).apply {
            text = "✕"
            textSize = 18f
            setTextColor(Color.parseColor("#FF5C8D"))
            setPadding(dp(8f), dp(4f), dp(10f), dp(4f))
            setOnClickListener {
                finish()
            }
        }
        toolbar.addView(closeBtn)

        cardLayout.addView(toolbar)

        // Loading Progress Bar
        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(3f))
            max = 100
            progress = 0
            visibility = View.GONE
        }
        cardLayout.addView(progressBar)

        // WebView
        webView = WebView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
            setBackgroundColor(Color.parseColor("#020A14"))
        }

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            useWideViewPort = true
            loadWithOverviewMode = true
            builtInZoomControls = true
            displayZoomControls = false
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            userAgentString = "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36 SiyaBrowser/1.0"
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val u = request?.url?.toString() ?: return false
                if (u.startsWith("http://") || u.startsWith("https://")) {
                    return false
                }
                return true
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, url, favicon)
                progressBar.visibility = View.VISIBLE
                url?.let { if (!urlEditText.hasFocus()) urlEditText.setText(it) }
                updateNavButtons()
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                progressBar.visibility = View.GONE
                url?.let { if (!urlEditText.hasFocus()) urlEditText.setText(it) }
                updateNavButtons()
            }

            @SuppressLint("WebViewClientOnReceivedSslError")
            override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) {
                handler?.proceed()
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                progressBar.progress = newProgress
                if (newProgress >= 100) {
                    progressBar.visibility = View.GONE
                } else {
                    progressBar.visibility = View.VISIBLE
                }
                updateNavButtons()
            }
        }

        cardLayout.addView(webView)
        scrimLayout.addView(cardLayout)
        setContentView(scrimLayout)

        val rawInput = intent.getStringExtra("query_or_url")?.trim().orEmpty()
        loadFromInput(rawInput.ifBlank { "https://www.google.com" })
    }

    private fun updateNavButtons() {
        backBtn.setTextColor(if (webView.canGoBack()) Color.WHITE else Color.parseColor("#475569"))
        forwardBtn.setTextColor(if (webView.canGoForward()) Color.WHITE else Color.parseColor("#475569"))
    }

    private fun loadFromInput(input: String) {
        val query = input.trim()
        val url = when {
            query.startsWith("http://") || query.startsWith("https://") -> query
            query.contains(".") && !query.contains(" ") -> "https://$query"
            query.isNotBlank() -> "https://www.google.com/search?q=" + URLEncoder.encode(query, "UTF-8")
            else -> "https://www.google.com"
        }
        urlEditText.setText(url)
        webView.loadUrl(url)
    }

    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        try {
            webView.stopLoading()
            webView.clearHistory()
            webView.destroy()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
