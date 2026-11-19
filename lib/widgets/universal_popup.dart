import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Universal Smart Floating & Full-Screen Popup System.
///
/// Supports:
/// 1. OSINT Intelligence & Web Research Results (links, summary, copy, cleanup)
/// 2. Gallery Image Viewer (interactive pinch-to-zoom, pan, share)
/// 3. App-in-Popup (Floating Companion for Freeform launched apps)
/// 4. Mini Floating Card <-> Normal <-> Full-Screen toggle with dynamic theme glow.
class UniversalPopup extends StatefulWidget {
  const UniversalPopup({
    super.key,
    required this.data,
    required this.accent,
    required this.onClose,
    required this.onClearData,
    this.onShareImage,
    this.onLaunchFullApp,
  });

  final Map<String, dynamic> data;
  final Color accent;
  final VoidCallback onClose;
  final VoidCallback onClearData;
  final void Function(String path)? onShareImage;
  final void Function(String pkg)? onLaunchFullApp;

  @override
  State<UniversalPopup> createState() => _UniversalPopupState();
}

class _UniversalPopupState extends State<UniversalPopup> {
  bool _isMini = false;
  bool _isFullScreen = false;

  @override
  Widget build(BuildContext context) {
    final mode = (widget.data['popup_type'] ?? widget.data['mode'] ?? widget.data['type'] ?? 'osint').toString().toLowerCase();
    final title = (widget.data['title'] ?? widget.data['query'] ?? widget.data['name'] ?? 'Siya Smart Intelligence').toString();
    final summary = (widget.data['summary'] ?? widget.data['content'] ?? widget.data['text'] ?? widget.data['description'] ?? 'Result available.').toString();
    final mediaUrl = (widget.data['imageUrl'] ?? widget.data['media_url'] ?? widget.data['imagePath'] ?? widget.data['image_path'] ?? widget.data['path'] ?? widget.data['url'] ?? '').toString();
    final rawLinks = widget.data['links'];
    final List<String> links = rawLinks is List ? rawLinks.map((e) => e.toString()).toList() : [];
    final appPackage = (widget.data['package'] ?? widget.data['action_data'] ?? widget.data['packageName'] ?? widget.data['package_name'] ?? '').toString();

    final neonColor = switch (mode) {
      'image' || 'gallery' => const Color(0xFF00F2FE),
      'app' => const Color(0xFFFF9500),
      _ => widget.accent,
    };

    if (_isMini) {
      return _buildMiniFloatingCard(mode, title, summary, neonColor);
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Backdrop Barrier
          Positioned.fill(
            child: GestureDetector(
              onTap: _isFullScreen ? null : widget.onClose,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                color: Colors.black.withOpacity(_isFullScreen ? 0.90 : 0.65),
              ),
            ),
          ),

          // Central or Full-Screen Card
          Align(
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              margin: _isFullScreen
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
              constraints: _isFullScreen
                  ? const BoxConstraints.expand()
                  : const BoxConstraints(maxWidth: 440, maxHeight: 640),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_isFullScreen ? 0 : 26),
                boxShadow: [
                  BoxShadow(
                    color: neonColor.withOpacity(0.35),
                    blurRadius: 32,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.85),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_isFullScreen ? 0 : 26),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      _isFullScreen ? MediaQuery.of(context).padding.top + 12 : 18,
                      18,
                      _isFullScreen ? MediaQuery.of(context).padding.bottom + 16 : 18,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xF00D0E17),
                      borderRadius: BorderRadius.circular(_isFullScreen ? 0 : 26),
                      border: Border.all(
                        color: neonColor.withOpacity(0.55),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Bar
                        _buildHeader(mode, title, neonColor),
                        const SizedBox(height: 12),

                        // Body Content
                        Expanded(
                          child: switch (mode) {
                            'image' || 'gallery' => _buildImageViewer(mediaUrl, title, neonColor),
                            'app' => _buildAppInPopup(appPackage, title, summary, neonColor),
                            _ => _buildOsintAndWebBody(title, summary, mediaUrl, links, neonColor),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String mode, String title, Color neon) {
    final (icon, badgeLabel) = switch (mode) {
      'image' || 'gallery' => (Icons.photo_library_rounded, 'GALLERY VIEWER'),
      'app' => (Icons.open_in_browser_rounded, 'APP IN POPUP'),
      'web' => (Icons.travel_explore_rounded, 'WEB RESEARCH'),
      _ => (Icons.security_rounded, 'OSINT INTELLIGENCE'),
    };

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: neon.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: neon.withOpacity(0.65), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: neon),
              const SizedBox(width: 5),
              Text(
                badgeLabel,
                style: TextStyle(
                  color: neon,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Mini Floating Card Toggle
        IconButton(
          onPressed: () => setState(() {
            _isMini = true;
            _isFullScreen = false;
          }),
          icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 18),
          color: Colors.white70,
          tooltip: 'Mini Floating Card',
        ),
        // Full Screen Toggle
        IconButton(
          onPressed: () => setState(() => _isFullScreen = !_isFullScreen),
          icon: Icon(_isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, size: 21),
          color: Colors.white70,
          tooltip: _isFullScreen ? 'Restore' : 'Full Screen',
        ),
        // Close Button
        IconButton(
          onPressed: widget.onClose,
          icon: const Icon(Icons.close_rounded, size: 20),
          color: Colors.white,
          tooltip: 'Close',
        ),
      ],
    );
  }

