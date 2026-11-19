package com.siya.ai.browser

import android.annotation.SuppressLint
import android.content.Context
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.*
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * ObscuraMobileEngine: Native On-Device Headless Agent Browser for Siya AI.
 *
 * Runs 100% off-screen inside Android without launching any visible Window or Activity.
 * Screen par kabhi bhi koi browser open nahi hota.
 *
 * Capabilities:
 * 1. Obscura Content Extractor: Strips ads, banners, cookies, and scripts via injected JS.
 * 2. Numbered Interactive Indexing: Indexes clickable links, buttons, and inputs [1], [2]...
 * 3. Search Engine Integration: obscura_search(query) background search.
 * 4. Autonomous Interaction: obscura_interact(action, target, text) - click, type, scroll.
 * 5. Memory Cleanup: obscura_cleanup() resets to about:blank to save RAM & battery.
 */
object ObscuraMobileEngine {
    private const val TAG = "OBSCURA_HEADLESS"
    private const val TIMEOUT_SECONDS = 15L

    private val mainHandler = Handler(Looper.getMainLooper())
    private var headlessWebView: WebView? = null

    // Obscura JavaScript Extraction Payload
    private const val EXTRACTION_SCRIPT = """
(function() {
    try {
        // 1. Remove clutter (ads, banners, scripts, trackers)
        var garbage = ['script', 'style', 'noscript', 'svg', 'canvas', 'iframe',
            '.advertisement', '.ad-box', '#cookie-banner', '.cookie-consent',
            '.ad', '[class*="advert"]', '[id*="cookie"]', '[class*="cookie"]',
            '[aria-hidden="true"]'];
        garbage.forEach(function(sel) {
            document.querySelectorAll(sel).forEach(function(el) { el.remove(); });
        });

        var title = document.title || 'Untitled';
        var canonical = window.location.href;

        // 2. Discover and number interactive elements
        var interactive = [];
        var elements = document.querySelectorAll('a[href], button, input, textarea, select, [role="button"]');
        var id = 1;
        for (var i = 0; i < elements.length && id <= 35; i++) {
            var el = elements[i];
            var style = window.getComputedStyle(el);
            if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') continue;

            var tag = el.tagName.toLowerCase();
            var text = (el.innerText || el.textContent || el.getAttribute('aria-label') || el.getAttribute('placeholder') || el.getAttribute('value') || '').trim();
            text = text.replace(/[\r\n\t]+/g, ' ').substring(0, 80);

            el.setAttribute('data-obscura-id', id.toString());

            if (tag === 'a') {
                var href = el.getAttribute('href') || '';
                if (href && !href.startsWith('javascript:') && !href.startsWith('#')) {
                    interactive.push('[' + id + '] [Link] "' + (text || 'Link') + '" -> ' + href);
                    id++;
                }
            } else if (tag === 'button' || el.getAttribute('role') === 'button') {
                interactive.push('[' + id + '] [Button] "' + (text || 'Button') + '"');
                id++;
            } else if (tag === 'input' || tag === 'textarea') {
                var type = el.getAttribute('type') || 'text';
                var name = el.getAttribute('name') || '';
                var placeholder = el.getAttribute('placeholder') || '';
                interactive.push('[' + id + '] [Input:' + type + '] name="' + name + '" placeholder="' + placeholder + '" val="' + text + '"');
                id++;
            }
        }

        // 3. Extract main readable text
        var bodyClone = document.body ? document.body.cloneNode(true) : null;
        var cleanText = '';
        if (bodyClone) {
            ['nav', 'footer', 'header', 'aside', 'form'].forEach(function(tag) {
                bodyClone.querySelectorAll(tag).forEach(function(e) { e.remove(); });
            });
            cleanText = (bodyClone.innerText || '').replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
            if (cleanText.length > 2500) {
                cleanText = cleanText.substring(0, 2500) + '... [truncated]';
            }
        }

        return JSON.stringify({
            title: title,
            url: canonical,
            text: cleanText,
            interactive: interactive
        });
    } catch(e) {
        return JSON.stringify({ error: e.toString() });
    }
})();
"""

