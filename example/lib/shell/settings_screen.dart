import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'ui.dart';

/// Match, liveness and pose thresholds, plus the license and version lines.
/// Reset is on the header, as on Android.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AppSettings _settings = AppSettings.instance;
  final FaceEngine _engine = FaceEngine.instance;
  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngine);
    _engine.refreshLicense();
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngine);
    super.dispose();
  }

  void _onEngine() {
    if (mounted) setState(() {});
  }

  String get _licenseText {
    final status = _engine.license;
    final parts = <String>[
      status.label.trim().isEmpty
          ? (status.licensed ? 'Licensed' : 'Not licensed')
          : status.label,
      if (status.licensed &&
          status.levelName.trim().isNotEmpty &&
          status.levelName.toLowerCase() != 'none')
        status.levelName,
      if (status.recognition) 'Recognition',
      if (status.liveness) 'Liveness',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Settings',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () {
                _settings.reset();
                setState(() {});
              },
              child: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Matching',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              _UnitSlider(
                label: 'Match threshold',
                value: _settings.threshold,
                min: AppSettings.minThreshold,
                max: AppSettings.maxThreshold,
                onChanged: (v) => setState(() => _settings.threshold = v),
              ),
              Text(
                'Luxand FaceSDK standard identity verification is 0.80. A gallery face '
                'matches at or above this value. 0.70 is convenience, 0.90 is high security.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Liveness',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Liveness check'),
                subtitle: const Text(
                  'Reject photos of photos and screens before identifying. Luxand counts a '
                  'face as live when its score is above 0.5.',
                ),
                value: _settings.liveness,
                onChanged: (on) => setState(() => _settings.liveness = on),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Skip the capture review'),
                subtitle: const Text(
                  'Enroll straight away when every check passes. A capture that fails one '
                  'still opens the review, so you can see why.',
                ),
                value: _settings.skipReview,
                onChanged: (on) => setState(() => _settings.skipReview = on),
              ),
              _UnitSlider(
                label: 'Liveness',
                value: _settings.livenessThreshold,
                min: 0,
                max: 1,
                onChanged: (v) =>
                    setState(() => _settings.livenessThreshold = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Head pose',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                'Largest head turn allowed, in degrees.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              _AngleSlider(
                label: 'Yaw',
                value: _settings.yaw,
                onChanged: (v) => setState(() => _settings.yaw = v),
              ),
              _AngleSlider(
                label: 'Roll',
                value: _settings.roll,
                onChanged: (v) => setState(() => _settings.roll = v),
              ),
              _AngleSlider(
                label: 'Pitch',
                value: _settings.pitch,
                onChanged: (v) => setState(() => _settings.pitch = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'About',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              SectionRow(label: 'License', value: _licenseText),
              // Android reports these two the same way: the SDK name as a constant and the
              // demo app's own version.
              const SectionRow(label: 'SDK version', value: _sdkVersion),
              const SectionRow(label: 'App version', value: _appVersion),
              SectionRow(label: 'Engine', value: _engine.stateMessage),

            ],
          ),
        ),
        // The company mark closes the screen, now that About is no longer a tab.
        Padding(
          padding: const EdgeInsets.only(top: 32, bottom: 24),
          child: Center(
            child: Image.asset(
              'assets/images/fp_logo.png',
              height: 44,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ],
    );
  }
}

const _sdkVersion = 'Face Recognition SDK';
const _appVersion = '0.1.0';

class _UnitSlider extends StatelessWidget {
  const _UnitSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Pill(Ui.score(value)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) * 100).round(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _AngleSlider extends StatelessWidget {
  const _AngleSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Pill('${value.round()}°'),
          ],
        ),
        Slider(
          value: value.clamp(0, 90),
          max: 90,
          divisions: 90,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
