package com.siya.ai.core

import android.content.Context
import com.siya.ai.browser.AiBrowser
import com.siya.ai.data.LocationHelper
import com.siya.ai.data.MapWindow
import com.siya.ai.memory.MemoryStore
import com.siya.ai.service.SmartAccessibilityEngine
import org.json.JSONArray
import org.json.JSONObject

/** Gemini ke function-calling tools: declaration + execution. */
object ToolRouter {

    private fun fn(name: String, desc: String, vararg params: Triple<String, String, Boolean>): JSONObject {
        val o = JSONObject().put("name", name).put("description", desc)
        if (params.isNotEmpty()) {
            val props = JSONObject()
            val req = JSONArray()
            for ((n, d, r) in params) {
                props.put(n, JSONObject().put("type", "STRING").put("description", d))
                if (r) req.put(n)
            }
            o.put("parameters", JSONObject().put("type", "OBJECT").put("properties", props).put("required", req))
        }
        return o
    }

    private fun p(n: String, d: String, required: Boolean = true) = Triple(n, d, required)

    fun declarations(ctx: Context): JSONArray {
        val f = JSONArray()
        f.put(fn("open_app", "Phone mein koi bhi installed app kholo (WhatsApp, YouTube, Instagram, Settings, Camera, Chrome, kisi bhi app ka naam).", p("app_name", "App ka naam, jaise user ne bola")))
        f.put(fn("list_apps", "Phone mein installed saare apps ke naam batao."))
        f.put(fn("call_contact", "Kisi contact ya number ko normal phone call karo.", p("name", "Contact ka naam ya number")))
        f.put(fn("whatsapp_message", "WhatsApp par message bhejo (khud send bhi ho jaata hai).", p("name", "Contact ka naam ya number"), p("message", "Bhejne wala message")))
        f.put(fn("whatsapp_call", "WhatsApp voice ya video call karo.", p("name", "Contact ka naam"), p("video", "true agar video call, warna false", false)))
        f.put(fn("send_sms", "SMS bhejo.", p("name", "Contact ka naam ya number"), p("message", "SMS text")))
        f.put(fn("youtube_play", "YouTube par kuch search karke pehla video chalao.", p("query", "Kya chalana hai")))
        f.put(fn("spotify_play", "Spotify par gaana search karo.", p("query", "Gaana / artist")))
        f.put(fn("media_control", "Chal rahe music/video ko control karo.", p("action", "play, pause, next, previous, stop")))
        f.put(fn("open_url", "Browser mein link ya website kholo.", p("url", "Website / link")))
        f.put(fn("generate_image_web", "ChatGPT ya Gemini web par image prompt submit karo, generated image ka download button dhoondo, aur download ko SiyaAI Gallery mein save karo. edit_image=true hone par photo picker khulega aur user ko intended photo select karni hogi.", p("provider", "chatgpt ya gemini"), p("prompt", "Image generate/edit karne ka detailed prompt"), p("edit_image", "true agar existing photo ko edit karna hai; picker se photo select karni hogi", false)))
        f.put(fn("post_story_status", "WhatsApp Status ya Instagram Story mein recent accessible photo ke saath music aur caption set karke post karo. Permission/login aaye to user ko screen par complete karna hoga.", p("platform", "whatsapp ya instagram"), p("music_query", "Gaane ka naam ya music vibe; jaise Diwali festive instrumental", false), p("caption", "Story caption; khaali ho to festive caption use hoga", false)))
        f.put(fn("flashlight", "Torch on/off.", p("state", "on ya off")))
        f.put(fn("volume", "Volume control.", p("direction", "up, down, mute, max")))
        f.put(fn("read_screen", "Abhi phone ki screen par kya dikh raha hai padho (text + tap karne layak cheezein). Koi bhi screen kaam karne se pehle ise use karo."))
        f.put(fn("tap_on_screen", "Screen par kisi button/text/icon par tap karo.", p("text", "Button ya item ka text / description")))
        f.put(fn("long_press", "Screen par kisi item ko long press karo.", p("text", "Item ka text")))
        f.put(fn("scroll_screen", "Screen scroll karo. down = neeche ka content, up = upar ka content.", p("direction", "down ya up")))
        f.put(fn("swipe_screen", "Ungli se swipe karo (reels/shorts/next video/photo ke liye). direction ungli ki disha hai: up = agla reel/video.", p("direction", "up, down, left, right")))
        f.put(fn("type_text", "Jo input box focus mein hai usme text likho.", p("text", "Likhne wala text")))
        f.put(fn("press_key", "System button dabao.", p("key", "back, home, recents, notifications, quick_settings")))
        f.put(fn("take_screenshot", "Abhi ki screen ka screenshot lo aur gallery mein save karo."))
        f.put(fn("get_datetime", "Abhi ki exact date, din aur samay."))
        f.put(fn("battery_level", "Phone ki battery kitni hai."))
        f.put(fn("search_memory", "Purani chat/baat-cheet mein dhundo ki pehle kab kya baat hui thi. Jab user purani baat puchhe to zaroor use karo.", p("query", "Kya dhundna hai (keywords)")))
        f.put(fn("type_and_send", "Jo input box mein (ChatGPT, WhatsApp, koi bhi chat app) text likho aur turant Send karo. Sawal poochne / message bhejne ka sabse aasan tareeka.", p("text", "Likhne aur bhejne wala text")))
        f.put(fn("submit_text", "Input box mein likha hua text Send / Enter karke bhejo."))
        f.put(fn("look_camera", "Phone ke camera se photo lo aur dekho ki saamne kya hai (log, cheezein, text). Camera ke saamne kya hai poochhe to ise use karo.", p("camera", "back (default) ya front (selfie)", false), p("identify_people", "true agar saved logon ko pehchanna hai (default true)", false)))
        f.put(fn("look_screen", "Phone ki screen ko tasveer ki tarah dekho (image, video, chart jo text mein na padhi ja sake).", p("identify_people", "true agar saved logon ko pehchanna hai", false)))
        f.put(fn("set_location", "Kisi jagah ko user ki location set karo (kahin jaane / kisi sheher ki location ke liye). 'phone' bolo to asli GPS location par wapas.", p("place", "Jagah ka naam ya address, ya 'phone'")))
        f.put(fn("show_map", "Map popup dikhao (satellite ya normal). Window ko user khiska aur chhota-bada kar sakta hai.", p("place", "Jagah ka naam (khaali = user ki location)", false), p("satellite", "true = satellite view (default true)", false)))
        f.put(fn("close_map", "Map popup band karo."))
        f.put(fn("find_number_by_last_digits", "Number ke aakhri 2-4 ank se milte contacts / recent call numbers dhundo aur popup mein dikhao. Naam save na ho to bhi.", p("digits", "Aakhri ank, jaise 47")))
        f.put(fn("now_playing", "Abhi kaun sa gaana / video chal raha hai (naam, artist, app)."))
        f.put(fn("listen_around", "Aas-paas ya phone par chal rahe gaane / video ki awaaz kuch second bina filter ke suno taaki pehchan sako ya samajh sako.", p("seconds", "Kitne second (3-15, default 8)", false)))
        f.put(fn("get_location", "User ki abhi ki location (ya jo location user ne map par set ki hai) batao."))
        f.put(fn("show_on_map", "Maps app mein koi jagah dikhao / raasta kholo.", p("query", "Jagah ka naam ya address")))
        if (com.siya.ai.browser.AiBrowser.isEnabled(ctx)) {
            f.put(fn("browser_search", "Siya ke apne browser mein Google par search karo (popup ya poori screen).", p("query", "Kya search karna hai"), p("mode", "popup (default) ya full", false)))
            f.put(fn("browser_open", "Siya ke browser mein koi bhi website / link kholo.", p("url", "Website ya link"), p("mode", "popup (default) ya full", false)))
            f.put(fn("browser_read", "Browser ke abhi ke page ka text padho."))
            f.put(fn("browser_links", "Browser ke page ke links (text -> url) dekho."))
            f.put(fn("browser_click", "Browser ke page par kisi link / button / video ke text par click karo (gaana ya video chalane ke liye bhi).", p("text", "Click karne wale item ka text")))
            f.put(fn("browser_type", "Browser ke page ke input box mein likho (aur chaho to Enter).", p("text", "Likhne wala text"), p("submit", "true agar Enter karna hai", false)))
            f.put(fn("browser_scroll", "Browser ka page scroll karo.", p("direction", "down, up, top, bottom")))
            f.put(fn("browser_back", "Browser mein peeche jao."))
            f.put(fn("browser_download", "Koi file / link browser se download karo (Downloads mein).", p("url", "Download ka link")))
            f.put(fn("browser_menu", "Browser ke 3-dot menu ka koi bhi option chalao: reload, forward, add_bookmark, bookmarks, history, clear_history, downloads, dark_mode, desktop_site, find, zoom_in, zoom_out, share, open_external, clear_data.", p("action", "Option ka naam"), p("arg", "Zaroorat ho to: dark_mode/desktop_site ke liye on/off, find ke liye text", false)))
            f.put(fn("browser_window", "Browser window ko chhota / bada / poori screen / popup karo ya screen par idhar-udhar le jao.", p("action", "small, big, full, popup, min, restore, top, bottom, left, right, center")))
            f.put(fn("browser_close", "Browser band karo (chalta hua gaana / video bhi ruk jaata hai)."))
        }
        if (FileTools.hasAccess()) {
            f.put(fn("list_files", "Phone ke kisi folder ki files dikhao. Khaali path = main storage.", p("path", "Folder, jaise Download, DCIM/Camera, Documents", false)))
            f.put(fn("find_files", "Naam se file / folder dhundo.", p("query", "Naam ka hissa"), p("path", "Kahan dhundna hai (khaali = poora storage)", false)))
            f.put(fn("read_file", "Text file padho.", p("path", "File ka path")))
            f.put(fn("write_file", "Text file likho (naya banao / overwrite / append).", p("path", "File ka path"), p("content", "Likhne wala text"), p("mode", "overwrite (default), append, ya create", false)))
            f.put(fn("make_folder", "Naya folder banao.", p("path", "Folder ka path")))
            f.put(fn("move_file", "File ya folder ko move / rename karo.", p("from", "Purana path"), p("to", "Naya path ya folder")))
            f.put(fn("copy_file", "File ya folder ki copy banao.", p("from", "Original path"), p("to", "Copy ka path ya folder")))
            f.put(fn("delete_file", "File / folder hatao (Siya_Trash mein chali jaati hai, wapas mil sakti hai). Pehle user se confirm karo.", p("path", "Hatane wala path")))
            f.put(fn("share_file", "Koi bhi file kisi bhi app (WhatsApp, Gmail, Telegram...) mein share karo. Share screen khulne ke baad read_screen + tap_on_screen se contact chuno aur Send dabao.", p("path", "File ka path"), p("app", "App ka naam (khaali = share menu)", false)))
            f.put(fn("share_text", "Koi text kisi app mein share karo.", p("text", "Share karne wala text"), p("app", "App ka naam (khaali = share menu)", false)))
        }
        f.put(fn("end_conversation", "Jab user bye, so jao, band karo, stop, ruko jaisa kuch bole to baatcheet khatam karo (pehle chhota sa alvida bolo)."))
        f.put(fn("remember_fact", "Koi zaroori baat hamesha ke liye yaad rakho (user ka naam, pasand, birthday, plan, etc).", p("fact", "Yaad rakhne wali baat")))
        f.put(fn("brightness", "Screen brightness badlo.", p("level", "up, down, max, min ya 0-100")))
        f.put(fn("system_toggle", "Wifi, bluetooth, hotspot, airplane, location, dnd ka panel kholo.", p("what", "wifi, bluetooth, hotspot, airplane, location, dnd, internet")))
        f.put(fn("expense_summary", "UPI / bank SMS se bana kharcha batao.", p("period", "today ya month", false)))
        f.put(fn("set_sos_contacts", "Emergency (SOS) contacts ke numbers save karo, comma se alag.", p("numbers", "Phone numbers")))
        f.put(fn("send_sos", "Emergency: contacts ko location bhejo aur recording shuru karo."))
        f.put(fn("game_tap", "Game / screen par ek jagah tap ya dabaye rakho. x,y PERCENT (0-100) mein.", p("x", "Left se percent"), p("y", "Upar se percent"), p("hold_ms", "kitni der dabana hai (default 50)", false)))
        f.put(fn("game_swipe", "Game mein swipe / drag (joystick, nishana ghumana). Percent coordinates.", p("x1", "start x"), p("y1", "start y"), p("x2", "end x"), p("y2", "end y"), p("ms", "kitni der mein (default 300)", false)))
        f.put(fn("macro_run", "Saved game macro turant chalao (jaise gloo wall, revive, heal, jump).", p("name", "Macro ka naam")))
        f.put(fn("macro_learn", "Naya macro sikho: user game ka button dabayega aur uski jagah save hogi.", p("name", "Macro ka naam")))
        f.put(fn("macro_list", "Saved game macros ki list."))
        f.put(fn("macro_delete", "Macro hatao.", p("name", "Macro ka naam")))
        f.put(fn("game_autoplay", "Game khud khelna shuru / band karo. Tum har frame dekhkar game_tap / game_swipe chalaoge.", p("state", "on ya off"), p("goal", "Kya karna hai (jaise: car chalao, obstacles se bacho)", false)))
        f.put(fn("hud", "Game ke upar chhota gaming HUD (timer, mic, macro buttons) dikhao ya hatao.", p("state", "show ya hide")))
        f.put(fn("hud_timer", "HUD ka zone countdown timer set karo (seconds).", p("seconds", "Seconds")))
        f.put(fn("person_note", "Kisi insaan ke baare mein note yaad rakho (jaise 'Ramesh ne 500 rupaye liye'). Uska call aane par alert aayega.", p("name", "Insaan ka naam"), p("note", "Note"), p("number", "Phone number (optional)", false)))
        f.put(fn("person_notes", "Kisi insaan ke baare mein saved notes batao.", p("name", "Naam")))
        f.put(fn("habit_summary", "User ki aadatein, mood, game time aur pending kaam ka saar."))
        f.put(fn("add_task", "Pending kaam list mein jodo.", p("text", "Kaam")))
        f.put(fn("list_tasks", "Pending kaam batao."))
        f.put(fn("done_task", "Kaam poora hua mark karo.", p("text", "Kaam ka naam")))
        f.put(fn("summarize_screen", "Screen par jo chal raha hai (YouTube video, lamba document, chat) uska 30 second ka summary."))
        f.put(fn("scan_bill", "Camera se bill / handwritten note padho aur total jodo.", p("source", "camera (default) ya screen", false)))
        f.put(fn("find_by_time", "Phone mein file / bill / document dhundo aur kholo.", p("query", "Kya (jaise bijli bill)"), p("when", "aaj, kal, is hafte, pichle hafte, is mahine, pichle mahine (khaali = kabhi bhi)", false), p("open", "true to khol do (default true)", false)))
        f.put(fn("find_photos_of", "Gallery mein kisi saved insaan ki photos dhundo aur kholo.", p("person", "Naam")))
        f.put(fn("ghost_mode", "App ko Calculator ki tarah chhupao ya wapas dikhao.", p("state", "on ya off"), p("code", "Secret ank code (optional)", false)))
        f.put(fn("block_number", "Spam number ko hamesha ke liye reject karo.", p("number", "Number ya uske aakhri ank")))
        // Gemini ek hi naam ke do tools par session shuru hi nahi karta: duplicate ho to pehla rakho
        val seen = HashSet<String>()
        val unique = JSONArray()
        for (i in 0 until f.length()) {
            val o = f.getJSONObject(i)
            if (seen.add(o.optString("name"))) unique.put(o)
            else android.util.Log.w("SIYA_TOOLS", "duplicate tool hata diya: ${o.optString("name")}")
        }
        return JSONArray().put(JSONObject().put("functionDeclarations", unique))
    }

