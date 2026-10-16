import 'dart:io';

import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/siya_ui.dart';
import 'face_search_screen.dart';

/// User Data: khud ki / ghar walon ki photo + naam. Siya inhe camera mein pehchanti hai.
/// Sab kuch sirf is phone mein save hota hai.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  List<Person> _people = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await widget.bridge.getPeople();
    if (!mounted) return;
    setState(() {
      _people = l;
      _loading = false;
    });
  }

  Future<void> _edit([Person? p]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF06182A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _PersonSheet(bridge: widget.bridge, person: p),
    );
    _load();
  }

  Future<void> _delete(Person p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: SiyaColors.card,
        title: Text('${p.name} hatao?', style: const TextStyle(color: Colors.white)),
        content: const Text('Photo aur naam phone se hat jayega.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nahi')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hatao', style: TextStyle(color: SiyaColors.bad))),
        ],
      ),
    );
    if (ok == true) {
      await widget.bridge.deletePerson(p.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SiyaPage(
      title: 'User Data',
      actions: [SiyaIconBtn(icon: Icons.person_add_alt_1_outlined, onTap: () => _edit())],
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: SiyaColors.cyan))
          : _people.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.face_retouching_natural, color: Colors.white38, size: 54),
                        const SizedBox(height: 12),
                        const Text(
                          'Apni ya ghar walon ki photo aur naam daalo.\nSiya camera mein unhe pehchanegi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, height: 1.4),
                        ),
                        const SizedBox(height: 18),
                        SiyaButton(label: 'Add karo', icon: Icons.add, onTap: () => _edit()),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _people.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = _people[i];
                    return GestureDetector(
                      onTap: () => _edit(p),
                      child: SiyaCard(
                        child: Row(
                          children: [
                            _avatar(p.photo, p.name, 56),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(p.relation, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5)),
                                ],
                              ),
                            ),
                            if (p.photo.isNotEmpty)
                              SiyaIconBtn(
                                icon: Icons.image_search_outlined,
                                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (_) => FaceSearchScreen(bridge: widget.bridge, person: p))),
                              ),
                            const SizedBox(width: 8),
                            SiyaIconBtn(icon: Icons.delete_outline, danger: true, onTap: () => _delete(p)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

Widget _avatar(String photo, String name, double size) {
  final has = photo.isNotEmpty && File(photo).existsSync();
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: SiyaColors.cyan.withOpacity(0.6), width: 1.5),
      gradient: has ? null : const LinearGradient(colors: [SiyaColors.cyan, SiyaColors.purple]),
      image: has ? DecorationImage(image: FileImage(File(photo)), fit: BoxFit.cover) : null,
    ),
    alignment: Alignment.center,
    child: has
        ? null
        : Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w800)),
  );
}

class _PersonSheet extends StatefulWidget {
  const _PersonSheet({required this.bridge, this.person});

  final SiyaBridge bridge;
  final Person? person;

  @override
  State<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<_PersonSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.person?.name ?? '');
  late String _relation = widget.person?.relation ?? 'me';
  String? _newPhoto;
  bool _saving = false;

  static const _rels = {'me': 'Main', 'family': 'Ghar wala', 'friend': 'Dost', 'other': 'Anya'};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final p = await widget.bridge.pickMedia('image');
    if (p != null && mounted) setState(() => _newPhoto = p);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await widget.bridge.savePerson(
      id: widget.person?.id,
      name: _name.text.trim(),
      relation: _relation,
      photo: _newPhoto,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final photo = _newPhoto ?? widget.person?.photo ?? '';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _pick,
            child: Stack(
              children: [
                _avatar(photo, _name.text, 104),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(color: SiyaColors.cyan, shape: BoxShape.circle),
                    child: const Icon(Icons.photo_camera_outlined, color: Colors.black, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Saaf, seedhe chehre wali photo behtar rehti hai',
              style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11.5)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: siyaInput('Naam', Icons.person_outline),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _rels.entries.map((e) {
              final sel = _relation == e.key;
              return ChoiceChip(
                label: Text(e.value),
                selected: sel,
                onSelected: (_) => setState(() => _relation = e.key),
                selectedColor: SiyaColors.cyan.withOpacity(0.35),
                backgroundColor: const Color(0xFF071826),
                labelStyle: const TextStyle(color: Colors.white),
                side: BorderSide(color: SiyaColors.cyan.withOpacity(0.35)),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: SiyaButton(label: _saving ? 'Saving...' : 'Save', onTap: _saving ? null : _save),
          ),
        ],
      ),
    );
  }
}
