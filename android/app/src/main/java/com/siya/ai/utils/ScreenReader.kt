package com.siya.ai.utils

import android.view.accessibility.AccessibilityNodeInfo

object ScreenReader {
    
    // Ye function screen par dikhne wale saare text ko padh kar ek String banata hai
    fun dump(node: AccessibilityNodeInfo?): String {
        if (node == null) return ""
        
        val stringBuilder = java.lang.StringBuilder()
        extractText(node, stringBuilder)
        return stringBuilder.toString()
    }

    private fun extractText(node: AccessibilityNodeInfo?, stringBuilder: java.lang.StringBuilder) {
        if (node == null) return

        if (node.text != null) {
            stringBuilder.append(node.text).append(" ")
        } else if (node.contentDescription != null) {
            stringBuilder.append(node.contentDescription).append(" ")
        }

        for (i in 0 until node.childCount) {
            extractText(node.getChild(i), stringBuilder)
        }
    }
}
