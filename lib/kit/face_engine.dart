import 'dart:async';

import 'package:flutter/foundation.dart';

import '../license_status.dart';
import '../src/channel.dart' as channel;
import '../src/models.dart';

/// Where the engine is in its lifecycle. Mirrors the Android and iOS apps.
enum EngineState {
  loading,
  ready,
  notActivated,
  licenseInvalid,
  licenseExpired,
  failed,
}

/// The one engine for the process: activation, init, and the lock every SDK call runs under.
///
/// The native engine is not re-entrant, so every call goes through [run], which serializes
/// them. Call it from anywhere; it never blocks the UI isolate on native work beyond the
/// platform channel's own hop.
class FaceEngine extends ChangeNotifier {
  FaceEngine._();

  static final FaceEngine instance = FaceEngine._();

  EngineState _state = EngineState.loading;
  String _detail = '';
  String _machineCode = '';
  LicenseStatus _license = LicenseStatus.notLicensed;

  /// Serializes native calls: each queued call waits for the one before it.
  Future<void> _queue = Future<void>.value();

  EngineState get state => _state;
  bool get isReady => _state == EngineState.ready;
  String get machineCode => _machineCode;
  LicenseStatus get license => _license;

  /// Ready to show the user.
  String get stateMessage {
    switch (_state) {
      case EngineState.loading:
        return 'Loading the face engine…';
      case EngineState.ready:
        return _license.label.trim().isEmpty
            ? 'Ready'
            : 'Ready · ${_license.label}';
      case EngineState.notActivated:
        return _withDetail('The face engine is not activated.');
      case EngineState.licenseInvalid:
        return _withDetail('This license is not valid.');
      case EngineState.licenseExpired:
        return _withDetail('This license has expired.');
      case EngineState.failed:
        return _withDetail('The face engine could not start.');
    }
  }

  String _withDetail(String message) =>
      _detail.trim().isEmpty ? message : '$message $_detail';

  /// Activates with [license] and loads the models. Safe to call again to retry.
  Future<EngineState> start(String license) async {
    _set(EngineState.loading, '');
    try {
      _machineCode = await channel.getMachineCode();
      final activation = await channel.setActivation(license);
      if (activation != sdkSuccess) {
        _detail = await channel.lastLicenseError();
        return _set(_stateForCode(activation), _detail);
      }
      final code = await channel.init();
      if (code != sdkSuccess) {
        // An init failure is usually the license tier, and this is the only thing that says
        // which — the iOS app's stateMessage appends it the same way.
        _detail = await channel.lastLicenseError().catchError((_) => '');
        return _set(_stateForCode(code), _detail);
      }
      _license = LicenseStatus.fromJson(await channel.getLicenseStatus());
      return _set(EngineState.ready, '');
    } catch (e) {
      return _set(EngineState.failed, '$e');
    }
  }

  /// Re-reads the license tier from the engine.
  Future<LicenseStatus> refreshLicense() async {
    if (!isReady) return _license;
    _license = LicenseStatus.fromJson(await channel.getLicenseStatus());
    notifyListeners();
    return _license;
  }

  /// Runs [block] with the engine to itself. Every kit call goes through this.
  Future<T> run<T>(Future<T> Function() block) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await block());
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    });
    return completer.future;
  }

  EngineState _set(EngineState state, String detail) {
    _state = state;
    _detail = detail;
    notifyListeners();
    return state;
  }

  EngineState _stateForCode(int code) {
    switch (code) {
      case sdkSuccess:
        return EngineState.ready;
      case sdkLicenseInvalid:
        return EngineState.licenseInvalid;
      case sdkLicenseExpired:
        return EngineState.licenseExpired;
      case sdkNotActivated:
        return EngineState.notActivated;
      default:
        return EngineState.failed;
    }
  }
}
