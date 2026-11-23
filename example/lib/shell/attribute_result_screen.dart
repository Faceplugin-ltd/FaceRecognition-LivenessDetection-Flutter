import 'dart:io';
import 'dart:ui' as ui;

import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'face_detail_sheet.dart';
import 'status_card.dart';
import 'ui.dart';

/// Every face in the photo with every value the SDK returns: liveness, quality, detection
/// score, pose, eyes, age, gender, landmarks, box, gallery closest match. Each gated value
/// is checked against the limits in Settings. The call status card is at the bottom.
class AttributeResultScreen extends StatefulWidget {
  const AttributeResultScreen({super.key, required this.result});

  final AttributeResult result;

  /// Eyes read as open at or above this score.
  static const double eyeOpen = 0.25;

  /// Inner-lip gap / mouth width at or above which the mouth reads as open.
  static const double mouthOpen = 0.25;
  static const double mouthSlight = 0.10;

  @override
  State<AttributeResultScreen> createState() => _AttributeResultScreenState();
}

class _AttributeResultScreenState extends State<AttributeResultScreen> {
  final AppSettings _settings = AppSettings.instance;
  ui.Image? _photo;
  int _selected = 0;

  AttributeResult get _result => widget.result;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void dispose() {
    _photo?.dispose();
    super.dispose();
  }

  Future<void> _loadPhoto() async {
    try {
      final path = _result.probeUri.startsWith('file://')
          ? Uri.parse(_result.probeUri).toFilePath()
          : _result.probeUri;
      final bytes = await File(path).readAsBytes();
      final image = await decodeImageFromList(bytes);
      if (mounted) {
        setState(() => _photo = image);
      } else {
        image.dispose();
      }
    } catch (_) {
      // Without the photo the screen still shows every value; only the preview is missing.
    }
  }

  bool _hasLiveness(FaceBox b) => (b.livenessLabel ?? '').trim().isNotEmpty;

  /// Same rule as Identify: the Settings liveness threshold decides.
  bool _isLive(FaceBox b) => _settings.isLive(b.liveness);

  String _livenessWord(FaceBox b) => _isLive(b) ? 'Live' : 'Spoof';

  String _genderText(FaceBox b) {
    final label = (b.genderLabel ?? '').trim();
    if (label.isNotEmpty) return label;
    final g = b.gender;
    if (g == null) return '';
    return g.round() == 0 ? 'Male' : 'Female';
  }

