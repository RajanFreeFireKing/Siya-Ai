import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';

class _CallLogsSilkBackground extends StatelessWidget {
  const _CallLogsSilkBackground({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(accent.withOpacity(.09), const Color(0xFFFFF7FB)),
                Colors.white,
                Color.alphaBlend(accent.withOpacity(.07), const Color(0xFFFFEAF4)),
                Color.alphaBlend(accent.withOpacity(.04), const Color(0xFFFFF8FC)),
              ],
              stops: const [0, .40, .78, 1],
            ),
          ),
          child: CustomPaint(
            painter: _CallLogsSilkPainter(accent),
            size: Size.infinite,
          ),
        ),
      );
}

class _CallLogsSilkPainter extends CustomPainter {
  const _CallLogsSilkPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withOpacity(.12),
          accent.withOpacity(.03),
          Colors.transparent,
        ],
        stops: const [0, .55, 1],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .85, size.height * .28),
          radius: size.width * .75,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant _CallLogsSilkPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class CallLogsScreen extends StatefulWidget {
  const CallLogsScreen({super.key, required this.bridge});
  final SiyaBridge bridge;

  @override
  State<CallLogsScreen> createState() => _CallLogsScreenState();
}

class _CallLogsScreenState extends State<CallLogsScreen> {
  Color get _accent => SiyaTheme.accent.value;

  List<dynamic> _callLogs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _loading = true);
    try {
      final logs = await widget.bridge.getCallLogs();
      if (mounted) {
        setState(() {
          _callLogs = logs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _callBack(String number) async {
    if (number.trim().isEmpty) return;
    await widget.bridge.directCall(number);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Color.alphaBlend(_accent.withOpacity(.045), const Color(0xFFFFF5FA)),
      body: Stack(
        children: [
          Positioned.fill(child: _CallLogsSilkBackground(accent: _accent)),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 32),
                    children: [
                      // Screener Banner
                      _buildScreenerStatusBanner(),
                      const SizedBox(height: 16),

                      // Call History Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Calls (${_callLogs.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2A1C25),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.refresh_rounded, color: _accent, size: 22),
                            onPressed: _fetchLogs,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (_loading)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Center(child: CircularProgressIndicator(color: _accent)),
                        )
                      else if (_callLogs.isEmpty)
                        _buildEmptyState()
                      else
                        ..._callLogs.map((log) => _buildCallLogTile(log as Map)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.9)),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(Icons.chevron_left_rounded, color: _accent, size: 28),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Call Logs',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2A1C25),
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'AI-handled Calls & History',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenerStatusBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_accent.withOpacity(0.2), _accent.withOpacity(0.08)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.security_rounded, color: _accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'AI Call Screener',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2A1C25),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Unknown callers se pehle Siya baat karke naam aur purpose confirm karti hai.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF6B5C67),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Icon(Icons.phone_missed_rounded, size: 48, color: _accent.withOpacity(0.6)),
          const SizedBox(height: 12),
          const Text(
            'Koi Call Log nahi mila',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF2A1C25)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Call log permission allow karein taaki incoming aur screened calls yahan dikhein.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF6B5C67)),
          ),
        ],
      ),
    );
  }

  Widget _buildCallLogTile(Map log) {
    final name = (log['name'] as String?)?.trim().isNotEmpty == true
        ? log['name'] as String
        : 'Unknown / Anjaan';
    final number = (log['number'] as String?) ?? '';
    final type = (log['type'] as int?) ?? 1;
    final duration = (log['duration'] as num?)?.toInt() ?? 0;

    IconData typeIcon = Icons.call_received_rounded;
    Color typeColor = Colors.blue;
    String typeLabel = 'Incoming';

    if (type == 2) {
      typeIcon = Icons.call_made_rounded;
      typeColor = const Color(0xFF2E7D32);
      typeLabel = 'Outgoing';
    } else if (type == 3) {
      typeIcon = Icons.call_missed_rounded;
      typeColor = const Color(0xFFE53935);
      typeLabel = 'Missed';
    } else if (type == 5) {
      typeIcon = Icons.call_end_rounded;
      typeColor = const Color(0xFFFF9800);
      typeLabel = 'Rejected / Screened';
    }

    final durationFormatted = duration > 0 ? '${duration ~/ 60}m ${duration % 60}s' : '0s';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.95), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(typeIcon, color: typeColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2A1C25),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      number,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF5A4C56).withOpacity(0.85),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• $typeLabel ($durationFormatted)',
                      style: TextStyle(
                        fontSize: 11,
                        color: typeColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (number.isNotEmpty)
            InkWell(
              onTap: () => _callBack(number),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_forwarded_rounded, color: Color(0xFF2E7D32), size: 18),
              ),
            ),
        ],
      ),
    );
  }
}
