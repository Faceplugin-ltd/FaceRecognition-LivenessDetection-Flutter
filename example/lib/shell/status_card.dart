import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';

import 'ui.dart';

/// One status UI for every action (identify, enroll, import, attribute): outcome pill,
/// total time, when it finished, then one row per SDK call with pass/fail, its time and
/// its share of the total.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.report,
    this.title,
    this.showDetail = true,
  });

  final CallReport report;
  final String? title;
  final bool showDetail;

  /// Readable names for the stable step identifiers.
  static String stepName(String name) => switch (name) {
        'faceDetection' => 'Face detection',
        'templateExtraction' => 'Template extraction',
        'similarity' => '1:N search',
        'livenessCheck' => 'Liveness check',
        'duplicateCheck' => 'Duplicate check (1:N)',
        'save' => 'Save to gallery',
        _ => name,
      };

  static String functionName(String function) => switch (function) {
        'identify' => 'Identify',
        'enroll' => 'Enroll',
        'attribute' => 'Attribute',
        _ => function.isEmpty
            ? function
            : function[0].toUpperCase() + function.substring(1),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = report.steps.where((s) => s.ok).length;
    final at = Ui.time(report.finishedAtTime);
    final summary = [
      'Total ${Ui.ms(report.totalMs)} ms',
      '$ok of ${report.steps.length} calls',
      if (at.isNotEmpty) at,
    ].join('  ·  ');
    final total = report.totalMs > 0 ? report.totalMs : 1.0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title ?? '${functionName(report.function)} status',
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Pill(
                report.success ? 'Success' : 'Failed',
                color: report.success ? Ui.statusMatch : Ui.danger,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          if (report.steps.isEmpty)
            Text(
              'No SDK calls were made.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            )
          else
            for (final step in report.steps) _StepRow(step: step, total: total),
          if (showDetail && report.detail.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(report.detail, style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
    );
  }

  /// A dialog for an action that stopped: [reason] on top, then the status card.
  /// The enrollment status, in the same dialog the capture review uses.
  static Future<void> showAsDialog(
    BuildContext context, {
    required String title,
    String? reason,
    CallReport? report,
  }) {
    return showAppDialog<void>(
      context,
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reason != null && reason.trim().isNotEmpty) ...[
            Text(reason, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
          ],
          if (report != null) StatusCard(report: report),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.total});

  final CallStep step;
  final double total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = step.ok ? Ui.statusMatch : Ui.danger;
    final share = (step.ms / total).clamp(step.ms > 0 ? 0.01 : 0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              step.ok ? '✓' : '✕',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        StatusCard.stepName(step.name),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${Ui.ms(step.ms)} ms',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (step.detail.isNotEmpty)
                  Text(
                    step.detail,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 4,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
