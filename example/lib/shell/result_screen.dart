import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';

import 'face_detail_sheet.dart';
import 'gallery_widgets.dart';
import 'matches_screen.dart';
import 'status_card.dart';
import 'ui.dart';

/// Pushed from Identify: Match / No match, Probe vs Rank 1, metrics, and the matches at
/// or above the threshold.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.result});

  final IdentifyResult result;

  static const int maxRows = 3;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Map<int, FaceRecord?> _records = {};
  FaceGallery? _gallery;

  IdentifyResult get _result => widget.result;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _gallery?.removeListener(_loadRecords);
    super.dispose();
  }

  Future<void> _open() async {
    final gallery = await FaceGallery.open();
    if (!mounted) return;
    _gallery = gallery..addListener(_loadRecords);
    await _loadRecords();
  }

  /// Fetch the stored records (thumbnails, originals, current names) for every shown face.
  Future<void> _loadRecords() async {
    final gallery = _gallery;
    if (gallery == null) return;
    final ids = <int>{
      for (final f in _result.faces)
        if (f.best != null) f.best!.id,
      for (final m in _result.matches) m.id,
    };
    final map = <int, FaceRecord?>{};
    for (final id in ids) {
      map[id] = await gallery.get(id);
    }
    if (mounted) setState(() => _records = map);
  }

  /// Records not yet loaded count as present; deleted ones are dropped from the screen.
  bool _exists(int id) => !_records.containsKey(id) || _records[id] != null;

  void _openFace(Candidate c) =>
      FaceDetailSheet.show(context, c.id, similarity: c.similarity);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final threshold = _result.threshold;
    final primary = _result.primary;
    final rawBest = primary?.best;
    final best = (rawBest != null && _exists(rawBest.id)) ? rawBest : null;
    final matched = best != null && best.similarity >= threshold;
    final matches =
        _result.matches.where((c) => _exists(c.id)).toList(growable: false);
    final record = best == null ? null : _records[best.id];

    return Scaffold(
      appBar: AppBar(title: const Text('Identify result')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Result',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              Pill(
                matched ? 'Match' : 'No match',
                color: matched ? Ui.statusMatch : Ui.statusNoMatch,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Tile(
                  label: 'Probe',
                  child: GalleryImage(path: _pathOf(_result.probeUri)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Tile(
                  label: matched ? 'Rank 1' : 'Closest',
                  onTap: best == null ? null : () => _openFace(best),
                  // Rank 1 shows the stored original photo; falls back to the crop.
                  child: GalleryImage(
                    path: (record?.originalPath.isNotEmpty ?? false)
                        ? record!.originalPath
                        : record?.cropPath,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: best == null ? null : () => _openFace(best),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          best == null
                              ? 'No faces in the gallery'
                              : (record?.name ?? best.name),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (best != null) ...[
                        const SizedBox(width: 8),
                        Pill(Ui.idTag(best.id)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    matched
                        ? 'Similarity ${Ui.score(best.similarity)} is at or above the '
                            'threshold ${Ui.score(threshold)}.'
                        : 'No face reaches the threshold ${Ui.score(threshold)}.',
                    style:
                        TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          MetricsRow(tiles: [
            MetricTile(value: Ui.ms(_result.extractMs), label: 'Extract ms'),
            MetricTile(value: Ui.ms(_result.searchMs), label: 'Search ms'),
            MetricTile(value: '${_result.gallerySize}', label: 'Gallery size'),
          ]),
          if (_result.faces.length > 1) ...[
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Faces in the probe',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  for (final face in _result.faces) _faceLine(face, scheme),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  Ui.matchesCount(matches.length),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              if (matches.length > ResultScreen.maxRows)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MatchesScreen(result: _result),
                    ),
                  ),
                  child:
                      Text('${matches.length - ResultScreen.maxRows} more ›'),
                ),
            ],
          ),
          if (matches.isEmpty)
            Text(
              'No face reaches the threshold ${Ui.score(threshold)}.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            )
          else
            for (var i = 0; i < matches.take(ResultScreen.maxRows).length; i++)
              MatchRow(
                rank: i + 1,
                candidate: matches[i],
                record: _records[matches[i].id],
                onTap: () => _openFace(matches[i]),
              ),
          const SizedBox(height: 16),
          StatusCard(report: _result.report),
        ],
      ),
    );
  }

  Widget _faceLine(ProbeFace face, ColorScheme scheme) {
    final raw = face.best;
    final best = (raw != null && _exists(raw.id)) ? raw : null;
    final String text;
    if (best == null) {
      text = 'Face ${face.index + 1} · no gallery faces';
    } else if (best.similarity >= _result.threshold) {
      text = 'Face ${face.index + 1} · ${_records[best.id]?.name ?? best.name} · '
          '${Ui.idTag(best.id)} · ${Ui.score(best.similarity)}';
    } else {
      text = 'Face ${face.index + 1} · No match · closest '
          '${Ui.score(best.similarity)}';
    }
    return InkWell(
      onTap: best == null ? null : () => _openFace(best),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  static String _pathOf(String uri) =>
      uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.child, this.onTap});

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          AspectRatio(aspectRatio: 1, child: child),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
