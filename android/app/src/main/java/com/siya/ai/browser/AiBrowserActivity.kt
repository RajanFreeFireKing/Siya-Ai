package com.siya.ai.browser

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import com.siya.ai.R

/**
 * AI Browser ka poori screen wala roop.
 *  - Upar: gol (pill) address bar - lock icon, website ka naam, search; saath mein 3-dot menu aur band.
 *  - Neeche: Back / Aage / Home / Reload-Stop / Chhoti window.
 *  - Load hote waqt upar rang-birangi progress line.
 * App se bahar jaane par browser chhoti floating window ban kar piche chalta rahta hai.
 */
class AiBrowserActivity : Activity() {
    private lateinit var host: FrameLayout
    private lateinit var url: EditText
    private lateinit var lock: ImageView
    private lateinit var back: ImageView
    private lateinit var fwd: ImageView
    private lateinit var reload: ImageView
    private var d = 1f

    private fun icon(res: Int, size: Int = 44, tint: Int = 0xFF3EE6FF.toInt(), onClick: () -> Unit) = ImageView(this).apply {
        setImageResource(res); setColorFilter(tint)
        val p = (10 * d).toInt(); setPadding(p, p, p, p)
        layoutParams = LinearLayout.LayoutParams((size * d).toInt(), (size * d).toInt())
        setOnClickListener { onClick() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = 0xFF050E1A.toInt()
        window.navigationBarColor = 0xFF050E1A.toInt()
        d = resources.displayMetrics.density

        // ── address bar ──
        lock = ImageView(this).apply {
            setImageResource(R.drawable.ic_br_search); setColorFilter(0xFF8FB3D9.toInt())
            layoutParams = LinearLayout.LayoutParams((18 * d).toInt(), (18 * d).toInt()).apply { marginStart = (12 * d).toInt() }
        }
        url = EditText(this).apply {
            setTextColor(Color.WHITE); setHintTextColor(0x88FFFFFF.toInt()); hint = "Google par search ya website likho"
            textSize = 14.5f; setSingleLine(true); imeOptions = EditorInfo.IME_ACTION_GO
            background = null; setPadding((10 * d).toInt(), 0, (10 * d).toInt(), 0)
            inputType = android.text.InputType.TYPE_TEXT_VARIATION_URI
            setSelectAllOnFocus(true)
            setOnEditorActionListener { v, _, _ ->
                AiBrowser.navigate(this@AiBrowserActivity, v.text.toString()); v.clearFocus()
                (getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).hideSoftInputFromWindow(v.windowToken, 0)
                true
            }
            setOnFocusChangeListener { v, f -> if (f) (v as EditText).setText(AiBrowser.currentUrl) else syncUi() }
        }
        val pill = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply { setColor(0xFF0D2236.toInt()); cornerRadius = 24 * d; setStroke((1 * d).toInt(), 0x6622D3EE) }
            addView(lock); addView(url, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
        }
        val top = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(0xFF081A2C.toInt(), 0xFF050E1A.toInt()))
            setPadding((10 * d).toInt(), (6 * d).toInt(), (4 * d).toInt(), (6 * d).toInt())
            addView(pill, LinearLayout.LayoutParams(0, (44 * d).toInt(), 1f))
            addView(icon(R.drawable.ic_br_more) { AiBrowser.toggleMenu(this@AiBrowserActivity) })      // 3-dot menu (right side)
            addView(icon(R.drawable.ic_br_close, tint = 0xFFFF6B6B.toInt()) { AiBrowser.close(this@AiBrowserActivity) })
        }

        // ── content ──
        host = FrameLayout(this).apply { setBackgroundColor(0xFF020A14.toInt()) }

        // ── bottom navigation ──
        back = icon(R.drawable.ic_br_back, 48) { AiBrowser.back(this@AiBrowserActivity) }
        fwd = icon(R.drawable.ic_br_forward, 48) { AiBrowser.goForward() }
        val home = icon(R.drawable.ic_br_home, 48) { AiBrowser.goHome(this@AiBrowserActivity) }
        reload = icon(R.drawable.ic_br_reload, 48) { AiBrowser.stopOrReload() }
        val win = icon(R.drawable.ic_br_window, 48) { AiBrowser.windowControl(this@AiBrowserActivity, "popup") }
        val bottom = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                setColor(0xFF081A2C.toInt()); cornerRadii = floatArrayOf(22 * d, 22 * d, 22 * d, 22 * d, 0f, 0f, 0f, 0f)
                setStroke((1 * d).toInt(), 0x3322D3EE)
            }
            setPadding((8 * d).toInt(), (4 * d).toInt(), (8 * d).toInt(), (4 * d).toInt())
            listOf(back, fwd, home, reload, win).forEach {
                addView(it, LinearLayout.LayoutParams(0, (48 * d).toInt(), 1f))
            }
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setBackgroundColor(0xFF020A14.toInt()); fitsSystemWindows = true
            addView(top, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(host, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            addView(bottom, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        setContentView(root)
    }

    /** Address bar, back / aage ki chamak aur reload <-> stop badlo. */
    private fun syncUi() {
        runOnUiThread {
            if (!url.hasFocus()) {
                val u = AiBrowser.currentUrl
                val secure = u.startsWith("https://")
                url.setText(if (u.isBlank() || u == "about:blank") "" else AiBrowser.hostLabel())
                lock.setImageResource(if (u.isBlank() || u == "about:blank") R.drawable.ic_br_search else R.drawable.ic_br_lock)
                lock.setColorFilter(if (secure) 0xFF00E676.toInt() else 0xFF8FB3D9.toInt())
            }
            back.alpha = if (AiBrowser.canGoBack) 1f else 0.35f
            fwd.alpha = if (AiBrowser.canGoForward) 1f else 0.35f
            reload.setImageResource(if (AiBrowser.loading) R.drawable.ic_br_close else R.drawable.ic_br_reload)
        }
    }

    override fun onStart() {
        super.onStart()
        AiBrowser.activity = this
        AiBrowser.attachTo(host)
        AiBrowser.uiListener = { syncUi() }
        syncUi()
    }

    override fun onStop() {
        AiBrowser.uiListener = null
        // app se bahar: browser floating window ban kar chalta rahe (gaana / video na ruke)
        if (!isFinishing && !isChangingConfigurations) {
            AiBrowser.detachFrom(host)
            if (AiBrowser.activity === this) AiBrowser.activity = null
            AiBrowser.sendToBackground(this)
        }
        super.onStop()
    }

    override fun onDestroy() {
        AiBrowser.detachFrom(host)
        if (AiBrowser.activity === this) AiBrowser.activity = null
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (!AiBrowser.back(this).startsWith("OK")) super.onBackPressed()
    }
}
