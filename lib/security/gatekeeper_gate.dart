import 'package:flutter/material.dart';
import '../bridge/siya_bridge.dart';
import 'device_ban_view.dart';
import 'force_update_view.dart';
import 'remote_config_model.dart';
import 'remote_config_service.dart';
import 'remote_lock_view.dart';

/// GatekeeperGate wraps the entry point / screens.
///
/// Implements Dual-Tier Enforcement:
/// 1. Check A: Global Lock ("app_config/is_locked") -> RemoteLockView
/// 2. Check B: Specific Device Lock ("devices/{device_id}/is_locked") -> DeviceBanView
/// 3. In-App Force Updater ("app_config/force_update" & latest > installed) -> ForceUpdateView
/// 4. Normal flow granted only when neither condition is active.
class GatekeeperGate extends StatefulWidget {
  final Widget child;
  final SiyaBridge bridge;

  const GatekeeperGate({
    super.key,
    required this.child,
    required this.bridge,
  });

  @override
  State<GatekeeperGate> createState() => _GatekeeperGateState();
}

class _GatekeeperGateState extends State<GatekeeperGate> {
  int _currentVersionCode = 1;

  @override
  void initState() {
    super.initState();
    _loadDeviceAndInit();
  }

  void _loadDeviceAndInit() async {
    final devInfo = await widget.bridge.getDeviceInfo();
    final vCode = (devInfo['app_version_code'] as num?)?.toInt() ??
        await widget.bridge.getAppVersionCode();

    if (mounted) {
      setState(() {
        _currentVersionCode = vCode;
      });
    }

    // Initialize real-time continuous listener for both app_config and devices/{device_id}
    RemoteConfigService.instance.init(devInfo);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppRemoteConfig>(
      valueListenable: RemoteConfigService.instance.configNotifier,
      builder: (context, globalConfig, _) {
        return ValueListenableBuilder<DeviceRemoteConfig>(
          valueListenable: RemoteConfigService.instance.deviceConfigNotifier,
          builder: (context, deviceConfig, _) {
            // Tier 1: Global Lock (Affects ALL users)
            if (globalConfig.isLocked) {
              return RemoteLockView(config: globalConfig);
            }

            // Tier 2: Specific Device Lock (Affects ONLY this device)
            if (deviceConfig.isLocked) {
              return DeviceBanView(deviceConfig: deviceConfig);
            }

            // Tier 3: In-App Dynamic Force Updater
            if (globalConfig.forceUpdate && globalConfig.latestVersionCode > _currentVersionCode) {
              return ForceUpdateView(
                config: globalConfig,
                currentVersionCode: _currentVersionCode,
                bridge: widget.bridge,
              );
            }

            // Tier 4: Access Granted - Normal Application Flow
            return widget.child;
          },
        );
      },
    );
  }
}