    private fun showMap(ctx: Context, place: String, sat: Boolean): String {
        val prefs = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)
        val lat: Double; val lng: Double; val label: String
        if (place.isNotEmpty()) {
            val r = LocationHelper.search(ctx, place) ?: return "NOT_FOUND: '$place' jagah nahi mili"
            lat = r["lat"] as Double; lng = r["lng"] as Double; label = r["name"] as String
        } else if (prefs.getString("loc_mode", "device") == "custom" && prefs.contains("loc_lat")) {
            lat = prefs.getFloat("loc_lat", 0f).toDouble(); lng = prefs.getFloat("loc_lng", 0f).toDouble(); label = prefs.getString("loc_name", "").orEmpty()
        } else {
            val l = LocationHelper.device(ctx) ?: return "ERROR: location nahi mili (GPS / permission check karo)"
            lat = l.latitude; lng = l.longitude; label = "Aap yahan ho"
        }
        return if (MapWindow.show(ctx, lat, lng, label, sat)) "OK: map popup khul gaya: $label (${if (sat) "satellite" else "map"}). User ise khiska ya chhota-bada kar sakta hai."
        else "ERROR: map window nahi khuli (Display over other apps ON karo)"
    }

    fun execute(ctx: Context, name: String, a: JSONObject): String = try {
        when (name) {
            "open_app" -> PhoneController.openApp(ctx, a.optString("app_name"))
            "list_apps" -> PhoneController.appNames(ctx, 300)
            "call_contact" -> PhoneController.call(ctx, a.optString("name"))
            "whatsapp_message" -> PhoneController.whatsappMessage(ctx, a.optString("name"), a.optString("message"))
            "whatsapp_call" -> PhoneController.whatsappCall(ctx, a.optString("name"), a.optString("video").equals("true", true))
            "send_sms" -> PhoneController.sms(ctx, a.optString("name"), a.optString("message"))
            "youtube_play" -> PhoneController.youtubePlay(ctx, a.optString("query"))
            "spotify_play" -> PhoneController.spotifyPlay(ctx, a.optString("query"))
            "media_control" -> PhoneController.mediaKey(ctx, a.optString("action"))
            "open_url" -> PhoneController.openUrl(ctx, a.optString("url"))
            "generate_image_web" -> com.siya.ai.automation.BrowserAutomationEngine.start(ctx, a.optString("provider", "chatgpt"), a.optString("prompt"), a.optString("edit_image").equals("true", true))
            "post_story_status" -> SmartAccessibilityEngine.startStoryStatus(ctx, a.optString("platform", "whatsapp"), a.optString("music_query", "Diwali festive instrumental"), a.optString("caption"))
            "flashlight" -> PhoneController.flashlight(ctx, a.optString("state").equals("on", true))
            "volume" -> PhoneController.volume(ctx, a.optString("direction"))
            "read_screen" -> PhoneController.readScreen()
            "tap_on_screen" -> PhoneController.tap(a.optString("text"))
            "long_press" -> PhoneController.longPress(a.optString("text"))
            "scroll_screen" -> PhoneController.scroll(a.optString("direction"))
            "swipe_screen" -> PhoneController.swipe(a.optString("direction"))
            "type_text" -> PhoneController.typeText(a.optString("text"))
            "type_and_send" -> PhoneController.typeAndSend(a.optString("text"))
            "submit_text" -> PhoneController.submit()
            "look_camera" -> VisionTools.lookCamera(ctx, a.optString("camera", "back"), !a.optString("identify_people").equals("false", true))
            "look_screen" -> VisionTools.lookScreen(ctx, a.optString("identify_people").equals("true", true))
            "get_location" -> LocationHelper.describe(ctx)
            "show_on_map" -> {
                ctx.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW,
                    android.net.Uri.parse("geo:0,0?q=" + android.net.Uri.encode(a.optString("query"))))
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                "OK: maps mein khol diya"
            }
            "browser_search" -> AiBrowser.search(ctx, a.optString("query"), a.optString("mode", "popup"))
            "browser_open" -> AiBrowser.open(ctx, a.optString("url"), a.optString("mode", "popup"))
            "browser_read" -> AiBrowser.read(ctx)
            "browser_links" -> AiBrowser.links(ctx)
            "browser_click" -> AiBrowser.click(ctx, a.optString("text"))
            "browser_type" -> AiBrowser.type(ctx, a.optString("text"), a.optString("submit").equals("true", true))
            "browser_scroll" -> AiBrowser.scroll(ctx, a.optString("direction", "down"))
            "browser_back" -> AiBrowser.back(ctx)
            "browser_download" -> AiBrowser.download(ctx, a.optString("url"))
            "browser_close" -> AiBrowser.close(ctx)
            "browser_menu" -> AiBrowser.menuAction(ctx, a.optString("action"), a.optString("arg"))
            "browser_window" -> AiBrowser.windowControl(ctx, a.optString("action"))
            "set_location" -> if (a.optString("place").trim().equals("phone", true)) LocationHelper.useDevice(ctx) else LocationHelper.setCustom(ctx, a.optString("place"))
            "show_map" -> showMap(ctx, a.optString("place").trim(), !a.optString("satellite").equals("false", true))
            "close_map" -> { MapWindow.close(); "OK: map band" }
            "find_number_by_last_digits" -> CallFinder.run(ctx, a.optString("digits"))
            "now_playing" -> MediaTools.nowPlaying(ctx)
            "listen_around" -> SiyaSession.current?.listenAround(a.optString("seconds", "8").toIntOrNull() ?: 8) ?: "ERROR: live session chal nahi rahi"
            "list_files" -> FileTools.list(a.optString("path"))
            "find_files" -> FileTools.find(a.optString("query"), a.optString("path"))
            "read_file" -> FileTools.read(a.optString("path"))
            "write_file" -> FileTools.write(a.optString("path"), a.optString("content"), a.optString("mode", "overwrite"))
            "make_folder" -> FileTools.mkdir(a.optString("path"))
            "move_file" -> FileTools.move(a.optString("from"), a.optString("to"))
            "copy_file" -> FileTools.copy(a.optString("from"), a.optString("to"))
            "delete_file" -> FileTools.delete(a.optString("path"))
            "share_file" -> FileTools.share(ctx, a.optString("path"), a.optString("app"))
            "share_text" -> FileTools.shareText(ctx, a.optString("text"), a.optString("app"))
            "brightness" -> SystemControl.brightness(ctx, a.optString("level"))
            "system_toggle" -> SystemControl.toggle(ctx, a.optString("what"))
            "expense_summary" -> com.siya.ai.data.SmsLedger.summary(ctx, a.optString("period", "today"))
            "set_sos_contacts" -> com.siya.ai.security.SosManager.setContacts(ctx, a.optString("numbers"))
            "send_sos" -> com.siya.ai.security.SosManager.trigger(ctx)
            "game_tap" -> com.siya.ai.core.GameControl.tap(ctx, a.optString("x").toDoubleOrNull() ?: 50.0, a.optString("y").toDoubleOrNull() ?: 50.0, a.optString("hold_ms").toLongOrNull() ?: 50L)
            "game_swipe" -> com.siya.ai.core.GameControl.swipe(ctx, a.optString("x1").toDoubleOrNull() ?: 50.0, a.optString("y1").toDoubleOrNull() ?: 70.0, a.optString("x2").toDoubleOrNull() ?: 50.0, a.optString("y2").toDoubleOrNull() ?: 30.0, a.optString("ms").toLongOrNull() ?: 300L)
            "macro_run" -> com.siya.ai.core.GameControl.run(ctx, a.optString("name"))
            "macro_learn" -> com.siya.ai.core.GameControl.learn(ctx, a.optString("name"))
            "macro_list" -> com.siya.ai.core.GameControl.macroNames(ctx).joinToString().ifBlank { "Koi macro saved nahi" }
            "macro_delete" -> com.siya.ai.core.GameControl.delete(ctx, a.optString("name"))
            "game_autoplay" -> com.siya.ai.core.GameControl.autoplay(ctx, a.optString("state").equals("on", true), a.optString("goal", "game acche se khelo"))
            "hud" -> if (a.optString("state").equals("hide", true)) com.siya.ai.service.GameHud.hide() else com.siya.ai.service.GameHud.show(ctx)
            "hud_timer" -> { com.siya.ai.service.GameHud.setTimer(a.optString("seconds").toIntOrNull() ?: 120); "OK: timer set" }
            "person_note" -> com.siya.ai.data.PersonNotes.add(ctx, a.optString("name"), a.optString("note"), a.optString("number"))
            "person_notes" -> com.siya.ai.data.PersonNotes.get(ctx, a.optString("name"))
            "habit_summary" -> HabitTracker.summary(ctx)
            "add_task" -> HabitTracker.addTask(ctx, a.optString("text"))
            "list_tasks" -> HabitTracker.listTasks(ctx)
            "done_task" -> HabitTracker.doneTask(ctx, a.optString("text"))
            "summarize_screen" -> ScreenSummary.summarize(ctx)
            "scan_bill" -> BillScanner.scan(ctx, a.optString("source", "camera"))
            "find_by_time" -> FileFinder.find(ctx, a.optString("query"), a.optString("when"), !a.optString("open").equals("false", true))
            "find_photos_of" -> FileFinder.photosOf(ctx, a.optString("person"))
            "ghost_mode" -> GhostMode.set(ctx, a.optString("state").equals("on", true), a.optString("code").ifBlank { null })
            "block_number" -> { val pr = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE); pr.edit().putString("spam_numbers", (pr.getString("spam_numbers", "").orEmpty() + "," + a.optString("number").filter { it.isDigit() || it == '+' }).trim(',')).apply(); "OK: number block list mein" }
            "press_key" -> PhoneController.press(a.optString("key"))
            "take_screenshot" -> PhoneController.screenshot(ctx)
            "get_datetime" -> PhoneController.dateTime()
            "battery_level" -> PhoneController.battery(ctx)
            "search_memory" -> {
                val sem = com.siya.ai.memory.VectorMemory.search(ctx, a.optString("query"))
                if (sem.isNotBlank()) sem else {
                    val r = MemoryStore.search(ctx, a.optString("query"))
                    if (r.isEmpty()) "Memory mein kuch nahi mila" else r.joinToString("\n") { MemoryStore.format(it).take(300) }
                }
            }
            "remember_fact" -> if (MemoryStore.addFact(ctx, a.optString("fact"))) "OK: yaad kar liya" else "ERROR"
            else -> "ERROR: unknown tool $name"
        }
    } catch (e: Exception) { "ERROR: ${e.message}" }
}
