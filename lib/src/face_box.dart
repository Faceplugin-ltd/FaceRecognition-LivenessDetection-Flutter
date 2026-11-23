import 'dart:convert';

/// Structured face box + attributes returned by [faceDetection].
///
/// Field names are camelCase; JSON (de)serialization maps to/from the
/// snake_case keys the native `FaceRecognitionSDK` bridge uses
/// (`face_quality`, `left_eye_closed`, …).
class FaceBox {
  const FaceBox({
    this.detectionId,
    this.templateBase64,
    this.templateBytes = 0,
    this.templateMs = 0,
    this.x1 = 0,
    this.y1 = 0,
    this.x2 = 0,
    this.y2 = 0,
    this.yaw,
    this.pitch,
    this.roll,
    this.liveness,
    this.faceQuality,
    this.faceLuminance,
    this.leftEyeClosed,
    this.rightEyeClosed,
    this.faceOcclusion,
    this.mouthOpened,
    this.age,
    this.gender,
    this.livenessLabel,
    this.genderLabel,
    this.emotionLabel,
    this.maskLabel,
    this.qualityLabel,
    this.glassesLabel,
    this.sunglassesLabel,
    this.occlusionLabel,
    this.eyesLeftLabel,
    this.eyesRightLabel,
    this.attributes,
    this.landmarkCount,
    this.landmarks,
  });

  /// Opaque reference to the original native detection; not a persistent ID.
  final String? detectionId;

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  final double? yaw;
  final double? pitch;
  final double? roll;

  final double? liveness;
  final double? faceQuality;
  final double? faceLuminance;

  final double? leftEyeClosed;
  final double? rightEyeClosed;
  final double? faceOcclusion;
  final double? mouthOpened;

  final double? age;
  final double? gender;

  final String? livenessLabel;
  final String? genderLabel;
  final String? emotionLabel;
  final String? maskLabel;
  final String? qualityLabel;
  final String? glassesLabel;
  final String? sunglassesLabel;
  final String? occlusionLabel;
  final String? eyesLeftLabel;
  final String? eyesRightLabel;

  /// Full engine attribute map (PascalCase keys → display strings).
  final Map<String, String>? attributes;

  final int? landmarkCount;

  /// Flattened `[x0, y0, x1, y1, …]` landmark coordinates in image pixels.
  final List<double>? landmarks;

  /// The recognition template, when it was asked for on the same detect call — base64, or
  /// null when it was not requested or the engine could not read this face.
  final String? templateBase64;

  /// Size of [templateBase64] in bytes, or 0.
  final int templateBytes;

  /// How long the engine took over this face's template, in milliseconds.
  final double templateMs;

  /// Box width in image pixels.
  double get width => x2 - x1;

  /// Box height in image pixels.
  double get height => y2 - y1;

  /// Box area in square image pixels, used to order faces largest first.
  double get area => width * height;

  FaceBox copyWith({
    double? x1,
    double? y1,
    double? x2,
    double? y2,
    double? yaw,
    double? pitch,
    double? roll,
    double? liveness,
    double? faceQuality,
    double? faceLuminance,
    double? leftEyeClosed,
    double? rightEyeClosed,
    double? faceOcclusion,
    double? mouthOpened,
    double? age,
    double? gender,
    String? livenessLabel,
    String? genderLabel,
    String? emotionLabel,
    String? maskLabel,
    String? qualityLabel,
    String? glassesLabel,
    String? sunglassesLabel,
    String? occlusionLabel,
    String? eyesLeftLabel,
    String? eyesRightLabel,
    Map<String, String>? attributes,
    int? landmarkCount,
    List<double>? landmarks,
  }) {
    return FaceBox(
      detectionId: this.detectionId,
      templateBase64: templateBase64,
      templateBytes: templateBytes,
      templateMs: templateMs,
      x1: x1 ?? this.x1,
      y1: y1 ?? this.y1,
      x2: x2 ?? this.x2,
      y2: y2 ?? this.y2,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      roll: roll ?? this.roll,
      liveness: liveness ?? this.liveness,
      faceQuality: faceQuality ?? this.faceQuality,
      faceLuminance: faceLuminance ?? this.faceLuminance,
      leftEyeClosed: leftEyeClosed ?? this.leftEyeClosed,
      rightEyeClosed: rightEyeClosed ?? this.rightEyeClosed,
      faceOcclusion: faceOcclusion ?? this.faceOcclusion,
      mouthOpened: mouthOpened ?? this.mouthOpened,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      livenessLabel: livenessLabel ?? this.livenessLabel,
      genderLabel: genderLabel ?? this.genderLabel,
      emotionLabel: emotionLabel ?? this.emotionLabel,
      maskLabel: maskLabel ?? this.maskLabel,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      glassesLabel: glassesLabel ?? this.glassesLabel,
      sunglassesLabel: sunglassesLabel ?? this.sunglassesLabel,
      occlusionLabel: occlusionLabel ?? this.occlusionLabel,
      eyesLeftLabel: eyesLeftLabel ?? this.eyesLeftLabel,
      eyesRightLabel: eyesRightLabel ?? this.eyesRightLabel,
      attributes: attributes ?? this.attributes,
      landmarkCount: landmarkCount ?? this.landmarkCount,
      landmarks: landmarks ?? this.landmarks,
    );
  }

