import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../src/channel.dart' as channel;
import '../src/face_box.dart';
import '../src/face_recognition_sdk_platform_interface.dart';
import '../src/models.dart';
import 'call_report.dart';
import 'face_engine.dart';
import 'face_limits.dart';
import 'gallery_db.dart';
import 'gallery_types.dart';

/// The on-device gallery: enroll, 1:N identify, attribute analysis, and the stored people.
///
/// Every engine call runs under [FaceEngine.run], so calls never overlap. The same steps,
/// thresholds and timings as the Android and iOS apps, because this is the same design.
///
/// ```dart
/// final gallery = await FaceGallery.open();
/// final outcome = await gallery.enroll('Mina', 'Front desk', photoUri, limits);
/// ```
class FaceGallery extends ChangeNotifier {
  FaceGallery._(this._db, this._imagesDir);

  /// The name a face gets when none was typed: it matches the ID shown beside it.
  static String autoName(int id) => 'Person $id';

  static const int topK = 100;
  static const int maxAttributeFaces = 10;
  static const String noFace = 'No face found. Use a clear, front-facing photo.';
  static const String livenessFailed =
      'Liveness check failed. Use a live face, not a photo or screen.';
  static const String noTemplate =
      'Could not read this face. Use a clear, front-facing photo.';

  final GalleryDb _db;
  final Directory _imagesDir;

  List<GalleryTemplate>? _cache;

  static FaceGallery? _instance;

  /// Opens the gallery once per process. Later calls return the same instance.
  static Future<FaceGallery> open() async {
    final existing = _instance;
    if (existing != null) return existing;
    final db = await GalleryDb.open();
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/gallery');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _instance = FaceGallery._(db, dir);
  }

  /// Null until [open] has completed; screens that only read can use this to avoid awaiting.
  static FaceGallery? get instanceOrNull => _instance;

  void _changed() {
    _cache = null;
    notifyListeners();
  }

  Future<List<GalleryTemplate>> _templates() async =>
      _cache ??= await _db.allTemplates();

  // ---- read ----

  Future<int> count([String query = '']) => _db.count(query);

  Future<FaceRecord?> get(int id) => _db.get(id);

  Future<List<FaceRecord>> page(String query, int limit, int offset) =>
      _db.page(query, limit, offset);

  // ---- enroll ----

  /// Exactly-one-face enrollment from [photoUri].
  /// Steps: detection, template, duplicate check (1:N against the gallery), save.
  Future<EnrollOutcome> enroll(
    String name,
    String note,
    String photoUri, {
    FaceLimits limits = FaceLimits.standard,
  }) async {
    final cleanName = name.trim();
    final engine = FaceEngine.instance;
    if (!engine.isReady) return EnrollRejected(engine.stateMessage);

    final steps = <CallStep>[];
    // One engine pass: the template comes back with the detection, from the same open image,
    // as the Android app's kit does. The two still show as separate steps below.
    final found = await engine.run(() => _timed(
          steps,
          'faceDetection',
          () => channel.faceDetection(
            photoUri,
            const FaceDetectionParam(
              checkPose: true,
              checkLandmarks: true,
              checkQuality: true,
            ),
            1,
          ),
          detail: (faces) => _facesDetail(faces.length),
          ok: (faces) => faces.length == 1,
        ));
    _splitTemplateTime(steps, found);

    if (found.isEmpty) {
      return EnrollRejected(noFace,
          report: _report('enroll', steps, 'No face', success: false));
    }
    if (found.length > 1) {
      return EnrollRejected(
        '${found.length} faces found. Use a photo that shows only one person.',
        report: _report('enroll', steps, '${found.length} faces', success: false),
      );
    }

    final face = found.first;
    final featureB64 = face.templateBase64 ?? '';
    steps.add(CallStep(
      'templateExtraction',
      _templateMs(found),
      featureB64.isEmpty ? 'no template' : '${_bytesOf(featureB64).length} bytes',
      ok: featureB64.isNotEmpty,
    ));
    if (featureB64.isEmpty) {
      return EnrollRejected(noTemplate,
          report: _report('enroll', steps, 'template failed', success: false));
    }

    final gallery = await _templates();
    final ranked = await engine.run(() => _timed(
          steps,
          'duplicateCheck',
          () => _scoreAll(featureB64, gallery)
              .then((list) => list..sort((a, b) => b.similarity.compareTo(a.similarity))),
          detail: (list) {
            if (list.isEmpty) return 'gallery empty';
            final over =
                list.where((c) => c.similarity >= limits.match).toList(growable: false);
            if (over.isEmpty) {
              return 'closest ${list.first.name} · ID ${list.first.id} · '
                  '${_f2(list.first.similarity)}';
            }
            return '${over.map((c) => '${c.name} · ID ${c.id} · ${_f2(c.similarity)}').join(', ')}'
                ' · possible duplicate${over.length > 1 ? 's' : ''}';
          },
        ));

    final cropB64 = await engine.run(() => channel.cropFace(photoUri, face));
    final id = await _timed(
      steps,
      'save',
      () async {
        final newId = await _db.insert(
          cleanName,
          note.trim(),
          _isoNow(),
          _bytesOf(featureB64),
        );
        final cropFile = File('${_imagesDir.path}/${newId}_crop.jpg');
        final originalFile = File('${_imagesDir.path}/${newId}_original.jpg');
        if (cropB64.isNotEmpty) {
          await cropFile.writeAsBytes(_bytesOf(cropB64), flush: true);
        }
        await _copyTo(photoUri, originalFile);
        await _db.setPaths(
          newId,
          cropFile.existsSync() ? cropFile.path : '',
          originalFile.existsSync() ? originalFile.path : '',
        );
        return newId;
      },
      detail: (newId) => 'ID $newId · ${gallery.length + 1} enrolled',
    );

    // A blank name is named after the id it was just given, so the People list and the
    // identify headline never show an empty space where a name belongs.
    final finalName = cleanName.isEmpty ? autoName(id) : cleanName;
    if (finalName != cleanName) await _db.update(id, finalName, note.trim());

    final duplicates =
        ranked.where((c) => c.similarity >= limits.match).toList(growable: false);
    final report = _report(
      'enroll',
      steps,
      duplicates.isEmpty
          ? 'Saved $finalName as ID $id'
          : 'Saved $finalName as ID $id · looks like '
              '${duplicates.map((c) => '${c.name} (ID ${c.id})').join(', ')}',
      progress: '${steps.length} of ${steps.length} · saved',
    );
    await _db.setReport(id, report.toJsonString());
    _changed();
    final record = await _db.get(id);
    if (record == null) {
      return EnrollRejected('Could not read the saved face back.', report: report);
    }
    return Enrolled(record, report, duplicates: duplicates);
  }

