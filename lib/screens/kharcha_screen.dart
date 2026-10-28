import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';

class _KharchaSilkBackground extends StatelessWidget {
  const _KharchaSilkBackground({required this.accent});
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
            painter: _KharchaSilkPainter(accent),
            size: Size.infinite,
          ),
        ),
      );
}

class _KharchaSilkPainter extends CustomPainter {
  const _KharchaSilkPainter(this.accent);
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
  bool shouldRepaint(covariant _KharchaSilkPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class KharchaScreen extends StatefulWidget {
  const KharchaScreen({super.key, required this.bridge});
  final SiyaBridge bridge;

  @override
  State<KharchaScreen> createState() => _KharchaScreenState();
}

class _KharchaScreenState extends State<KharchaScreen> {
  Color get _accent => SiyaTheme.accent.value;

  Map<String, dynamic>? _ledgerData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchLedger();
  }

  Future<void> _fetchLedger() async {
    setState(() => _loading = true);
    try {
      final data = await widget.bridge.getSmsLedger();
      if (mounted) {
        setState(() {
          _ledgerData = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final day = (_ledgerData?['daySummary'] as Map?) ?? {};
    final month = (_ledgerData?['monthSummary'] as Map?) ?? {};
    final entries = (_ledgerData?['entries'] as List?) ?? [];

    final dayDebit = ((day['totalDebit'] as num?) ?? 0).toDouble();
    final dayCredit = ((day['totalCredit'] as num?) ?? 0).toDouble();
    final monthDebit = ((month['totalDebit'] as num?) ?? 0).toDouble();

    return Scaffold(
      backgroundColor: Color.alphaBlend(_accent.withOpacity(.045), const Color(0xFFFFF5FA)),
      body: Stack(
        children: [
          Positioned.fill(child: _KharchaSilkBackground(accent: _accent)),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 32),
                    children: [
                      // Today's Expense & Income Cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              title: "Aaj Ka Kharcha",
                              amount: "₹${dayDebit.toStringAsFixed(0)}",
                              subtitle: "Spent today",
                              color: const Color(0xFFE53935),
                              icon: Icons.arrow_outward_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryCard(
                              title: "Aaj Aaye",
                              amount: "₹${dayCredit.toStringAsFixed(0)}",
                              subtitle: "Received today",
                              color: const Color(0xFF2E7D32),
                              icon: Icons.arrow_downward_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Month Overview
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _accent.withOpacity(0.18)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.calendar_month_rounded, color: _accent, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'Is Mahine Ka Kharcha',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2A1C25),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '₹${monthDebit.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: _accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Transactions List Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'UPI / Bank Transactions (${entries.length})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2A1C25),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.refresh_rounded, color: _accent, size: 22),
                            onPressed: _fetchLedger,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (_loading)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Center(child: CircularProgressIndicator(color: _accent)),
                        )
                      else if (entries.isEmpty)
                        _buildEmptyState()
                      else
                        ...entries.map((entry) => _buildTransactionTile(entry as Map)),
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
                  'SMS / Kharcha Tracker',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2A1C25),
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Automated UPI & Bank Ledger',
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

  Widget _buildSummaryCard({
    required String title,
    required String amount,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.95), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5A4C56),
                ),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10.5,
              color: Color(0xFF8A7B85),
              fontWeight: FontWeight.w500,
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
          Icon(Icons.receipt_long_rounded, size: 48, color: _accent.withOpacity(0.6)),
          const SizedBox(height: 12),
          const Text(
            'Koi Transaction SMS nahi mila',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF2A1C25)),
          ),
          const SizedBox(height: 6),
          const Text(
            'SMS permission allow karein taaki Bank aur UPI transactions ka daily kharcha auto-track ho sake.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF6B5C67)),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(Map entry) {
    final sender = (entry['sender'] as String?) ?? 'Bank SMS';
    final amount = ((entry['amount'] as num?) ?? 0).toDouble();
    final isDebit = (entry['isDebit'] as bool?) ?? true;
    final body = (entry['body'] as String?) ?? '';
    final date = (entry['date'] as String?) ?? '';

    final color = isDebit ? const Color(0xFFE53935) : const Color(0xFF2E7D32);
    final sign = isDebit ? '-' : '+';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.95), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      sender,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _accent,
                      ),
                    ),
                  ),
                  if (date.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      date,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8A7B85)),
                    ),
                  ],
                ],
              ),
              Text(
                '$sign₹${amount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4A3C45),
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
