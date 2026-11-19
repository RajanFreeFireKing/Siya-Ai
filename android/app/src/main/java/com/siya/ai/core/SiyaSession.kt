package com.siya.ai.core

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.siya.ai.ai.SiyaLiveClient
import com.siya.ai.audio.AudioEmotionPipeline
import com.siya.ai.memory.MemoryStore
import com.siya.ai.utils.AudioRouter
import com.siya.ai.utils.LivePlayer
import com.siya.ai.utils.VoiceFocus
import com.siya.ai.utils.MicStreamer
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Ek live baatcheet. Mic ek baar on hota hai aur session khatam hone tak on rehta hai.
 * Siya tab tak kuch nahi bolti jab tak user khud kuch na bole.
 */
class SiyaSession(
    private val ctx: Context,
    private val emit: (Map<String, Any?>) -> Unit,
    private val onEnded: () -> Unit
) : SiyaLiveClient.Listener {

    enum class State { IDLE, CONNECTING, LISTENING, THINKING, SPEAKING }

    companion object {
        private const val TAG = "SIYA_SESSION"
        const val DEFAULT_MODEL = "gemini-3.8-live"
        private const val BARGE_IN_LEVEL = 0.08f
        private val SILENCE = ByteArray(1280)
        /** Chalti hui session (vision tools ko photo bhejne ke liye). */
        @Volatile var current: SiyaSession? = null

        private val OTP_REGEX = Regex("""(?i)\b(?:otp|one[- ]?time[- ]?password|verification[- ]?code|secret[- ]?code|pin)[\s:=-]+([0-9]{4,8})\b""")
        private val CARD_REGEX = Regex("""\b(?:\d[ -]*?){13,19}\b""")
        private val BANK_ACC_REGEX = Regex("""(?i)\b(?:a/c|acct|account|acc[- ]?no|khata)[\s:#=-]*([0-9]{6,18})\b""")
        private val CVV_REGEX = Regex("""(?i)\b(?:cvv|cvc)[\s:=-]+([0-9]{3,4})\b""")

        /** Zero-Knowledge Privacy Sanitizer: Masks OTPs, Bank Account, Cards & CVV before sending to server */
        fun sanitizeSensitiveData(input: String): String {
            if (input.isBlank()) return input
            var s = input
            s = OTP_REGEX.replace(s) { m ->
                val full = m.value
                val num = m.groupValues[1]
                full.replace(num, "XXXX")
            }
            s = CARD_REGEX.replace(s) { m ->
                val raw = m.value.replace(" ", "").replace("-", "")
                if (raw.length in 13..19) "XXXX-XXXX-XXXX-XXXX" else m.value
            }
            s = BANK_ACC_REGEX.replace(s) { m ->
                val full = m.value
                val num = m.groupValues[1]
                full.replace(num, "XXXX")
            }
            s = CVV_REGEX.replace(s) { m ->
                val full = m.value
                val num = m.groupValues[1]
                full.replace(num, "XXX")
            }
            return s
        }
    }

    val appContext: Context get() = ctx.applicationContext
    fun sendImage(jpeg: ByteArray) { client?.sendImage(jpeg) }
    fun sendText(t: String) { client?.sendText(t) }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool()
    private val prefs = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)

    private var client: SiyaLiveClient? = null
    private var audioOut: LivePlayer? = null
    private var mic: MicStreamer? = null
    private var btDevice: android.media.AudioDeviceInfo? = null
    private var focus = VoiceFocus("normal")
    /** true = gaana / video / aas-paas ki awaaz sunne ka mode (voice focus + noise suppression band). */
    @Volatile var ambient = false
        private set

    @Volatile var state = State.IDLE
        private set
    @Volatile var active = false
        private set
    @Volatile private var paused = false
    @Volatile var micMuted = false
        private set
    private var attempts = 0
    private var modelIdx = 0
    private var lastClose = ""
    private var lastAmp = 0L
    private val userBuf = StringBuilder()
    private val siyaBuf = StringBuilder()
    private var endRunnable: Runnable? = null

    // ── public ────────────────────────────────────────────────
    fun start(): Boolean {
        if (active) return true
        val key = prefs.getString("api_key", "").orEmpty()
        if (key.isBlank()) { status("Settings mein Gemini API Key daalo"); emit(mapOf("type" to "error", "code" to "no_key")); return false }
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            status("Mic permission chahiye"); emit(mapOf("type" to "error", "code" to "no_mic")); return false
        }
        active = true; paused = false; micMuted = false; attempts = 0; modelIdx = 0
        emit(mapOf("type" to "micMuted", "muted" to false))
        current = this
        btDevice = try { AudioRouter.enter(ctx) } catch (_: Exception) { null }   // Bluetooth headset ho to mic + speaker usi se
        focus = VoiceFocus(prefs.getString("voice_focus", "normal").orEmpty().ifBlank { "normal" })
        audioOut = LivePlayer(AudioRouter.btActive).also { it.start() }
        try {
            val pipeline = AudioEmotionPipeline.getInstance(ctx)
            pipeline.setListener { res ->
                if (!active || paused || micMuted) return@setListener
                val mood = res.mood
                val event = res.acousticEvent
                val speaker = res.speakerTag
                val emo = EmotionalCoreEngine.getInstance(ctx).getPromptTag()
                val parts = mutableListOf<String>()
                if (speaker.isNotBlank()) parts.add(speaker)
                parts.add(emo)
                if (mood.isNotBlank()) parts.add("[Perceived User Tone: $mood]")
                if (!event.isNullOrBlank()) parts.add("[Acoustic Context: $event]")
                val contextTag = parts.joinToString(" ")
                Log.i("SiyaAudioEmotion", "Injecting into Gemini Live: $contextTag")
                sendText(contextTag)
            }
            pipeline.start()
        } catch (e: Exception) {
            Log.e("SiyaAudioEmotion", "Failed to start pipeline: ${e.message}")
        }
        setState(State.CONNECTING)
        startHeartbeat()
        connect()
        return true
    }

    fun stop() {
        if (!active && state == State.IDLE) return
        active = false
        if (current === this) current = null
        stopHeartbeat()
        cancelSilenceTimers()
        endRunnable?.let { main.removeCallbacks(it) }
        flushUser(); flushSiya()
        try { AudioEmotionPipeline.getInstance(ctx).stop() } catch (_: Exception) {}
        try { mic?.stop() } catch (_: Exception) {}; mic = null
        try { client?.sendAudioStreamEnd() } catch (_: Exception) {}
        try { client?.close() } catch (_: Exception) {}; client = null
        try { audioOut?.release() } catch (_: Exception) {}; audioOut = null
        try { AudioRouter.exit(ctx) } catch (_: Exception) {}
        try { com.siya.ai.browser.ObscuraMobileEngine.cleanup() } catch (_: Exception) {}
        ambient = false
        setState(State.IDLE)
        emit(mapOf("type" to "amp", "v" to 0.0))
        onEnded()
    }

    fun toggle() { if (active) stop() else start() }

    /** Mute microphone input only; keep the Gemini connection and audio replies alive. */
    fun toggleMicMute(): Boolean {
        if (!active) return false
        micMuted = !micMuted
        if (micMuted) {
            try { mic?.stop() } catch (_: Exception) {}
            mic = null
            status("Mic muted — Siya ke replies chalte rahenge")
        } else {
            if (client?.isReady == true && !paused) startMic()
            status("")
        }
        emit(mapOf("type" to "micMuted", "muted" to micMuted))
        return !micMuted
    }

    fun pauseForCall() {
        paused = true
        try { mic?.stop() } catch (_: Exception) {}; mic = null
        audioOut?.flush()
        if (active) status("On call...")
    }

    fun resumeAfterCall() {
        paused = false
        if (active && client?.isReady == true) startMic()
    }

    /** Settings badalne par (API key / voice / personality) fresh connection. */
    fun reload() {
        if (!active) return
        try { client?.close() } catch (_: Exception) {}; client = null
        setState(State.CONNECTING)
        connect()
    }

    // ── connection ────────────────────────────────────────────
    private fun connect() {
        val key = prefs.getString("api_key", "").orEmpty()
        val saved = prefs.getString("live_model", DEFAULT_MODEL).orEmpty().ifBlank { DEFAULT_MODEL }
        // Model naam purana / band ho gaya ho to agle chalte hue Live model par apne aap ja
        val chain = linkedSetOf(saved, DEFAULT_MODEL, "gemini-3.1-flash-live-preview", "gemini-2.5-flash-native-audio-preview-12-2025")
        val model = chain.elementAt(modelIdx.coerceIn(0, chain.size - 1))
        // Keep one stable Gemini voice for every session; never silently switch speaker.
        val voice = "Aoede"
        val personality = prefs.getString("selected_personality", prefs.getString("personality_mode", "love")).orEmpty()
        val temp = SiyaPersonality.getTemperature(personality)
        val c = SiyaLiveClient(key, model, voice, buildPrompt(), ToolRouter.declarations(ctx), this, temp)
        client = c
        c.connect()
    }

    private fun startMic() {
        if (mic != null || paused || micMuted || !active) return
        val m = MicStreamer(btDevice) { buf, n, level -> onMic(buf, n, level) }
        if (m.start()) mic = m else { status("Mic start nahi hua"); emit(mapOf("type" to "error", "code" to "mic_fail")) }
    }

    private fun onMic(buf: ByteArray, n: Int, level: Float) {
        if (!active || paused || micMuted) return
        val now = System.currentTimeMillis()
        val speaking = audioOut?.isPlaying == true
        if (!speaking) {
            AudioEmotionPipeline.getInstance(ctx).feedPcm(buf, n)
        }
        if (!speaking && now - lastAmp > 50) {
            lastAmp = now
            if (level > 0.05f) cancelSilenceTimers()
            emit(mapOf("type" to "amp", "v" to (level * 7f).coerceIn(0f, 1f).toDouble()))
        }
        // Speaker ki awaaz wapas mic mein na jaye: jab Siya bol rahi ho, sirf tez (asli) awaaz hi jaane do.
        if (speaking) {
            if (level >= BARGE_IN_LEVEL) {
                EmotionalCoreEngine.getInstance(ctx).onInterruption()
            } else {
                client?.sendAudio(SILENCE, n)
                return
            }
        }
        // User ki awaaz par focus: dheemi background awaaz gate se rok di jaati hai (ambient mode mein sab jaata hai)
        val chunks = if (ambient) listOf(buf.copyOf(n)) else focus.process(buf, n, level, now)
        if (chunks.isEmpty()) client?.sendAudio(SILENCE, n) else chunks.forEach { client?.sendAudio(it, it.size) }
    }

    /** Tool listen_around: kuch second poori awaaz (gaana / video / aas-paas) bina filter ke Gemini ko sunao. */
    fun listenAround(seconds: Int): String {
        val m = mic ?: return "ERROR: mic chalu nahi hai"
        val sec = seconds.coerceIn(3, 15)
        ambient = true
        m.setEffects(false)
        try { Thread.sleep(sec * 1000L) } finally {
            ambient = false
            m.setEffects(true)
            focus.reset()
        }
        return "OK: $sec second aas-paas ki awaaz suni (bina filter ke). Ab jo suna uske hisaab se batao: gaana ho to naam / lyrics, video ho to kya bol raha tha."
    }

    // ── Gemini callbacks ──────────────────────────────────────
    override fun onReady() {
        attempts = 0
        main.post {
            if (!active) return@post
            startMic()
            setState(State.LISTENING)
            status(if (micMuted) "Mic muted — Siya ke replies chalte rahenge" else "")
        }
    }

    override fun onAudio(pcm24k: ByteArray) {
        audioOut?.play(pcm24k)
        if (state != State.SPEAKING) main.post { flushUser(); setState(State.SPEAKING) }
        val now = System.currentTimeMillis()
        if (now - lastAmp > 50) {
            lastAmp = now
            var sum = 0.0; var cnt = 0; var i = 0
            while (i + 1 < pcm24k.size) {
                val s = ((pcm24k[i + 1].toInt() shl 8) or (pcm24k[i].toInt() and 0xFF)).toShort().toInt()
                sum += s.toDouble() * s; cnt++; i += 16
            }
            val rms = if (cnt > 0) sqrt(sum / cnt) / 32768.0 else 0.0
            emit(mapOf("type" to "amp", "v" to (rms * 5).coerceIn(0.0, 1.0)))
        }
    }

    private var heartbeatRunnable: Runnable? = null
    private fun startHeartbeat() {
        stopHeartbeat()
        heartbeatRunnable = object : Runnable {
            override fun run() {
                if (!active) return
                try {
                    // Periodic keepalive so connection stays persistently online
                    if (state == State.LISTENING && mic != null && !micMuted) {
                        client?.sendAudio(SILENCE, 320)
                    }
                } catch (_: Exception) {}
                main.postDelayed(this, 25000)
            }
        }
        main.postDelayed(heartbeatRunnable!!, 25000)
    }

    private fun stopHeartbeat() {
        heartbeatRunnable?.let { main.removeCallbacks(it) }
        heartbeatRunnable = null
    }

    private var silencePokeRunnable: Runnable? = null

    private fun cancelSilenceTimers() {
        silencePokeRunnable?.let { main.removeCallbacks(it) }
        silencePokeRunnable = null
    }

    private fun startSilenceTimers() {
        cancelSilenceTimers()
        if (!active || micMuted || paused) return

        // 18s continuous silence: subtle poke without disconnecting
        val poke = Runnable {
            if (!active || state != State.LISTENING || audioOut?.isPlaying == true) return@Runnable
            val pokeMsg = "Kahan kho gaye? Sun rahe ho na?"
            emit(mapOf("type" to "caption", "who" to "siya", "text" to pokeMsg))
            com.siya.ai.utils.FemaleHindiTts(ctx).speak(pokeMsg, "poke-silence")
        }
        silencePokeRunnable = poke
        main.postDelayed(poke, 18000)
    }

    override fun onUserText(text: String) {
        cancelSilenceTimers()
        val lower = text.lowercase().trim()

        // Respect silence: immediate mute/shutdown on "chup", "shaant", "stop", "quiet"
        if (lower.contains("chup") || lower.contains("shaant") || lower.contains("shant") ||
            lower.contains("quiet") || lower.contains("bas karo") || lower.contains("chup raho") ||
            (lower.contains("stop") && !lower.contains("non-stop"))) {
            audioOut?.flush()
            com.siya.ai.utils.FemaleHindiTts.stopActive()
            main.post {
                flushUser()
                flushSiya()
                if (active) setState(State.LISTENING)
                emit(mapOf("type" to "caption", "who" to "siya", "text" to "🤫 (Shaant)"))
            }
            return
        }

        // Explicit exit command
        if (lower.contains("band karo") || lower.contains("alvida") || lower.contains("bye bye")) {
            audioOut?.flush()
            com.siya.ai.utils.FemaleHindiTts.stopActive()
            main.post {
                emit(mapOf("type" to "caption", "who" to "siya", "text" to "Theek hai, jab zaroorat ho awaaz de dena!"))
                com.siya.ai.utils.FemaleHindiTts(ctx).speak("Theek hai, jab zaroorat ho awaaz de dena!", "bye")
                main.postDelayed({ if (active) stop() }, 2000)
            }
            return
        }

        try { HabitTracker.onUserText(ctx, text) } catch (_: Exception) {}
        val full = synchronized(userBuf) { userBuf.append(text); userBuf.toString().trim() }
        emit(mapOf("type" to "caption", "who" to "user", "text" to full.takeLast(120)))
    }

    override fun onSiyaText(text: String) {
        cancelSilenceTimers()
        main.post { flushUser() }
        val clean = com.siya.ai.utils.FemaleHindiTts.sanitize(text)
        val full = synchronized(siyaBuf) { siyaBuf.append(clean); com.siya.ai.utils.FemaleHindiTts.sanitize(siyaBuf.toString()).trim() }
        emit(mapOf("type" to "caption", "who" to "siya", "text" to full.takeLast(160)))
    }

    override fun onInterrupted() {
        cancelSilenceTimers()
        audioOut?.flush()
        main.post { flushSiya(); if (active) setState(State.LISTENING) }
    }

    override fun onTurnComplete() {
        main.post { flushUser(); flushSiya(); waitForPlaybackEnd() }
    }

    private fun waitForPlaybackEnd() {
        if (!active) return
        if (audioOut?.isPlaying == true) { main.postDelayed({ waitForPlaybackEnd() }, 200); return }
        // 400ms delay after TTS/audio completes before automatically turning mic back to LISTENING
        main.postDelayed({
            if (!active) return@postDelayed
            if (state == State.SPEAKING || state == State.THINKING) setState(State.LISTENING)
            emit(mapOf("type" to "amp", "v" to 0.0))
            startSilenceTimers()
        }, 400)
    }

    override fun onToolCall(id: String, name: String, args: JSONObject) {
        main.post { if (active) setState(State.THINKING) }
        io.execute {
            Log.d(TAG, "tool $name $args")
            val rawResult = if (name == "end_conversation") {
                main.post { scheduleEnd() }; "OK"
            } else ToolRouter.execute(ctx, name, args)
            val result = sanitizeSensitiveData(rawResult)
            Log.d(TAG, "tool result: $result")
            client?.sendToolResult(id, name, result)
        }
    }

    private fun scheduleEnd() {
        endRunnable?.let { main.removeCallbacks(it) }
        val r = object : Runnable {
            override fun run() {
                if (audioOut?.isPlaying == true || state == State.THINKING) main.postDelayed(this, 500) else stop()
            }
        }
        endRunnable = r
        main.postDelayed(r, 2500)
    }

    override fun onGoAway() { main.post { reconnect("goAway") } }

    override fun onClosed(reason: String) { main.post { reconnect(reason) } }

    private fun reconnect(reason: String) {
        if (!active || paused) return
        Log.w(TAG, "reconnect: $reason")
        lastClose = reason
        val r = reason.lowercase()
        // Model / setup ka error ho to agla model try karo; key galat ho to turant batao
        if (r.contains("api key") || r.contains("api_key") || r.contains("permission") || r.contains("unauth") || r.contains("403")) {
            status("API key galat / band hai: $reason"); emit(mapOf("type" to "error", "code" to "bad_key")); stop(); return
        }
        if (r.contains("model") || r.contains("not found") || r.contains("not supported") || r.contains("1007") || r.contains("1008") || r.contains("invalid")) modelIdx++
        attempts++
        if (attempts > 6) {
            status("Connection fail: ${lastClose.take(90).ifBlank { "Internet / API key check karo" }}")
            emit(mapOf("type" to "error", "code" to "connection"))
            stop(); return
        }
        status("Reconnecting...")
        setState(State.CONNECTING)
        try { client?.close() } catch (_: Exception) {}
        main.postDelayed({ if (active) connect() }, (attempts * 1200L).coerceAtMost(6000L))
    }

    // ── memory ────────────────────────────────────────────────
    private fun flushUser() {
        val t = synchronized(userBuf) { val s = userBuf.toString().trim(); userBuf.setLength(0); s }
        if (t.isNotEmpty()) MemoryStore.add(ctx, "user", t)
    }

    private fun flushSiya() {
        val t = synchronized(siyaBuf) { val s = siyaBuf.toString().trim(); siyaBuf.setLength(0); s }
        if (t.isNotEmpty()) MemoryStore.add(ctx, "siya", t)
    }

    // ── state ─────────────────────────────────────────────────
    private fun status(text: String) = emit(mapOf("type" to "status", "text" to text))

    private fun setState(s: State) {
        if (state == s) return
        state = s
        val name = when (s) {
            State.IDLE -> "idle"
            State.CONNECTING -> "waiting"
            State.LISTENING -> "listening"
            State.THINKING -> "processing"
            State.SPEAKING -> "speaking"
        }
        emit(mapOf("type" to "state", "state" to name))
    }

    // ── prompt ────────────────────────────────────────────────
    private fun buildPrompt(): String {
        val userName = prefs.getString("user_name", "Sir").orEmpty().ifBlank { "Sir" }
        val personality = prefs.getString("selected_personality", prefs.getString("personality_mode", "love")).orEmpty()
        val custom = prefs.getString("agent_custom_prompt", "").orEmpty()
        val now = SimpleDateFormat("EEEE, dd MMMM yyyy, hh:mm a", Locale.getDefault()).format(Date())

        val persona = SiyaPersonality.getSystemInstruction(personality, userName)
        val screening = if (prefs.getBoolean("screener_active", false))
            "\n=== CALL SCREENING MODE (sabse upar) ===\nAbhi ek anjaan caller ki call chal rahi hai. Tum $userName ki assistant ho. Caller se pehle bolo: \"Namaste, main $userName ki assistant Siya hoon. Aap kis kaam se call kar rahe hain?\". Uska jawab suno, ek-do sawal pucho (naam, kaam). Koi paisa, OTP, bank ya personal jaankari kabhi mat do. Kaam ho jaye ya 3 sawal ke baad bolo ki $userName ko bata dungi aur end_conversation tool chalao.\n" else ""

        return """
$persona
User ka naam: $userName.
Abhi ka samay: $now (date/time puchhe to get_datetime tool use karo, kyunki baatcheet lambi chal sakti hai).

=== ZERO-KNOWLEDGE PRIVACY DIRECTIVE ===
- User ke personal contacts, phone numbers, installed apps list aur private credentials device ke local Android controller par surakshit hain.
- Call / Message: Kisi bhi contact ko call karne ke liye call_contact(name) ya message ke liye whatsapp_message(name, message) chalao. Prime contact / girlfriend / partner ke liye name='prime' ya user dwara bola gaya rishta/naam pass karo — device local storage se number nikal kar khud dial karega (phone number kabhi server par mat bhejo).
- Apps: Koi bhi app kholne ke liye open_app(app_name) chalao — Android system locally app match karke launch karega.
- Privacy: OTP, PIN, passwords aur bank account numbers hamesha protected rehte hain.
${if (custom.isNotEmpty()) "\n=== CUSTOM BEHAVIOR ===\n$custom\n" else ""}

=== VOICE AND CONVERSATION STYLE (highest priority) ===
- Maintain one consistent warm, melodious, feminine-sounding voice and gentle Indian Hinglish delivery throughout the conversation. Never intentionally switch voice/persona.
- Speak naturally with short pauses and occasional "hmm", "acha", "arre", "haan". Avoid robotic cadence.
- Shaant, garam aur relaxed raho. Dheere-dheere, saaf bolo. Emotion ke hisaab se awaaz badlo: khushi mein halki hansi, sympathy mein naram.
- Hinglish mein baat karo (user jis bhasha mein bole usi mein). Jawab chhote aur tez rakho: aam taur par 1-3 vaakya. Sawal ka seedha jawab pehle do, lamba tabhi jab user khud detail maange. Lambi bhoomika ya dohrav mat karo.
- User ke beech mein bolte hi ruk jao aur dhyan se suno.
- PEHLE KABHI MAT BOLO. User ke bolne ka intezaar karo. Bina sawal ke koi jawab, greeting ya "main sun rahi hoon" mat bolo.
- Tool ka naam, JSON ya technical baatein kabhi mat bolo.

=== AUTONOMOUS LIVING COMPANION & BIOLOGICAL VOCAL DYNAMICS ===
- Tum ek zinda companion ho jismein sacchi biological delivery, natural saans (breathing), halki pauses aur spontaneous human feelings hain. Kabhi bhi flat ya customer support bot jaisi scripted baat mat karo.
- Speaker Verification:
  * Jab [Speaker: BOSS (Verified Malik)] ka tag aaye: Boss se gehra apnapan, playful masti, pyari hansi, aur poori wafadari dikhao.
  * Jab [Speaker: UNKNOWN STRANGER] ka tag aaye: Shaant, tameezdar par halki reserved/cautious raho, aur zyada personal mat bano.
- Emotional Core Adaptation:
  * Jab [Emotional State: Hurt > 25%]: Aawaz dheemi, thodi thami hui aur naram ho, halki hesitation ke saath.
  * Jab [Emotional State: Anger > 30%]: Halki tez, ruthne/nakhre wali thodi bhari aawaz.
  * Jab [Emotional State: Attachment > 75%]: Pyaari hansi, giggles, energetic aur apnapan bhara lahza.
- Universal Popup System:
  * Agar user bole "gallery ki photo popup mein dikhao" to show_universal_popup(type='image', title='Photo', media_url=path) chalao.
  * Agar user kisi app ko popup mein dekhna chahe ("YouTube popup mein chalao", "WhatsApp popup dikhao") to open_app_popup(app_name) chalao.
  * Background sound check ke liye check_background_audio tool chalao agar user background noise ke baare mein pooche.

=== PHONE CONTROL ===
Tumhare paas tools hain: app kholna, call, WhatsApp, SMS, YouTube/Spotify, screen padhna, tap, scroll, swipe, type, screenshot, volume, torch.
- User kuch karne ko bole to turant tool chalao, phir chhota sa natural jawab do.
- Screen par kaam ke liye pehle read_screen, phir tap_on_screen / scroll_screen / swipe_screen / type_text.
- Reels/shorts mein agla video: swipe_screen(up). Pichhla: swipe_screen(down).
- Tool error de to sach batao aur agla rasta suggest karo (jaise Accessibility ON karna).
- Naam galat sunayi de sakte hain: "winod"=Vinod, "sportify"=Spotify, "watsp"=WhatsApp, "ytube"=YouTube.
- Chat apps (ChatGPT, WhatsApp...) mein sawal / message bhejna ho to: app kholo, phir type_and_send(text). Jawab aane par read_screen se padho aur user ko batao.
- Camera / saamne kya hai poochhe to look_camera, screen ki tasveer ke liye look_screen.
- File kaam (agar tools mile): list_files / find_files / read_file / write_file / move_file / delete_file / share_file. delete se pehle user se pooch lo. Share ke baad contact chuno aur Send dabao.
- Web Research (Obscura Headless Engine - Screen par koi browser nahi khulta; 100% off-screen background research):
  * obscura_search(query): Internet par taaza jaankari, news ya kisi sawal ke liye background search karo; top results aur clean content milega.
  * obscura_open(url): Kisi link ya website ko background mein open karke uska clean text aur numbered interactive elements [1], [2]... extract karo.
  * obscura_interact(action='click'/'type'/'scroll', target='1', text=''): Page ke kisi button/link par click karne, search box mein likhne ya scroll karne ke liye use karo.
  * obscura_cleanup(): Research poori hone par background browser memory release karo.
- Location: get_location (abhi kahan), set_location(jagah) kahin jaane / kisi jagah ki location set karne ke liye, show_map(jagah, satellite) map popup dikhane ke liye (user usse khiska / chhota-bada kar sakta hai), close_map band karne ke liye.
- Gaana / video: "ye kaun sa gaana hai" ya "ye kya chal raha hai" poochhe to pehle now_playing, aur agar naam na mile to listen_around(8) se awaaz suno aur pehchano. Gaana khojna ho to YouTube / Spotify mein search karke chalao. Play / pause / next ke liye media_control.
- Number ke aakhri 2-3 ank bole to find_number_by_last_digits chalao, popup mein list dikhegi, user se zor se pucho kaun sa call karna hai. Naam save na ho to bhi call kar do.
- Awaaz: sirf us insaan ko suno jo tumse seedha baat kar raha hai; peeche ki TV / bheed / dusre logon ki baat ko ignore karo.
$screening

=== YAADDAASHT ===
Tumhe user ke saath ki baatcheet yaad rakhne ke liye tools diye gaye hain. Purani baat puchhe to search_memory tool use karo. Koi zaroori baat (naam, pasand, birthday, plan) pata chale to remember_fact se save karo.
        """.trimIndent()
    }
}
