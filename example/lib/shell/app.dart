import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';

import '../core/constants/license.dart';
import 'main_tabs.dart';
import 'ui.dart';

/// The demo app: one Material 3 theme, a splash while the engine starts, then the tabs.
class FaceRecognitionApp extends StatelessWidget {
  const FaceRecognitionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FacePlugin Face Recognition',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const SplashScreen(),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Ui.accent,
        brightness: brightness,
      ),
    );
  }
}

/// Starts the engine, then shows the tabs. A failure stays here with the reason and a
/// Retry, because nothing in the app works without the engine.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FaceEngine _engine = FaceEngine.instance;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final state = await _engine.start(demoLicense());
    if (!mounted || state != EngineState.ready) {
      if (mounted) setState(() {});
      return;
    }
    // Opening the gallery here keeps the first People tab instant.
    await FaceGallery.open();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainTabs()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loading = _engine.state == EngineState.loading;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/fp_logo.png',
                height: 56,
                errorBuilder: (_, __, ___) => const SizedBox(height: 56),
              ),
              const SizedBox(height: 32),
              if (loading)
                const CircularProgressIndicator()
              else
                const Icon(Icons.error_outline, size: 40, color: Ui.danger),
              const SizedBox(height: 20),
              Text(
                _engine.stateMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
              if (!loading) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: _start, child: const Text('Retry')),
                const SizedBox(height: 12),
                SelectableText(
                  'Machine code: ${_engine.machineCode}',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
