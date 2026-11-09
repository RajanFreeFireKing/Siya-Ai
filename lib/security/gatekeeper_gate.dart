import 'package:flutter/material.dart';
import '../bridge/siya_bridge.dart';
import 'force_update_view.dart';
import 'remote_config_model.dart';
import 'remote_config_service.dart';
import 'remote_lock_view.dart';

/// GatekeeperGate wraps the entry point / screens.
///
/// Ensures that:
/// 1. If "is_locked" is true, the user is locked out immediately with RemoteLockView.
/// 2. If "force_update" is true and "latest_version_code" > current app build number,
///    the user is presented with ForceUpdateView.
/// 3. Normal application flow is only granted when neither condition is active.
/// 4. Operates with Zero-Write privacy and resilient offline/latency tolerance.
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
    _loadVersionCodeAndInit();
  }

  void _loadVersionCodeAndInit() async {
    final vCode = await widget.bridge.getAppVersionCode();
    if (mounted) {
      setState(() {
        _currentVersionCode = vCode;
      });
    }

    // Initialize real-time continuous listener and fast initial fetch
    RemoteConfigService.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppRemoteConfig>(
      valueListenable: RemoteConfigService.instance.configNotifier,
      builder: (context, config, _) {
        // Priority 1: Remote App Lock
        if (config.isLocked) {
          return RemoteLockView(config: config);
        }

        // Priority 2: Force Mandatory Update
        if (config.forceUpdate && config.latestVersionCode > _currentVersionCode) {
          return ForceUpdateView(
            config: config,
            currentVersionCode: _currentVersionCode,
            bridge: widget.bridge,
          );
        }

        // Priority 3: Granted Normal Application Flow
        return widget.child;
      },
    );
  }
}
