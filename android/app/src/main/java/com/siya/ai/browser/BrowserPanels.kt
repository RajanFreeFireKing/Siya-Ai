package com.siya.ai.browser

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.text.InputType
import android.view.Gravity
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Browser ke andar ke chhote panels: 3-dot menu, history / bookmarks list, find-in-page bar. */
object BrowserPanels {

    private fun box(ctx: Context): GradientDrawable {
        val d = ctx.resources.displayMetrics.density
        return GradientDrawable().apply {
            setColor(0xF5071826.toInt()); cornerRadius = 18 * d; setStroke((1.2f * d).toInt(), 0x9922D3EE.toInt())
        }
    }

    private fun row(ctx: Context, label: String, sub: String? = null, onClick: () -> Unit): TextView {
        val d = ctx.resources.displayMetrics.density
        return TextView(ctx).apply {
            text = if (sub.isNullOrBlank()) label else "$label\n$sub"
            setTextColor(0xFFFFFFFF.toInt()); textSize = 14.5f
            setPadding((18 * d).toInt(), (13 * d).toInt(), (18 * d).toInt(), (13 * d).toInt())
            setOnClickListener { onClick() }
            val ripple = android.util.TypedValue()
            context.theme.resolveAttribute(android.R.attr.selectableItemBackground, ripple, true)
            foreground = try { context.getDrawable(ripple.resourceId) } catch (_: Exception) { null }
        }
    }

    /** items: (action, label). Dark / Desktop ke aage tick AiBrowser se aata hai. */
    fun menu(ctx: Context, items: List<Pair<String, String>>, onPick: (String) -> Unit): FrameLayout {
        val d = ctx.resources.displayMetrics.density
        val col = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        items.forEach { (a, l) -> col.addView(row(ctx, l) { onPick(a) }) }
        val sv = ScrollView(ctx).apply { addView(col); background = box(ctx) }
        return FrameLayout(ctx).apply {
            addView(sv, FrameLayout.LayoutParams((210 * d).toInt(), ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.END).apply {
                setMargins(0, (4 * d).toInt(), (6 * d).toInt(), (40 * d).toInt())
            })
            setOnClickListener { onPick("close_panel") }
        }
    }

    /** items: (title, subtitle, url) */
    fun list(ctx: Context, title: String, items: List<Triple<String, String, String>>, onOpen: (String) -> Unit, onClear: (() -> Unit)?, onClose: () -> Unit): FrameLayout {
        val d = ctx.resources.displayMetrics.density
        val col = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        val head = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding((16 * d).toInt(), (8 * d).toInt(), (8 * d).toInt(), (8 * d).toInt())
            addView(TextView(ctx).apply { text = title; setTextColor(0xFF3EE6FF.toInt()); textSize = 16f }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            if (onClear != null) addView(TextView(ctx).apply { text = "Saaf karo"; setTextColor(0xFFFF6B6B.toInt()); setPadding((10 * d).toInt(), (6 * d).toInt(), (10 * d).toInt(), (6 * d).toInt()); setOnClickListener { onClear() } })
            addView(TextView(ctx).apply { text = "\u2715"; textSize = 18f; setTextColor(0xFFFFFFFF.toInt()); setPadding((12 * d).toInt(), (4 * d).toInt(), (12 * d).toInt(), (4 * d).toInt()); setOnClickListener { onClose() } })
        }
        col.addView(head)
        if (items.isEmpty()) col.addView(TextView(ctx).apply { text = "Kuch nahi hai"; setTextColor(0x99FFFFFF.toInt()); setPadding((16 * d).toInt(), (20 * d).toInt(), 0, (20 * d).toInt()) })
        items.forEach { (t, s, u) -> col.addView(row(ctx, t.ifBlank { u }.take(70), s.take(80)) { onOpen(u) }) }
        val sv = ScrollView(ctx).apply { addView(col); background = box(ctx) }
        return FrameLayout(ctx).apply {
            setPadding((8 * d).toInt(), (8 * d).toInt(), (8 * d).toInt(), (8 * d).toInt())
            addView(sv, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }
    }

    fun find(ctx: Context, onQuery: (String) -> Unit, onNext: (Boolean) -> Unit, onClose: () -> Unit): FrameLayout {
        val d = ctx.resources.displayMetrics.density
        val et = EditText(ctx).apply {
            hint = "Page mein dhundo"; setHintTextColor(0x88FFFFFF.toInt()); setTextColor(0xFFFFFFFF.toInt()); textSize = 14f
            inputType = InputType.TYPE_CLASS_TEXT; imeOptions = EditorInfo.IME_ACTION_SEARCH; setSingleLine(true)
            setOnEditorActionListener { v, _, _ -> onQuery(v.text.toString()); true }
        }
        fun b(t: String, f: () -> Unit) = TextView(ctx).apply { text = t; textSize = 18f; setTextColor(0xFF3EE6FF.toInt()); setPadding((10 * d).toInt(), (4 * d).toInt(), (10 * d).toInt(), (4 * d).toInt()); setOnClickListener { f() } }
        val bar = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; background = box(ctx)
            setPadding((12 * d).toInt(), 0, (4 * d).toInt(), 0)
            addView(et, LinearLayout.LayoutParams(0, (44 * d).toInt(), 1f))
            addView(b("\u25B2") { onNext(false) }); addView(b("\u25BC") { onNext(true) }); addView(b("\u2715") { onClose() })
        }
        return FrameLayout(ctx).apply {
            addView(bar, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM).apply { setMargins((8 * d).toInt(), 0, (8 * d).toInt(), (44 * d).toInt()) })
        }
    }
}