  // ---- identify ----

  Future<IdentifyOutcome> identify(
    String probeUri,
    FaceLimits limits, {
    required bool livenessOn,
  }) async {
    final engine = FaceEngine.instance;
    if (!engine.isReady) return IdentifyRejected(engine.stateMessage);

    final steps = <CallStep>[];
    // One engine pass again: every probe face is templated from the same open image.
    final faces = await engine.run(() => _timed(
          steps,
          'faceDetection',
          () => channel.faceDetection(
            probeUri,
            FaceDetectionParam(
              checkLiveness: livenessOn,
              checkPose: true,
              checkLandmarks: true,
              // Both native kits identify with eyes on; the probe's eye openness is shown
              // beside the match.
              checkEyeCloseness: true,
            ),
            maxAttributeFaces,
          ),
          detail: (f) => _facesDetail(f.length),
          ok: (f) => f.isNotEmpty,
        ));
    _splitTemplateTime(steps, faces);

    if (faces.isEmpty) {
      return IdentifyRejected(noFace,
          report: _report('identify', steps, 'No face', success: false));
    }

    if (livenessOn) {
      final live = faces.where((f) => limits.isLive(f.liveness)).length;
      final lowest = faces
          .map((f) => f.liveness ?? double.nan)
          .fold<double>(double.infinity, (a, b) => b.isNaN ? a : (b < a ? b : a));
      // Liveness is scored during detection; this step applies the threshold.
      steps.add(CallStep(
        'livenessCheck',
        0,
        '$live of ${faces.length} live · lowest ${_f2(lowest)} / ${_f2(limits.liveness)}',
        ok: live == faces.length,
      ));
      if (live < faces.length) {
        return IdentifyRejected(
          livenessFailed,
          report: _report('identify', steps, 'Liveness failed', success: false),
        );
      }
    }

    final extracted = <({FaceBox face, String feature})>[];
    for (final face in faces) {
      final b64 = face.templateBase64;
      if (b64 != null && b64.isNotEmpty) extracted.add((face: face, feature: b64));
    }
    steps.add(CallStep(
      'templateExtraction',
      _templateMs(faces),
      '${extracted.length} templates',
      ok: extracted.isNotEmpty,
    ));

    if (extracted.isEmpty) {
      return IdentifyRejected(noTemplate,
          report: _report('identify', steps, 'template failed', success: false));
    }

    final gallery = await _templates();
    final probeFaces = await engine.run(() => _timed(
          steps,
          'similarity',
          () async {
            final out = <ProbeFace>[];
            for (var i = 0; i < extracted.length; i++) {
              final scored = await _scoreAll(extracted[i].feature, gallery);
              scored.sort((a, b) => b.similarity.compareTo(a.similarity));
              out.add(ProbeFace(
                index: i,
                box: extracted[i].face,
                ranked: scored.take(topK).toList(growable: false),
              ));
            }
            return out;
          },
          detail: (_) =>
              '${gallery.length} enrolled · ${extracted.length} probes',
        ));

    double? best;
    for (final f in probeFaces) {
      final s = f.best?.similarity;
      if (s != null && (best == null || s > best)) best = s;
    }
    final report = _report(
      'identify',
      steps,
      best == null
          ? 'Gallery empty'
          : 'Best similarity ${_f2(best)} · threshold ${_f2(limits.match)}',
      progress: '${steps.length} of ${steps.length} · similarity',
    );
    final searchMs = steps
        .where((s) => s.name == 'similarity')
        .fold<double>(0, (sum, s) => sum + s.ms);

    return IdentifyDone(IdentifyResult(
      probeUri: probeUri,
      faces: probeFaces,
      threshold: limits.match,
      extractMs: report.totalMs - searchMs,
      searchMs: searchMs,
      gallerySize: gallery.length,
      report: report,
    ));
  }

