import 'dart:convert';

/// One timed SDK call. [detail] is the short result of that call; [ok] is false when this
/// step stopped the action.
class CallStep {
  const CallStep(this.name, this.ms, this.detail, {this.ok = true});

  /// A stable identifier, not a label: hosts translate it for display.
  /// One of `faceDetection`, `templateExtraction`, `similarity`, `livenessCheck`,
  /// `duplicateCheck`, `save`.
  final String name;
  final double ms;
  final String detail;
  final bool ok;

  Map<String, Object?> toJson() =>
      {'name': name, 'ms': ms, 'detail': detail, 'ok': ok};

  factory CallStep.fromJson(Map<Object?, Object?> json) => CallStep(
        json['name']?.toString() ?? '',
        (json['ms'] as num?)?.toDouble() ?? 0,
        json['detail']?.toString() ?? '',
        ok: json['ok'] as bool? ?? true,
      );
}

/// Shown after a customer action finishes: total time, each call, progress, detail and
/// overall outcome.
class CallReport {
  CallReport({
    required this.function,
    required this.steps,
    required this.progress,
    required this.detail,
    this.success = true,
    int? finishedAt,
  }) : finishedAt = finishedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String function;
  final List<CallStep> steps;
  final String progress;
  final String detail;
  final bool success;

  /// Wall-clock time the action finished (epoch ms).
  final int finishedAt;

  double get totalMs =>
      steps.fold<double>(0, (sum, step) => sum + step.ms);

  DateTime? get finishedAtTime => finishedAt > 0
      ? DateTime.fromMillisecondsSinceEpoch(finishedAt)
      : null;

  Map<String, Object?> toJson() => {
        'function': function,
        'progress': progress,
        'detail': detail,
        'success': success,
        'finishedAt': finishedAt,
        'steps': steps.map((s) => s.toJson()).toList(growable: false),
      };

  String toJsonString() => jsonEncode(toJson());

  /// Returns null for empty or unparsable JSON, so a record saved before reports were
  /// stored simply has no card.
  static CallReport? fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final steps = decoded['steps'];
      return CallReport(
        function: decoded['function']?.toString() ?? '',
        steps: steps is List
            ? steps
                .whereType<Map>()
                .map((e) => CallStep.fromJson(Map<Object?, Object?>.from(e)))
                .toList(growable: false)
            : const [],
        progress: decoded['progress']?.toString() ?? '',
        detail: decoded['detail']?.toString() ?? '',
        success: decoded['success'] as bool? ?? true,
        finishedAt: (decoded['finishedAt'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
