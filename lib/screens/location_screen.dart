import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';

/// Full-Screen Edge-to-Edge Smart Location & Interactive Map
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final MapController _map = MapController();
  final TextEditingController _search = TextEditingController();
  LatLng _center = const LatLng(20.5937, 78.9629); // India fallback
  LatLng? _picked;
  String _name = '';
  String _mode = 'device';
  bool _busy = false;
  bool _ready = false;
  bool _satellite = false;

  Color get _accent => SiyaTheme.accent.value;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final s = await widget.bridge.getSettings();
      _mode = (s['loc_mode'] as String?) ?? 'device';
      final lat = ((s['loc_lat'] as num?) ?? 0).toDouble();
      final lng = ((s['loc_lng'] as num?) ?? 0).toDouble();
      _name = (s['loc_name'] as String?) ?? '';
      if (_mode == 'custom' && (lat != 0 || lng != 0)) {
        _picked = LatLng(lat, lng);
        _center = _picked!;
      } else {
        final d = await widget.bridge.getLocation();
        if (d != null) {
          _center = LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble());
          _name = (d['name'] as String?) ?? '';
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _useDevice() async {
    setState(() => _busy = true);
    try {
      var d = await widget.bridge.getLocation();
      if (d == null) {
        await widget.bridge.requestPermissions();
        d = await widget.bridge.getLocation();
      }
      if (!mounted) return;
      if (d == null) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location nahi mili. GPS on karo aur permission do'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final p = LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble());
      await widget.bridge.saveSettings({'loc_mode': 'device'});
      setState(() {
        _mode = 'device';
        _picked = null;
        _center = p;
        _name = (d!['name'] as String?) ?? '';
        _busy = false;
      });
      _map.move(p, 16);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setCustom(LatLng p, {String? name}) async {
    setState(() {
      _picked = p;
      _mode = 'custom';
      _name = name ?? '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
    });
    await widget.bridge.saveSettings({
      'loc_mode': 'custom',
      'loc_lat': p.latitude,
      'loc_lng': p.longitude,
      'loc_name': _name,
    });
  }

  Future<void> _doSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final r = await widget.bridge.searchPlace(q);
      if (!mounted) return;
      if (r == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Jagah nahi mili'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final p = LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble());
        _map.move(p, 15);
        await _setCustom(p, name: r['name'] as String?);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF131722),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Full-Screen Interactive Edge-to-Edge Map
          if (_ready)
            Positioned.fill(
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _picked ?? _center,
                  initialZoom: _picked != null || _mode == 'device' ? 15.5 : 5.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                  onTap: (_, p) => _setCustom(p),
                ),
                children: [
                  TileLayer(
                    urlTemplate: _satellite
                        ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.siya.ai',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _picked ?? _center,
                        width: 56,
                        height: 56,
                        alignment: Alignment.topCenter,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _accent.withOpacity(0.25),
                              ),
                            ),
                            Icon(
                              Icons.location_on_rounded,
                              size: 46,
                              color: _accent,
                              shadows: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Center(
              child: CircularProgressIndicator(color: _accent),
            ),

          // 2. Floating Top Transparent Glass Header & Search Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  // Back Button
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.88),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        color: _accent,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Search Address Field
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(Icons.search_rounded, color: _accent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _search,
                              style: const TextStyle(
                                color: Color(0xFF1E232F),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _doSearch(),
                              decoration: const InputDecoration(
                                hintText: 'Address ya jagah search karein...',
                                hintStyle: TextStyle(
                                  color: Color(0xFF8A7B85),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          if (_search.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Map / Satellite Toggle
                  InkWell(
                    onTap: () => setState(() => _satellite = !_satellite),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.88),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        _satellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
                        color: _accent,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Floating Bottom Glass Card (Address, Coordinates & Recenter Button)
          Positioned(
            left: 14,
            right: 14,
            bottom: bottomPadding + 14,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.95), width: 1.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Mode Icon / Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _mode == 'custom' ? Icons.touch_app_rounded : Icons.my_location_rounded,
                              size: 13,
                              color: _accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _mode == 'custom' ? 'Custom Location' : 'Live GPS Location',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Satellite/Street indicator
                      Text(
                        _satellite ? 'Satellite View' : 'Street Map',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7A6B75),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Location name / address
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _name.isEmpty ? 'Tap map to set position' : _name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2A1C25),
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Lat: ${(_picked ?? _center).latitude.toStringAsFixed(5)}, Lng: ${(_picked ?? _center).longitude.toStringAsFixed(5)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF8A7B85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Recenter Button
                      InkWell(
                        onTap: _useDevice,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _accent,
                                Color.lerp(_accent, const Color(0xFFFF4081), 0.4)!,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _accent.withOpacity(0.40),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Recenter',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 4. Loading overlay
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.35),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: CircularProgressIndicator(color: _accent),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
