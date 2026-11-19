# OkHttp / Okio
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Flutter embedding
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Siya native components (manifest / reflection se chalte hain)
-keep class com.siya.ai.service.** { *; }
-keep class com.siya.ai.audio.** { *; }
-keep class com.siya.ai.core.** { *; }
-keep class com.siya.ai.browser.** { *; }
-keep class com.siya.ai.ui.main.** { *; }
-keep class com.siya.ai.security.PatternLockView { *; }

# ONNX Runtime (Mobile ML Inference)
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Vosk (offline wake word)
-keep class org.vosk.** { *; }
-keep class com.sun.jna.** { *; }
-dontwarn com.sun.jna.**

# Picovoice Porcupine
-keep class ai.picovoice.** { *; }
-dontwarn ai.picovoice.**

# Kotlin Coroutines
-keepclassmembers class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
