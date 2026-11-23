import 'dart:io';

import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'status_card.dart';
import 'ui.dart';

/// Enroll with camera: the capture guide, then a review of the captured still.
///
/// The review and the enrollment status that follows are the same dialog, so the flow does
/// not change shape between two consecutive steps. The review lists each check with its value
/// and the Settings limit; name, note, Retake and Enroll are there from the start. Enroll is
/// blocked while a required check fails: one face, liveness (when on in Settings), and head
/// pose. Low quality only warns.
class AddPersonScreen extends StatefulWidget {
  const AddPersonScreen({super.key});

  @override
  State<AddPersonScreen> createState() => _AddPersonScreenState();
}

class _AddPersonScreenState extends State<AddPersonScreen> {
  final AppSettings _settings = AppSettings.instance;
  bool _reviewing = false;

  CaptureSettings get _captureSettings => CaptureSettings(
        cameraLens: CameraLens.front,
        livenessThreshold: _settings.livenessThreshold,
        livenessLevel: 0,
        yawThreshold: _settings.yaw,
        rollThreshold: _settings.roll,
        pitchThreshold: _settings.pitch,
        // The eye check during the hold is not useful: the review below checks the still.
        eyecloseThreshold: 1,
        matchThreshold: _settings.threshold,
      );

  Future<void> _onCaptured(CaptureResult result) async {
    if (_reviewing) return;
    _reviewing = true;
    final enrolled = await showAppDialog<Enrolled>(
      context,
      title: 'Review the capture',
      // Dismissing is a retake, not a silent exit: the capture is not yet enrolled.
      content: _ReviewBody(uri: result.uri),
      actions: const [],
    );
    _reviewing = false;
    if (!mounted || enrolled == null) return;

    await StatusCard.showAsDialog(
      context,
      title: 'Enrolled ${enrolled.record.name} as ${Ui.idTag(enrolled.record.id)}',
      // Every person over the threshold is named, not just the closest.
      reason: enrolled.duplicates.isEmpty
          ? null
          : 'This face also matches '
              '${enrolled.duplicates.map((c) => '${c.name} (${Ui.idTag(c.id)}) at ${Ui.score(c.similarity)}').join(', ')}'
              ' (threshold ${Ui.score(_settings.threshold)}). '
              'Enroll again only if it is the same person.',
      report: enrolled.report,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // No AppBar. The guide is centered in the camera itself; a bar above it
    // shifts that oval off the middle of the preview.
    return Scaffold(
      backgroundColor: Colors.black,
      body: FaceCapture(
        settings: _captureSettings,
        title: 'Hold still inside the oval',
        onCaptured: (result) => _onCaptured(result),
        onCancel: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// The body of the review dialog: the still, the checks, the fields and the two buttons.
///
/// It owns its own state because it lives inside a dialog route, which does not rebuild when
/// the screen behind it does. It pops with the [Enrolled] outcome, or with null for a retake.
class _ReviewBody extends StatefulWidget {
  const _ReviewBody({required this.uri});

  final String uri;

  @override
  State<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends State<_ReviewBody> {
  final AppSettings _settings = AppSettings.instance;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _note = TextEditingController();

  FaceBox? _face;
  int _faceCount = 0;
  bool _analyzing = true;
  bool _saving = false;
  String? _error;
  CallReport? _failedReport;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Re-detects with every estimator on, so the review shows real values rather than
  /// whatever the capture gate happened to need.
  Future<void> _analyze() async {
    final faces = await FaceEngine.instance.run(() => faceDetection(
          widget.uri,
          const FaceDetectionParam(
            allAttributes: true,
            checkLiveness: true,
            checkPose: true,
            checkLandmarks: true,
            checkEyeCloseness: true,
            estimateAgeGender: true,
            checkQuality: true,
            checkEmotion: true,
          ),
        ));
    if (!mounted) return;
    setState(() {
      _faceCount = faces.length;
      _face = faces.length == 1 ? faces.first : null;
      _analyzing = false;
    });
    // Nothing to report, and the tester asked not to be stopped: enroll straight away.
    if (_blocked == null && _settings.skipReview) await _enroll();
  }

  /// Why Enroll is blocked, or null when it is not.
  String? get _blocked {
    if (_analyzing) return null;
    final reasons = <String>[];
    final face = _face;
    if (_faceCount != 1 || face == null) {
      reasons.add(
        'The still must show exactly one face. Retake with one person in frame.',
      );
    } else {
      if (_settings.liveness &&
          (face.livenessLabel ?? '').trim().isNotEmpty &&
          !_settings.isLive(face.liveness)) {
        reasons.add(
          'The face did not pass the liveness threshold. Use a live face, not a photo '
          'or a screen.\nYou can turn Liveness off in Settings to enroll anyway.',
        );
      }
      if (!_settings.limits.poseOk(
        face.yaw ?? 0,
        face.roll ?? 0,
        face.pitch ?? 0,
      )) {
        reasons.add('The head is turned too far. Retake facing the camera.');
      }
    }
    return reasons.isEmpty ? null : reasons.join('\n');
  }

  String? get _warning {
    final q = _face?.faceQuality;
    if (_blocked != null || q == null || !q.isFinite || q >= 0.5) return null;
    return 'The face quality is low. The template will be weaker than usual.';
  }

  /// Enroll turns on once the checks have run and nothing blocks. The name is optional: a
  /// blank one is saved as Person N, so testing is capture then Enroll with no typing.
  bool get _canEnroll => !_saving && !_analyzing && _blocked == null;

  Future<void> _enroll() async {
    if (!_canEnroll) return;
    setState(() {
      _saving = true;
      _error = null;
      _failedReport = null;
    });

    final gallery = await FaceGallery.open();
    final outcome = await gallery.enroll(
      _name.text.trim(),
      _note.text.trim(),
      widget.uri,
      limits: _settings.limits,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    switch (outcome) {
      case Enrolled():
        // The status dialog is opened by the screen, so the two never stack.
        Navigator.of(context).pop(outcome);
      case EnrollRejected(:final reason, :final report):
        setState(() {
          _error = reason;
          _failedReport = report;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocked = _blocked;
    final warning = _warning;
    final path = widget.uri.startsWith('file://')
        ? Uri.parse(widget.uri).toFilePath()
        : widget.uri;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Pill(
            _analyzing
                ? 'Checking…'
                : blocked == null
                    ? 'Ready to enroll'
                    : 'Retake needed',
            color: _analyzing
                ? Ui.statusInfo
                : blocked == null
                    ? Ui.statusMatch
                    : Ui.danger,
          ),
        ),
        const SizedBox(height: 12),
        // While typing, the still gives up most of its height so the fields and the two
        // buttons stay reachable on a short screen.
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 150),
            child: Image.file(
              File(path),
              height: keyboardIsOpen(context) ? 96 : 220,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(height: 96),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_analyzing)
          const Center(child: CircularProgressIndicator())
        else
          SectionCard(
            title: 'Capture checks',
            rows: [
              SectionRow(
                label: 'Faces',
                value: '$_faceCount',
                badge: _faceCount == 1
                    ? ('Pass', RowBadge.pass)
                    : ('Fail', RowBadge.fail),
              ),
              if (_face != null) ..._faceRows(_face!),
            ],
          ),
        if (blocked != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              blocked,
              style: const TextStyle(fontSize: 13, color: Ui.danger),
            ),
          ),
        if (warning != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              warning,
              style: const TextStyle(fontSize: 13, color: Ui.statusNoMatch),
            ),
          ),
        TextField(
          controller: _name,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name (optional)',
            helperText: 'Left blank, this face is saved as Person N, matching its ID.',
            helperMaxLines: 2,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Ui.danger)),
        ],
        if (_failedReport != null) ...[
          const SizedBox(height: 12),
          StatusCard(report: _failedReport!, title: 'Enrollment status'),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  // Null pops the dialog as a retake; the screen goes back to the guide.
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Retake'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _canEnroll ? _enroll : null,
                  child: Text(_saving ? 'Saving…' : 'Enroll'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'The name is what Identify shows when this face matches.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  List<Widget> _faceRows(FaceBox face) {
    final rows = <Widget>[];
    final limits = _settings.limits;

    // Liveness: the Settings threshold decides; when Liveness is off it is shown, not enforced.
    if ((face.livenessLabel ?? '').trim().isNotEmpty) {
      final live = _settings.isLive(face.liveness);
      final value =
          '${live ? 'Live' : 'Spoof'} · ${Ui.score(face.liveness ?? double.nan)}'
          '  (≥ ${Ui.score(limits.liveness)})';
      rows.add(
        _settings.liveness
            ? SectionRow(
                label: 'Liveness',
                value: value,
                badge: live ? ('Pass', RowBadge.pass) : ('Fail', RowBadge.fail),
                score: face.liveness,
              )
            : SectionRow(
                label: 'Liveness',
                value: '$value · not enforced',
                score: face.liveness,
              ),
      );
    }

    // Quality warns only.
    final q = face.faceQuality;
    if (q != null && q.isFinite) {
      rows.add(SectionRow(
        label: 'Face quality',
        value: Ui.score(q),
        badge: q < 0.5
            ? ('Low', RowBadge.fail)
            : q < 0.75
                ? ('Medium', RowBadge.warn)
                : ('High', RowBadge.pass),
        score: q,
      ));
    }

    // Head pose against the Settings limits.
    final poseOk = limits.poseOk(
      face.yaw ?? 0,
      face.roll ?? 0,
      face.pitch ?? 0,
    );
    final widest =
        [limits.yaw, limits.roll, limits.pitch].reduce((a, b) => a > b ? a : b);
    rows.add(SectionRow(
      label: 'Head pose',
      value: 'yaw ${Ui.angle(face.yaw ?? 0)}° · roll ${Ui.angle(face.roll ?? 0)}° · '
          'pitch ${Ui.angle(face.pitch ?? 0)}°  (±${Ui.angle(widest)}°)',
      badge: poseOk ? ('Pass', RowBadge.pass) : ('Over', RowBadge.fail),
    ));

    return rows;
  }
}
