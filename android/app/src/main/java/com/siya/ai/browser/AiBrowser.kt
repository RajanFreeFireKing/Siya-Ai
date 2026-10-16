package com.siya.ai.browser

import android.annotation.SuppressLint
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.URLUtil
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.graphics.Bitmap
import android.graphics.drawable.GradientDrawable
import android.widget.FrameLayout
import android.widget.TextView
import com.siya.ai.ui.widget.FloatingWindow
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.net.URLEncoder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Siya ka browser. Ek hi WebView: ya to dusre apps ke upar tairti hui window mein (khiskao / chhota-bada karo)
 * ya poori screen (AiBrowserActivity) mein. App se bahar jaane par bhi chalta rehta hai (gaana / video nahi rukta).
 * Sab kuch Siya tools se control ho sakta hai, 3-dot menu se user bhi.
 */
object AiBrowser {
    private val main = Handler(Looper.getMainLooper())
    private var web: WebView? = null
    private var container: FrameLayout? = null
    private var panelHost: FrameLayout? = null
    private var window: FloatingWindow? = null
    @Volatile var activity: AiBrowserActivity? = null
    @Volatile private var loadLatch: CountDownLatch? = null
    @Volatile var currentTitle: String = ""
        private set
    private lateinit var appCtx: Context
    private var progressBar: View? = null
    @Volatile var progress = 100
        private set
    @Volatile var loading = false
        private set
    /** Activity apna URL bar / back-forward ka haal isi se refresh karti hai. */
    var uiListener: (() -> Unit)? = null

    val currentUrl: String get() = web?.url.orEmpty()
    val canGoBack: Boolean get() = web?.canGoBack() == true
    val canGoForward: Boolean get() = web?.canGoForward() == true

    private fun hostOf(u: String?): String = try { Uri.parse(u).host?.removePrefix("www.").orEmpty() } catch (_: Exception) { "" }

    private fun refreshUi() {
        val bar = progressBar
        if (bar != null) {
            bar.visibility = if (loading && progress < 100) View.VISIBLE else View.INVISIBLE
            bar.pivotX = 0f
            bar.scaleX = (progress.coerceIn(3, 100)) / 100f
        }
        window?.setTitle(currentTitle.ifBlank { hostOf(web?.url) }.ifBlank { "Siya Browser" })
        uiListener?.invoke()
    }

    private const val UA_MOBILE = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    private const val UA_DESKTOP = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private const val OFF = "ERROR: AI Browser band hai. Siya Settings > Features mein AI Browser ON karo."

