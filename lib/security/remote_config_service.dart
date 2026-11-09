import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'remote_config_model.dart';

/// Realtime Database Remote Config & Device Registration Service.
///
/// Features:
/// 1. Global config real-time listener ("app_config").
/// 2. Unique Device registration & real-time specific device listener ("devices/{device_id}").
///    - Preserves admin-set flags (is_locked, is_premium, ban_reason) on re-registration/heartbeat.
///    - Only updates device metadata (last_active, app_version_code, etc.).
/// 3. Resilient network handling: Gracefully handles offline mode and auto-reconnects.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  static const String _baseUrl = 'https://siya-ai-d1ce7-default-rtdb.firebaseio.com';
  static const String _appConfigUrl = '$_baseUrl/app_config.json';

  final ValueNotifier<AppRemoteConfig> configNotifier =
      ValueNotifier<AppRemoteConfig>(const AppRemoteConfig());

  final ValueNotifier<DeviceRemoteConfig> deviceConfigNotifier =
      ValueNotifier<DeviceRemoteConfig>(const DeviceRemoteConfig());

  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);

  AppRemoteConfig get currentConfig => configNotifier.value;
  DeviceRemoteConfig get currentDeviceConfig => deviceConfigNotifier.value;

  HttpClient? _globalStreamClient;
  HttpClient? _deviceStreamClient;
  bool _isDisposed = false;
  bool _isStarted = false;
  Timer? _globalReconnectTimer;
  Timer? _deviceReconnectTimer;
  Timer? _heartbeatTimer;
  int _globalRetryCount = 0;
  int _deviceRetryCount = 0;

  Map<String, dynamic> _deviceInfo = {};

  /// Initialize real-time listening and device registration.
  Future<void> init(Map<String, dynamic> deviceInfo) async {
    if (_isStarted) {
      if (deviceInfo.isNotEmpty && _deviceInfo.isEmpty) {
        _deviceInfo = deviceInfo;
        await _registerAndListenDevice();
      }
      return;
    }
    _isStarted = true;
    _isDisposed = false;
    _deviceInfo = deviceInfo;

    // 1. Fetch & stream global config
    await fetchGlobalConfig();
    _connectGlobalRealtimeStream();

    // 2. Register & stream device-specific node
    if (_deviceInfo.isNotEmpty) {
      await _registerAndListenDevice();
    }
  }

  /// Initial HTTP GET for global app_config
  Future<AppRemoteConfig> fetchGlobalConfig() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(_appConfigUrl));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        if (body.trim().isNotEmpty && body.trim() != 'null') {
          final dynamic decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            final newConfig = AppRemoteConfig.fromJson(decoded);
            configNotifier.value = newConfig;
            isConnectedNotifier.value = true;
            _globalRetryCount = 0;
            return newConfig;
          }
        }
      }
    } catch (_) {
      // Offline fallback
    } finally {
      client?.close(force: true);
    }
    return configNotifier.value;
  }

  /// Establishes continuous SSE connection to Firebase for app_config.
  void _connectGlobalRealtimeStream() async {
    if (_isDisposed) return;

    _globalStreamClient?.close(force: true);
    _globalStreamClient = HttpClient()..connectionTimeout = const Duration(seconds: 15);

    try {
      final request = await _globalStreamClient!.getUrl(Uri.parse(_appConfigUrl));
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

      final response = await request.close();

      if (response.statusCode == 200) {
        isConnectedNotifier.value = true;
        _globalRetryCount = 0;

        String currentEvent = 'put';
        final dataBuffer = StringBuffer();

        await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())) {
          if (_isDisposed) break;

          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            if (dataBuffer.isNotEmpty) {
              _processGlobalSseEvent(currentEvent, dataBuffer.toString());
              dataBuffer.clear();
            }
            currentEvent = 'put';
          } else if (trimmed.startsWith('event:')) {
            currentEvent = trimmed.substring(6).trim();
          } else if (trimmed.startsWith('data:')) {
            final dataPart = trimmed.substring(5).trim();
            if (dataBuffer.isNotEmpty) {
              dataBuffer.write('\n');
            }
            dataBuffer.write(dataPart);
          }
        }
      }
    } catch (_) {
      // Disconnection
    } finally {
      _scheduleGlobalReconnect();
    }
  }

  void _processGlobalSseEvent(String event, String rawData) {
    if (event == 'keep-alive' || rawData.trim() == 'null' || rawData.trim().isEmpty) {
      return;
    }

    try {
      final dynamic decoded = jsonDecode(rawData);
      if (decoded is! Map<String, dynamic>) return;

      if (decoded.containsKey('path')) {
        final path = (decoded['path'] as String? ?? '').trim();
        final payload = decoded['data'];

        if (path == '/' || path.isEmpty) {
          if (payload is Map<String, dynamic>) {
            if (event == 'put') {
              configNotifier.value = AppRemoteConfig.fromJson(payload);
            } else if (event == 'patch') {
              final merged = Map<String, dynamic>.from(configNotifier.value.toJson());
              payload.forEach((k, v) => merged[k] = v);
              configNotifier.value = AppRemoteConfig.fromJson(merged);
            }
          }
        } else {
          final cleanKey = path.startsWith('/') ? path.substring(1) : path;
          final current = configNotifier.value;
          switch (cleanKey) {
            case 'is_locked':
              configNotifier.value = current.copyWith(isLocked: payload == true || payload == 'true');
              break;
            case 'lock_message':
              configNotifier.value = current.copyWith(lockMessage: payload?.toString());
              break;
            case 'latest_version_code':
              final v = payload is num ? payload.toInt() : (int.tryParse(payload.toString()) ?? current.latestVersionCode);
              configNotifier.value = current.copyWith(latestVersionCode: v);
              break;
            case 'force_update':
              configNotifier.value = current.copyWith(forceUpdate: payload == true || payload == 'true');
              break;
            case 'update_url':
              configNotifier.value = current.copyWith(updateUrl: payload?.toString());
              break;
          }
        }
      } else {
        configNotifier.value = AppRemoteConfig.fromJson(decoded);
      }
    } catch (_) {}
  }

  void _scheduleGlobalReconnect() {
    if (_isDisposed) return;
    _globalReconnectTimer?.cancel();
    _globalRetryCount++;
    final delaySeconds = (_globalRetryCount * 2).clamp(2, 30);
    _globalReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isDisposed) _connectGlobalRealtimeStream();
    });
  }

  // ── DEVICE REGISTRATION & STREAMING ────────────────────────────

  String get _currentDeviceId => (_deviceInfo['device_id'] ?? '').toString().trim();

  String get _deviceUrl => '$_baseUrl/devices/$_currentDeviceId.json';

  Future<void> _registerAndListenDevice() async {
    final devId = _currentDeviceId;
    if (devId.isEmpty) return;

    // 1. Fetch current device state to avoid overwriting admin status
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(_deviceUrl));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 8));

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        if (body.trim().isNotEmpty && body.trim() != 'null') {
          // Device exists in database! Read admin flags and PATCH ONLY metadata
          final dynamic existingData = jsonDecode(body);
          if (existingData is Map<String, dynamic>) {
            deviceConfigNotifier.value = DeviceRemoteConfig.fromJson(existingData);

            // Metadata update only (preserves is_locked, is_premium, ban_reason)
            await _patchDeviceMetadata({
              'device_id': devId,
              'device_name': _deviceInfo['device_name'] ?? '',
              'device_model': _deviceInfo['device_model'] ?? '',
              'brand': _deviceInfo['brand'] ?? '',
              'model': _deviceInfo['model'] ?? '',
              'android_version': _deviceInfo['android_version'] ?? '',
              'build_display': _deviceInfo['build_display'] ?? '',
              'app_version_code': _deviceInfo['app_version_code'] ?? 1,
              'last_active': nowMs,
            });
          }
        } else {
          // First time registration: Write initial defaults
          final initial = {
            'device_id': devId,
            'device_name': _deviceInfo['device_name'] ?? '',
            'device_model': _deviceInfo['device_model'] ?? '',
            'brand': _deviceInfo['brand'] ?? '',
            'model': _deviceInfo['model'] ?? '',
            'android_version': _deviceInfo['android_version'] ?? '',
            'build_display': _deviceInfo['build_display'] ?? '',
            'app_version_code': _deviceInfo['app_version_code'] ?? 1,
            'last_active': nowMs,
            'is_locked': false,
            'is_premium': false,
            'ban_reason': '',
          };
          await _putDevice(initial);
          deviceConfigNotifier.value = DeviceRemoteConfig.fromJson(initial);
        }
      }
    } catch (_) {
      // Offline fallback
    } finally {
      client?.close(force: true);
    }

    // 2. Start continuous SSE stream for this specific device
    _connectDeviceRealtimeStream();

    // 3. Heartbeat periodic ping (every 5 minutes)
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _patchDeviceMetadata({'last_active': DateTime.now().millisecondsSinceEpoch});
    });
  }

  Future<void> _patchDeviceMetadata(Map<String, dynamic> metadata) async {
    if (_currentDeviceId.isEmpty) return;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.patchUrl(Uri.parse(_deviceUrl));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode(jsonEncode(metadata)));
      final res = await req.close();
      await res.drain();
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> _putDevice(Map<String, dynamic> data) async {
    if (_currentDeviceId.isEmpty) return;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.putUrl(Uri.parse(_deviceUrl));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode(jsonEncode(data)));
      final res = await req.close();
      await res.drain();
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  /// Continuous real-time SSE stream for devices/{device_id}.json
  void _connectDeviceRealtimeStream() async {
    if (_isDisposed || _currentDeviceId.isEmpty) return;

    _deviceStreamClient?.close(force: true);
    _deviceStreamClient = HttpClient()..connectionTimeout = const Duration(seconds: 15);

    try {
      final req = await _deviceStreamClient!.getUrl(Uri.parse(_deviceUrl));
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      req.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

      final res = await req.close();
      if (res.statusCode == 200) {
        _deviceRetryCount = 0;
        String currentEvent = 'put';
        final dataBuffer = StringBuffer();

        await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
          if (_isDisposed) break;

          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            if (dataBuffer.isNotEmpty) {
              _processDeviceSseEvent(currentEvent, dataBuffer.toString());
              dataBuffer.clear();
            }
            currentEvent = 'put';
          } else if (trimmed.startsWith('event:')) {
            currentEvent = trimmed.substring(6).trim();
          } else if (trimmed.startsWith('data:')) {
            final dataPart = trimmed.substring(5).trim();
            if (dataBuffer.isNotEmpty) {
              dataBuffer.write('\n');
            }
            dataBuffer.write(dataPart);
          }
        }
      }
    } catch (_) {
    } finally {
      _scheduleDeviceReconnect();
    }
  }

  void _processDeviceSseEvent(String event, String rawData) {
    if (event == 'keep-alive' || rawData.trim() == 'null' || rawData.trim().isEmpty) {
      return;
    }

    try {
      final dynamic decoded = jsonDecode(rawData);
      if (decoded is! Map<String, dynamic>) return;

      if (decoded.containsKey('path')) {
        final path = (decoded['path'] as String? ?? '').trim();
        final payload = decoded['data'];

        if (path == '/' || path.isEmpty) {
          if (payload is Map<String, dynamic>) {
            if (event == 'put') {
              deviceConfigNotifier.value = DeviceRemoteConfig.fromJson(payload);
            } else if (event == 'patch') {
              final merged = Map<String, dynamic>.from(deviceConfigNotifier.value.toJson());
              payload.forEach((k, v) => merged[k] = v);
              deviceConfigNotifier.value = DeviceRemoteConfig.fromJson(merged);
            }
          }
        } else {
          final cleanKey = path.startsWith('/') ? path.substring(1) : path;
          final current = deviceConfigNotifier.value;
          switch (cleanKey) {
            case 'is_locked':
              deviceConfigNotifier.value = current.copyWith(isLocked: payload == true || payload == 'true');
              break;
            case 'is_premium':
              deviceConfigNotifier.value = current.copyWith(isPremium: payload == true || payload == 'true');
              break;
            case 'ban_reason':
              deviceConfigNotifier.value = current.copyWith(banReason: payload?.toString());
              break;
          }
        }
      } else {
        deviceConfigNotifier.value = DeviceRemoteConfig.fromJson(decoded);
      }
    } catch (_) {}
  }

  void _scheduleDeviceReconnect() {
    if (_isDisposed) return;
    _deviceReconnectTimer?.cancel();
    _deviceRetryCount++;
    final delaySeconds = (_deviceRetryCount * 2).clamp(2, 30);
    _deviceReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isDisposed) _connectDeviceRealtimeStream();
    });
  }

  void dispose() {
    _isDisposed = true;
    _isStarted = false;
    _globalReconnectTimer?.cancel();
    _deviceReconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _globalStreamClient?.close(force: true);
    _deviceStreamClient?.close(force: true);
  }
}
