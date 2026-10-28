import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/siya_ui.dart';

/// Wallpaper: photo / video chuno (sirf select hota hai), neeche preview dikhta hai,
/// "Save karo" dabane par hi wallpaper lagti hai.
class WallpaperScreen extends StatefulWidget {
  const WallpaperScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<WallpaperScreen> createState() => _WallpaperScreenState();
}

class _WallpaperScreenState extends State<WallpaperScreen> {
  String _tab = 'image'; // image | video
  List<MediaItem> _items = [];
  bool _loading = true;
  bool _denied = false;
  bool _sound = false;
  double _dim = 0.35;
  String _curType = 'none';

  // select hui (abhi lagi nahi)
  MediaItem? _selItem;
  String? _selPath; // upload ki hui file
  String _selKind = 'image';
  bool _saving = false;
  bool _justSaved = false;

  final Map<String, Future<Uint8List?>> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadMedia();
  }

  bool get _hasSel => _selItem != null || _selPath != null;

  Future<void> _loadSettings() async {
    final s = await widget.bridge.getSettings();
    if (!mounted) return;
    setState(() {
      _sound = (s['wallpaper_sound'] as bool?) ?? false;
      _dim = ((s['wallpaper_dim'] as num?) ?? 0.35).toDouble();
      _curType = (s['wallpaper_type'] as String?) ?? 'none';
    });
  }

  Future<void> _loadMedia() async {
    setState(() => _loading = true);
    var l = await widget.bridge.listMedia(_tab);
    if (l.isEmpty) {
      final left = await widget.bridge.requestPermissions();
      l = await widget.bridge.listMedia(_tab);
      _denied = l.isEmpty && left > 0;
    } else {
      _denied = false;
    }
    if (!mounted) return;
    setState(() {
      _items = l;
      _loading = false;
    });
  }

  Future<Uint8List?> _thumb(MediaItem m, {int size = 320}) =>
      _thumbs.putIfAbsent('${m.uri}@$size', () => widget.bridge.mediaThumb(m.uri, m.kind, size: size));

  void _select(MediaItem m) => setState(() {
        _selItem = m;
        _selPath = null;
        _selKind = m.kind;
        _justSaved = false;
      });

  Future<void> _upload() async {
    final path = await widget.bridge.pickMedia(_tab);
    if (path == null || !mounted) return;
    setState(() {
      _selPath = path;
      _selItem = null;
      _selKind = _tab;
      _justSaved = false;
    });
  }

  Future<void> _save() async {
    if (!_hasSel || _saving) return;
    setState(() => _saving = true);
    final out = await widget.bridge.setWallpaper(uri: _selItem?.uri, path: _selPath, kind: _selKind);
    if (!mounted) return;
    setState(() => _saving = false);
    if (out == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wallpaper save nahi hui, dobara try karo')));
      return;
    }
    setState(() {
      _curType = _selKind;
      _justSaved = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wallpaper save ho gayi \u2713  Home screen par dekho')));
  }

  Future<void> _saveOpts() => widget.bridge.saveSettings({'wallpaper_sound': _sound, 'wallpaper_dim': _dim});

  @override
  Widget build(BuildContext context) {
    return SiyaPage(
      title: 'Wallpaper',
      actions: [
        if (_curType != 'none')
          SiyaIconBtn(
            icon: Icons.layers_clear_outlined,
            danger: true,
            onTap: () async {
              await widget.bridge.clearWallpaper();
              if (mounted) setState(() => _curType = 'none');
            },
          ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                _tabBtn('image', 'Photos', Icons.image_outlined),
                const SizedBox(width: 10),
                _tabBtn('video', 'Live (video)', Icons.movie_outlined),
                const SizedBox(width: 10),
                SiyaIconBtn(icon: Icons.upload_file_outlined, onTap: _upload),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SiyaCard(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.brightness_6_outlined, color: SiyaTheme.accent.value, size: 20),
                      const SizedBox(width: 10),
                      const Text('Dim', style: TextStyle(color: Color(0xFF2A1C25))),
                      Expanded(
                        child: Slider(
                          value: _dim,
                          min: 0,
                          max: 0.8,
                          activeColor: SiyaTheme.accent.value,
                          onChanged: (v) => setState(() => _dim = v),
                          onChangeEnd: (_) => _saveOpts(),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.volume_up_outlined, color: SiyaTheme.accent.value, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Live wallpaper ki awaaz', style: TextStyle(color: Color(0xFF2A1C25)))),
                      Switch(
                        value: _sound,
                        activeColor: SiyaTheme.accent.value,
                        activeTrackColor: SiyaTheme.accent.value.withOpacity(0.35),
                        onChanged: (v) {
                          setState(() => _sound = v);
                          _saveOpts();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: SiyaTheme.accent.value))
                : _items.isEmpty
                    ? _empty()
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 0.62,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _tile(_items[i]),
                      ),
          ),
          _saveBar(),
        ],
      ),
    );
  }

  Widget _saveBar() {
    final accent = SiyaTheme.accent.value;
    final status = _curType == 'none' ? 'Abhi koi wallpaper nahi' : (_curType == 'video' ? 'Abhi: Live wallpaper lagi hai' : 'Abhi: Photo wallpaper lagi hai');
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          border: Border(top: BorderSide(color: accent.withOpacity(0.25))),
          boxShadow: [
            BoxShadow(color: accent.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, -4)),
          ],
        ),
        child: _hasSel
            ? Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(width: 52, height: 70, child: _previewThumb()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_justSaved ? 'Save ho gayi \u2713' : 'Select ki hui ${_selKind == 'video' ? 'video' : 'photo'}',
                            style: TextStyle(
                                color: _justSaved ? const Color(0xFF00C853) : const Color(0xFF2A1C25), fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(_justSaved ? 'Home screen par lag gayi' : 'Abhi lagi nahi - Save dabao',
                            style: const TextStyle(color: Color(0xFF6F6470), fontSize: 12)),
                      ],
                    ),
                  ),
                  SiyaButton(
                    label: _saving ? 'Saving...' : (_justSaved ? 'Saved' : 'Save karo'),
                    icon: _justSaved ? Icons.check : Icons.save_alt,
                    onTap: (_saving || _justSaved) ? null : _save,
                  ),
                ],
              )
            : Text('$status. Photo chuno, phir Save dabao.',
                textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6F6470), fontSize: 13)),
      ),
    );
  }

  Widget _previewThumb() {
    if (_selPath != null && _selKind == 'image') {
      return Image.file(File(_selPath!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEFE8ED)));
    }
    if (_selItem != null) {
      return FutureBuilder<Uint8List?>(
        future: _thumb(_selItem!, size: 200),
        builder: (_, s) => s.data == null ? const ColoredBox(color: Color(0xFFEFE8ED)) : Image.memory(s.data!, fit: BoxFit.cover),
      );
    }
    return const ColoredBox(color: Color(0xFFEFE8ED), child: Icon(Icons.movie_outlined, color: Color(0xFF6F6470)));
  }

  Widget _tile(MediaItem m) {
    final accent = SiyaTheme.accent.value;
    final sel = _selItem?.uri == m.uri;
    return GestureDetector(
      onTap: () => _select(m),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: sel ? accent : Colors.transparent, width: 2.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List?>(
                future: _thumb(m),
                builder: (_, s) => s.data == null
                    ? const ColoredBox(color: Color(0xFFEFE8ED))
                    : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
              ),
              if (m.kind == 'video')
                const Positioned(right: 6, bottom: 6, child: Icon(Icons.play_circle_fill, color: Colors.white, size: 22)),
              if (sel)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 15, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final accent = SiyaTheme.accent.value;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, color: accent.withOpacity(0.4), size: 48),
            const SizedBox(height: 12),
            Text(_denied ? 'Gallery ki permission chahiye' : 'Gallery mein kuch nahi mila',
                style: const TextStyle(color: Color(0xFF6F6470), fontSize: 15)),
            const SizedBox(height: 16),
            SiyaButton(
              label: _denied ? 'Permission do' : 'Upload karo',
              icon: _denied ? Icons.lock_open : Icons.upload_file_outlined,
              onTap: _denied ? _loadMedia : _upload,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(String k, String label, IconData icon) {
    final accent = SiyaTheme.accent.value;
    final sel = _tab == k;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_tab == k) return;
          setState(() => _tab = k);
          _loadMedia();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: sel ? LinearGradient(colors: [accent, Color.lerp(accent, Colors.white, 0.45)!]) : null,
            color: sel ? null : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(sel ? 0 : 0.25)),
            boxShadow: [
              BoxShadow(color: accent.withOpacity(sel ? 0.25 : 0.05), blurRadius: 10),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: sel ? Colors.white : const Color(0xFF2A1C25), size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: sel ? Colors.white : const Color(0xFF2A1C25),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
