import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'shell/app.dart';
import 'shell/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capture and identify expect a fixed upright portrait frame — do not follow device
  // rotation. The Android and iOS apps are locked the same way.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  // Settings must be readable before the first screen builds: every threshold the kit
  // checks against is passed in from here.
  await AppSettings.load();

  runApp(const FaceRecognitionApp());
}
