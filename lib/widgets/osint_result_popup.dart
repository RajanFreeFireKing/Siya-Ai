import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dark Glassmorphic Neon Popup for OSINT Intelligence (Image & Name Lookup).
class OsintResultPopup extends StatelessWidget {
  const OsintResultPopup({
    super.key,
    required this.data,
    required this.accent,
    required this.onClose,
    required this.onClearData,
  });

  final Map<String, dynamic> data;
  final Color accent;
  final VoidCallback onClose;
  final VoidCallback onClearData;

  @override
  Widget build(BuildContext context) {
    final mode = (data['mode'] as String?) ?? 'osint';
    final query = (data['query'] as String?) ?? '';
    final imageUrl = (data['imageUrl'] as String?) ?? '';
    final summary = (data['summary'] as String?) ?? 'OSINT search completed.';
    final rawLinks = data['links'];
    final List<String> links = rawLinks is List ? rawLinks.map((e) => e.toString()).toList() : [];

    final isImage = mode == 'image';
    final neonColor = isImage ? const Color(0xFF00FFCC) : const Color(0xFF7000FF);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Semi-transparent backdrop barrier
          Positioned.fill(
            child: GestureDetector(
              onTap: onClose,
              child: Container(
                color: Colors.black.withOpacity(0.65),
              ),
            ),
          ),

          // Central Glassmorphic Card
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: neonColor.withOpacity(0.25),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.8),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xE60D0E17), // Deep dark glass
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: neonColor.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header: Glowing Neon Badge & Close Button
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: neonColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: neonColor.withOpacity(0.6), width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isImage ? Icons.image_search : Icons.person_search,
                                    size: 15,
                                    color: neonColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isImage ? 'REVERSE IMAGE LOOKUP' : 'OSINT PROFILE SCAN',
                                    style: TextStyle(
                                      color: neonColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: onClose,
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Query Title
                        Text(
                          query.isNotEmpty ? query : 'Target Analysis',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Scrollable content area
                        Flexible(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Optional Image Thumbnail for Reverse Search
                                if (imageUrl.isNotEmpty) ...[
                                  Container(
                                    height: 120,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.white24),
                                      image: DecorationImage(
                                        image: NetworkImage(imageUrl),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ],

                                // AI Summary Box
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Text(
                                    summary,
                                    style: const TextStyle(
                                      color: Color(0xFFE2E8F0),
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // Discovered Public Footprints / Links
                                if (links.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      Icon(Icons.link, size: 14, color: neonColor),
                                      const SizedBox(width: 6),
                                      Text(
                                        'MATCHING PUBLIC PROFILES (${links.length})',
                                        style: TextStyle(
                                          color: neonColor.withOpacity(0.9),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...links.map((link) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.04),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.white10),
                                      ),
                                      child: ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        title: Text(
                                          link,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF67E8F9),
                                            fontSize: 12,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                        trailing: const Icon(
                                          Icons.copy,
                                          size: 14,
                                          color: Colors.white54,
                                        ),
                                        onTap: () {
                                          final cleanUrl = link.contains("http")
                                              ? link.substring(link.indexOf("http"))
                                              : link;
                                          Clipboard.setData(ClipboardData(text: cleanUrl.trim()));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Link copied to clipboard!'),
                                              duration: Duration(seconds: 2),
                                              backgroundColor: Color(0xFF1E293B),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Action Buttons: "Clear Search Data" & "Done"
                        Row(
                          children: [
                            // "Clear Search Data" Button (Obscura Cleanup)
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFFF4D4D), width: 1.2),
                                  backgroundColor: const Color(0x22FF4D4D),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.delete_sweep, size: 16, color: Color(0xFFFF6B6B)),
                                label: const Text(
                                  'Clear Search Data',
                                  style: TextStyle(
                                    color: Color(0xFFFF6B6B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () {
                                  onClearData();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Browser cache & memory cleared!'),
                                      duration: Duration(seconds: 2),
                                      backgroundColor: Color(0xFF0F172A),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: neonColor.withOpacity(0.2),
                                foregroundColor: neonColor,
                                side: BorderSide(color: neonColor.withOpacity(0.8), width: 1.2),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: onClose,
                              child: const Text(
                                'Done',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
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
}
