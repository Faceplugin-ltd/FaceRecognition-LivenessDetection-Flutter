/// The thresholds every check in this library uses. Hold one instance per app — build it from
/// your own settings store and pass it in; the library never reads preferences itself.
///
/// The defaults are the engine's operating points: identify at 0.80 and liveness at 0.5.
///
/// ```dart
/// const limits = FaceLimits(match: 0.82, liveness: 0.6);
/// final outcome = await FaceGallery.instance.identify(photo, limits, livenessOn: true);
/// ```
class FaceLimits {
  const FaceLimits({
    this.match = defaultMatch,
    this.liveness = defaultLiveness,
    this.yaw = defaultAngle,
    this.roll = defaultAngle,
    this.pitch = defaultAngle,
  });

  /// Lowest similarity that counts as the same person (1:N identify and the duplicate check).
  final double match;

  /// Lowest liveness score that counts as a live face.
  final double liveness;

  /// Largest head turn allowed, in degrees.
  final double yaw;
  final double roll;
  final double pitch;

  static const double defaultMatch = 0.80;
  static const double defaultLiveness = 0.5;
  static const double defaultAngle = 20;
  static const double _epsilon = 0.0001;

  /// The engine's operating points.
  static const FaceLimits standard = FaceLimits();

  /// True when [score] counts as a live face. A missing score (liveness not run) is not live.
  bool isLive(double? score) =>
      score != null && !score.isNaN && score + _epsilon >= liveness;

  /// True when the head is within [yaw], [roll] and [pitch] of facing the camera.
  bool poseOk(double yawDeg, double rollDeg, double pitchDeg) =>
      yawDeg.abs() <= yaw && rollDeg.abs() <= roll && pitchDeg.abs() <= pitch;

  /// True when [similarity] counts as the same person.
  bool matches(double similarity) => similarity >= match;

  FaceLimits copyWith({
    double? match,
    double? liveness,
    double? yaw,
    double? roll,
    double? pitch,
  }) {
    return FaceLimits(
      match: match ?? this.match,
      liveness: liveness ?? this.liveness,
      yaw: yaw ?? this.yaw,
      roll: roll ?? this.roll,
      pitch: pitch ?? this.pitch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FaceLimits &&
      other.match == match &&
      other.liveness == liveness &&
      other.yaw == yaw &&
      other.roll == roll &&
      other.pitch == pitch;

  @override
  int get hashCode => Object.hash(match, liveness, yaw, roll, pitch);
}
