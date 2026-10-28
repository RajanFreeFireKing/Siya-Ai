import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import 'location_screen.dart';
import 'smart_contacts_screen.dart';

class _PowerSilkBackground extends StatelessWidget {
  const _PowerSilkBackground({required this.primaryThemeColor});
  final Color primaryThemeColor;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(primaryThemeColor.withOpacity(.09), const Color(0xFFFFF7FB)),
                Colors.white,
                Color.alphaBlend(primaryThemeColor.withOpacity(.07), const Color(0xFFFFEAF4)),
                Color.alphaBlend(primaryThemeColor.withOpacity(.04), const Color(0xFFFFF8FC)),
              ],
              stops: const [0, .40, .78, 1],
            ),
          ),
          child: CustomPaint(
            painter: _PowerSilkPainter(primaryThemeColor),
            size: Size.infinite,
          ),
        ),
      );
}

class _PowerSilkPainter extends CustomPainter {
  const _PowerSilkPainter(this.accent);
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

    final ribbonPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 6; i++) {
      final y = size.height * (.05 + i * .18);
      final ribbon = Path()
        ..moveTo(-size.width * .12, y)
        ..cubicTo(
          size.width * .16, y - size.height * .14,
          size.width * .36, y + size.height * .12,
          size.width * .65, y - size.height * .02,
        )
        ..cubicTo(
          size.width * .86, y - size.height * .09,
          size.width * .97, y + size.height * .09,
          size.width * 1.12, y + size.height * .01,
        )
        ..lineTo(size.width * 1.12, y + size.height * .04)
        ..cubicTo(
          size.width * .86, y + size.height * .16,
          size.width * .66, y + size.height * .05,
          size.width * .40, y + size.height * .11,
        )
        ..cubicTo(
          size.width * .16, y + size.height * .16,
          size.width * .035, y + size.height * .02,
          -size.width * .12, y + size.height * .06,
        )
        ..close();

      ribbonPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(.02),
          accent.withOpacity(i.isEven ? .15 : .08),
          const Color(0xFFFF6EB0).withOpacity(.06),
          Colors.white.withOpacity(.02),
        ],
      ).createShader(
        Rect.fromLTWH(0, y - size.height * .18, size.width, size.height * .36),
      );
      canvas.drawPath(ribbon, ribbonPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PowerSilkPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// PowerScreen: ⚡ Quick Tools & Action Hub
/// 1. AI Browser Tool (Direct Search & Web Page viewer)
/// 2. Smart Location Tool (Map view & GPS detect)
/// 3. Smart Call Logs (AI Screened calls & summary)
/// 4. SMS / Kharcha Tracker (Direct expense sheet & ledger)
class PowerScreen extends StatefulWidget {
  const PowerScreen({
    super.key,
    required this.bridge,
    this.embedded = false,
    this.onBackToHome,
  });

  final SiyaBridge bridge;
  final bool embedded;
  final VoidCallback? onBackToHome;

  @override
  State<PowerScreen> createState() => _PowerScreenState();
}

class _PowerScreenState extends State<PowerScreen> with WidgetsBindingObserver {
  Color _primaryThemeColor = SiyaTheme.defaultAccent;
  final _searchCtrl = TextEditingController();

  bool _loading = false;
  String _locName = '';
  double? _locLat;
  double? _locLng;
  bool _locDetecting = false;

  Map<String, dynamic> _ledgerData = {};
  List<Map<String, dynamic>> _callLogs = [];
  bool _callScreenerActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _primaryThemeColor = SiyaTheme.accent.value;
    _loadToolsData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadToolsData();
  }

  Future<void> _loadToolsData() async {
    setState(() => _loading = true);
    _primaryThemeColor = SiyaTheme.accent.value;

    final s = await widget.bridge.getSettings();
    _callScreenerActive = (s['call_screener'] as bool?) ?? false;

    // Load ledger & calls concurrently
    try {
      final ledgerFuture = widget.bridge.getSmsLedger();
      final callsFuture = widget.bridge.getCallLogs();

      final results = await Future.wait([ledgerFuture, callsFuture]);
      if (mounted) {
        setState(() {
          _ledgerData = results[0] as Map<String, dynamic>;
          _callLogs = (results[1] as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _detectLocation() async {
    setState(() => _locDetecting = true);
    try {
      final loc = await widget.bridge.getLocation();
      if (!mounted) return;
      if (loc != null) {
        setState(() {
          _locName = (loc['name'] as String?) ?? 'Current Location';
          _locLat = (loc['lat'] as num?)?.toDouble();
          _locLng = (loc['lng'] as num?)?.toDouble();
          _locDetecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location detect ho gayi: $_locName'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() => _locDetecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS detect nahi hua. Pehle Location permission dein.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _locDetecting = false);
    }
  }

  Future<void> _launchBrowser([String? query]) async {
    String url = 'https://www.google.com';
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim();
      if (q.startsWith('http://') || q.startsWith('https://')) {
        url = q;
      } else if (q.contains('.') && !q.contains(' ')) {
        url = 'https://$q';
      } else {
        url = 'https://www.google.com/search?q=${Uri.encodeComponent(q)}';
      }
    }
    await widget.bridge.openBrowser(url);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Color.alphaBlend(_primaryThemeColor.withOpacity(.045), const Color(0xFFFFF5FA)),
      body: Stack(
        children: [
          Positioned.fill(
            child: _PowerSilkBackground(primaryThemeColor: _primaryThemeColor),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _header(context),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      4,
                      16,
                      widget.embedded ? bottomInset + 120 : bottomInset + 32,
                    ),
                    children: [
                      // 0. Smart Call & Nicknames Tool
                      _actionCard(
                        icon: Icons.contact_phone_rounded,
                        badge: 'Voice Call Hub',
                        title: 'Smart Call & Nicknames',
                        subtitle: 'Custom numbers aur unke multiple nicknames (Papa, Dost) manage karein',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SmartContactsScreen(bridge: widget.bridge),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // 1. AI Browser Tool
                      _toolCard(
                        icon: Icons.travel_explore_rounded,
                        badge: 'Web Tool',
                        title: 'AI Browser',
                        subtitle: 'In-app automated web viewer aur live web search',
                        child: _buildBrowserContent(),
                      ),
                      const SizedBox(height: 16),

                      // 2. Smart Location Tool
                      _toolCard(
                        icon: Icons.explore_rounded,
                        badge: 'Location Tool',
                        title: 'Smart Location',
                        subtitle: 'GPS detect, interactive map aur location queries',
                        child: _buildLocationContent(),
                      ),
                      const SizedBox(height: 16),

                      // 3. Smart Call Logs / Screened Calls
                      _toolCard(
                        icon: Icons.phone_in_talk_rounded,
                        badge: 'Calls Tool',
                        title: 'Smart Call Logs',
                        subtitle: 'AI-handled calls, caller detection aur history',
                        child: _buildCallLogsContent(),
                      ),
                      const SizedBox(height: 16),

                      // 4. SMS / Kharcha Tracker
                      _toolCard(
                        icon: Icons.account_balance_wallet_rounded,
                        badge: 'Finance Tool',
                        title: 'SMS / Kharcha Tracker',
                        subtitle: 'Bank & UPI SMS expense sheet aur daily ledger',
                        child: _buildLedgerContent(),
                      ),
                      const SizedBox(height: 20),
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

  // ── 1. AI Browser Content ─────────────────────────────────────
  Widget _buildBrowserContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search & Navigate Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primaryThemeColor.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: _primaryThemeColor.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: _primaryThemeColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search web ya URL type karein...',
                    hintStyle: TextStyle(color: Color(0xFF9E8E98), fontSize: 13.5),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(color: Color(0xFF2A1C25), fontSize: 14, fontWeight: FontWeight.w600),
                  onSubmitted: (v) => _launchBrowser(v),
                ),
              ),
              GestureDetector(
                onTap: () => _launchBrowser(_searchCtrl.text),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_primaryThemeColor, Color.lerp(_primaryThemeColor, const Color(0xFFFF0077), 0.5)!],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Go 🚀',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Quick Bookmark Shortcuts
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _quickTag('🔍 Google', 'https://www.google.com'),
            _quickTag('🤖 Gemini AI', 'https://gemini.google.com'),
            _quickTag('📚 Wikipedia', 'https://www.wikipedia.org'),
            _quickTag('📰 News', 'https://news.google.com'),
            _quickTag('▶️ YouTube', 'https://www.youtube.com'),
          ],
        ),
        const SizedBox(height: 14),

        // Direct Launch Button
        _primaryActionButton(
          label: 'Launch In-App AI Browser',
          icon: Icons.open_in_browser_rounded,
          onTap: () => _launchBrowser(),
        ),
      ],
    );
  }

  Widget _quickTag(String label, String url) => InkWell(
        onTap: () => _launchBrowser(url),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _primaryThemeColor.withOpacity(0.2)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: const Color(0xFF2A1C25),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      );

  // ── 2. Smart Location Content ─────────────────────────────────
  Widget _buildLocationContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Detected Location Preview
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primaryThemeColor.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _primaryThemeColor.withOpacity(0.12),
                ),
                child: Icon(Icons.location_searching_rounded, color: _primaryThemeColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _locDetecting
                          ? 'GPS se jagah dhund rahe hain...'
                          : (_locName.isNotEmpty ? _locName : 'Location abhi detect nahi hui'),
                      style: const TextStyle(
                        color: Color(0xFF2A1C25),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _locLat != null && _locLng != null
                          ? 'Lat: ${_locLat!.toStringAsFixed(4)}, Lng: ${_locLng!.toStringAsFixed(4)}'
                          : 'Detect button dabayein',
                      style: const TextStyle(color: Color(0xFF6F6470), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (_locDetecting)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: _primaryThemeColor),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2 Action Buttons: Detect GPS & Open Interactive Map
        Row(
          children: [
            Expanded(
              child: _secondaryButton(
                icon: Icons.my_location_rounded,
                label: 'Detect GPS',
                onTap: _detectLocation,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _primaryActionButton(
                icon: Icons.map_rounded,
                label: 'Open Map View',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => LocationScreen(bridge: widget.bridge)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── 3. Smart Call Logs Content ────────────────────────────────
  Widget _buildCallLogsContent() {
    final recentCalls = _callLogs.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Screening status badge
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  _callScreenerActive ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: _callScreenerActive ? SiyaColors.ok : const Color(0xFF8B7180),
                ),
                const SizedBox(width: 6),
                Text(
                  _callScreenerActive ? 'AI Call Screener: ACTIVE' : 'AI Call Screener: OFF',
                  style: TextStyle(
                    color: _callScreenerActive ? SiyaColors.ok : const Color(0xFF6F6470),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Text(
              '${_callLogs.length} calls',
              style: const TextStyle(color: Color(0xFF6F6470), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (recentCalls.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            child: const Text(
              'Koi recent call nahi mili ya permission pending hai.',
              style: TextStyle(color: Color(0xFF8B7180), fontSize: 12.5),
            ),
          )
        else
          Column(
            children: recentCalls.map((call) {
              final name = (call['name'] as String?).orEmpty();
              final numStr = (call['number'] as String?).orEmpty();
              final type = (call['type'] as int?) ?? 1;
              final dur = (call['duration'] as int?) ?? 0;

              IconData typeIcon = Icons.call_received_rounded;
              Color typeColor = Colors.blue;
              if (type == 3) {
                typeIcon = Icons.call_missed_rounded;
                typeColor = Colors.red;
              } else if (type == 2) {
                typeIcon = Icons.call_made_rounded;
                typeColor = Colors.green;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _primaryThemeColor.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    Icon(typeIcon, color: typeColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isNotEmpty ? name : (numStr.isNotEmpty ? numStr : 'Unknown Caller'),
                            style: const TextStyle(
                              color: Color(0xFF2A1C25),
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (name.isNotEmpty && numStr.isNotEmpty)
                            Text(numStr, style: const TextStyle(color: Color(0xFF6F6470), fontSize: 11)),
                        ],
                      ),
                    ),
                    if (dur > 0)
                      Text('${dur}s', style: const TextStyle(color: Color(0xFF8B7180), fontSize: 11)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        if (numStr.isNotEmpty) {
                          // Quick call helper
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$numStr par call mila rahe hain...')),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: _primaryThemeColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.call_rounded, color: _primaryThemeColor, size: 16),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 6),
        _secondaryButton(
          icon: Icons.list_alt_rounded,
          label: 'Call Screening Log Sheet',
          onTap: () => _showAllCallsSheet(),
        ),
      ],
    );
  }

  void _showAllCallsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Screened & Recent Calls',
                  style: TextStyle(color: Color(0xFF2A1C25), fontSize: 18, fontWeight: FontWeight.w800),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: _callLogs.isEmpty
                  ? const Center(child: Text('Koi calls nahi hain.'))
                  : ListView.builder(
                      itemCount: _callLogs.length,
                      itemBuilder: (context, i) {
                        final call = _callLogs[i];
                        final name = (call['name'] as String?).orEmpty();
                        final numStr = (call['number'] as String?).orEmpty();
                        return ListTile(
                          leading: const Icon(Icons.phone_rounded),
                          title: Text(name.isNotEmpty ? name : numStr, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(name.isNotEmpty ? numStr : 'Unknown'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 4. SMS / Kharcha Content ──────────────────────────────────
  Widget _buildLedgerContent() {
    final entries = (_ledgerData['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final daySum = (_ledgerData['daySummary'] as String?) ?? '';

    // Calculate totals from entries
    double todayDebit = 0;
    double todayCredit = 0;
    for (final e in entries.take(10)) {
      final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
      if (e['kind'] == 'debit') {
        todayDebit += amt;
      } else {
        todayCredit += amt;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kharcha vs Aaya Stats Row
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFECEF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🔻 Kharcha (Spent)', style: TextStyle(color: Color(0xFFD32F2F), fontSize: 11.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      '₹${todayDebit.toInt()}',
                      style: const TextStyle(color: Color(0xFFC62828), fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8F0),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00C853).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🔺 Aaya (Received)', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 11.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      '₹${todayCredit.toInt()}',
                      style: const TextStyle(color: Color(0xFF1B5E20), fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Recent Transactions Preview
        if (entries.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            child: const Text(
              'Abhi tak koi bank/UPI SMS nahi mila hai.',
              style: TextStyle(color: Color(0xFF8B7180), fontSize: 12.5),
            ),
          )
        else
          Column(
            children: entries.take(3).map((e) {
              final isDebit = e['kind'] == 'debit';
              final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
              final from = (e['from'] as String?).orEmpty();
              final note = (e['note'] as String?).orEmpty();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _primaryThemeColor.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: (isDebit ? Colors.red : Colors.green).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDebit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                        color: isDebit ? Colors.red : Colors.green,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            from.isNotEmpty ? from : 'Bank SMS',
                            style: const TextStyle(
                              color: Color(0xFF2A1C25),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          if (note.isNotEmpty)
                            Text(
                              note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF6F6470), fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${isDebit ? "-" : "+"}₹${amt.toInt()}',
                      style: TextStyle(
                        color: isDebit ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 6),
        _primaryActionButton(
          icon: Icons.receipt_long_rounded,
          label: 'View Expense Sheet / Ledger',
          onTap: () => _showFullLedgerSheet(entries, daySum),
        ),
      ],
    );
  }

  void _showFullLedgerSheet(List<Map<String, dynamic>> entries, String daySum) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SMS Kharcha Ledger',
                  style: TextStyle(color: Color(0xFF2A1C25), fontSize: 18, fontWeight: FontWeight.w800),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            if (daySum.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(daySum, style: const TextStyle(color: Color(0xFF6F6470), fontSize: 12)),
              ),
            const Divider(),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('Koi transactions nahi hain.'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final isDebit = e['kind'] == 'debit';
                        final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
                        return ListTile(
                          leading: Icon(
                            isDebit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                            color: isDebit ? Colors.red : Colors.green,
                          ),
                          title: Text(e['from'] ?? 'SMS', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(e['note'] ?? ''),
                          trailing: Text(
                            '${isDebit ? "-" : "+"}₹${amt.toInt()}',
                            style: TextStyle(
                              color: isDebit ? Colors.red : Colors.green,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── UI Helpers ────────────────────────────────────────────────
  Widget _actionCard({
    required IconData icon,
    required String badge,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.78),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(.95), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _primaryThemeColor.withOpacity(.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primaryThemeColor.withOpacity(0.2), _primaryThemeColor.withOpacity(0.08)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _primaryThemeColor.withOpacity(0.3)),
              ),
              child: Icon(icon, color: _primaryThemeColor, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF2A1C25),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _primaryThemeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: _primaryThemeColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B5C67),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _primaryThemeColor.withOpacity(0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward_ios_rounded, color: _primaryThemeColor, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolCard({
    required IconData icon,
    required String badge,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(.95), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _primaryThemeColor.withOpacity(.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_primaryThemeColor.withOpacity(0.18), _primaryThemeColor.withOpacity(0.08)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _primaryThemeColor.withOpacity(0.3)),
                ),
                child: Icon(icon, color: _primaryThemeColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFF2A1C25),
                            fontWeight: FontWeight.w900,
                            fontSize: 16.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _primaryThemeColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: _primaryThemeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF6F6470), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _primaryActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_primaryThemeColor, Color.lerp(_primaryThemeColor, const Color(0xFFFF0077), 0.5)!],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _primaryThemeColor.withOpacity(0.32),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _primaryThemeColor.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _primaryThemeColor, size: 18),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(color: _primaryThemeColor, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                _iconBtn(Icons.arrow_back_ios_new_rounded, () {
                  if (widget.onBackToHome != null) {
                    widget.onBackToHome!();
                  } else if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                }),
                const SizedBox(width: 14),
                Expanded(
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (rect) => LinearGradient(
                      colors: [_primaryThemeColor, const Color(0xFF8D003A)],
                    ).createShader(rect),
                    child: const Row(
                      children: [
                        Text(
                          'Power Tools',
                          style: TextStyle(
                            fontSize: 28,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.9,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.bolt_rounded, size: 28, color: Colors.amber),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1.4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        _primaryThemeColor.withOpacity(.02),
                        _primaryThemeColor,
                        _primaryThemeColor.withOpacity(.08),
                      ]),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 20,
                    color: _primaryThemeColor,
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1.4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        _primaryThemeColor.withOpacity(.08),
                        _primaryThemeColor,
                        _primaryThemeColor.withOpacity(.02),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _primaryThemeColor.withOpacity(.12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _primaryThemeColor.withOpacity(0.6)),
          ),
          child: Icon(icon, color: const Color(0xFF2A1C25), size: 20),
        ),
      );
}

extension StringExt on String? {
  String orEmpty() => this ?? '';
}
