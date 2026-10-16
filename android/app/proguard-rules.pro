# OkHttp / Okio
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Flutter embedding
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Siya native components (manifest se chalte hain)
-keep class com.siya.ai.service.** { *; }
-keep class com.siya.ai.ui.main.OrbAnimationView { *; }
-keep class com.siya.ai.ui.main.WaveformView { *; }
-keep class com.siya.ai.security.PatternLockView { *; }

# Vosk (offline wake word)
-keep class org.vosk.** { *; }
-keep class com.sun.jna.** { *; }
-dontwarn com.sun.jna.**
