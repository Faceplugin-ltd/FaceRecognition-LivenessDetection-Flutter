import 'dart:io';

import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_settings.dart';
import 'status_card.dart';
import 'ui.dart';

/// Import photos: each photo becomes one person named after the file.
/// Photos with no face, or more than one, are skipped with the reason.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.paths});

  final List<String> paths;

  static const Set<String> imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.heic',
    '.heif',
    '.bmp',
    '.webp',
  };

  /// Every image directly inside [directory], name-sorted so the order is predictable.
  static List<String> imagesIn(String directory) {
    try {
      final dir = Directory(directory);
      if (!dir.existsSync()) return const [];
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              imageExtensions.contains(p.extension(f.path).toLowerCase()))
          .map((f) => f.path)
          .toList()
        ..sort((a, b) =>
            p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));
      return files;
    } catch (_) {
      return const [];
    }
  }

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportRow {
  _ImportRow({
    required this.fileName,
    required this.subtitle,
    required this.enrolled,
    this.report,
  });

  final String fileName;
  final String subtitle;
  final bool enrolled;
  final CallReport? report;
  bool expanded = false;
}

class _ImportScreenState extends State<ImportScreen> {
  final List<_ImportRow> _rows = [];

  int _enrolled = 0;
  int _skipped = 0;
  double _totalMs = 0;
  int _index = 0;
  bool _started = false;
  bool _finished = false;
  bool _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _started = true);
    final gallery = await FaceGallery.open();
    final limits = AppSettings.instance.limits;

    for (var i = 0; i < widget.paths.length; i++) {
      if (_cancelled) return;
      setState(() => _index = i);
      final path = widget.paths[i];
      final fileName = p.basename(path);
      final outcome = await gallery.enroll(
        p.basenameWithoutExtension(path),
        '',
        path,
        limits: limits,
      );
      if (_cancelled || !mounted) return;
      setState(() => _addResult(fileName, outcome));
    }

    if (!mounted) return;
    setState(() {
      _index = widget.paths.length;
      _finished = true;
    });
  }

  void _addResult(String fileName, EnrollOutcome outcome) {
    switch (outcome) {
      case Enrolled(:final record, :final report, :final duplicates):
        var subtitle = '${record.name} · ${Ui.idTag(record.id)}';
        if (duplicates.isNotEmpty) {
          // Bulk enroll names every match over the threshold, as Enroll with camera does.
          subtitle += ' · Duplicate check: '
              '${duplicates.map((c) => '${c.name} ${Ui.idTag(c.id)} ${Ui.score(c.similarity)}').join(', ')}';
        }
        _enrolled++;
        _totalMs += report.totalMs;
        _rows.insert(
          0,
          _ImportRow(
            fileName: fileName,
            subtitle: subtitle,
            enrolled: true,
            report: report,
          ),
        );
      case EnrollRejected(:final reason, :final report):
        _skipped++;
        _totalMs += report?.totalMs ?? 0;
        _rows.insert(
          0,
          _ImportRow(
            fileName: fileName,
            subtitle: reason,
            enrolled: false,
            report: report,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = widget.paths.length;
    final done = _enrolled + _skipped;
    final average = done == 0 ? '–' : Ui.ms(_totalMs / done);

    return Scaffold(
      appBar: AppBar(title: const Text('Bulk enroll from photos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            total == 0
                ? 'No images found'
                : _finished
                    ? 'Imported $total ${total == 1 ? 'photo' : 'photos'}'
                    : 'Import $total ${total == 1 ? 'photo' : 'photos'}?',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (!_started)
            Text(
              'Each photo becomes one person, named after the file. Photos with no face '
              'or more than one face are skipped.',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
            ),
          if (_started) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : _index / total,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _finished
                  ? '$total of $total · Done'
                  : '${_index + 1} of $total · ${p.basename(widget.paths[_index.clamp(0, total - 1)])}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            MetricsRow(tiles: [
              MetricTile(value: '$_enrolled', label: 'Enrolled'),
              MetricTile(value: '$_skipped', label: 'Skipped'),
              MetricTile(value: average, label: 'Avg ms / photo'),
            ]),
          ],
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                const Text(
                  'Results',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Pill('${_rows.length}'),
              ],
            ),
            const SizedBox(height: 4),
            for (final row in _rows) _resultRow(row, scheme),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: total == 0 || _finished
                  ? () => Navigator.of(context).pop()
                  : _started
                      ? null
                      : _start,
              child: Text(total == 0 || _finished ? 'Done' : 'Start import'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(_ImportRow row, ColorScheme scheme) {
    final report = row.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: report == null
              ? null
              : () => setState(() => row.expanded = !row.expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        row.subtitle,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Pill(
                      row.enrolled ? 'Enrolled' : 'Skipped',
                      color: row.enrolled ? Ui.statusMatch : Ui.danger,
                      fontSize: 11,
                    ),
                    if (report != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${Ui.ms(report.totalMs)} ms',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        if (row.expanded && report != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StatusCard(report: report, title: 'Enrollment status'),
          ),
      ],
    );
  }
}
