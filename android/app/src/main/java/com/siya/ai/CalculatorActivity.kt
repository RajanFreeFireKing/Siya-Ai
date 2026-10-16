package com.siya.ai.ui.main

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.widget.Button
import android.widget.EditText
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.text.InputType
import java.math.BigDecimal
import java.math.MathContext
import java.util.Locale

/** Native calculator with an optional PIN-gated entry to Siya. */
class CalculatorActivity : Activity() {
    private var expr = ""
    private lateinit var display: TextView

    companion object {
        const val PREFS_NAME = "siya_prefs"
        const val KEY_SECRET_PIN = "KEY_SECRET_PIN"
        const val DEFAULT_SECRET_PIN = "4456"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val d = resources.displayMetrics.density
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            setPadding((12 * d).toInt(), (24 * d).toInt(), (12 * d).toInt(), (16 * d).toInt())
        }
        display = TextView(this).apply {
            text = "0"
            setTextColor(Color.WHITE)
            textSize = 52f
            gravity = Gravity.END or Gravity.BOTTOM
            maxLines = 2
            setPadding(0, 0, (8 * d).toInt(), (20 * d).toInt())
            contentDescription = "Calculator display. Long press to change secret PIN."
            setOnLongClickListener { showPinDialog(); true }
        }
        root.addView(display, LinearLayout.LayoutParams(-1, 0, 1f))
        val keys = listOf("C", "⌫", "%", "÷", "7", "8", "9", "×", "4", "5", "6", "-", "1", "2", "3", "+", "00", "0", ".", "=")
        val grid = GridLayout(this).apply { columnCount = 4; rowCount = 5 }
        keys.forEach { key ->
            val operator = key in listOf("÷", "×", "-", "+", "=")
            grid.addView(Button(this).apply {
                text = key
                textSize = 24f
                setTextColor(Color.WHITE)
                isAllCaps = false
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(if (operator) 0xFFFF9F0A.toInt() else if (key in listOf("C", "⌫", "%")) 0xFF636366.toInt() else 0xFF333333.toInt())
                }
                setOnClickListener { press(key) }
            }, GridLayout.LayoutParams(
                GridLayout.spec(GridLayout.UNDEFINED, 1f),
                GridLayout.spec(GridLayout.UNDEFINED, 1f)
            ).apply {
                width = 0
                height = (78 * d).toInt()
                setMargins((5 * d).toInt(), (5 * d).toInt(), (5 * d).toInt(), (5 * d).toInt())
            })
        }
        root.addView(grid, LinearLayout.LayoutParams(-1, -2))
        setContentView(root)
    }

    private fun press(key: String) {
        when (key) {
            "C" -> expr = ""
            "⌫" -> expr = expr.dropLast(1)
            "=" -> {
                val pin = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .getString(KEY_SECRET_PIN, DEFAULT_SECRET_PIN) ?: DEFAULT_SECRET_PIN
                if (expr == pin) {
                    display.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                    val intent = Intent(this, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }
                    startActivity(intent)
                    finish()
                    return
                }
                expr = try {
                    formatResult(ExpressionParser(expr).parse())
                } catch (_: IllegalArgumentException) {
                    // Invalid/incomplete expressions remain editable; never show a false "Error.".
                    expr = expr
                    return
                } catch (_: ArithmeticException) {
                    return
                }
            }
            else -> {
                if (expr.length >= 80) return
                if (key in listOf("+", "-", "×", "÷") && (expr.isEmpty() || expr.last() in "+-×÷")) {
                    if (key == "-" && expr.isEmpty()) expr = "-"
                    else if (expr.isNotEmpty()) expr = expr.dropLast(1) + key
                } else {
                    expr += key
                }
            }
        }
        display.text = expr.ifEmpty { "0" }
    }

    private fun formatResult(value: BigDecimal): String {
        val normalized = value.stripTrailingZeros()
        return if (normalized.scale() < 0) normalized.setScale(0).toPlainString()
        else normalized.toPlainString()
    }

    private fun showPinDialog() {
        val input = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
            hint = "4–8 digit PIN"
            setText(getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(KEY_SECRET_PIN, DEFAULT_SECRET_PIN))
            setSelection(text.length)
        }
        AlertDialog.Builder(this)
            .setTitle("Change secret PIN")
            .setMessage("Set a new 4–8 digit PIN. Enter it in the calculator and press = to open Siya.")
            .setView(input)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Save") { _, _ ->
                val pin = input.text.toString().trim()
                if (pin.length in 4..8 && pin.all(Char::isDigit)) {
                    getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putString(KEY_SECRET_PIN, pin).apply()
                    display.text = "PIN saved"
                    display.postDelayed({ if (!isFinishing) display.text = expr.ifEmpty { "0" } }, 1200)
                } else {
                    display.text = "Use 4–8 digits"
                    display.postDelayed({ if (!isFinishing) display.text = expr.ifEmpty { "0" } }, 1500)
                }
            }
            .show()
    }

    /** Recursive-descent parser with conventional precedence and exact decimal arithmetic. */
    private class ExpressionParser(source: String) {
        private val text = source.replace('×', '*').replace('÷', '/').replace(" ", "")
        private var index = 0

        fun parse(): BigDecimal {
            require(text.isNotEmpty()) { "empty expression" }
            val result = parseAddSubtract()
            require(index == text.length) { "unexpected character" }
            return result
        }

        private fun parseAddSubtract(): BigDecimal {
            var value = parseMultiplyDivide()
            while (peek() == '+' || peek() == '-') {
                val op = text[index++]
                val right = parseMultiplyDivide()
                value = if (op == '+') value.add(right) else value.subtract(right)
            }
            return value
        }

        private fun parseMultiplyDivide(): BigDecimal {
            var value = parseUnary()
            while (peek() == '*' || peek() == '/') {
                val op = text[index++]
                val right = parseUnary()
                value = if (op == '*') value.multiply(right) else {
                    require(right.compareTo(BigDecimal.ZERO) != 0) { "division by zero" }
                    value.divide(right, MathContext.DECIMAL64)
                }
            }
            return value
        }

        private fun parseUnary(): BigDecimal {
            if (peek() == '+') { index++; return parseUnary() }
            if (peek() == '-') { index++; return parseUnary().negate() }
            var value = parseNumber()
            while (peek() == '%') {
                index++
                value = value.divide(BigDecimal("100"), MathContext.DECIMAL64)
            }
            return value
        }

        private fun parseNumber(): BigDecimal {
            val start = index
            var dots = 0
            while (index < text.length && (text[index].isDigit() || text[index] == '.')) {
                if (text[index] == '.') dots++
                require(dots <= 1) { "invalid decimal" }
                index++
            }
            require(index > start && text.substring(start, index) != ".") { "number expected" }
            return try { BigDecimal(text.substring(start, index)) }
            catch (_: NumberFormatException) { throw IllegalArgumentException("invalid number") }
        }

        private fun peek(): Char = if (index < text.length) text[index] else '\u0000'
    }
}
