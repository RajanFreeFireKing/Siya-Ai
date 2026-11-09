class AppRemoteConfig {
  final bool isLocked;
  final String lockMessage;
  final int latestVersionCode;
  final bool forceUpdate;
  final String updateUrl;

  const AppRemoteConfig({
    this.isLocked = false,
    this.lockMessage = 'Maintenance chal raha hai. Kripya baad mein koshish karein.',
    this.latestVersionCode = 1,
    this.forceUpdate = false,
    this.updateUrl = '',
  });

  factory AppRemoteConfig.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic value, bool fallback) {
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final lower = value.trim().toLowerCase();
        if (lower == 'true' || lower == '1') return true;
        if (lower == 'false' || lower == '0') return false;
      }
      return fallback;
    }

    int parseInt(dynamic value, int fallback) {
      if (value == null) return fallback;
      if (value is num) return value.toInt();
      if (value is String) {
        return int.tryParse(value.trim()) ?? fallback;
      }
      return fallback;
    }

    return AppRemoteConfig(
      isLocked: parseBool(json['is_locked'], false),
      lockMessage: (json['lock_message'] ?? 'Maintenance chal raha hai. Kripya baad mein koshish karein.').toString(),
      latestVersionCode: parseInt(json['latest_version_code'], 1),
      forceUpdate: parseBool(json['force_update'], false),
      updateUrl: (json['update_url'] ?? '').toString().trim(),
    );
  }

  AppRemoteConfig copyWith({
    bool? isLocked,
    String? lockMessage,
    int? latestVersionCode,
    bool? forceUpdate,
    String? updateUrl,
  }) {
    return AppRemoteConfig(
      isLocked: isLocked ?? this.isLocked,
      lockMessage: lockMessage ?? this.lockMessage,
      latestVersionCode: latestVersionCode ?? this.latestVersionCode,
      forceUpdate: forceUpdate ?? this.forceUpdate,
      updateUrl: updateUrl ?? this.updateUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'is_locked': isLocked,
    'lock_message': lockMessage,
    'latest_version_code': latestVersionCode,
    'force_update': forceUpdate,
    'update_url': updateUrl,
  };
}

class DeviceRemoteConfig {
  final String deviceId;
  final String deviceName;
  final String deviceModel;
  final String brand;
  final String model;
  final String androidVersion;
  final String buildDisplay;
  final int appVersionCode;
  final dynamic lastActive;
  final bool isLocked;
  final bool isPremium;
  final String banReason;

  const DeviceRemoteConfig({
    this.deviceId = '',
    this.deviceName = '',
    this.deviceModel = '',
    this.brand = '',
    this.model = '',
    this.androidVersion = '',
    this.buildDisplay = '',
    this.appVersionCode = 1,
    this.lastActive,
    this.isLocked = false,
    this.isPremium = false,
    this.banReason = '',
  });

  factory DeviceRemoteConfig.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic value, bool fallback) {
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final lower = value.trim().toLowerCase();
        if (lower == 'true' || lower == '1') return true;
        if (lower == 'false' || lower == '0') return false;
      }
      return fallback;
    }

    int parseInt(dynamic value, int fallback) {
      if (value == null) return fallback;
      if (value is num) return value.toInt();
      if (value is String) {
        return int.tryParse(value.trim()) ?? fallback;
      }
      return fallback;
    }

    return DeviceRemoteConfig(
      deviceId: (json['device_id'] ?? '').toString(),
      deviceName: (json['device_name'] ?? '').toString(),
      deviceModel: (json['device_model'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      androidVersion: (json['android_version'] ?? '').toString(),
      buildDisplay: (json['build_display'] ?? '').toString(),
      appVersionCode: parseInt(json['app_version_code'], 1),
      lastActive: json['last_active'],
      isLocked: parseBool(json['is_locked'], false),
      isPremium: parseBool(json['is_premium'], false),
      banReason: (json['ban_reason'] ?? '').toString().trim(),
    );
  }

  DeviceRemoteConfig copyWith({
    String? deviceId,
    String? deviceName,
    String? deviceModel,
    String? brand,
    String? model,
    String? androidVersion,
    String? buildDisplay,
    int? appVersionCode,
    dynamic lastActive,
    bool? isLocked,
    bool? isPremium,
    String? banReason,
  }) {
    return DeviceRemoteConfig(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceModel: deviceModel ?? this.deviceModel,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      androidVersion: androidVersion ?? this.androidVersion,
      buildDisplay: buildDisplay ?? this.buildDisplay,
      appVersionCode: appVersionCode ?? this.appVersionCode,
      lastActive: lastActive ?? this.lastActive,
      isLocked: isLocked ?? this.isLocked,
      isPremium: isPremium ?? this.isPremium,
      banReason: banReason ?? this.banReason,
    );
  }

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'device_name': deviceName,
    'device_model': deviceModel,
    'brand': brand,
    'model': model,
    'android_version': androidVersion,
    'build_display': buildDisplay,
    'app_version_code': appVersionCode,
    'last_active': lastActive,
    'is_locked': isLocked,
    'is_premium': isPremium,
    'ban_reason': banReason,
  };
}
