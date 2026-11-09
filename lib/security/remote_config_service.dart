import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'remote_config_model.dart';

/// Realtime Database listener for Firebase "app_config" node.
///
/// Features:
/// 1. Real-time continuous SSE (Server-Sent Events) streaming directly from Firebase RTDB.
/// 2. Fast initial HTTP fetch on startup for sub-second cold start response.
/// 3. Zero-write policy & Strict Data Privacy: Only GET requests. No user info, device ID,
///    or telemetry ever collected or transmitted.
/// 4. Resilient network handling: Gracefully handles latency, offline mode, and auto-reconnects
///    with exponential backoff without crashing.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  static const String _defaultUrl =
      'https://siya-ai-d1ce7-default-rtdb.firebaseio.com/app_config.json';

  final ValueNotifier<AppRemoteConfig> configNotifier =
      ValueNotifier<AppRemoteConfig>(const AppRemoteConfig());

  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);

  AppRemoteConfig get currentConfig => configNotifier.value;

  HttpClient? _streamClient;
  bool _isDisposed = false;
  bool _isStarted = false;
  Timer? _reconnectTimer;
  int _retryAttempts = 0;

  /// Start real-time listening and initial config fetch.
  Future<void> init([String? url]) async {
    if (_isStarted) return;
    _isStarted = true;
    _isDisposed = false;

    final targetUrl = url ?? _defaultUrl;

    // Fast initial fetch for immediate UI decision
    await fetchOnce(targetUrl);

    // Launch continuous background real-time SSE listener
    _connectRealtimeStream(targetUrl);
  }

  /// Perform a single HTTP GET to fetch latest config immediately.
  Future<AppRemoteConfig> fetchOnce([String? url]) async {
    final targetUrl = url ?? _defaultUrl;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(targetUrl));
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
            _retryAttempts = 0;
            return newConfig;
          }
        }
      }
    } catch (_) {
      // Offline or network latency - preserve current/default state gracefully
    } finally {
      client?.close(force: true);
    }
    return configNotifier.value;
  }

  /// Establishes continuous SSE connection to Firebase Realtime Database.
  void _connectRealtimeStream(String targetUrl) async {
    if (_isDisposed) return;

    _streamClient?.close(force: true);
    _streamClient = HttpClient()..connectionTimeout = const Duration(seconds: 15);

    try {
      final request = await _streamClient!.getUrl(Uri.parse(targetUrl));
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

      final response = await request.close();

      if (response.statusCode == 200) {
        isConnectedNotifier.value = true;
        _retryAttempts = 0;

        String currentEvent = 'put';
        final dataBuffer = StringBuffer();

        await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())) {
          if (_isDisposed) break;

          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            // End of event frame
            if (dataBuffer.isNotEmpty) {
              _processSseEvent(currentEvent, dataBuffer.toString());
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
      // Stream dropped or network error
    } finally {
      isConnectedNotifier.value = false;
      _scheduleReconnect(targetUrl);
    }
  }

  void _processSseEvent(String event, String rawData) {
    if (event == 'keep-alive' || rawData.trim() == 'null' || rawData.trim().isEmpty) {
      return;
    }

    try {
      final dynamic decoded = jsonDecode(rawData);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      // Check if it's a Firebase SSE payload with "path" and "data"
      if (decoded.containsKey('path')) {
        final path = (decoded['path'] as String? ?? '').trim();
        final payload = decoded['data'];

        if (path == '/' || path.isEmpty) {
          if (payload is Map<String, dynamic>) {
            if (event == 'put') {
              configNotifier.value = AppRemoteConfig.fromJson(payload);
            } else if (event == 'patch') {
              _applyPartialPatch(payload);
            }
          }
        } else {
          // Sub-path like "/is_locked", "/lock_message", etc.
          final cleanKey = path.startsWith('/') ? path.substring(1) : path;
          _applySingleKey(cleanKey, payload);
        }
      } else {
        // Direct root json map
        configNotifier.value = AppRemoteConfig.fromJson(decoded);
      }
    } catch (_) {
      // Malformed json ignored safely
    }
  }

  void _applyPartialPatch(Map<String, dynamic> patch) {
    final current = configNotifier.value;
    final merged = Map<String, dynamic>.from(current.toJson());
    patch.forEach((k, v) {
      merged[k] = v;
    });
    configNotifier.value = AppRemoteConfig.fromJson(merged);
  }

  void _applySingleKey(String key, dynamic value) {
    final current = configNotifier.value;
    switch (key) {
      case 'is_locked':
        final isLocked = value == true || value == 'true' || value == 1;
        configNotifier.value = current.copyWith(isLocked: isLocked);
        break;
      case 'lock_message':
        configNotifier.value = current.copyWith(lockMessage: value?.toString());
        break;
      case 'latest_version_code':
        final code = value is num ? value.toInt() : (int.tryParse(value.toString()) ?? current.latestVersionCode);
        configNotifier.value = current.copyWith(latestVersionCode: code);
        break;
      case 'force_update':
        final force = value == true || value == 'true' || value == 1;
        configNotifier.value = current.copyWith(forceUpdate: force);
        break;
      case 'update_url':
        configNotifier.value = current.copyWith(updateUrl: value?.toString());
        break;
    }
  }

  void _scheduleReconnect(String targetUrl) {
    if (_isDisposed) return;
    _reconnectTimer?.cancel();

    // Exponential backoff with ceiling (2s, 4s, 8s, up to 30s)
    _retryAttempts++;
    final delaySeconds = (_retryAttempts * 2).clamp(2, 30);

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isDisposed) {
        _connectRealtimeStream(targetUrl);
      }
    });
  }

  void dispose() {
    _isDisposed = true;
    _isStarted = false;
    _reconnectTimer?.cancel();
    _streamClient?.close(force: true);
  }
}
