import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted demo settings. The library reads no preferences of its own — every threshold
/// it checks against comes from [limits].
///
/// Defaults are the engine operating points: match 0.80, liveness 0.5, head pose ±20°.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static const double defaultThreshold = FaceLimits.defaultMatch;
  static const double minThreshold = 0.70;
  static const double maxThreshold = 0.90;

  static const double defaultLiveness = FaceLimits.defaultLiveness;
  static const double defaultAngle = FaceLimits.defaultAngle;

  static const _keyThreshold = 'threshold';
  static const _keyLiveness = 'liveness';
  static const _keyLivenessThreshold = 'liveness_threshold';
  static const _keyYaw = 'yaw';
  static const _keyRoll = 'roll';
  static const _keyPitch = 'pitch';
  static const _keyAuto = 'auto_capture';
  static const _keySkipReview = 'skip_review';

  final SharedPreferences _prefs;

  static AppSettings? _instance;

  /// Null until [load] has completed.
  static AppSettings get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('AppSettings.load() must run before the first read.');
    }
    return value;
  }

  static Future<AppSettings> load() async =>
      _instance ??= AppSettings._(await SharedPreferences.getInstance());

  double get threshold =>
      clampThreshold(_prefs.getDouble(_keyThreshold) ?? defaultThreshold);

  set threshold(double v) {
    _prefs.setDouble(_keyThreshold, clampThreshold(v));
    notifyListeners();
  }

  /// Snapped to two decimals so the slider and the shown value never disagree.
  static double clampThreshold(double v) =>
      ((v.clamp(minThreshold, maxThreshold)) * 100).round() / 100;

  /// Whether identify enforces the liveness threshold.
  bool get liveness => _prefs.getBool(_keyLiveness) ?? false;

  set liveness(bool on) {
    _prefs.setBool(_keyLiveness, on);
    notifyListeners();
  }

  double get livenessThreshold => _unit(_keyLivenessThreshold, defaultLiveness);

  set livenessThreshold(double v) => _putUnit(_keyLivenessThreshold, v);

  double get yaw => _angle(_keyYaw);

  set yaw(double v) => _putAngle(_keyYaw, v);

  double get roll => _angle(_keyRoll);

  set roll(double v) => _putAngle(_keyRoll, v);

  double get pitch => _angle(_keyPitch);

  set pitch(double v) => _putAngle(_keyPitch, v);

  /// Skip the post-capture review when every check passes. Off by default: the review is
  /// where the SDK is seen refusing a bad capture, which is worth showing a customer.
  bool get skipReview => _prefs.getBool(_keySkipReview) ?? false;

  set skipReview(bool on) {
    _prefs.setBool(_keySkipReview, on);
    notifyListeners();
  }

  bool get autoCapture => _prefs.getBool(_keyAuto) ?? false;

  set autoCapture(bool on) {
    _prefs.setBool(_keyAuto, on);
    notifyListeners();
  }

  /// Every threshold the library checks against, read from these settings.
  FaceLimits get limits => FaceLimits(
        match: threshold,
        liveness: livenessThreshold,
        yaw: yaw,
        roll: roll,
        pitch: pitch,
      );

  /// The one liveness rule, so Identify, Add person and Attribute all agree.
  bool isLive(double? score) => limits.isLive(score);

  void reset() {
    _prefs.setDouble(_keyThreshold, defaultThreshold);
    _prefs.setBool(_keyLiveness, false);
    _prefs.setDouble(_keyLivenessThreshold, defaultLiveness);
    _prefs.setDouble(_keyYaw, defaultAngle);
    _prefs.setDouble(_keyRoll, defaultAngle);
    _prefs.setDouble(_keyPitch, defaultAngle);
    notifyListeners();
  }

  double _unit(String key, double fallback) =>
      (_prefs.getDouble(key) ?? fallback).clamp(0, 1);

  void _putUnit(String key, double v) {
    _prefs.setDouble(key, v.clamp(0, 1));
    notifyListeners();
  }

  double _angle(String key) =>
      (_prefs.getDouble(key) ?? defaultAngle).clamp(0, 90);

  void _putAngle(String key, double v) {
    _prefs.setDouble(key, v.clamp(0, 90));
    notifyListeners();
  }
}
