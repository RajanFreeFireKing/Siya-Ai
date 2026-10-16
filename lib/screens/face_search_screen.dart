import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/siya_ui.dart';

/// Gallery mein is insaan ki saari photos dhundo aur poori photo dekho.
class FaceSearchScreen extends StatefulWidget {
  const FaceSearchScreen({super.key, required this.bridge, required this.person});

  final SiyaBridge bridge;
  final Person person;

  @override
  State<FaceSearchScreen> createState() => _FaceSearchScreenState();
}

class _FaceSearchScreenState extends State<FaceSearchScreen> {
  FaceSearchStatus? _st;
  Timer? _poll;
  final Map<String, Future<Uint8List?>> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(milliseconds: 900), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await widget.bridge.faceSearchStatus(widget.person.id);
    if (mounted) setState(() => _st = s);
  }

  Future<void> _start(int limit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: SiyaColors.card,
        title: const Text('Gallery search', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Match dhundne ke liye gallery ki chhoti photos aur reference photo aapke Gemini API key se Google ke AI ko bheji jaayengi. '
          'Photos phone par hi rehti hain, koi photo badli ya delete nahi hoti.\n\nSirf apni / ghar walon ki photos ke liye use karo. Aage badhein?',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nahi')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Haan, dhundo')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.bridge.requestPermissions();
    await widget.bridge.faceSearchStart(widget.person.id, limit: limit);
    _refresh();
  }

  Future<Uint8List?> _thumb(MediaItem m) => _thumbs.putIfAbsent(m.uri, () => widget.bridge.mediaThumb(m.uri, 'image', size: 360));

  void _open(List<MediaItem> list, int index) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PhotoViewer(bridge: widget.bridge, items: list, index: index, name: widget.person.name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final running = st?.running ?? false;
    final matches = st?.matches ?? const <MediaItem>[];
    final progress = (st != null && st.total > 0) ? st.done / st.total : null;
    return SiyaPage(
      title: widget.person.name,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SiyaCard(
              child: Column(
                children: [
                  if (running) ...[
                    LinearProgressIndicator(value: progress, color: SiyaColors.cyan, backgroundColor: Colors.white12),
                    const SizedBox(height: 10),
                    Text('Dhundh rahi hoon... ${st?.done ?? 0} / ${st?.total ?? 0}   (mili: ${matches.length})',
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 10),
                    SiyaButton(label: 'Rok do', outlined: true, onTap: () => widget.bridge.faceSearchCancel()),
                  ] else ...[
                    Text(
                      matches.isEmpty
                          ? 'Gallery mein is insaan ki photos dhundo'
                          : '${matches.length} photos mili',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    if ((st?.error ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(st!.error, style: const TextStyle(color: SiyaColors.bad, fontSize: 12.5)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: SiyaButton(label: 'Latest 300', icon: Icons.search, onTap: () => _start(300))),
                        const SizedBox(width: 10),
                        Expanded(child: SiyaButton(label: 'Zyada (1500)', outlined: true, onTap: () => _start(1500))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Text(running ? 'Photos aate hi yahan dikhengi' : 'Abhi koi result nahi',
                        style: TextStyle(color: Colors.white.withOpacity(0.45))),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
                    itemCount: matches.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _open(matches, i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FutureBuilder<Uint8List?>(
                          future: _thumb(matches[i]),
                          builder: (_, s) => s.data == null
                              ? const ColoredBox(color: Color(0xFF0A1826))
                              : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
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

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.bridge, required this.items, required this.index, required this.name});

  final SiyaBridge bridge;
  final List<MediaItem> items;
  final int index;
  final String name;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pc = PageController(initialPage: widget.index);
  late int _cur = widget.index;
  final Map<int, Future<Uint8List?>> _full = {};

  Future<Uint8List?> _load(int i) => _full.putIfAbsent(i, () => widget.bridge.mediaFull(widget.items[i].uri));

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.name}  ${_cur + 1}/${widget.items.length}', style: const TextStyle(fontSize: 16)),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _cur = i),
        itemBuilder: (_, i) => FutureBuilder<Uint8List?>(
          future: _load(i),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: SiyaColors.cyan));
            }
            if (s.data == null) return const Center(child: Text('Photo khul nahi payi', style: TextStyle(color: Colors.white54)));
            return InteractiveViewer(minScale: 1, maxScale: 5, child: Center(child: Image.memory(s.data!, fit: BoxFit.contain)));
          },
        ),
      ),
    );
  }
}
