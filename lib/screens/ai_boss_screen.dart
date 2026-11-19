import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';

/// Dedicated AI Boss Biometric Voiceprint Lock Screen.
/// Provides free-speech voice enrollment (3.5s sample capture with live audio level visualization),
/// Hindi TTS audio instructions (🔊), and profile management.
class AiBossScreen extends StatefulWidget {
  const AiBossScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<AiBossScreen> createState() => _AiBossScreenState();
}

class _AiBossScreenState extends State<AiBossScreen> {
  bool _loaded = false;
  bool _bossEnrolled = false;
  int _bossSampleCount = 0;
  int _currentSamples = 0;
  bool _isRecording = false;
  bool _isSpeaking = false;

  Color get _accent => SiyaTheme.accent.value;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await widget.bridge.getBossProfileStatus();
      if (!mounted) return;
      setState(() {
        _bossEnrolled = (status['enrolled'] as bool?) ?? false;
        _bossSampleCount = ((status['sampleCount'] as num?) ?? 0).toInt();
        _currentSamples = _bossSampleCount;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _speakInstruction() async {
    if (_isSpeaking) {
      await widget.bridge.stopSpeaking();
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }
    setState(() => _isSpeaking = true);
    await widget.bridge.speakHindiText(
      'Kripya apni aawaz mein teen second tak kuch bhi boliye, jaise main tumhara boss hoon ya koi bhi baat.',
    );
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _recordSample() async {
    if (_isRecording) return;
    if (_isSpeaking) {
      await widget.bridge.stopSpeaking();
      _isSpeaking = false;
    }
    setState(() => _isRecording = true);
    try {
      final count = await widget.bridge.enrollBossVoiceSample();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        if (count > 0) {
          _currentSamples = count;
          _bossSampleCount = count;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0
              ? 'Sample $count recorded successfully!'
              : 'Sample recording incomplete. Kripya dobara boliye.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _saveAndActivate() async {
    final ok = await widget.bridge.finalizeBossEnrollment();
    if (!mounted) return;
    if (ok) {
      setState(() {
        _bossEnrolled = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 AI Boss voiceprint activated! Ab Siya sirf aapko Malik pehchanegi.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF00C853),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activation failed. Kripya 3-4 saaf samples record karein.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFFF5252),
        ),
      );
    }
  }

  Future<void> _resetProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B2E),
        title: const Text('Reset Boss Profile?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text(
          'Kya aap Boss voice profile delete karna chahte hain? Reset ke baad Siya sabhi ko normal guest treat karegi.',
          style: TextStyle(color: Colors.white70, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
            child: const Text('Delete Profile', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.bridge.clearBossVoiceProfile();
      if (!mounted) return;
      setState(() {
        _bossEnrolled = false;
        _bossSampleCount = 0;
        _currentSamples = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Boss voice profile deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // Background ambient gradient glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.4),
                  radius: 1.2,
                  colors: [
                    _accent.withOpacity(0.12),
                    const Color(0xFF161522).withOpacity(0.8),
                    const Color(0xFF121212),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: !_loaded
                ? Center(child: CircularProgressIndicator(color: _accent))
                : Column(
                    children: [
                      _buildHeader(),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                          children: [
                            // Status Card
                            _buildStatusCard(),
                            const SizedBox(height: 16),

                            // Hindi Voice Instruction Card with 🔊 Button
                            _buildInstructionCard(),
                            const SizedBox(height: 20),

                            // Sample Progress Indicators (1 to 4)
                            _buildSampleProgress(),
                            const SizedBox(height: 28),

                            // Dynamic Live Audio Waveform / Level Meter
                            _buildLiveWaveform(),
                            const SizedBox(height: 16),

                            // Big Animated Mic Button
                            _buildMicButton(),
                            const SizedBox(height: 12),

                            // Mic Status Label
                            Center(
                              child: Text(
                                _isRecording
                                    ? 'Listening (3.5s)... Free Speech Boliye!'
                                    : (_currentSamples >= 4
                                        ? 'All 4 samples recorded!'
                                        : 'Tap mic button to record sample ${_currentSamples + 1} of 4'),
                                style: TextStyle(
                                  color: _isRecording ? const Color(0xFFFF5252) : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Activate Button
                            if (_currentSamples >= 3) ...[
                              ElevatedButton.icon(
                                onPressed: _saveAndActivate,
                                icon: const Icon(Icons.verified_user_rounded, size: 20),
                                label: Text(
                                  _bossEnrolled ? 'Update Boss Profile' : 'Save & Activate Boss Profile',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E676),
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 6,
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            // Reset Profile Button
                            if (_bossEnrolled || _currentSamples > 0)
                              OutlinedButton.icon(
                                onPressed: _resetProfile,
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFFF5252)),
                                label: const Text(
                                  'Reset Voice Profile',
                                  style: TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.w600),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: const Color(0xFFFF5252).withOpacity(0.5)),
                                  minimumSize: const Size.fromHeight(46),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Boss',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Biometric Voiceprint Lock',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1829),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (_bossEnrolled ? const Color(0xFF00E676) : _accent).withOpacity(0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (_bossEnrolled ? const Color(0xFF00E676) : _accent).withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: (_bossEnrolled ? const Color(0xFF00E676) : _accent).withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (_bossEnrolled ? const Color(0xFF00E676) : _accent).withOpacity(0.6),
              ),
            ),
            child: Icon(
              _bossEnrolled ? Icons.verified_user_rounded : Icons.lock_open_rounded,
              color: _bossEnrolled ? const Color(0xFF00E676) : _accent,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _bossEnrolled ? 'Verified Boss (Malik)' : 'Voiceprint Not Enrolled',
                      style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (_bossEnrolled ? const Color(0xFF00E676) : Colors.amber).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _bossEnrolled ? 'ACTIVE' : 'OPEN',
                        style: TextStyle(
                          color: _bossEnrolled ? const Color(0xFF00E676) : Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _bossEnrolled
                      ? 'WeSpeaker 0.2s voiceprint lock active ($_bossSampleCount samples). Siya treats you as Boss!'
                      : 'Enroll 3-4 voice samples. Siya will instantly recognize you within 0.2s.',
                  style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181624),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.record_voice_over_rounded, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Free Speech Instruction',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              // Hindi TTS Audio Speaker Button 🔊
              InkWell(
                onTap: _speakInstruction,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isSpeaking ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: _accent,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isSpeaking ? 'Stop 🔇' : 'Sunein 🔊',
                        style: TextStyle(color: _accent, fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '"Kripya 3.5 second tak apni aawaz mein kuch bhi boliye — jaise: \'Main tumhara Boss hoon\', \'Namaste Siya\', ya koi bhi baat."',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 6),
          const Text(
            '💡 Note: Kisi fixed phrase ki zaroorat nahi hai. Apni aam boli boliye.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSampleProgress() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (idx) {
            final isDone = idx < _currentSamples;
            final isCurrent = idx == _currentSamples && _isRecording;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 8,
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFF00E676)
                      : (isCurrent ? _accent : Colors.white12),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: isDone
                      ? [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.6), blurRadius: 6)]
                      : (isCurrent ? [BoxShadow(color: _accent.withOpacity(0.7), blurRadius: 8)] : null),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Text(
          '$_currentSamples of 4 Samples Collected',
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildLiveWaveform() {
    return ValueListenableBuilder<double>(
      valueListenable: widget.bridge.enrollmentAmp,
      builder: (context, amp, _) {
        final activeAmp = _isRecording ? amp.clamp(0.0, 1.0) : 0.0;
        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(16, (i) {
              final waveMod = math.sin((i / 15.0) * math.pi);
              final barHeight = _isRecording
                  ? (6.0 + 36.0 * (activeAmp * waveMod)).clamp(4.0, 44.0)
                  : 4.0;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: 4,
                height: barHeight,
                decoration: BoxDecoration(
                  color: _isRecording
                      ? Color.lerp(const Color(0xFF00E676), const Color(0xFFFF5252), activeAmp)!
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildMicButton() {
    return Center(
      child: GestureDetector(
        onTap: _isRecording ? null : _recordSample,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _isRecording ? 92 : 82,
          height: _isRecording ? 92 : 82,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: _isRecording
                  ? [const Color(0xFFFF5252), const Color(0xFFFF1744)]
                  : [_accent, Color.lerp(_accent, Colors.white, 0.25)!],
            ),
            boxShadow: [
              BoxShadow(
                color: (_isRecording ? const Color(0xFFFF5252) : _accent).withOpacity(0.5),
                blurRadius: _isRecording ? 32 : 18,
                spreadRadius: _isRecording ? 4 : 1,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              _isRecording ? Icons.graphic_eq_rounded : Icons.mic_rounded,
              color: Colors.white,
              size: _isRecording ? 42 : 36,
            ),
          ),
        ),
      ),
    );
  }
}