  static double _toDouble(Object? v, [double fallback = 0]) {
    if (v is num) return v.toDouble();
    if (v is String && v.trim().isNotEmpty) {
      return double.tryParse(v) ?? fallback;
    }
    return fallback;
  }

  static double? _toDoubleOrNull(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String && v.trim().isNotEmpty) return double.tryParse(v);
    return null;
  }

  static String? _toStringOrNull(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  static Map<String, String>? _toStringMap(Object? v) {
    if (v is! Map) return null;
    final out = <String, String>{};
    v.forEach((key, value) {
      if (key == null || value == null) return;
      final sv = value.toString();
      if (sv.trim().isEmpty) return;
      out['$key'] = sv;
    });
    return out.isEmpty ? null : out;
  }

  static List<double>? _toDoubleList(Object? v) {
    if (v is! List) return null;
    final out = <double>[];
    for (final e in v) {
      out.add(_toDouble(e));
    }
    return out.isEmpty ? null : out;
  }

  factory FaceBox.fromJson(Map<Object?, Object?> json) {
    return FaceBox(
      detectionId: json['detectionId']?.toString(),
      templateBase64: _toStringOrNull(json['template']),
      templateBytes: (json['templateBytes'] as num?)?.toInt() ?? 0,
      templateMs: (json['templateMs'] as num?)?.toDouble() ?? 0,
      x1: _toDouble(json['x1']),
      y1: _toDouble(json['y1']),
      x2: _toDouble(json['x2']),
      y2: _toDouble(json['y2']),
      yaw: _toDoubleOrNull(json['yaw']),
      pitch: _toDoubleOrNull(json['pitch']),
      roll: _toDoubleOrNull(json['roll']),
      liveness: _toDoubleOrNull(json['liveness']),
      faceQuality: _toDoubleOrNull(json['face_quality']),
      faceLuminance: _toDoubleOrNull(json['face_luminance']),
      leftEyeClosed: _toDoubleOrNull(json['left_eye_closed']),
      rightEyeClosed: _toDoubleOrNull(json['right_eye_closed']),
      faceOcclusion: _toDoubleOrNull(json['face_occlusion']),
      mouthOpened: _toDoubleOrNull(json['mouth_opened']),
      age: _toDoubleOrNull(json['age']),
      gender: _toDoubleOrNull(json['gender']),
      livenessLabel: _toStringOrNull(json['livenessLabel']),
      genderLabel: _toStringOrNull(json['genderLabel']),
      emotionLabel: _toStringOrNull(json['emotionLabel']),
      maskLabel: _toStringOrNull(json['maskLabel']),
      qualityLabel: _toStringOrNull(json['qualityLabel']),
      glassesLabel: _toStringOrNull(json['glassesLabel']),
      sunglassesLabel: _toStringOrNull(json['sunglassesLabel']),
      occlusionLabel: _toStringOrNull(json['occlusionLabel']),
      eyesLeftLabel: _toStringOrNull(json['eyesLeftLabel']),
      eyesRightLabel: _toStringOrNull(json['eyesRightLabel']),
      attributes: _toStringMap(json['attributes']),
      landmarkCount: _toDoubleOrNull(json['landmarkCount'])?.round(),
      landmarks: _toDoubleList(json['landmarks']),
    );
  }

  /// Serialize using the snake_case keys the native bridge expects
  /// (`jsonToFaceBox` on Android / iOS).
  Map<String, dynamic> toJson() {
    return {
      if (detectionId != null) 'detectionId': detectionId,
      if (templateBase64 != null) 'template': templateBase64,
      'templateBytes': templateBytes,
      'templateMs': templateMs,
      'x1': x1,
      'y1': y1,
      'x2': x2,
      'y2': y2,
      'yaw': yaw ?? 0,
      'roll': roll ?? 0,
      'pitch': pitch ?? 0,
      'liveness': liveness ?? 0,
      'face_quality': faceQuality ?? 0,
      'face_luminance': faceLuminance ?? 0,
      'left_eye_closed': leftEyeClosed ?? 0,
      'right_eye_closed': rightEyeClosed ?? 0,
      'face_occlusion': faceOcclusion ?? 0,
      'mouth_opened': mouthOpened ?? 0,
      'age': age ?? 0,
      'gender': gender ?? 0,
      'livenessLabel': livenessLabel ?? '',
      'genderLabel': genderLabel ?? '',
      'emotionLabel': emotionLabel ?? '',
      'maskLabel': maskLabel ?? '',
      'qualityLabel': qualityLabel ?? '',
      'glassesLabel': glassesLabel ?? '',
      'sunglassesLabel': sunglassesLabel ?? '',
      'occlusionLabel': occlusionLabel ?? '',
      'eyesLeftLabel': eyesLeftLabel ?? '',
      'eyesRightLabel': eyesRightLabel ?? '',
      if (attributes != null) 'attributes': attributes,
      'landmarkCount': landmarkCount ?? 0,
      if (landmarks != null) 'landmarks': landmarks,
    };
  }

  String toJsonString() => jsonEncode(toJson());
}
