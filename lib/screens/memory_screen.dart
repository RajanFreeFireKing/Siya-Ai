import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import 'people_screen.dart';

/// AI Data: Siya ki poori yaaddaasht - chat history (date + time ke saath), facts, search, export.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

enum _Filter { all, you, siya }

class _MemoryScreenState extends State<MemoryScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  MemoryData _data = const MemoryData([], [], 0);
  bool _loading = true;
  bool _factsOpen = false;
  _Filter _filter = _Filter.all;
  Timer? _timer;
  bool _firstScrollDone = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Live baatcheet chal rahi ho to history apne aap update hoti rahe
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final d = await widget.bridge.getMemory();
    if (!mounted) return;
    final grew = d.messages.length != _data.messages.length;
    setState(() {
      _data = d;
      _loading = false;
    });
    if ((!_firstScrollDone && d.messages.isNotEmpty) || (silent && grew && _nearBottom())) {
      _firstScrollDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  bool _nearBottom() =>
      !_scroll.hasClients || (_scroll.position.maxScrollExtent - _scroll.offset) < 160;

  List<MemoryMsg> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _data.messages.where((m) {
      if (_filter == _Filter.you && !m.isUser) return false;
      if (_filter == _Filter.siya && m.isUser) return false;
      if (q.isNotEmpty && !m.text.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: SiyaColors.card,
        title: const Text('Saara data hatayein?'),
        content: const Text('Siya ki poori chat history aur yaad ki hui baatein hamesha ke liye delete ho jayengi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nahi')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Haan, hata do', style: TextStyle(color: SiyaColors.bad)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.bridge.clearMemory();
      _firstScrollDone = false;
      await _load();
    }
  }

  Future<void> _copy() async {
    await widget.bridge.copyMemory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Poori chat copy ho gayi')));
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    final days = _data.messages.map((m) => m.day).toSet().length;

    return Scaffold(
      backgroundColor: SiyaColors.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF06182A), Color(0xFF020A14)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              _stats(days),
              _searchBar(),
              _filters(),
              if (_data.facts.isNotEmpty) _factsCard(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: SiyaColors.cyan))
                    : list.isEmpty
                        ? _empty()
                        : RefreshIndicator(
                            color: SiyaColors.cyan,
                            backgroundColor: SiyaColors.card,
                            onRefresh: _load,
                            child: _messages(list),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            _iconBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.of(context).pop()),
            const SizedBox(width: 14),
            Expanded(
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(colors: [SiyaColors.cyanSoft, SiyaColors.violet]).createShader(r),
                child: const Text('AI Data', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              ),
            ),
            _iconBtn(Icons.face_outlined, () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => PeopleScreen(bridge: widget.bridge)))),
            const SizedBox(width: 8),
            _iconBtn(Icons.copy_all_outlined, _copy),
            const SizedBox(width: 8),
            _iconBtn(Icons.delete_outline, _clear, danger: true),
          ],
        ),
      );

  Widget _iconBtn(IconData icon, VoidCallback onTap, {bool danger = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF071826),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: (danger ? SiyaColors.bad : SiyaColors.cyan).withOpacity(0.6)),
          ),
          child: Icon(icon, color: danger ? SiyaColors.bad : Colors.white, size: 20),
        ),
      );

  Widget _stats(int days) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            _stat('Messages', '${_data.total}', Icons.chat_bubble_outline),
            const SizedBox(width: 10),
            _stat('Din', '$days', Icons.calendar_today_outlined),
            const SizedBox(width: 10),
            _stat('Facts', '${_data.facts.length}', Icons.bookmark_outline),
          ],
        ),
      );

  Widget _stat(String label, String value, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: SiyaColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SiyaColors.cyan.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: SiyaColors.cyanSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Chat mein dhundo...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
            prefixIcon: Icon(Icons.search, color: SiyaColors.cyanSoft.withOpacity(0.8)),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    onPressed: () => setState(_search.clear),
                  ),
            filled: true,
            fillColor: const Color(0xFF071420),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      );

  Widget _filters() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Row(
          children: [
            _chip('Sab', _Filter.all),
            const SizedBox(width: 8),
            _chip('Aap', _Filter.you),
            const SizedBox(width: 8),
            _chip('Siya', _Filter.siya),
          ],
        ),
      );

  Widget _chip(String label, _Filter f) {
    final sel = _filter == f;
    return GestureDetector(
      onTap: () => setState(() => _filter = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          gradient: sel ? const LinearGradient(colors: [SiyaColors.cyan, SiyaColors.purple]) : null,
          color: sel ? null : const Color(0xFF071420),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SiyaColors.cyan.withOpacity(sel ? 0 : 0.25)),
        ),
        child: Text(label, style: TextStyle(color: Colors.white, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
      ),
    );
  }

  Widget _factsCard() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Container(
          decoration: BoxDecoration(
            color: SiyaColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SiyaColors.purple.withOpacity(0.35)),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _factsOpen = !_factsOpen),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      const Icon(Icons.bookmark_added_outlined, size: 18, color: SiyaColors.violet),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Siya ko yaad hai (${_data.facts.length})',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                      Icon(_factsOpen ? Icons.expand_less : Icons.expand_more, color: Colors.white54),
                    ],
                  ),
                ),
              ),
              if (_factsOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final f in _data.facts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $f', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 56, color: SiyaColors.cyanSoft.withOpacity(0.5)),
              const SizedBox(height: 14),
              Text(
                _data.messages.isEmpty
                    ? 'Abhi koi chat history nahi hai.\nSiya se baat karo, yahan sab save hoga.'
                    : 'Koi message nahi mila.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.6), height: 1.4),
              ),
            ],
          ),
        ),
      );

  Widget _messages(List<MemoryMsg> list) {
    final items = <Widget>[];
    String? lastDay;
    for (final m in list) {
      if (m.day != lastDay) {
        lastDay = m.day;
        items.add(_dayHeader(m.day));
      }
      items.add(_bubble(m));
    }
    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: items,
    );
  }

  Widget _dayHeader(String day) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0B2236),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(day, style: TextStyle(color: SiyaColors.cyanSoft.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget _bubble(MemoryMsg m) {
    final user = m.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
        decoration: BoxDecoration(
          gradient: user
              ? const LinearGradient(colors: [Color(0xFF0E5E78), Color(0xFF1B4FA8)])
              : const LinearGradient(colors: [Color(0xFF241A4F), Color(0xFF3B2478)]),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 4),
            bottomRight: Radius.circular(user ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(user ? 'Aap' : 'Siya',
                style: TextStyle(
                  color: user ? SiyaColors.cyanSoft : SiyaColors.violet,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 2),
            _highlight(m.text),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              child: Text(m.clock, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _highlight(String text) {
    final q = _search.text.trim();
    const base = TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35);
    if (q.isEmpty) return SelectableText(text, style: base);
    final lower = text.toLowerCase();
    final ql = q.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final j = lower.indexOf(ql, i);
      if (j < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      if (j > i) spans.add(TextSpan(text: text.substring(i, j)));
      spans.add(TextSpan(
        text: text.substring(j, j + ql.length),
        style: const TextStyle(backgroundColor: Color(0x8822D3EE), fontWeight: FontWeight.w700),
      ));
      i = j + ql.length;
    }
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }
}
