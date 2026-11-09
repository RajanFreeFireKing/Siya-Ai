import 'package:flutter/material.dart';
import 'remote_config_model.dart';

/// Full-screen, non-dismissible device restriction screen.
/// Triggered when "devices/{device_id}/is_locked" evaluates to true.
/// Displays device details (model, Android version, build) and the custom ban reason.
class DeviceBanView extends StatefulWidget {
  final DeviceRemoteConfig deviceConfig;

  const DeviceBanView({
    super.key,
    required this.deviceConfig,
  });

  @override
  State<DeviceBanView> createState() => _DeviceBanViewState();
}

class _DeviceBanViewState extends State<DeviceBanView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dev = widget.deviceConfig;
    final reason = dev.banReason.isNotEmpty
        ? dev.banReason
        : 'This specific device has been restricted by admin.';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0B12),
        body: Stack(
          children: [
            // Ambient red warning glow
            Positioned(
              top: -90,
              left: -90,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE53935).withOpacity(0.2),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB71C1C).withOpacity(0.18),
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Pulsing Ban Icon
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, _) {
                          final pulse = _pulseAnimation.value;
                          return Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE53935).withOpacity(0.35 * pulse + 0.15),
                                  blurRadius: 36 * pulse + 12,
                                  spreadRadius: 4 * pulse,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [Color(0xFFE53935), Color(0xFF880E4F)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.phonelink_erase_rounded,
                                  size: 42,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),

                      // Title
                      const Text(
                        'Device Restricted',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 6),

                      const Text(
                        'Hardware Access Revocation',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFEF9A9A),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Ban Reason Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B141C),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFE53935).withOpacity(0.35),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.gavel_rounded,
                                  size: 16,
                                  color: Color(0xFFFF5252),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'RESTRICTION REASON',
                                  style: TextStyle(
                                    color: Color(0xFFFF5252),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              reason,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFECEFF1),
                                fontSize: 15,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Detailed Device Specifications Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14141E),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.phone_android_rounded, size: 16, color: Color(0xFF90CAF9)),
                                SizedBox(width: 8),
                                Text(
                                  'DEVICE INFORMATION',
                                  style: TextStyle(
                                    color: Color(0xFF90CAF9),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildInfoRow('Device Model', dev.deviceName.isNotEmpty ? dev.deviceName : dev.deviceModel),
                            _buildInfoRow('Android OS', dev.androidVersion),
                            if (dev.buildDisplay.isNotEmpty)
                              _buildInfoRow('OS Build', dev.buildDisplay),
                            _buildInfoRow('Device ID', dev.deviceId),
                            _buildInfoRow('Status', 'Restricted / Suspended', valueColor: const Color(0xFFFF5252)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Live sync indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E2C).withOpacity(0.8),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFFF5252),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Device restricted by administrator',
                              style: TextStyle(
                                color: Color(0xFFB0B3C7),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF888A9E),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? const Color(0xFFECEFF1),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
