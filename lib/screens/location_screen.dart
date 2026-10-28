import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/siya_ui.dart';

/// Location map (OpenStreetMap): phone ki location dekho, kuch bhi search karo, kahin bhi tap karke
/// location set karo. "Phone ki location" mode mein Siya asli GPS use karti hai.
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  LatLng _center = const LatLng(20.5937, 78.9629); // India
  LatLng? _picked;
  String _name = '';
  String _mode = 'device';
  bool _busy = false;
  bool _ready = false;
  bool _satellite = true;
  double _mapH = 340; // neeche ke handle se chhota / bada

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
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _useDevice() async {
    setState(() => _busy = true);
    var d = await widget.bridge.getLocation();
    if (d == null) {
      await widget.bridge.requestPermissions();
      d = await widget.bridge.getLocation();
    }
    if (!mounted) return;
    if (d == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Location nahi mili. GPS on karo aur permission do')));
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
    _map.move(p, 15);
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jagah nahi mili')));
      } else {
        final p = LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble());
        _map.move(p, 14);
        await _setCustom(p, name: r['name'] as String?);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = SiyaTheme.accent.value;
    return SiyaPage(
      title: 'Location',
      child: !_ready
          ? Center(child: CircularProgressIndicator(color: accent))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          style: const TextStyle(color: Color(0xFF1E232F)),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _doSearch(),
                          decoration: siyaInput('Kahin ka bhi naam search karo', Icons.search),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SiyaIconBtn(icon: Icons.my_location, onTap: _useDevice),
                    ],
                  ),
                ),
                SizedBox(
                  height: _mapH,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _map,
                            options: MapOptions(
                              initialCenter: _center,
                              initialZoom: _picked != null || _mode == 'device' ? 14 : 4.5,
                              onTap: (_, p) => _setCustom(p),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: _satellite
                                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.siya.ai',
                              ),
                              MarkerLayer(markers: [
                                Marker(
                                  point: _picked ?? _center,
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.topCenter,
                                  child: Icon(Icons.location_on,
                                      size: 44, color: accent),
                                ),
                              ]),
                            ],
                          ),
                          Positioned(
                            top: 10,
                            left: 10,
                            child: GestureDetector(
                              onTap: () => setState(() => _satellite = !_satellite),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: accent.withOpacity(0.35)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(_satellite ? Icons.map_outlined : Icons.satellite_alt, size: 16, color: accent),
                                  const SizedBox(width: 6),
                                  Text(_satellite ? 'Map' : 'Satellite', style: const TextStyle(color: Color(0xFF2A1C25), fontSize: 12.5, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ),
                          ),
                          if (_busy)
                            Positioned.fill(
                              child: const ColoredBox(
                                color: Color(0x33000000),
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) => setState(() => _mapH = (_mapH + d.delta.dy).clamp(140.0, MediaQuery.of(context).size.height * 0.7)),
                  child: SizedBox(
                    height: 30,
                    child: Center(
                      child: Container(width: 64, height: 5, decoration: BoxDecoration(color: accent.withOpacity(0.4), borderRadius: BorderRadius.circular(4))),
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: SiyaCard(
                    child: Row(
                      children: [
                        Icon(_mode == 'custom' ? Icons.push_pin_outlined : Icons.gps_fixed,
                            color: accent, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_mode == 'custom' ? 'Aapki chuni hui location' : 'Phone ki asli location',
                                  style: const TextStyle(color: Color(0xFF2A1C25), fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(_name.isEmpty ? 'Map par tap karke set karo' : _name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFF6F6470), fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