    @SuppressLint("SetJavaScriptEnabled")
    private fun getOrCreateWebView(ctx: Context): WebView {
        headlessWebView?.let { return it }
        val app = ctx.applicationContext
        val web = WebView(app)
        web.layout(0, 0, 1080, 1920) // Virtual off-screen bounds
        web.isVerticalScrollBarEnabled = false
        web.isHorizontalScrollBarEnabled = false

        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            useWideViewPort = true
            loadWithOverviewMode = true
            cacheMode = WebSettings.LOAD_DEFAULT
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            // Modern Chrome Mobile User-Agent
            userAgentString = "Mozilla/5.0 (Linux; Android 14; Mobile; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"
        }

        headlessWebView = web
        return web
    }

    /**
     * Loads a URL in background off-screen and extracts clean Obscura content.
     */
    fun open(ctx: Context, rawUrl: String): String {
        val url = cleanUrl(rawUrl)
        val latch = CountDownLatch(1)
        val resultHolder = AtomicReference<String>("")

        mainHandler.post {
            try {
                val web = getOrCreateWebView(ctx)
                var hasFinished = false

                web.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        if (hasFinished) return
                        hasFinished = true
                        // Wait 600ms for dynamic single-page apps to settle
                        mainHandler.postDelayed({
                            extractObscuraContent(web) { extracted ->
                                resultHolder.set(extracted)
                                latch.countDown()
                            }
                        }, 600)
                    }

                    @SuppressLint("WebViewClientOnReceivedSslError")
                    override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) {
                        handler?.proceed()
                    }

                    override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                        super.onReceivedError(view, request, error)
                        if (request?.isForMainFrame == true && !hasFinished) {
                            hasFinished = true
                            mainHandler.postDelayed({
                                extractObscuraContent(web) { extracted ->
                                    resultHolder.set("NOTE: Page loaded with warnings.\n$extracted")
                                    latch.countDown()
                                }
                            }, 500)
                        }
                    }
                }

                web.loadUrl(url)
            } catch (e: Exception) {
                Log.e(TAG, "open error: ${e.message}", e)
                resultHolder.set("ERROR: Obscura open failed: ${e.message}")
                latch.countDown()
            }
        }

        val completed = latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        return if (completed) {
            resultHolder.get().ifBlank { "ERROR: Obscura extracted empty content" }
        } else {
            // Timed out: still try to extract whatever has loaded
            forceExtract(ctx)
        }
    }

    /**
     * Searches the web in background without opening any visible browser.
     */
    fun search(ctx: Context, query: String): String {
        val q = query.trim()
        if (q.startsWith("http://") || q.startsWith("https://")) {
            return open(ctx, q)
        }
        val encoded = URLEncoder.encode(q, "UTF-8")
        // Privacy-focused fast HTML search engine: no bot blockers, instant results
        val searchUrl = "https://html.duckduckgo.com/html/?q=$encoded"
        return open(ctx, searchUrl)
    }

    /**
     * Obscura Interaction: click, type, scroll, or submit on the background page.
     */
    fun interact(ctx: Context, action: String, target: String, text: String): String {
        val act = action.lowercase().trim()
        val latch = CountDownLatch(1)
        val resultHolder = AtomicReference<String>("")

        mainHandler.post {
            val web = headlessWebView
            if (web == null) {
                resultHolder.set("ERROR: No webpage currently loaded in Obscura. Use obscura_open or obscura_search first.")
                latch.countDown()
                return@post
            }

            val sanitizedText = JSONObject.quote(text)
            val script = when (act) {
                "click" -> """
(function() {
    var target = "$target";
    var el = document.querySelector('[data-obscura-id="' + target + '"]');
    if (!el) {
        var all = document.querySelectorAll('a, button, input[type=button], input[type=submit], [role=button]');
        for (var i = 0; i < all.length; i++) {
            if ((all[i].innerText || '').toLowerCase().includes(target.toLowerCase())) {
                el = all[i];
                break;
            }
        }
    }
    if (el) {
        el.click();
        return "CLICKED: " + (el.innerText || target);
    }
    return "NOT_FOUND: Element " + target + " not found";
})();
"""
                "type" -> """
(function() {
    var target = "$target";
    var text = $sanitizedText;
    var el = document.querySelector('[data-obscura-id="' + target + '"]') || document.querySelector('input[type=text], input[type=search], input:not([type]), textarea');
    if (el) {
        el.focus();
        el.value = text;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return "TYPED: " + text + " into element " + target;
    }
    return "NOT_FOUND: Input " + target + " not found";
})();
"""
                "scroll" -> """
(function() {
    var dir = "$target".toLowerCase();
    var delta = (dir === 'up') ? -800 : 800;
    window.scrollBy(0, delta);
    return "SCROLLED: " + dir;
})();
"""
                "submit" -> """
(function() {
    var target = "$target";
    var el = document.querySelector('[data-obscura-id="' + target + '"]');
    var form = el ? el.closest('form') : document.querySelector('form');
    if (form) {
        form.submit();
        return "SUBMITTED form";
    }
    return "NOT_FOUND: Form not found";
})();
"""
                else -> """ "UNKNOWN ACTION: $act" """
            }

            web.evaluateJavascript(script) { evalRes ->
                Log.d(TAG, "interact action $act result: $evalRes")
                // Wait 1.2s for navigation or DOM update after action
                mainHandler.postDelayed({
                    extractObscuraContent(web) { updatedContent ->
                        resultHolder.set("ACTION ($act): $evalRes\n\n$updatedContent")
                        latch.countDown()
                    }
                }, 1200)
            }
        }

        val completed = latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        return if (completed) {
            resultHolder.get()
        } else {
            "ACTION_EXECUTED: Timed out waiting for updated content."
        }
    }

    /**
     * Resets the background WebView to about:blank to immediately free phone RAM & battery.
     */
    fun cleanup(): String {
        mainHandler.post {
            try {
                headlessWebView?.apply {
                    stopLoading()
                    loadUrl("about:blank")
                    clearHistory()
                }
                Log.i(TAG, "Obscura Headless Engine memory cleaned up.")
            } catch (e: Exception) {
                Log.e(TAG, "cleanup error: ${e.message}")
            }
        }
        return "OK: Obscura background memory cleared"
    }

    private fun extractObscuraContent(web: WebView, onResult: (String) -> Unit) {
        web.evaluateJavascript(EXTRACTION_SCRIPT) { rawJson ->
            try {
                if (rawJson == null || rawJson == "null") {
                    onResult("NOTE: Page returned empty content.")
                    return@evaluateJavascript
                }
                val unquoted = if (rawJson.startsWith("\"") && rawJson.endsWith("\"")) {
                    // Unescape JSON string returned by evaluateJavascript
                    val wrapper = JSONObject("{ \"res\": $rawJson }")
                    wrapper.getString("res")
                } else {
                    rawJson
                }

                val obj = JSONObject(unquoted)
                val title = obj.optString("title", "Untitled")
                val url = obj.optString("url", web.url.orEmpty())
                val text = obj.optString("text", "")
                val interactiveArr = obj.optJSONArray("interactive")

                val sb = java.lang.StringBuilder()
                sb.append("=== OBSCURA HEADLESS AGENT PAGE ===\n")
                sb.append("Title: ").append(title).append("\n")
                sb.append("URL: ").append(url).append("\n\n")

                sb.append("--- PAGE CONTENT ---\n")
                if (text.isNotBlank()) {
                    sb.append(text).append("\n\n")
                } else {
                    sb.append("(No readable body text found)\n\n")
                }

                sb.append("--- NUMBERED INTERACTIVE ELEMENTS ---\n")
                if (interactiveArr != null && interactiveArr.length() > 0) {
                    for (i in 0 until interactiveArr.length()) {
                        sb.append(interactiveArr.getString(i)).append("\n")
                    }
                } else {
                    sb.append("(No interactive links/buttons found)\n")
                }

                onResult(sb.toString().trim())
            } catch (e: Exception) {
                Log.e(TAG, "JSON parse error: ${e.message} on raw: $rawJson")
                onResult("OBSCURA PAGE: Title: ${web.title}, URL: ${web.url}")
            }
        }
    }

    private fun forceExtract(ctx: Context): String {
        val latch = CountDownLatch(1)
        val res = AtomicReference<String>("")
        mainHandler.post {
            headlessWebView?.let { web ->
                extractObscuraContent(web) {
                    res.set("NOTE: (Slow network; extracted partial page)\n$it")
                    latch.countDown()
                }
            } ?: run {
                res.set("ERROR: Network timed out before page could load.")
                latch.countDown()
            }
        }
        latch.await(3, TimeUnit.SECONDS)
        return res.get().ifBlank { "ERROR: Request timed out." }
    }

    private fun cleanUrl(raw: String): String {
        var u = raw.trim()
        if (u.startsWith("http://") || u.startsWith("https://")) return u
        if (u.contains(".") && !u.contains(" ")) return "https://$u"
        return "https://html.duckduckgo.com/html/?q=" + URLEncoder.encode(u, "UTF-8")
    }
}
