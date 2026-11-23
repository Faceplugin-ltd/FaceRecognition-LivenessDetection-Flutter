import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:face_recognition_sdk/api/types.dart' as api;
import 'package:face_recognition_sdk/src/face_box.dart' as channel;
import 'package:face_recognition_sdk/src/channel.dart' as bridge;
import 'package:face_recognition_sdk/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const detected = <String, dynamic>{
    'detectionId': 'original-native-face',
    'x1': 10,
    'y1': 20,
    'x2': 110,
    'y2': 120,
  };

  test('public face keeps its detection reference through normalization and copies', () {
    final face = api.FaceBox.fromJson(detected);
    final copied = face.copyWith(livenessLabel: 'Live');
    expect(copied.toJson()['detectionId'], detected['detectionId']);
    expect(api.FaceBox.fromJson(copied.toJson()).detectionId, face.detectionId);
  });

  test('channel face keeps its detection reference through normalization and copies', () {
    final face = channel.FaceBox.fromJson(detected);
    final copied = face.copyWith(attributes: {'Liveness2D': 'Live'});
    expect(copied.toJson()['detectionId'], detected['detectionId']);
    expect(channel.FaceBox.fromJson(copied.toJson()).detectionId, face.detectionId);
  });

  test('detection keeps per-face templates through the actual channel normalization', () async {
    const native = MethodChannel('FaceRecognitionSdk');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      expect(call.method, 'faceDetection');
      final params = jsonDecode((call.arguments as Map)['param'] as String);
      expect(params['templates'], 2);
      return jsonEncode([
        {...detected, 'template': 'AQID', 'templateBytes': 3, 'templateMs': 4.5, 'attributes': {}},
        {...detected, 'detectionId': 'second-face', 'template': 'BAUG', 'templateBytes': 3, 'templateMs': 2.5, 'attributes': {}},
      ]);
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null));

    final faces = await bridge.faceDetection('photo.jpg', const FaceDetectionParam(), 2);
    expect(faces.map((f) => f.templateBase64), ['AQID', 'BAUG']);
    expect(faces.map((f) => f.templateBytes), [3, 3]);
    expect(faces.map((f) => f.templateMs), [4.5, 2.5]);
    expect(faces.first.toJson()['template'], 'AQID');
    expect(calls.length, 1); // No second detection or extraction call.
  });
}
