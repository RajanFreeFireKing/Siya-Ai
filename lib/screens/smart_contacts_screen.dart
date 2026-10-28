import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';

class _SmartContactsSilkBackground extends StatelessWidget {
  const _SmartContactsSilkBackground({required this.primaryThemeColor});
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
            painter: _SmartContactsSilkPainter(primaryThemeColor),
            size: Size.infinite,
          ),
        ),
      );
}

class _SmartContactsSilkPainter extends CustomPainter {
  const _SmartContactsSilkPainter(this.accent);
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
          center: Offset(size.width * .85, size.height * .24),
          radius: size.width * .75,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);

    final ribbonPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 6; i++) {
      final y = size.height * (.06 + i * .18);
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
          accent.withOpacity(i.isEven ? .14 : .07),
          const Color(0xFFFF6EB0).withOpacity(.05),
          Colors.white.withOpacity(.02),
        ],
      ).createShader(
        Rect.fromLTWH(0, y - size.height * .18, size.width, size.height * .36),
      );
      canvas.drawPath(ribbon, ribbonPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SmartContactsSilkPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class SmartContactsScreen extends StatefulWidget {
  const SmartContactsScreen({super.key, required this.bridge});
  final SiyaBridge bridge;

  @override
  State<SmartContactsScreen> createState() => _SmartContactsScreenState();
}

class _SmartContactsScreenState extends State<SmartContactsScreen> {
  Color get _accent => SiyaTheme.accent;

  List<SmartContact> _contacts = [];
  bool _loading = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    try {
      final list = await widget.bridge.getSmartContacts();
      if (mounted) {
        setState(() {
          _contacts = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SmartContact> get _filteredContacts {
    if (_searchQuery.trim().isEmpty) return _contacts;
    final q = _searchQuery.trim().toLowerCase();
    return _contacts.where((c) {
      if (c.name.toLowerCase().contains(q)) return true;
      if (c.number.replaceAll(RegExp(r'[^0-9+]'), '').contains(q)) return true;
      for (final a in c.aliases) {
        if (a.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  Future<void> _directCall(String number, String name) async {
    try {
      final ok = await widget.bridge.directCall(number);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name ($number) par call lagane mein asafal raha.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Call error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteContact(SmartContact contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Contact hatayein?',
          style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2A1C25)),
        ),
        content: Text(
          'Kya aap "${contact.name.isNotEmpty ? contact.name : contact.number}" ko smart contacts se delete karna chahte hain?',
          style: const TextStyle(color: Color(0xFF5A4C56), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF7A6B75))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.bridge.deleteSmartContact(contact.id);
      _loadContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact delete ho gaya.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openAddEditBottomSheet([SmartContact? existing]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddEditContactSheet(
        bridge: widget.bridge,
        accent: _accent,
        contact: existing,
        onSaved: () {
          _loadContacts();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Color.alphaBlend(_accent.withOpacity(.045), const Color(0xFFFFF5FA)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEditBottomSheet(),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Add Smart Contact',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _SmartContactsSilkBackground(primaryThemeColor: _accent),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 88),
                    children: [
                      _buildTipBanner(),
                      const SizedBox(height: 14),
                      _buildSearchBar(),
                      const SizedBox(height: 16),
                      if (_loading)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Center(
                            child: CircularProgressIndicator(color: _accent),
                          ),
                        )
                      else if (_contacts.isEmpty)
                        _buildEmptyState()
                      else if (_filteredContacts.isEmpty)
                        _buildNoSearchResults()
                      else
                        ..._filteredContacts.map(_buildContactCard),
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
                  'Smart Contacts',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2A1C25),
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Voice Calling & Nicknames (${_contacts.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _openAddEditBottomSheet(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_accent, Color.lerp(_accent, Colors.white, 0.25)!],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_accent.withOpacity(0.2), _accent.withOpacity(0.08)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mic_none_rounded, color: _accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'AI Voice Calling Tip',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '100% Accuracy',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Yahan set kiye nicknames bolkar call karein: "Papa ko call lagao", "Mera dost ko call karo", "Jaan ko call karo". Siya bina confusion ke call lagayegi.',
                  style: TextStyle(
                    color: Color(0xFF5A4C56),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(fontSize: 14, color: Color(0xFF2A1C25), fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Naam, number ya nickname search karein...',
          hintStyle: TextStyle(fontSize: 13, color: const Color(0xFF7A6B75).withOpacity(0.7)),
          prefixIcon: Icon(Icons.search_rounded, color: _accent, size: 22),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  color: const Color(0xFF7A6B75),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.9)),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent.withOpacity(0.12),
            ),
            child: Icon(Icons.contact_phone_rounded, color: _accent, size: 36),
          ),
          const SizedBox(height: 18),
          const Text(
            'Koi Smart Contact nahi mila',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2A1C25),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Naya contact jodne ke liye niche button dabayein ya phonebook se import karein taaki Siya voice se unke nicknames pehchan sake.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6B5C67),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _openAddEditBottomSheet(),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Pehla Contact Add Karein'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: const Color(0xFF8A7B85).withOpacity(0.6)),
          const SizedBox(height: 12),
          Text(
            '"$_searchQuery" se koi contact match nahi hua',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2A1C25),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kripya koi doosra naam, number ya nickname search karein.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF7A6B75)),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(SmartContact c) {
    final initials = c.name.trim().isNotEmpty
        ? c.name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
        : '#';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.95), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Avatar, Name & Number, Actions (Call, Edit, Delete)
          Row(
            children: [
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _accent.withOpacity(0.24),
                      _accent.withOpacity(0.08),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: _accent.withOpacity(0.3), width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Name & Number
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name.isNotEmpty ? c.name : 'Bina Naam',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2A1C25),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.phone_rounded, size: 12, color: _accent.withOpacity(0.8)),
                        const SizedBox(width: 4),
                        Text(
                          c.number.isNotEmpty ? c.number : 'Number nahi hai',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF5A4C56).withOpacity(0.9),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Quick Actions: Call Button
              if (c.number.trim().isNotEmpty) ...[
                InkWell(
                  onTap: () => _directCall(c.number, c.name),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF2E7D32), size: 20),
                  ),
                ),
                const SizedBox(width: 6),
              ],

              // Edit Button
              InkWell(
                onTap: () => _openAddEditBottomSheet(c),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.edit_rounded, color: _accent, size: 18),
                ),
              ),
              const SizedBox(width: 6),

              // Delete Button
              InkWell(
                onTap: () => _deleteContact(c),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE53935), size: 18),
                ),
              ),
            ],
          ),

          // Nickname Chips Section
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.65),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accent.withOpacity(0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.label_outline_rounded, size: 13, color: _accent),
                    const SizedBox(width: 5),
                    Text(
                      'Voice Nicknames (${c.aliases.length})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (c.aliases.isEmpty)
                  InkWell(
                    onTap: () => _openAddEditBottomSheet(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '+ Nickname add karein (Papa, Dost, etc.)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _accent.withOpacity(0.85),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: c.aliases.map((alias) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _accent.withOpacity(0.14),
                              _accent.withOpacity(0.06),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _accent.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🏷️ ', style: TextStyle(fontSize: 10)),
                            Text(
                              alias,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2A1C25),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEditContactSheet extends StatefulWidget {
  const _AddEditContactSheet({
    required this.bridge,
    required this.accent,
    this.contact,
    required this.onSaved,
  });

  final SiyaBridge bridge;
  final Color accent;
  final SmartContact? contact;
  final VoidCallback onSaved;

  @override
  State<_AddEditContactSheet> createState() => _AddEditContactSheetState();
}

class _AddEditContactSheetState extends State<_AddEditContactSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _numberCtrl;
  late final TextEditingController _aliasCtrl;
  final List<String> _aliases = [];
  bool _saving = false;

  final List<String> _suggestedNicknames = const [
    'Papa',
    'Mummy',
    'Bhai',
    'Behan',
    'Dost',
    'Mera dost',
    'Ghar',
    'Office',
    'Babu',
    'Jaan',
    'Shona',
    'Sir',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.contact?.name ?? '');
    _numberCtrl = TextEditingController(text: widget.contact?.number ?? '');
    _aliasCtrl = TextEditingController();
    if (widget.contact != null) {
      _aliases.addAll(widget.contact!.aliases);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  void _addAlias([String? custom]) {
    final text = (custom ?? _aliasCtrl.text).trim();
    if (text.isEmpty) return;
    final parts = text.split(RegExp(r'[,;\n]'));
    setState(() {
      for (final p in parts) {
        final clean = p.trim();
        if (clean.isNotEmpty && !_aliases.contains(clean)) {
          _aliases.add(clean);
        }
      }
    });
    if (custom == null) {
      _aliasCtrl.clear();
    }
  }

  Future<void> _pickFromPhonebook() async {
    try {
      final picked = await widget.bridge.pickContact();
      if (picked != null) {
        final name = picked['name']?.trim() ?? '';
        final number = picked['number']?.trim() ?? '';
        setState(() {
          if (number.isNotEmpty) _numberCtrl.text = number;
          if (_nameCtrl.text.trim().isEmpty && name.isNotEmpty) {
            _nameCtrl.text = name;
          }
          if (name.isNotEmpty && !_aliases.contains(name)) {
            _aliases.add(name);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Phonebook error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final number = _numberCtrl.text.trim();

    if (name.isEmpty && number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kripya contact ka naam ya number likhein.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_aliasCtrl.text.trim().isNotEmpty) {
      _addAlias();
    }

    setState(() => _saving = true);
    try {
      final toSave = SmartContact(
        id: widget.contact?.id ?? '',
        name: name,
        number: number,
        aliases: _aliases,
      );
      await widget.bridge.saveSmartContact(toSave);
      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Smart Contact "${name.isNotEmpty ? name : number}" save ho gaya!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.contact != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: widget.accent.withOpacity(0.16),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top drag pill
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6C8D1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sheet Title
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.accent.withOpacity(0.2),
                            widget.accent.withOpacity(0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isEdit ? Icons.edit_note_rounded : Icons.person_add_alt_1_rounded,
                        color: widget.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit ? 'Contact Edit Karein' : 'Naya Smart Contact',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2A1C25),
                            ),
                          ),
                          Text(
                            'Name, number aur voice nicknames map karein',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                      color: const Color(0xFF7A6B75),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Primary Name Field
                _fieldLabel('Primary Name (Asli Naam)'),
                const SizedBox(height: 6),
                _inputField(
                  controller: _nameCtrl,
                  hintText: 'Jaise: Ramesh Kumar ya Papa',
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 16),

                // Mobile Number Field
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _fieldLabel('Mobile Number'),
                    InkWell(
                      onTap: _pickFromPhonebook,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: widget.accent.withOpacity(0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.import_contacts_rounded, size: 14, color: widget.accent),
                            const SizedBox(width: 4),
                            Text(
                              'Phonebook 📱',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: widget.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _inputField(
                  controller: _numberCtrl,
                  hintText: '+91 9876543210',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 20),

                // Voice Nicknames Section
                _fieldLabel('Voice Nicknames / Aliases (Bolne Wale Naam)'),
                const SizedBox(height: 2),
                Text(
                  'Jab user bole "Papa ko call lagao" ya "Mera dost ko call karo" toh ye nicknames match honge.',
                  style: TextStyle(
                    fontSize: 11,
                    color: const Color(0xFF6B5C67).withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 8),

                // Alias Input Field with '+' Button
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F6F8),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: widget.accent.withOpacity(0.2)),
                        ),
                        child: TextField(
                          controller: _aliasCtrl,
                          onSubmitted: (_) => _addAlias(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2A1C25),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Jaise: Papa, Dost, Babu, Jaan...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: const Color(0xFF7A6B75).withOpacity(0.7),
                            ),
                            prefixIcon: Icon(Icons.label_outline_rounded, color: widget.accent, size: 20),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _addAlias(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                      child: const Text('Add +', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Added Chips
                if (_aliases.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _aliases.map((alias) {
                      return Chip(
                        label: Text(
                          '🏷️ $alias',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2A1C25),
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        deleteIconColor: const Color(0xFFE53935),
                        onDeleted: () {
                          setState(() => _aliases.remove(alias));
                        },
                        backgroundColor: widget.accent.withOpacity(0.12),
                        side: BorderSide(color: widget.accent.withOpacity(0.28)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                // Quick suggestions
                _fieldLabel('Quick Suggestions (Tap karke add karein):'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _suggestedNicknames.map((sug) {
                    final isAdded = _aliases.contains(sug);
                    return InkWell(
                      onTap: isAdded ? null : () => _addAlias(sug),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isAdded
                              ? widget.accent.withOpacity(0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isAdded
                                ? widget.accent.withOpacity(0.15)
                                : widget.accent.withOpacity(0.28),
                          ),
                        ),
                        child: Text(
                          isAdded ? '✓ $sug' : '+ $sug',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isAdded
                                ? const Color(0xFF9E8E98)
                                : widget.accent,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Save Action Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 5,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            isEdit ? 'Update Smart Contact ✨' : 'Save Smart Contact ✨',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xFF2A1C25),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.accent.withOpacity(0.22)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF2A1C25),
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            fontSize: 13,
            color: const Color(0xFF7A6B75).withOpacity(0.7),
          ),
          prefixIcon: Icon(icon, color: widget.accent, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}
