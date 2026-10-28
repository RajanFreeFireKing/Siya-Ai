import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/siya_ui.dart';
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Saara data hatayein?', style: TextStyle(color: Color(0xFF2A1C25), fontWeight: FontWeight.w700)),
        content: const Text(
          'Siya ki poori chat history aur yaad ki hui baatein hamesha ke liye delete ho jayengi.',
          style: TextStyle(color: Color(0xFF6F6470)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Nahi', style: TextStyle(color: Color(0xFF6F6470))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Haan, hata do', style: TextStyle(color: SiyaColors.bad, fontWeight: FontWeight.w700)),
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

    return ValueListenableBuilder<Color>(
      valueListenable: SiyaTheme.accent,
      builder: (context, accent, _) {
        return SiyaPage(
          title: 'AI Data',
          actions: [
            SiyaIconBtn(
              icon: Icons.face_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => PeopleScreen(bridge: widget.bridge)),
              ),
            ),
            const SizedBox(width: 8),
            SiyaIconBtn(icon: Icons.copy_all_outlined, onTap: _copy),
            const SizedBox(width: 8),
            SiyaIconBtn(icon: Icons.delete_outline, onTap: _clear, danger: true),
          ],
          child: Column(
            children: [
              _stats(days, accent),
              _searchBar(accent),
              _filters(accent),
              if (_data.facts.isNotEmpty) _factsCard(accent),
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator(color: accent))
                    : list.isEmpty
                        ? _empty(accent)
                        : RefreshIndicator(
                            color: accent,
                            backgroundColor: Colors.white,
                            onRefresh: _load,
                            child: _messages(list, accent),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stats(int days, Color accent) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            _stat('Messages', '${_data.total}', Icons.chat_bubble_outline, accent),
            const SizedBox(width: 10),
            _stat('Din', '$days', Icons.calendar_today_outlined, accent),
            const SizedBox(width: 10),
            _stat('Facts', '${_data.facts.length}', Icons.bookmark_outline, accent),
          ],
        ),
      );

  Widget _stat(String label, String value, IconData icon, Color accent) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: const TextStyle(color: Color(0xFF2A1C25), fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(label, style: const TextStyle(color: Color(0xFF6F6470), fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _searchBar(Color accent) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: Color(0xFF2A1C25)),
          decoration: InputDecoration(
            hintText: 'Chat mein dhundo...',
            hintStyle: const TextStyle(color: Color(0xFF9E929E)),
            prefixIcon: Icon(Icons.search, color: accent),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF6F6470), size: 18),
                    onPressed: () => setState(_search.clear),
                  ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.92),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: accent.withOpacity(0.2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: accent, width: 1.5)),
          ),
        ),
      );

  Widget _filters(Color accent) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            _chip('Sab', _Filter.all, accent),
            const SizedBox(width: 8),
            _chip('Aap', _Filter.you, accent),
            const SizedBox(width: 8),
            _chip('Siya', _Filter.siya, accent),
          ],
        ),
      );

  Widget _chip(String label, _Filter f, Color accent) {
    final sel = _filter == f;
    return GestureDetector(
      onTap: () => setState(() => _filter = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? accent : Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(sel ? 0 : 0.25)),
          boxShadow: [
            if (sel)
              BoxShadow(
                color: accent.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : const Color(0xFF2A1C25),
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _factsCard(Color accent) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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
                      Icon(Icons.bookmark_added_outlined, size: 18, color: accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Siya ko yaad hai (${_data.facts.length})',
                          style: const TextStyle(color: Color(0xFF2A1C25), fontWeight: FontWeight.w700),
                        ),
                      ),
                      Icon(_factsOpen ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF6F6470)),
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
                          child: Text('• $f', style: const TextStyle(color: Color(0xFF6F6470), fontSize: 13)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _empty(Color accent) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 56, color: accent.withOpacity(0.5)),
              const SizedBox(height: 14),
              Text(
                _data.messages.isEmpty
                    ? 'Abhi koi chat history nahi hai.\nSiya se baat karo, yahan sab save hoga.'
                    : 'Koi message nahi mila.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6F6470), height: 1.4),
              ),
            ],
          ),
        ),
      );

  Widget _messages(List<MemoryMsg> list, Color accent) {
    final items = <Widget>[];
    String? lastDay;
    for (final m in list) {
      if (m.day != lastDay) {
        lastDay = m.day;
        items.add(_dayHeader(m.day, accent));
      }
      items.add(_bubble(m, accent));
    }
    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: items,
    );
  }

  Widget _dayHeader(String day, Color accent) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(day, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _bubble(MemoryMsg m, Color accent) {
    final user = m.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
        decoration: BoxDecoration(
          color: user ? accent : Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 4),
            bottomRight: Radius.circular(user ? 4 : 18),
          ),
          border: user ? null : Border.all(color: accent.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: (user ? accent : Colors.black).withOpacity(user ? 0.22 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user ? 'Aap' : 'Siya',
              style: TextStyle(
                color: user ? Colors.white.withOpacity(0.85) : accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            _highlight(m.text, user ? Colors.white : const Color(0xFF2A1C25)),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                m.clock,
                style: TextStyle(
                  color: (user ? Colors.white : const Color(0xFF6F6470)).withOpacity(0.65),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _highlight(String text, Color textColor) {
    final q = _search.text.trim();
    final base = TextStyle(color: textColor, fontSize: 14.5, height: 1.35);
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
        style: const TextStyle(backgroundColor: Color(0x66FFEB3B), fontWeight: FontWeight.w700),
      ));
      i = j + ql.length;
    }
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }
}