  /// Pass/fail of each gated value the engine computed.
  List<bool> _gates(FaceAttributes f) {
    final b = f.box;
    return [
      if (_hasLiveness(b)) _isLive(b),
      (b.yaw ?? 0).abs() <= _settings.yaw,
      (b.roll ?? 0).abs() <= _settings.roll,
      (b.pitch ?? 0).abs() <= _settings.pitch,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faces = _result.faces;
    final n = faces.length;
    final selected = n == 0 ? null : faces[_selected.clamp(0, n - 1)];
    final detectMs = _result.report.steps
        .where((s) => s.name == 'faceDetection')
        .fold<double>(0, (sum, s) => sum + s.ms);

    return Scaffold(
      appBar: AppBar(title: const Text('Attribute result')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Attributes',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              Pill(
                n == 0 ? 'No face found' : Ui.facesCount(n),
                color: n == 0 ? Ui.danger : Ui.statusMatch,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            n == 0
                ? 'Point the camera at a face, or pick a photo that shows one.'
                : n > FaceGallery.maxAttributeFaces
                    ? 'Only the largest ${FaceGallery.maxAttributeFaces} faces are searched '
                        'against the gallery.'
                    : 'Tap a face to see its values.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_photo != null) _ProbePhoto(image: _photo!),
          const SizedBox(height: 12),
          MetricsRow(tiles: [
            MetricTile(value: '$n', label: 'Faces'),
            MetricTile(value: Ui.ms(detectMs), label: 'Detect ms'),
            MetricTile(
              value: Ui.ms(_result.report.totalMs),
              label: 'Total ms',
            ),
          ]),
          if (n > 1) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in faces)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('Face ${f.index + 1}'),
                        selected: f.index == _selected,
                        onSelected: (_) =>
                            setState(() => _selected = f.index),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (selected == null)
            const SectionCard(
              title: 'Result',
              rows: [
                SectionRow(
                  label: 'Status',
                  value: 'No face found',
                  badge: ('Failed', RowBadge.fail),
                ),
              ],
            )
          else ...[
            _header(selected, scheme),
            const SizedBox(height: 12),
            ..._sections(selected),
          ],
          StatusCard(report: _result.report),
        ],
      ),
    );
  }

  Widget _header(FaceAttributes f, ColorScheme scheme) {
    final b = f.box;
    final failed = _gates(f).where((ok) => !ok).length;
    final subtitle = [
      if ((b.age ?? 0) > 0) '${b.age!.round()} years',
      if (_genderText(b).isNotEmpty) _genderText(b),
      if ((b.emotionLabel ?? '').trim().isNotEmpty) b.emotionLabel!.trim(),
      if (_hasLiveness(b)) _livenessWord(b),
    ].join(' · ');

    return AppCard(
      child: Row(
        children: [
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child: CustomPaint(
                  painter: _CropPainter(image: _photo!, box: b),
                ),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Face ${f.index + 1}',
                  style:
                      const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle.isEmpty ? 'Not computed' : subtitle,
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Pill(
            failed == 0
                ? 'All checks pass'
                : '$failed ${failed == 1 ? 'check' : 'checks'} failed',
            color: failed == 0 ? Ui.statusMatch : Ui.statusNoMatch,
            fontSize: 11,
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(FaceAttributes f) {
    final b = f.box;
    const notComputed = 'Not computed';

    return [
      // Authenticity
      SectionCard(
        title: 'Authenticity',
        rows: [
          if (_hasLiveness(b))
            SectionRow(
              label: 'Liveness',
              value: '${_livenessWord(b)} · ${Ui.score(b.liveness ?? double.nan)}'
                  '  (≥ ${Ui.score(_settings.livenessThreshold)})',
              badge: _isLive(b) ? ('Pass', RowBadge.pass) : ('Fail', RowBadge.fail),
              score: b.liveness,
            )
          else
            const SectionRow(label: 'Liveness', value: notComputed),
        ],
      ),

      // Person
      SectionCard(
        title: 'Person',
        rows: [
          SectionRow(
            label: 'Age',
            value: (b.age ?? 0) > 0 ? '${b.age!.round()}' : notComputed,
          ),
          SectionRow(
            label: 'Gender',
            value: _genderText(b).isEmpty ? notComputed : _genderText(b),
          ),
        ],
      ),

      // Quality
      SectionCard(
        title: 'Quality',
        rows: [
          _qualityRow(b),
          if ((b.faceLuminance ?? double.nan).isFinite)
            SectionRow(
              label: 'Luminance',
              value: Ui.score(b.faceLuminance!),
              score: b.faceLuminance,
            ),
        ],
      ),

      // Pose
      SectionCard(
        title: 'Head pose',
        rows: [
          _poseRow('Yaw', b.yaw, _settings.yaw),
          _poseRow('Roll', b.roll, _settings.roll),
          _poseRow('Pitch', b.pitch, _settings.pitch),
        ],
      ),

      // One eyes-open score from the engine, read against eyeOpen. Not a Settings threshold:
      // the engine's own label uses a fixed 0.5, which calls a half-open eye closed.
      //
      // One row, not two: the engine scores eye openness per face, and the bridge copies that
      // single value into both eyes, so a Left/Right pair printed the same number twice.
      SectionCard(
        title: 'Eyes',
        rows: [
          _eyeRow('Eyes open', b.leftEyeClosed, b.eyesLeftLabel),
        ],
      ),

      // Expression: the engine's emotion label, plus mouth openness from the lip points.
      SectionCard(
        title: 'Expression',
        rows: [
          SectionRow(
            label: 'Emotion',
            value: (b.emotionLabel ?? '').trim().isEmpty
                ? notComputed
                : b.emotionLabel!.trim(),
            badge: (b.emotionLabel ?? '').trim().isEmpty
                ? null
                : (b.emotionLabel!.trim(), RowBadge.info),
          ),
          _mouthRow(b),
        ],
      ),

      // Gallery
      SectionCard(
        title: 'Gallery',
        rows: [
          _closestRow(f),
          SectionRow(
            label: 'Template',
            value: f.templateBytes > 0
                ? '${f.templateBytes} bytes'
                : 'No template',
          ),
        ],
      ),

      // Geometry
      SectionCard(
        title: 'Geometry',
        rows: [
          SectionRow(
            label: 'Box',
            value: '${b.x1.round()}, ${b.y1.round()} → '
                '${b.x2.round()}, ${b.y2.round()}',
          ),
          SectionRow(
            label: 'Size',
            value: '${b.width.round()} × ${b.height.round()} px',
          ),
          SectionRow(
            label: 'Landmarks',
            value: (b.landmarkCount ?? 0) > 0
                ? '${b.landmarkCount} points'
                : notComputed,
          ),
          if ((b.landmarkCount ?? 0) > 0 && b.landmarks != null)
            SectionRow(
              label: 'Positions',
              value: _landmarkText(b),
              collapsed: true,
            ),
        ],
      ),

      // Anything else the engine reported
      if (_extras(b).isNotEmpty)
        SectionCard(
          title: 'More from the engine',
          rows: [
            for (final e in _extras(b).entries)
              SectionRow(label: e.key, value: e.value),
          ],
        ),
    ];
  }

  Widget _qualityRow(FaceBox b) {
    final q = b.faceQuality;
    if (q == null || !q.isFinite) {
      return const SectionRow(label: 'Face quality', value: 'Not computed');
    }
    final badge = q < 0.5
        ? ('Low', RowBadge.fail)
        : q < 0.75
            ? ('Medium', RowBadge.warn)
            : ('High', RowBadge.pass);
    return SectionRow(
      label: 'Face quality',
      value: Ui.score(q),
      badge: badge,
      score: q,
    );
  }

  Widget _poseRow(String label, double? value, double limit) {
    if (value == null || !value.isFinite) {
      return SectionRow(label: label, value: 'Not computed');
    }
    final ok = value.abs() <= limit;
    return SectionRow(
      label: label,
      value: '${Ui.angle(value)}°  (±${Ui.angle(limit)}°)',
      badge: ok ? ('Pass', RowBadge.pass) : ('Over', RowBadge.fail),
    );
  }

  Widget _mouthRow(FaceBox b) {
    final m = b.mouthOpened;
    if (m == null || !m.isFinite) {
      return const SectionRow(label: 'Mouth', value: 'Not computed');
    }
    final (word, kind) = m >= AttributeResultScreen.mouthOpen
        ? ('Open', RowBadge.warn)
        : m >= AttributeResultScreen.mouthSlight
            ? ('Slightly open', RowBadge.info)
            : ('Closed', RowBadge.pass);
    return SectionRow(
      label: 'Mouth',
      value: '$word · ${Ui.score(m)}',
      badge: (word, kind),
      score: m,
    );
  }

  Widget _closestRow(FaceAttributes f) {
    final c = f.closest;
    if (_result.gallerySize == 0) {
      return const SectionRow(
        label: 'Closest match',
        value: 'No faces in the gallery',
      );
    }
    if (f.templateBytes == 0) {
      return const SectionRow(label: 'Closest match', value: 'No template');
    }
    if (c == null) {
      return const SectionRow(
        label: 'Closest match',
        value: 'No faces in the gallery',
      );
    }
    final matched = c.similarity >= _result.threshold;
    return SectionRow(
      label: 'Closest match',
      value: '${c.name} · ${Ui.idTag(c.id)}\n${Ui.score(c.similarity)}'
          '  (≥ ${Ui.score(_result.threshold)})',
      badge: matched ? ('Match', RowBadge.pass) : ('No match', RowBadge.warn),
      score: c.similarity,
      onTap: () =>
          FaceDetailSheet.show(context, c.id, similarity: c.similarity),
    );
  }

  /// One eye, with its open score read against [AttributeResultScreen.eyeOpen].
  Widget _eyeRow(String label, double? closed, String? engineLabel) {
    if (closed == null || !closed.isFinite) {
      final text = (engineLabel ?? '').trim();
      return SectionRow(
        label: label,
        value: text.isEmpty ? 'Not computed' : text,
      );
    }
    final open = (1 - closed).clamp(0.0, 1.0);
    final isOpen = open >= AttributeResultScreen.eyeOpen;
    final word = isOpen ? 'Open' : 'Closed';
    return SectionRow(
      label: label,
      value: '$word · ${Ui.score(open)}'
          '  (≥ ${Ui.score(AttributeResultScreen.eyeOpen)})',
      badge: (word, isOpen ? RowBadge.pass : RowBadge.warn),
      score: open,
    );
  }

  static String _landmarkText(FaceBox b) {
    final points = b.landmarks ?? const [];
    final count = b.landmarkCount ?? 0;
    final lines = <String>[];
    for (var i = 0; i < count && i * 2 + 1 < points.length; i++) {
      lines.add('${i + 1}:  ${Ui.angle(points[i * 2])}, '
          '${Ui.angle(points[i * 2 + 1])}');
    }
    return lines.join('\n');
  }

  /// Engine attributes the sections above do not already name.
  static Map<String, String> _extras(FaceBox b) {
    const shown = {
      'Age',
      'Gender',
      'Emotion',
      'Liveness2D',
      'FaceQuality',
      'EyesLeft',
      'EyesRight',
    };
    final out = <String, String>{};
    for (final e in (b.attributes ?? const <String, String>{}).entries) {
      if (shown.contains(e.key)) continue;
      if (e.value.trim().isEmpty || e.value.length >= 400) continue;
      out[e.key] = e.value;
    }
    return out;
  }
}

/// The probe photo, without face boxes or numbers.
class _ProbePhoto extends StatelessWidget {
  const _ProbePhoto({required this.image});

  final ui.Image image;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: image.width / image.height,
        child: CustomPaint(
          painter: _PhotoPainter(image: image),
        ),
      ),
    );
  }
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter({required this.image});

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(_PhotoPainter old) => old.image != image;
}

/// Draws just the face region of the photo, filling the given box.
class _CropPainter extends CustomPainter {
  _CropPainter({required this.image, required this.box});

  final ui.Image image;
  final FaceBox box;

  @override
  void paint(Canvas canvas, Size size) {
    // A little margin round the box reads better than a tight crop.
    final margin = box.width * 0.15;
    final src = Rect.fromLTRB(
      (box.x1 - margin).clamp(0.0, image.width.toDouble()),
      (box.y1 - margin).clamp(0.0, image.height.toDouble()),
      (box.x2 + margin).clamp(0.0, image.width.toDouble()),
      (box.y2 + margin).clamp(0.0, image.height.toDouble()),
    );
    if (src.width <= 0 || src.height <= 0) return;
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.box != box;
}