  // ---- attributes ----

  /// Attribute detection on every face, then a template and a 1:N gallery search per face
  /// (up to [maxAttributeFaces]), timing each call.
  Future<AttributeResult> attributes(
    String probeUri, {
    FaceLimits limits = FaceLimits.standard,
  }) async {
    final steps = <CallStep>[];
    final engine = FaceEngine.instance;
    if (!engine.isReady) {
      return AttributeResult(
        probeUri: probeUri,
        report: _report('attribute', steps, engine.stateMessage, success: false),
        threshold: limits.match,
      );
    }

    final gallery = await _templates();
    final found = await engine.run(() => _timed(
          steps,
          'faceDetection',
          () => channel.faceDetection(
            probeUri,
            const FaceDetectionParam(
              allAttributes: true,
              checkLiveness: true,
              checkPose: true,
              checkLandmarks: true,
              checkEyeCloseness: true,
              checkFaceOcclusion: true,
              estimateAgeGender: true,
              checkQuality: true,
              checkEmotion: true,
              checkMask: true,
              checkGlasses: true,
            ),
            maxAttributeFaces,
            true,
          ),
          detail: (f) => '${_facesDetail(f.length)} · attributes',
          ok: (f) => f.isNotEmpty,
        ));
    _splitTemplateTime(steps, found);

    // The bridge already ordered them largest first, so the templates belong to the faces
    // this screen searches.
    final ordered = found;
    final searched = ordered.take(maxAttributeFaces).toList(growable: false);

    final features = <String>[];
    if (searched.isNotEmpty) {
      for (final f in searched) {
        features.add(f.templateBase64 ?? '');
      }
      steps.add(CallStep(
        'templateExtraction',
        _templateMs(found),
        '${features.where((e) => e.isNotEmpty).length} of ${features.length} templates',
        ok: features.any((e) => e.isNotEmpty),
      ));
    }

    var closest = <Candidate?>[];
    if (features.any((e) => e.isNotEmpty)) {
      closest = await engine.run(() => _timed(
            steps,
            'similarity',
            () async {
              final out = <Candidate?>[];
              for (final feature in features) {
                out.add(feature.isEmpty || gallery.isEmpty
                    ? null
                    : await _closest(feature, gallery));
              }
              return out;
            },
            detail: (_) =>
                '${gallery.length} enrolled · ${features.where((e) => e.isNotEmpty).length} probes',
          ));
    }

    final faces = <FaceAttributes>[];
    for (var i = 0; i < ordered.length; i++) {
      final feature = i < features.length ? features[i] : '';
      faces.add(FaceAttributes(
        index: i,
        box: ordered[i],
        templateBytes: feature.isEmpty ? 0 : _bytesOf(feature).length,
        closest: i < closest.length ? closest[i] : null,
      ));
    }

    Candidate? bestHit;
    for (final f in faces) {
      final c = f.closest;
      if (c != null && (bestHit == null || c.similarity > bestHit.similarity)) {
        bestHit = c;
      }
    }
    final detail = faces.isEmpty
        ? 'No face'
        : _facesDetail(faces.length) +
            (bestHit == null
                ? ''
                : ' · closest ${bestHit.name} ${_f2(bestHit.similarity)}');

    return AttributeResult(
      probeUri: probeUri,
      report: _report('attribute', steps, detail, success: faces.isNotEmpty),
      faces: faces,
      threshold: limits.match,
      gallerySize: gallery.length,
    );
  }

