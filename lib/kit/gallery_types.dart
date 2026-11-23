import '../src/face_box.dart';
import 'call_report.dart';

/// One enrolled face. Images live as JPEG files in app-private storage (see `FaceGallery`).
class FaceRecord {
  const FaceRecord({
    required this.id,
    required this.name,
    required this.note,
    required this.createdAt,
    required this.cropPath,
    required this.originalPath,
    this.enrollReport = '',
  });

  final int id;
  final String name;
  final String note;

  /// ISO-8601 UTC.
  final String createdAt;
  final String cropPath;
  final String originalPath;

  /// JSON of the [CallReport] from enrollment; empty for faces enrolled before it was stored.
  final String enrollReport;

  /// Null when the record predates stored reports, or the JSON cannot be read.
  CallReport? get report => CallReport.fromJsonString(enrollReport);

  /// Null when [createdAt] is not a timestamp this app wrote.
  DateTime? get createdAtTime => DateTime.tryParse(createdAt)?.toLocal();
}

/// One gallery hit for a probe face.
class Candidate {
  const Candidate(this.id, this.name, this.note, this.similarity);

  final int id;
  final String name;
  final String note;
  final double similarity;
}

class ProbeFace {
  const ProbeFace({
    required this.index,
    required this.box,
    required this.ranked,
  });

  final int index;
  final FaceBox box;

  /// Top [FaceGallery.topK] by similarity, highest first.
  final List<Candidate> ranked;

  Candidate? get best => ranked.isEmpty ? null : ranked.first;

  List<Candidate> matches(double threshold) =>
      ranked.where((c) => c.similarity >= threshold).toList(growable: false);

  bool matched(double threshold) => (best?.similarity ?? -1) >= threshold;
}

class IdentifyResult {
  const IdentifyResult({
    required this.probeUri,
    required this.faces,
    required this.threshold,
    required this.extractMs,
    required this.searchMs,
    required this.gallerySize,
    required this.report,
  });

  /// File URI of the probe image, kept for the result screen.
  final String probeUri;
  final List<ProbeFace> faces;
  final double threshold;
  final double extractMs;
  final double searchMs;
  final int gallerySize;
  final CallReport report;

  /// The face whose best candidate scores highest (drives the headline and Rank 1 tile).
  /// Falls back to the first face when nothing scored, so a probe against an empty gallery
  /// still has something to show.
  ProbeFace? get primary {
    if (faces.isEmpty) return null;
    var best = faces.first;
    var bestScore = best.best?.similarity ?? -1;
    for (final face in faces) {
      final score = face.best?.similarity ?? -1;
      if (score > bestScore) {
        bestScore = score;
        best = face;
      }
    }
    return best;
  }

  bool get matched => faces.any((f) => f.matched(threshold));

  /// Matches at/above the threshold across all probe faces, best score per person,
  /// highest first.
  List<Candidate> get matches {
    final best = <int, Candidate>{};
    for (final face in faces) {
      for (final c in face.ranked) {
        if (c.similarity < threshold) continue;
        final existing = best[c.id];
        if (existing == null || c.similarity > existing.similarity) {
          best[c.id] = c;
        }
      }
    }
    final out = best.values.toList(growable: false)
      ..sort((a, b) => b.similarity.compareTo(a.similarity));
    return out;
  }
}

/// One detected face on the Attribute page. [closest] is the best gallery hit
/// (null when the gallery is empty or there is no template).
class FaceAttributes {
  const FaceAttributes({
    required this.index,
    required this.box,
    required this.templateBytes,
    this.closest,
  });

  final int index;
  final FaceBox box;
  final int templateBytes;
  final Candidate? closest;
}

class AttributeResult {
  const AttributeResult({
    required this.probeUri,
    required this.report,
    this.faces = const [],
    this.threshold = 0,
    this.gallerySize = 0,
  });

  final String probeUri;
  final CallReport report;

  /// Every detected face, largest first. Empty when detection found nobody.
  final List<FaceAttributes> faces;
  final double threshold;
  final int gallerySize;
}

/// Outcomes are discriminated by type, so a caller never has to guess.
sealed class EnrollOutcome {
  const EnrollOutcome();
}

class Enrolled extends EnrollOutcome {
  const Enrolled(this.record, this.report, {this.duplicates = const []});

  final FaceRecord record;
  final CallReport report;

  /// Every already-enrolled person scoring at or above the identify threshold, highest
  /// first — not just the closest. One new face can match several existing ones, and hiding
  /// the rest makes the gallery look cleaner than it is.
  final List<Candidate> duplicates;

  /// The strongest match, for callers that only show one.
  Candidate? get duplicate => duplicates.isEmpty ? null : duplicates.first;
}

class EnrollRejected extends EnrollOutcome {
  const EnrollRejected(this.reason, {this.report});

  final String reason;
  final CallReport? report;
}

sealed class IdentifyOutcome {
  const IdentifyOutcome();
}

class IdentifyDone extends IdentifyOutcome {
  const IdentifyDone(this.result);

  final IdentifyResult result;
}

class IdentifyRejected extends IdentifyOutcome {
  const IdentifyRejected(this.reason, {this.report});

  final String reason;
  final CallReport? report;
}