    private fun prefs(ctx: Context) = ctx.applicationContext.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)
    fun isEnabled(ctx: Context) = prefs(ctx).getBoolean("ai_browser_enabled", false)
    private var dark: Boolean
        get() = prefs(appCtx).getBoolean("browser_dark", false)
        set(v) { prefs(appCtx).edit().putBoolean("browser_dark", v).apply() }
    private var desktop: Boolean
        get() = prefs(appCtx).getBoolean("browser_desktop", false)
        set(v) { prefs(appCtx).edit().putBoolean("browser_desktop", v).apply() }

    // ── WebView ───────────────────────────────────────────────
    @SuppressLint("SetJavaScriptEnabled")
    private fun webView(ctx: Context): WebView {
        web?.let { return it }
        appCtx = ctx.applicationContext
        val w = WebView(appCtx)
        w.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            userAgentString = if (desktop) UA_DESKTOP else UA_MOBILE
            loadWithOverviewMode = true
            useWideViewPort = true
            setSupportZoom(true)
            builtInZoomControls = true
            displayZoomControls = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(w, true)
        w.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: android.webkit.WebResourceRequest): Boolean {
                val s = request.url.scheme ?: return true
                return s != "http" && s != "https"
            }
            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                loading = true; progress = 5; refreshUi()
            }
            override fun onPageFinished(view: WebView, url: String?) {
                currentTitle = view.title.orEmpty()
                loading = false; progress = 100; refreshUi()
                if (dark) applyDark(true)
                if (!url.isNullOrBlank() && url != "about:blank") addHistory(currentTitle, url)
                loadLatch?.countDown()
            }
        }
        w.webChromeClient = object : WebChromeClient() {
            override fun onReceivedTitle(view: WebView, title: String?) { currentTitle = title.orEmpty(); refreshUi() }
            override fun onProgressChanged(view: WebView, newProgress: Int) { progress = newProgress; loading = newProgress < 100; refreshUi() }
        }
        w.setDownloadListener { url, ua, cd, mime, _ -> enqueueDownload(appCtx, url, ua, cd, mime) }
        web = w
        return w
    }

    /** WebView + upar panels ka host; popup aur activity dono yahi container lete hain. */
    fun containerView(ctx: Context): FrameLayout {
        container?.let { return it }
        val c = FrameLayout(ctx.applicationContext)
        val w = webView(ctx)
        (w.parent as? ViewGroup)?.removeView(w)
        c.addView(w, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        val d = ctx.resources.displayMetrics.density
        val bar = View(ctx.applicationContext).apply {
            background = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(0xFF22D3EE.toInt(), 0xFF8B5CF6.toInt(), 0xFFD946EF.toInt()))
            visibility = View.INVISIBLE
        }
        c.addView(bar, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, (3 * d).toInt(), android.view.Gravity.TOP))
        progressBar = bar
        val host = FrameLayout(ctx.applicationContext)
        c.addView(host, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        container = c; panelHost = host
        return c
    }

    private fun enqueueDownload(ctx: Context, url: String, ua: String?, cd: String?, mime: String?) {
        try {
            val req = DownloadManager.Request(Uri.parse(url))
            if (!mime.isNullOrBlank()) req.setMimeType(mime)
            if (!ua.isNullOrBlank()) req.addRequestHeader("User-Agent", ua)
            CookieManager.getInstance().getCookie(url)?.let { req.addRequestHeader("Cookie", it) }
            req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, URLUtil.guessFileName(url, cd, mime))
            (ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager).enqueue(req)
        } catch (_: Exception) {}
    }

    private fun <T> onMain(timeoutMs: Long = 6000, block: () -> T): T? {
        if (Looper.myLooper() == Looper.getMainLooper()) return block()
        val ref = AtomicReference<T?>()
        val latch = CountDownLatch(1)
        main.post { try { ref.set(block()) } catch (_: Exception) {} finally { latch.countDown() } }
        latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        return ref.get()
    }

    private fun beep() {
        try {
            val t = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 55)
            t.startTone(ToneGenerator.TONE_PROP_ACK, 140)
            main.postDelayed({ try { t.release() } catch (_: Exception) {} }, 400)
        } catch (_: Exception) {}
    }

    // ── window / activity switching ───────────────────────────
    private fun menuButton(ctx: Context): View {
        val d = ctx.resources.displayMetrics.density
        return android.widget.ImageView(ctx).apply {
            setImageResource(com.siya.ai.R.drawable.ic_br_more)
            setColorFilter(0xFF3EE6FF.toInt())
            setPadding((8 * d).toInt(), (6 * d).toInt(), (8 * d).toInt(), (6 * d).toInt())
            layoutParams = android.widget.LinearLayout.LayoutParams((38 * d).toInt(), (34 * d).toInt())
            setOnClickListener { toggleMenu(ctx) }
        }
    }

    private fun showWindow(ctx: Context, small: Boolean = false): Boolean {
        val app = ctx.applicationContext
        if (activity != null) return false
        if (window?.shown == true) return true
        if (!Settings.canDrawOverlays(app)) return false
        val c = containerView(app)
        val w = FloatingWindow(app, currentTitle.ifBlank { "Siya Browser" }, c, 0.94f, 0.5f,
            onClose = { window = null; closeInternal() }, onFull = { launchFull(app) },
            headerExtra = listOf(menuButton(app)))
        window = w
        val ok = w.show()
        if (ok && small) w.resize("small")
        if (!ok) window = null
        return ok
    }

    private fun hideWindow() { window?.hide(); window = null }

    fun launchFull(ctx: Context) {
        val app = ctx.applicationContext
        hideWindow()
        if (activity == null)
            app.startActivity(Intent(app, AiBrowserActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
    }

    fun attachTo(host: ViewGroup) {
        hideWindow()
        val c = containerView(host.context)
        (c.parent as? ViewGroup)?.removeView(c)
        host.addView(c, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        web?.onResume()
    }

    fun detachFrom(host: ViewGroup) { container?.let { if (it.parent === host) host.removeView(it) } }

    /** User app se bahar gaya: browser chhoti window ban kar piche chalta rahe. */
    fun sendToBackground(ctx: Context) {
        if (web == null || !isEnabled(ctx)) return
        main.post { if (activity == null && window == null) showWindow(ctx, small = true) }
    }

    // ── tools ─────────────────────────────────────────────────
    private fun normalize(u: String): String {
        val t = u.trim()
        return when {
            t.startsWith("http://") || t.startsWith("https://") -> t
            t.contains(".") && !t.contains(" ") -> "https://$t"
            else -> "https://www.google.com/search?q=" + URLEncoder.encode(t, "UTF-8")
        }
    }

    /** mode: "popup" (default) ya "full". */
    fun open(ctx: Context, url: String, mode: String = "popup"): String {
        if (!isEnabled(ctx)) return OFF
        val u = normalize(url)
        val latch = CountDownLatch(1)
        loadLatch = latch
        onMain {
            webView(ctx)
            containerView(ctx)
            val ok = if (mode.equals("full", true)) false else (activity != null || showWindow(ctx))
            if (!ok) launchFull(ctx)
            web?.loadUrl(u)
        }
        beep()
        latch.await(9, TimeUnit.SECONDS)
        return "OK: browser mein khul gaya: $u (${currentTitle.ifBlank { "loading" }}). Padhne ke liye browser_read use karo."
    }

    fun search(ctx: Context, query: String, mode: String = "popup") =
        open(ctx, "https://www.google.com/search?q=" + URLEncoder.encode(query, "UTF-8"), mode)

    private fun decode(v: String?): String = try {
        if (v == null || v == "null") "" else if (v.startsWith("\"")) JSONTokener(v).nextValue().toString() else v
    } catch (_: Exception) { v ?: "" }

    private fun js(script: String, waitMs: Long = 5000): String {
        val ref = AtomicReference<String>()
        val latch = CountDownLatch(1)
        main.post {
            val w = web
            if (w == null) latch.countDown() else w.evaluateJavascript(script) { ref.set(decode(it)); latch.countDown() }
        }
        latch.await(waitMs, TimeUnit.MILLISECONDS)
        return ref.get() ?: "ERROR: browser ne jawab nahi diya"
    }

    private fun need(ctx: Context): String? = when {
        !isEnabled(ctx) -> OFF
        web == null || (window == null && activity == null) -> "ERROR: browser abhi khula nahi hai (pehle browser_search ya browser_open)"
        else -> null
    }

    fun read(ctx: Context): String {
        need(ctx)?.let { return it }
        return js("(function(){var t=document.title||'';var b=(document.body&&document.body.innerText)||'';return location.href+'\\n'+t+'\\n'+b.replace(/\\n{3,}/g,'\\n\\n').slice(0,5000);})()")
    }

    fun links(ctx: Context): String {
        need(ctx)?.let { return it }
        return js("(function(){var a=[].slice.call(document.querySelectorAll('a[href]'));var seen={},out=[];for(var i=0;i<a.length&&out.length<30;i++){var t=(a[i].innerText||a[i].getAttribute('aria-label')||'').trim().replace(/\\s+/g,' ').slice(0,80);var h=a[i].href;if(!t||seen[h])continue;seen[h]=1;out.push(t+' -> '+h);}return out.join('\\n');})()")
    }

    fun click(ctx: Context, text: String): String {
        need(ctx)?.let { return it }
        val arg = JSONObject.quote(text)
        val r = js("""(function(t){t=t.toLowerCase();var els=[].slice.call(document.querySelectorAll('a,button,[role=button],[role=link],input[type=submit],h3,h4,li,span,div'));var best=null;for(var i=0;i<els.length;i++){var e=els[i];var s=((e.innerText||e.value||e.getAttribute('aria-label')||'')+'').trim().toLowerCase();if(!s||s.length>240)continue;if(s===t){best=e;break;}if(!best&&s.indexOf(t)>=0&&s.length<t.length*5)best=e;}if(!best)return 'NOT_FOUND';var c=best.closest('a,button,[role=button],[role=link]')||best;c.scrollIntoView({block:'center'});c.click();return 'OK';})($arg)""")
        return if (r == "OK") "OK: '$text' par click kiya" else "NOT_FOUND: page par '$text' nahi mila (browser_links ya browser_read se dekho)"
    }

    fun type(ctx: Context, text: String, submit: Boolean): String {
        need(ctx)?.let { return it }
        val arg = JSONObject.quote(text)
        val r = js("""(function(v,sub){var el=document.activeElement;if(!el||!(el.tagName==='INPUT'||el.tagName==='TEXTAREA'||el.isContentEditable)){el=document.querySelector('input[type=search],input[name=q],textarea,input[type=text],input:not([type]),[contenteditable=true]');}if(!el)return 'NOT_FOUND';el.focus();if(el.isContentEditable){el.textContent=v;}else{var proto=el.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;var d=Object.getOwnPropertyDescriptor(proto,'value');if(d&&d.set)d.set.call(el,v);else el.value=v;}el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));if(sub){var f=el.form;if(f){if(f.requestSubmit)f.requestSubmit();else f.submit();}else{['keydown','keypress','keyup'].forEach(function(n){el.dispatchEvent(new KeyboardEvent(n,{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));});}}return 'OK';})($arg,$submit)""")
        return if (r == "OK") "OK: likh diya${if (submit) " aur enter kiya" else ""}" else "NOT_FOUND: page par input box nahi mila"
    }

    fun scroll(ctx: Context, direction: String): String {
        need(ctx)?.let { return it }
        val dy = when (direction.lowercase()) { "up" -> "-Math.round(window.innerHeight*0.8)"; "top" -> "-1e7"; "bottom" -> "1e7"; else -> "Math.round(window.innerHeight*0.8)" }
        js("window.scrollBy(0,$dy);'ok'")
        return "OK: scroll $direction"
    }

    fun back(ctx: Context): String {
        need(ctx)?.let { return it }
        return onMain { val w = web; if (w != null && w.canGoBack()) { w.goBack(); "OK: peeche gaya" } else "ERROR: peeche koi page nahi" } ?: "ERROR"
    }

    fun download(ctx: Context, url: String): String {
        if (!isEnabled(ctx)) return OFF
        enqueueDownload(ctx.applicationContext, normalize(url), UA_MOBILE, null, null)
        return "OK: download shuru (Downloads folder mein save hoga, notification dikhegi)"
    }

    fun close(ctx: Context): String {
        onMain { closeInternal(); hideWindow(); activity?.finish() }
        beep()
        return "OK: browser band kar diya"
    }

    private fun closeInternal() { web?.loadUrl("about:blank"); web?.clearHistory() }

    fun goHome(ctx: Context) { onMain { web?.loadUrl("https://www.google.com") } }

    fun stopOrReload() { onMain { val w = web; if (w != null) { if (loading) w.stopLoading() else w.reload() } } }

    fun goForward() { onMain { if (web?.canGoForward() == true) web?.goForward() } }

    /** URL bar se: website ya Google search. */
    fun navigate(ctx: Context, text: String) { val u = normalize(text); onMain { web?.loadUrl(u) } }

    fun hostLabel(): String = hostOf(web?.url).ifBlank { "Siya Browser" }

    // ── window control (agent + user) ─────────────────────────
    /** action: small, big, full, popup, min, restore, top, bottom, left, right, center */
    fun windowControl(ctx: Context, action: String): String {
        if (!isEnabled(ctx)) return OFF
        return onMain {
            when (action.lowercase()) {
                "full" -> { if (web == null) return@onMain "ERROR: browser khula nahi hai"; launchFull(ctx); "OK: poori screen" }
                "popup" -> { activity?.finish(); showWindow(ctx); "OK: popup window" }
                "small", "big", "min", "restore" -> {
                    if (window?.shown != true) return@onMain "ERROR: popup window khuli nahi hai"
                    window?.resize(action.lowercase()); "OK: window $action"
                }
                "top", "bottom", "left", "right", "center" -> {
                    if (window?.shown != true) return@onMain "ERROR: popup window khuli nahi hai"
                    window?.moveTo(action.lowercase()); "OK: window $action le gaya"
                }
                else -> "ERROR: action small / big / full / popup / min / restore / top / bottom / left / right / center mein se do"
            }
        } ?: "ERROR"
    }

    // ── history & bookmarks ───────────────────────────────────
    private fun readList(ctx: Context, key: String): MutableList<Triple<String, String, String>> {
        val out = ArrayList<Triple<String, String, String>>()
        try {
            val a = JSONArray(prefs(ctx).getString(key, "[]"))
            for (i in 0 until a.length()) { val o = a.getJSONObject(i); out.add(Triple(o.optString("t"), o.optString("d"), o.optString("u"))) }
        } catch (_: Exception) {}
        return out
    }

    private fun writeList(ctx: Context, key: String, l: List<Triple<String, String, String>>) {
        val a = JSONArray()
        l.forEach { a.put(JSONObject().put("t", it.first).put("d", it.second).put("u", it.third)) }
        prefs(ctx).edit().putString(key, a.toString()).apply()
    }

    private fun addHistory(title: String, url: String) {
        if (!::appCtx.isInitialized) return
        val l = readList(appCtx, "browser_history")
        l.removeAll { it.third == url }
        l.add(0, Triple(title, java.text.SimpleDateFormat("dd MMM, HH:mm", java.util.Locale.getDefault()).format(java.util.Date()) + "  " + url, url))
        writeList(appCtx, "browser_history", l.take(120))
    }

    // ── 3-dot menu ────────────────────────────────────────────
    private fun clearPanels() { panelHost?.removeAllViews() }

    fun toggleMenu(ctx: Context) {
        val host = panelHost ?: return
        if (host.childCount > 0) { clearPanels(); return }
        val items = listOf(
            "reload" to "\u27F3  Reload",
            "forward" to "\u2192  Aage",
            "add_bookmark" to "\u2606  Bookmark karo",
            "bookmarks" to "\u2605  Bookmarks",
            "history" to "\uD83D\uDD58  History",
            "downloads" to "\u2B07  Downloads",
            "dark_mode" to "\uD83C\uDF19  Dark mode ${if (dark) "\u2713" else ""}",
            "desktop_site" to "\uD83D\uDDA5  Desktop site ${if (desktop) "\u2713" else ""}",
            "find" to "\uD83D\uDD0D  Page mein dhundo",
            "zoom_in" to "\uFF0B  Zoom in",
            "zoom_out" to "\uFF0D  Zoom out",
            "share" to "\u2197  Share",
            "open_external" to "\uD83C\uDF10  Chrome mein kholo",
            "clear_data" to "\uD83E\uDDF9  Browsing data saaf karo",
        )
        host.addView(BrowserPanels.menu(ctx.applicationContext, items) { a -> if (a == "close_panel") clearPanels() else { clearPanels(); menuAction(ctx, a, "") } })
    }

    private fun showList(ctx: Context, title: String, key: String, clearable: Boolean) {
        val host = panelHost ?: return
        clearPanels()
        host.addView(BrowserPanels.list(ctx.applicationContext, title, readList(ctx, key),
            onOpen = { u -> clearPanels(); web?.loadUrl(u) },
            onClear = if (clearable) ({ writeList(ctx, key, emptyList()); showList(ctx, title, key, true) }) else null,
            onClose = { clearPanels() }))
    }

    private fun applyDark(on: Boolean) {
        val s = if (on)
            "(function(){if(document.getElementById('siya-dark'))return;var s=document.createElement('style');s.id='siya-dark';s.textContent='html{filter:invert(1) hue-rotate(180deg)!important;background:#fff}img,video,picture,canvas{filter:invert(1) hue-rotate(180deg)!important}';document.documentElement.appendChild(s);})()"
        else "(function(){var e=document.getElementById('siya-dark');if(e)e.remove();})()"
        web?.evaluateJavascript(s, null)
    }

    /**
     * 3-dot menu ka har option; Siya bhi browser_menu tool se yahi chalati hai.
     * action: reload, forward, add_bookmark, bookmarks, history, downloads, dark_mode, desktop_site, find, zoom_in, zoom_out,
     *         share, open_external, clear_data, clear_history
     */
    fun menuAction(ctx: Context, action: String, arg: String): String {
        if (!isEnabled(ctx)) return OFF
        if (web == null && action != "downloads") return "ERROR: browser abhi khula nahi hai"
        val app = ctx.applicationContext
        return onMain {
            val w = web
            when (action.lowercase()) {
                "reload" -> { w?.reload(); "OK: reload" }
                "forward" -> if (w?.canGoForward() == true) { w.goForward(); "OK: aage gaya" } else "ERROR: aage koi page nahi"
                "add_bookmark" -> {
                    val u = w?.url.orEmpty()
                    if (u.isBlank() || u == "about:blank") return@onMain "ERROR: koi page khula nahi"
                    val l = readList(app, "browser_bookmarks"); l.removeAll { it.third == u }
                    l.add(0, Triple(w?.title.orEmpty(), u, u)); writeList(app, "browser_bookmarks", l)
                    "OK: bookmark ho gaya: ${w?.title}"
                }
                "bookmarks" -> { showList(app, "Bookmarks", "browser_bookmarks", false); "OK: bookmarks dikha diye:\n" + readList(app, "browser_bookmarks").take(15).joinToString("\n") { "${it.first} -> ${it.third}" } }
                "history" -> { showList(app, "History", "browser_history", true); "OK: history dikha di:\n" + readList(app, "browser_history").take(15).joinToString("\n") { "${it.first} -> ${it.third}" } }
                "clear_history" -> { writeList(app, "browser_history", emptyList()); "OK: history saaf" }
                "downloads" -> {
                    try { app.startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); "OK: Downloads khul gaya" }
                    catch (_: Exception) { "ERROR: Downloads khul nahi paya" }
                }
                "dark_mode" -> {
                    dark = if (arg.equals("on", true)) true else if (arg.equals("off", true)) false else !dark
                    applyDark(dark); "OK: dark mode ${if (dark) "ON" else "OFF"}"
                }
                "desktop_site" -> {
                    desktop = if (arg.equals("on", true)) true else if (arg.equals("off", true)) false else !desktop
                    w?.settings?.userAgentString = if (desktop) UA_DESKTOP else UA_MOBILE
                    w?.reload(); "OK: desktop site ${if (desktop) "ON" else "OFF"}"
                }
                "find" -> {
                    if (arg.isNotBlank()) { w?.findAllAsync(arg); "OK: '$arg' page mein highlight kiya" }
                    else {
                        val host = panelHost ?: return@onMain "ERROR"
                        clearPanels()
                        host.addView(BrowserPanels.find(app, { q -> w?.findAllAsync(q) }, { fwd -> w?.findNext(fwd) }, { w?.clearMatches(); clearPanels() }))
                        "OK: find bar khul gaya"
                    }
                }
                "zoom_in" -> { w?.zoomIn(); "OK: zoom in" }
                "zoom_out" -> { w?.zoomOut(); "OK: zoom out" }
                "share" -> {
                    val u = w?.url.orEmpty()
                    val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, u) }
                    app.startActivity(Intent.createChooser(send, "Share").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); "OK: share menu khul gaya"
                }
                "open_external" -> {
                    app.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(w?.url.orEmpty())).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); "OK: Chrome / default browser mein khula"
                }
                "clear_data" -> {
                    w?.clearCache(true); w?.clearHistory(); w?.clearFormData()
                    CookieManager.getInstance().removeAllCookies(null); WebStorage.getInstance().deleteAllData()
                    writeList(app, "browser_history", emptyList()); "OK: cache, cookies aur history saaf"
                }
                else -> "ERROR: action reload / forward / add_bookmark / bookmarks / history / clear_history / downloads / dark_mode / desktop_site / find / zoom_in / zoom_out / share / open_external / clear_data mein se do"
            }
        } ?: "ERROR: browser ne jawab nahi diya"
    }

    fun isShowing() = window?.shown == true || activity != null
}
