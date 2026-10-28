import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge/siya_bridge.dart';
import 'screens/home_screen.dart';
import 'screens/power_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // gradient ke upar white icons (design jaisa)
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  ));
  runApp(const SiyaApp());
}

class SiyaApp extends StatefulWidget {
  const SiyaApp({super.key});

  @override
  State<SiyaApp> createState() => _SiyaAppState();
}

class _SiyaAppState extends State<SiyaApp> {
  final SiyaBridge _bridge = SiyaBridge();

  @override
  void initState() {
    super.initState();
    SiyaTheme.loadFromSettings(_bridge.getSettings);
  }

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SiyaTheme.accent,
      builder: (context, accent, _) => MaterialApp(
      title: 'Siya Ai',
      debugShowCheckedModeBanner: false,
      // Baaki screens dark hi hain; sirf Home screen naye light design ka hai.
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Color.alphaBlend(accent.withOpacity(.045), const Color(0xFFFFF7FB)),
        colorScheme: ColorScheme.light(primary: accent, secondary: accent, surface: Color.alphaBlend(accent.withOpacity(.07), Colors.white)),
        useMaterial3: true,
      ),
      routes: {
        '/features': (_) => PowerScreen(bridge: _bridge),
        '/power': (_) => PowerScreen(bridge: _bridge),
      },
      home: HomeScreen(bridge: _bridge),
      ),
    );
  }
}
