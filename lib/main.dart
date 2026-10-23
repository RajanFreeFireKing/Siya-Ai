import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge/siya_bridge.dart';
import 'screens/home_screen.dart';
import 'screens/features_screen.dart';
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
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Siya Ai',
      debugShowCheckedModeBanner: false,
      // Baaki screens dark hi hain; sirf Home screen naye light design ka hai.
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: SiyaColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: SiyaColors.cyan,
          secondary: SiyaColors.purple,
          surface: SiyaColors.card,
        ),
        useMaterial3: true,
      ),
      routes: {
        '/features': (_) => FeaturesScreen(bridge: _bridge),
      },
      home: HomeScreen(bridge: _bridge),
    );
  }
}
