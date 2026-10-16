# Siya Ai

Flutter UI + Kotlin logic (Android).

## Structure
- `lib/` - Flutter UI: Home (open animation, orb, mic), Settings, **AI Data** (chat history / memory)
- `android/app/src/main/java/com/siya/ai/`
  - `service/SiyaService.kt` - background ghar: live session, "Hello Siya", floating orb, foreground notification
  - `core/SiyaSession.kt` - Gemini Live baatcheet (mic ek baar on, barge-in, auto-reconnect, memory save)
  - `ai/SiyaLiveClient.kt` - Gemini Live WebSocket (audio in/out, function-calling, transcription)
  - `core/PhoneController.kt` + `core/ToolRouter.kt` - phone control: app open (fuzzy/Hindi), call, WhatsApp, SMS, YouTube, screen read/tap/scroll/swipe/type/screenshot
  - `memory/MemoryStore.kt` - poori chat history + facts (date/time ke saath), phone mein hi save
  - `ui/main/MainActivity.kt` - Flutter host + MethodChannel `siya/engine` / EventChannel `siya/events`
  - `ui/main/AssistLauncherActivity.kt` - default assistant: app kholne ke bajay overlay mein Siya
  - `security/`, `ui/main/CallAssistantActivity.kt`, `service/CallMonitorService.kt` - purana logic (unchanged)

## Run
1. Flutter SDK (3.19+) install, `flutter doctor`
2. `flutter pub get`
3. `flutter run`  /  `flutter build apk --release`

## Pehli baar setup (Settings mein)
Gemini API Key -> Accessibility ON -> Display over other apps ON -> Background chalne do (battery) -> Default assistant = Siya.
Native-audio model badalna ho to prefs key `live_model` (default `gemini-2.5-flash-native-audio-preview-12-2025`).

## Naye changes (v1.1)
- Logo: sharp launcher icons (har density), adaptive foreground safe-zone, splash logo.
- Hologram mic: state ke hisaab se rang + alag effects (idle / listening / thinking / speaking), tap burst.
- Screen on: AI chalne tak (Settings > "Screen on rakho"), band hote hi normal timeout.
- Mic blink fix: app khula ho to "Hello Siya" mic chhod deta hai; "Hello Siya (hamesha on)" OFF ho to app hatane par mic bilkul band.
- Call detect default OFF (Settings se ON kar sakte ho).
- All files access: list / find / read / write / move / copy / delete (Siya_Trash) / share tools.
- Settings: Profile screen, Wallpaper (gallery + live video + upload), AI Browser (Google, popup / full), Location map (OpenStreetMap + search).
- AI Data > upar right "User Data": photo + naam, camera / screen se pehchan.
- ChatGPT / chat apps: type_and_send tool, look_camera / look_screen tools.
- `flutter pub get` zaroor chalao (video_player, flutter_map, latlong2 naye hain).
