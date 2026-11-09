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

  @override
  String toString() =>
      'AppRemoteConfig(isLocked: $isLocked, lockMessage: "$lockMessage", latestVersionCode: $latestVersionCode, forceUpdate: $forceUpdate, updateUrl: "$updateUrl")';
}