  Widget _buildMiniFloatingCard(String mode, String title, String summary, Color neon) {
    return Positioned(
      right: 14,
      bottom: 96,
      child: GestureDetector(
        onTap: () => setState(() => _isMini = false),
        child: Container(
          width: 290,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xF20F111D),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: neon.withOpacity(0.7), width: 1.4),
            boxShadow: [
              BoxShadow(color: neon.withOpacity(0.3), blurRadius: 18),
              BoxShadow(color: Colors.black.withOpacity(0.7), blurRadius: 12),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: neon.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.insights_rounded, color: neon, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_full_rounded, size: 16, color: Colors.white),
                onPressed: () => setState(() => _isMini = false),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white54),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageViewer(String pathOrUrl, String title, Color neon) {
    if (pathOrUrl.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 54, color: neon.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text(
              'Koi photo select nahi hui ya image path nahi mila.',
              style: TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    final isLocal = pathOrUrl.startsWith('/') || pathOrUrl.startsWith('file://');
    final cleanPath = pathOrUrl.replaceFirst('file://', '');
    final fileExists = isLocal && File(cleanPath).existsSync();

    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              color: Colors.black,
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.5,
                child: Center(
                  child: isLocal
                      ? (fileExists
                          ? Image.file(
                              File(cleanPath),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
                                const SizedBox(height: 8),
                                Text(
                                  'Photo file nahi mili:\n$cleanPath',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ))
                      : Image.network(
                          pathOrUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title.ifEmpty('Gallery Image'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
            if (fileExists)
              ElevatedButton.icon(
                onPressed: () => widget.onShareImage?.call(cleanPath),
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('Share Photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: neon.withOpacity(0.25),
                  foregroundColor: Colors.white,
                  side: BorderSide(color: neon.withOpacity(0.7)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppInPopup(String pkg, String title, String summary, Color neon) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: neon.withOpacity(0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: neon.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.apps_rounded, color: neon, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              summary.ifEmpty('App running in floating window.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => widget.onLaunchFullApp?.call(pkg),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: const Text('Open Full Screen App'),
              style: ElevatedButton.styleFrom(
                backgroundColor: neon,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOsintAndWebBody(
    String query,
    String summary,
    String imageUrl,
    List<String> links,
    Color neon,
  ) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        // Query Box
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: neon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  query,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Optional Thumbnail
        if (imageUrl.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 140,
              width: double.infinity,
              color: Colors.black38,
              child: _buildAdaptiveImage(imageUrl),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // AI Summary
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: neon.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: neon, size: 16),
                  const SizedBox(width: 6),
                  Text('AI Intelligence Summary',
                      style: TextStyle(color: neon, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                summary,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Clickable / Copyable Links
        if (links.isNotEmpty) ...[
          const Text(
            'Discovered Public Sources & Profiles:',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...links.map((link) => _buildLinkTile(link, neon)),
          const SizedBox(height: 12),
        ],

        // Clear Search Data Button
        OutlinedButton.icon(
          onPressed: widget.onClearData,
          icon: const Icon(Icons.delete_sweep_rounded, size: 16),
          label: const Text('Clear Search Data & Free RAM'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF5252),
            side: BorderSide(color: const Color(0xFFFF5252).withOpacity(0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkTile(String link, Color neon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, color: neon, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              link,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 15, color: Colors.white54),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied to clipboard!'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAdaptiveImage(String pathOrUrl, {BoxFit fit = BoxFit.cover}) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return Image.network(pathOrUrl, fit: fit, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    }
    final clean = pathOrUrl.replaceFirst('file://', '');
    final f = File(clean);
    if (f.existsSync()) {
      return Image.file(f, fit: fit, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    }
    return Image.network(pathOrUrl, fit: fit, errorBuilder: (_, __, ___) => const SizedBox.shrink());
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