  // ---- edit / delete ----

  Future<bool> update(int id, String name, String note) async {
    final ok = await _db.update(id, name.trim(), note.trim());
    if (ok) _changed();
    return ok;
  }

  Future<bool> delete(int id) async {
    final record = await _db.get(id);
    if (record == null) return false;
    final ok = await _db.delete(id);
    if (ok) {
      for (final path in [record.cropPath, record.originalPath]) {
        if (path.isEmpty) continue;
        try {
          final file = File(path);
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
      _changed();
    }
    return ok;
  }

  /// Removes every record and every stored crop/original. Returns the number deleted.
  Future<int> deleteAll() async {
    final n = await _db.deleteAll();
    try {
      for (final entity in _imagesDir.listSync()) {
        entity.deleteSync(recursive: true);
      }
    } catch (_) {}
    _changed();
    return n;
  }

  // ---- helpers ----

  Future<List<Candidate>> _scoreAll(
    String feature,
    List<GalleryTemplate> gallery,
  ) async {
    final platform = FaceRecognitionSdkPlatform.instance;
    final out = <Candidate>[];
    for (final t in gallery) {
      final score = await platform.similarity(feature, base64Encode(t.feature));
      out.add(Candidate(t.id, t.name, t.note, score));
    }
    return out;
  }

  Future<Candidate?> _closest(
    String feature,
    List<GalleryTemplate> gallery,
  ) async {
    Candidate? best;
    for (final c in await _scoreAll(feature, gallery)) {
      if (best == null || c.similarity > best.similarity) best = c;
    }
    return best;
  }

  /// Runs [block], appends a [CallStep] for it to [steps], and returns its value.
  Future<T> _timed<T>(
    List<CallStep> steps,
    String name,
    Future<T> Function() block, {
    required String Function(T) detail,
    bool Function(T)? ok,
  }) async {
    final watch = Stopwatch()..start();
    final value = await block();
    watch.stop();
    steps.add(CallStep(
      name,
      watch.elapsedMicroseconds / 1000,
      detail(value),
      ok: ok?.call(value) ?? true,
    ));
    return value;
  }

  CallReport _report(
    String function,
    List<CallStep> steps,
    String detail, {
    String progress = '',
    bool success = true,
  }) {
    final shown = progress.isNotEmpty
        ? progress
        : success
            ? '${steps.length} of ${steps.length} · ${steps.isEmpty ? 'done' : steps.last.name}'
            : '${steps.where((s) => s.ok).length} of ${steps.length} · stopped at '
                '${steps.firstWhere((s) => !s.ok, orElse: () => const CallStep('start', 0, '')).name}';
    return CallReport(
      function: function,
      steps: List<CallStep>.unmodifiable(steps),
      progress: shown,
      detail: detail,
      success: success,
    );
  }

  /// Template time reported per face by the bridge, summed.
  static double _templateMs(List<FaceBox> faces) =>
      faces.fold<double>(0, (sum, f) => sum + f.templateMs);

  /// The detect step measured the whole call, templates included. This takes the template
  /// time back out so the two steps on the status card still read as separate work.
  static void _splitTemplateTime(List<CallStep> steps, List<FaceBox> faces) {
    final index = steps.lastIndexWhere((s) => s.name == 'faceDetection');
    if (index < 0) return;
    final step = steps[index];
    final detectOnly = step.ms - _templateMs(faces);
    steps[index] = CallStep(
      step.name,
      detectOnly > 0 ? detectOnly : step.ms,
      step.detail,
      ok: step.ok,
    );
  }

  static String _facesDetail(int n) => n == 1 ? '1 face' : '$n faces';

  static String _f2(double v) => v.isFinite ? v.toStringAsFixed(2) : '–';

  static Uint8List _bytesOf(String base64Value) {
    try {
      return base64Decode(base64Value);
    } catch (_) {
      return Uint8List(0);
    }
  }

  static String _isoNow() {
    final now = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}T'
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}Z';
  }

  /// Copies the probe image into the gallery folder, accepting a path or a `file://` URI.
  static Future<void> _copyTo(String uri, File target) async {
    try {
      final path = uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
      final source = File(path);
      if (source.existsSync()) await source.copy(target.path);
    } catch (_) {}
  }
}
