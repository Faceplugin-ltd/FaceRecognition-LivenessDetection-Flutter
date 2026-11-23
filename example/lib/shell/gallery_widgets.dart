import 'dart:io';

import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';

import 'ui.dart';

/// A stored crop or original, by file path. Shows a person placeholder while the path is
/// empty or the file has gone (a record whose photo was cleared still lists).
class GalleryImage extends StatelessWidget {
  const GalleryImage({
    super.key,
    required this.path,
    this.size,
    this.radius = 12,
    this.fit = BoxFit.cover,
    this.onMissing,
  });

  final String? path;
  final double? size;
  final double radius;
  final BoxFit fit;

  /// Shown instead of the placeholder when the file is not there.
  final Widget? onMissing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = path;
    final hasFile = p != null && p.isNotEmpty && File(p).existsSync();

    final Widget child = hasFile
        ? Image.file(
            File(p),
            width: size,
            height: size,
            fit: fit,
            // A file replaced in place keeps its path, so key on the write time.
            key: ValueKey('$p@${File(p).lastModifiedSync().millisecondsSinceEpoch}'),
            errorBuilder: (_, __, ___) => _placeholder(scheme),
          )
        : (onMissing ?? _placeholder(scheme));

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _placeholder(ColorScheme scheme) => Container(
        width: size,
        height: size,
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.person,
          size: (size ?? 48) * 0.5,
          color: scheme.onSurfaceVariant,
        ),
      );
}

/// One match row: rank, thumbnail, name, ID tag, similarity bar and score.
class MatchRow extends StatelessWidget {
  const MatchRow({
    super.key,
    required this.rank,
    required this.candidate,
    this.record,
    this.onTap,
  });

  final int rank;
  final Candidate candidate;
  final FaceRecord? record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            GalleryImage(path: record?.cropPath, size: 44, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          record?.name ?? candidate.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Pill(Ui.idTag(candidate.id), fontSize: 11),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: candidate.similarity.clamp(0, 1),
                      minHeight: 4,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: Ui.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              Ui.score(candidate.similarity),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
