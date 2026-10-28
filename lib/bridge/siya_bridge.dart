import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter <-> Kotlin bridge.
/// Saara logic Kotlin (SiyaService, SiyaSession, PhoneController, MemoryStore) mein hai;
/// yahan sirf channel calls aur events hain.
class SiyaBridge extends ChangeNotifier {
  static const MethodChannel _method = MethodChannel('siya/engine');
  static const EventChannel _events = EventChannel('siya/events');

  /// idle | listening | processing | speaking | waiting
  String state = 'idle';
  String status = '';
  bool micMuted = false;
  final ValueNotifier<double> amp = ValueNotifier<double>(0);
  final ValueNotifier<String> transcript = ValueNotifier<String>('');

  /// Native se aayi error ka code (no_key, no_mic, connection...). UI dikhane ke baad null kar deta hai.
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  StreamSubscription<dynamic>? _sub;
  bool _initStarted = false;

  bool get isActive => state != 'idle';

  /// Events sunna turant shuru (halka). Baaki init background mein.
  void listen() {
    _sub ??= _events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
  }

  Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    listen();
    try {
      await _method.invokeMethod<bool>('init');
    } on PlatformException {
      // ignore
    }
  }

  void _onEvent(dynamic e) {
    if (e is! Map) return;
    switch (e['type']) {
      case 'state':
        state = (e['state'] as String?) ?? 'idle';
        if (state == 'idle') amp.value = 0;
        notifyListeners();
        break;
      case 'micMuted':
        micMuted = (e['muted'] as bool?) ?? false;
        notifyListeners();
        break;
      case 'status':
        status = (e['text'] as String?) ?? '';
        notifyListeners();
        break;
      case 'transcript':
        transcript.value = (e['text'] as String?) ?? '';
        notifyListeners();
        break;
      case 'amp':
        amp.value = ((e['v'] as num?) ?? 0).toDouble().clamp(0.0, 1.0);
        break;
      case 'error':
        error.value = e['code'] as String?;
        break;
    }
  }

  Future<void> toggleMic() async {
    try {
      await _method.invokeMethod<void>('toggleMic');
    } on PlatformException {
      // ignore
    }
  }

  Future<void> toggleMicMute() async {
    try {
      await _method.invokeMethod<void>('toggleMicMute');
    } on PlatformException {
      // Native session remains authoritative.
    }
  }

  Future<void> minimizeApp() async {
    try {
      await _method.invokeMethod<void>('minimizeApp');
    } on PlatformException {
      // Overlay mode is Android-only.
    }
  }

  Future<bool> consumeFirstRun() async =>
      (await _method.invokeMethod<bool>('consumeFirstRun')) ?? false;

  // ── Settings ──────────────────────────────────────────────
  Future<Map<String, dynamic>> getSettings() async =>
      (await _method.invokeMapMethod<String, dynamic>('getSettings')) ?? {};

  Future<void> saveSettings(Map<String, dynamic> s) =>
      _method.invokeMethod<void>('saveSettings', s);

  Future<Map<String, dynamic>> getStatus() async =>
      (await _method.invokeMapMethod<String, dynamic>('getStatus')) ?? {};

  Future<int> requestPermissions() async =>
      (await _method.invokeMethod<int>('requestPermissions')) ?? 0;

  Future<Map<String, String>?> pickContact() async =>
      _method.invokeMapMethod<String, String>('pickContact');

  Future<void> openAccessibility() => _method.invokeMethod<void>('openAccessibility');
  Future<void> openOverlaySettings() => _method.invokeMethod<void>('openOverlaySettings');
  Future<void> requestBatteryExemption() => _method.invokeMethod<void>('requestBatteryExemption');
  Future<void> toggleAdmin() => _method.invokeMethod<void>('toggleAdmin');
  Future<void> openSecurity() => _method.invokeMethod<void>('openSecurity');
  Future<void> setDefaultAssistant() => _method.invokeMethod<void>('setDefaultAssistant');

  // ── New: files, gallery, wallpaper, people, location, browser ──
  Future<void> openAllFilesSettings() => _method.invokeMethod<void>('openAllFilesSettings');

  /// Gallery se ek photo/video chuno; app ke andar copy hua path milta hai (cancel = null).
  Future<String?> pickMedia(String kind) =>
      _method.invokeMethod<String>('pickMedia', {'kind': kind});

  Future<List<MediaItem>> listMedia(String kind) async {
    final r = await _method.invokeListMethod<dynamic>('listMedia', {'kind': kind}) ?? const [];
    return r.map((e) => MediaItem.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Uint8List?> mediaThumb(String uri, String kind, {int size = 256}) =>
      _method.invokeMethod<Uint8List>('mediaThumb', {'uri': uri, 'kind': kind, 'size': size});

  Future<String?> setWallpaper({String? uri, String? path, required String kind}) =>
      _method.invokeMethod<String>('setWallpaper', {'uri': uri, 'path': path, 'kind': kind});

  Future<void> clearWallpaper() => _method.invokeMethod<void>('clearWallpaper');

  Future<List<Person>> getPeople() async {
    final r = await _method.invokeListMethod<dynamic>('getPeople') ?? const [];
    return r.map((e) => Person.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Person?> savePerson({String? id, required String name, required String relation, String? photo}) async {
    final r = await _method.invokeMapMethod<String, dynamic>(
        'savePerson', {'id': id, 'name': name, 'relation': relation, 'photo': photo});
    return r == null ? null : Person.fromMap(r);
  }

  Future<void> deletePerson(String id) => _method.invokeMethod<void>('deletePerson', {'id': id});

  /// Phone ki GPS location: {lat, lng, name} ya null.
  Future<Map<String, dynamic>?> getLocation() =>
      _method.invokeMapMethod<String, dynamic>('getLocation');

  /// Jagah ka naam -> {lat, lng, name} (null = nahi mili).
  Future<Map<String, dynamic>?> searchPlace(String q) =>
      _method.invokeMapMethod<String, dynamic>('searchPlace', {'q': q});

  // ── face search (gallery mein insaan ki photos) ──
  Future<void> faceSearchStart(String id, {int limit = 300}) =>
      _method.invokeMethod<void>('faceSearchStart', {'id': id, 'limit': limit});

  Future<FaceSearchStatus> faceSearchStatus(String id) async {
    final m = await _method.invokeMapMethod<String, dynamic>('faceSearchStatus', {'id': id}) ?? const {};
    final list = (m['matches'] as List?) ?? const [];
    return FaceSearchStatus(
      running: (m['running'] as bool?) ?? false,
      done: (m['done'] as int?) ?? 0,
      total: (m['total'] as int?) ?? 0,
      error: (m['error'] as String?) ?? '',
      matches: list.map((e) => MediaItem.fromMap({...Map<String, dynamic>.from(e as Map), 'kind': 'image'})).toList(),
    );
  }

  Future<void> faceSearchCancel() => _method.invokeMethod<void>('faceSearchCancel');

  Future<Uint8List?> mediaFull(String uri) => _method.invokeMethod<Uint8List>('mediaFull', {'uri': uri});

  Future<void> openNotificationAccess() => _method.invokeMethod<void>('openNotificationAccess');

  Future<bool> openBrowser([String? url]) async =>
      (await _method.invokeMethod<bool>('openBrowser', url != null ? {'url': url} : null)) ?? false;

  Future<Map<String, dynamic>> getSmsLedger() async =>
      (await _method.invokeMapMethod<String, dynamic>('getSmsLedger')) ?? {};

  Future<List<Map<String, dynamic>>> getCallLogs() async {
    final list = await _method.invokeListMethod<dynamic>('getCallLogs') ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> requestCallScreening() => _method.invokeMethod<void>('requestCallScreening');

  // ── AI Data / Memory ──────────────────────────────────────
  Future<MemoryData> getMemory() async {
    final r = await _method.invokeMapMethod<String, dynamic>('getMemory');
    if (r == null) return const MemoryData([], [], 0);
    final msgs = ((r['messages'] as List?) ?? const [])
        .map((e) => MemoryMsg.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final facts = ((r['facts'] as List?) ?? const []).map((e) => e.toString()).toList();
    return MemoryData(msgs, facts, (r['total'] as int?) ?? msgs.length);
  }

  Future<void> clearMemory() => _method.invokeMethod<void>('clearMemory');
  Future<void> copyMemory() => _method.invokeMethod<void>('copyMemory');

  @override
  void dispose() {
    _sub?.cancel();
    amp.dispose();
    transcript.dispose();
    error.dispose();
    super.dispose();
  }
}

class MemoryMsg {
  MemoryMsg({required this.time, required this.role, required this.text, required this.day, required this.clock});

  factory MemoryMsg.fromMap(Map<String, dynamic> m) => MemoryMsg(
        time: (m['time'] as num?)?.toInt() ?? 0,
        role: (m['role'] as String?) ?? 'user',
        text: (m['text'] as String?) ?? '',
        day: (m['day'] as String?) ?? '',
        clock: (m['clock'] as String?) ?? '',
      );

  final int time;
  final String role;
  final String text;
  final String day;
  final String clock;

  bool get isUser => role == 'user';
}

class MemoryData {
  const MemoryData(this.messages, this.facts, this.total);
  final List<MemoryMsg> messages;
  final List<String> facts;
  final int total;
}

class MediaItem {
  MediaItem({required this.uri, required this.name, required this.kind});

  factory MediaItem.fromMap(Map<String, dynamic> m) => MediaItem(
        uri: (m['uri'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        kind: (m['kind'] as String?) ?? 'image',
      );

  final String uri;
  final String name;
  final String kind;
}

class Person {
  Person({required this.id, required this.name, required this.relation, required this.photo});

  factory Person.fromMap(Map<String, dynamic> m) => Person(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        relation: (m['relation'] as String?) ?? 'family',
        photo: (m['photo'] as String?) ?? '',
      );

  final String id;
  final String name;
  final String relation;
  final String photo;
}

class FaceSearchStatus {
  FaceSearchStatus({required this.running, required this.done, required this.total, required this.error, required this.matches});

  final bool running;
  final int done;
  final int total;
  final String error;
  final List<MediaItem> matches;
}
