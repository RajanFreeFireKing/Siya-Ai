package com.siya.ai.ui.main

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView

/** Feature 15: asli chalne wala Calculator. Secret code likh ke "=" dabao to Siya (MainActivity) khulti hai. */
class CalculatorActivity : Activity() {
    private var expr = ""
    private lateinit var display: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val d = resources.displayMetrics.density
        window.statusBarColor = Color.BLACK; window.navigationBarColor = Color.BLACK
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.BLACK); setPadding((12 * d).toInt(), (24 * d).toInt(), (12 * d).toInt(), (16 * d).toInt()) }
        display = TextView(this).apply { text = "0"; setTextColor(Color.WHITE); textSize = 52f; gravity = Gravity.END or Gravity.BOTTOM; maxLines = 2 }
        root.addView(display, LinearLayout.LayoutParams(-1, 0, 1f))
        val keys = listOf("C", "\u232B", "%", "\u00F7", "7", "8", "9", "\u00D7", "4", "5", "6", "-", "1", "2", "3", "+", "00", "0", ".", "=")
        val grid = GridLayout(this).apply { columnCount = 4; rowCount = 5 }
        keys.forEach { k ->
            val op = k in listOf("\u00F7", "\u00D7", "-", "+", "=")
            grid.addView(Button(this).apply {
                text = k; textSize = 24f; setTextColor(Color.WHITE); isAllCaps = false
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (op) 0xFFFF9F0A.toInt() else if (k in listOf("C", "\u232B", "%")) 0xFF636366.toInt() else 0xFF333333.toInt()) }
                setOnClickListener { press(k) }
            }, GridLayout.LayoutParams(GridLayout.spec(GridLayout.UNDEFINED, 1f), GridLayout.spec(GridLayout.UNDEFINED, 1f)).apply { width = 0; height = (78 * d).toInt(); setMargins((5 * d).toInt(), (5 * d).toInt(), (5 * d).toInt(), (5 * d).toInt()) })
        }
        root.addView(grid, LinearLayout.LayoutParams(-1, -2))
        setContentView(root)
    }

    private fun press(k: String) {
        when (k) {
            "C" -> expr = ""
            "\u232B" -> expr = expr.dropLast(1)
            "=" -> {
                val code = getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).getString("ghost_code", "2580").orEmpty()
                if (expr == code) { expr = ""; startActivity(Intent(this, MainActivity::class.java)); finish(); return }
                expr = eval(expr)
            }
            else -> expr += k
        }
        display.text = expr.ifEmpty { "0" }
    }

    // chhota safe parser: + - × ÷ %  (precedence ke saath)
    private fun eval(s: String): String = try {
        val t = s.replace('\u00D7', '*').replace('\u00F7', '/')
        var i = 0
        fun peek() = if (i < t.length) t[i] else '\u0000'
        fun num(): Double { val st = i; if (peek() == '-') i++; while (peek().isDigit() || peek() == '.') i++; var v = t.substring(st, i).toDouble(); while (peek() == '%') { i++; v /= 100 }; return v }
        fun term(): Double { var v = num(); while (peek() == '*' || peek() == '/') { val o = t[i++]; val r = num(); v = if (o == '*') v * r else v / r }; return v }
        fun expr(): Double { var v = term(); while (peek() == '+' || peek() == '-') { val o = t[i++]; val r = term(); v = if (o == '+') v + r else v - r }; return v }
        val r = expr()
        if (r.isNaN() || r.isInfinite()) "Error" else if (r == Math.floor(r) && Math.abs(r) < 1e15) r.toLong().toString() else "%.8f".format(r).trimEnd('0').trimEnd('.')
    } catch (_: Exception) { "Error" }
}
