import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';

class _AiBrowserSilkBackground extends StatelessWidget {
  const _AiBrowserSilkBackground({required this.accent});
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
            painter: _AiBrowserSilkPainter(accent),
            size: Size.infinite,
          ),
        ),
      );
}

class _AiBrowserSilkPainter extends CustomPainter {
  const _AiBrowserSilkPainter(this.accent);
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
  bool shouldRepaint(covariant _AiBrowserSilkPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class AiBrowserScreen extends StatefulWidget {
  const AiBrowserScreen({super.key, required this.bridge});
  final SiyaBridge bridge;

  @override
  State<AiBrowserScreen> createState() => _AiBrowserScreenState();
}

class _AiBrowserScreenState extends State<AiBrowserScreen> {
  Color get _accent => SiyaTheme.accent.value;
  final TextEditingController _urlCtrl = TextEditingController();

  final List<Map<String, String>> _bookmarks = const [
    {'title': '🔍 Google', 'url': 'https://www.google.com'},
    {'title': '🤖 Gemini AI', 'url': 'https://gemini.google.com'},
    {'title': '📚 Wikipedia', 'url': 'https://www.wikipedia.org'},
    {'title': '📰 News', 'url': 'https://news.google.com'},
    {'title': '▶️ YouTube', 'url': 'https://www.youtube.com'},
    {'title': '🛒 Amazon', 'url': 'https://www.amazon.in'},
    {'title': '🗺️ Google Maps', 'url': 'https://maps.google.com'},
  ];

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _launch([String? query]) async {
    String url = 'https://www.google.com';
    final target = query ?? _urlCtrl.text;
    if (target.trim().isNotEmpty) {
      final q = target.trim();
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
      backgroundColor: Color.alphaBlend(_accent.withOpacity(.045), const Color(0xFFFFF5FA)),
      body: Stack(
        children: [
          Positioned.fill(child: _AiBrowserSilkBackground(accent: _accent)),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 32),
                    children: [
                      // Search Card
                      _buildSearchCard(),
                      const SizedBox(height: 16),

                      // Quick Bookmarks
                      _buildBookmarksCard(),
                      const SizedBox(height: 16),

                      // AI Web Automation Features Card
                      _buildAutomationInfoCard(),
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
                  'AI Browser',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2A1C25),
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Automated Web Viewer & Live Search',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'LIVE',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.95), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.travel_explore_rounded, color: _accent, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Search or Enter URL',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2A1C25),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F6F8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _accent.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: _accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    onSubmitted: (v) => _launch(v),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2A1C25),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search Google ya URL enter karein...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: const Color(0xFF7A6B75).withOpacity(0.7),
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _launch(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    elevation: 2,
                  ),
                  child: const Text('Go', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _launch(),
              icon: const Icon(Icons.open_in_browser_rounded, size: 20),
              label: const Text(
                'Open In-App AI Browser',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookmarksCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.95), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark_border_rounded, color: _accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Quick Bookmarks',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2A1C25),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _bookmarks.map((bm) {
              return InkWell(
                onTap: () => _launch(bm['url']),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    bm['title']!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2A1C25),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.95), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: _accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'AI Web Agent Capabilities',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2A1C25),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _bulletPoint('Voice Search: "Google par latest cricket score search karo"'),
          _bulletPoint('Auto Click & Navigation: Page ke links aur buttons par AI khud click kar sakti hai'),
          _bulletPoint('Web Reader: Kisi bhi web article ya news ka summary AI bolkar sunati hai'),
          _bulletPoint('YouTube Player: Browser popup mein gaane ya videos live play ho sakte hain'),
        ],
      ),
    );
  }

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: _accent, fontWeight: FontWeight.w900, fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF5A4C56),
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
