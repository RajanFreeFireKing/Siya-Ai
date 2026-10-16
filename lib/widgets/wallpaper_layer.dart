import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Home screen ke hologram ke peeche ki wallpaper: photo ya video (live wallpaper, sound ke saath bhi).
class WallpaperLayer extends StatefulWidget {
  const WallpaperLayer({
    super.key,
    required this.type, // none | image | video
    required this.path,
    required this.sound,
    required this.dim,
  });

  final String type;
  final String path;
  final bool sound;
  final double dim;

  @override
  State<WallpaperLayer> createState() => _WallpaperLayerState();
}

class _WallpaperLayerState extends State<WallpaperLayer> with WidgetsBindingObserver {
  VideoPlayerController? _vc;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void didUpdateWidget(covariant WallpaperLayer old) {
    super.didUpdateWidget(old);
    if (old.type != widget.type || old.path != widget.path) {
      _setup();
    } else if (old.sound != widget.sound) {
      _vc?.setVolume(widget.sound ? 1.0 : 0.0);
    }
  }

  Future<void> _setup() async {
    final old = _vc;
    _vc = null;
    _ready = false;
    if (mounted) setState(() {});
    await old?.dispose();
    if (widget.type != 'video' || widget.path.isEmpty || !File(widget.path).existsSync()) return;
    final c = VideoPlayerController.file(File(widget.path));
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(widget.sound ? 1.0 : 0.0);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _vc = c;
        _ready = true;
      });
    } catch (_) {
      await c.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = _vc;
    if (c == null || !_ready) return;
    if (s == AppLifecycleState.resumed) {
      c.play();
    } else if (s == AppLifecycleState.paused) {
      c.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget? bg;
    if (widget.type == 'image' && widget.path.isNotEmpty && File(widget.path).existsSync()) {
      bg = Image.file(File(widget.path), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox());
    } else if (widget.type == 'video' && _ready && _vc != null) {
      final v = _vc!.value;
      bg = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: v.size.width, height: v.size.height, child: VideoPlayer(_vc!)),
      );
    }
    if (bg == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        bg,
        // hologram saaf dikhe isliye halka dim
        ColoredBox(color: Colors.black.withOpacity(widget.dim.clamp(0.0, 0.85))),
      ],
    );
  }
}
