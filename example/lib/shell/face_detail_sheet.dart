import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';

import 'gallery_widgets.dart';
import 'status_card.dart';
import 'ui.dart';

/// Face detail sheet, opened from a result, the matches list or the People list.
/// [similarity] below zero hides the Similarity row (the People list has no score).
class FaceDetailSheet extends StatefulWidget {
  const FaceDetailSheet({super.key, required this.id, this.similarity = -1});

  final int id;
  final double similarity;

  static Future<void> show(
    BuildContext context,
    int id, {
    double similarity = -1,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FaceDetailSheet(id: id, similarity: similarity),
    );
  }

  @override
  State<FaceDetailSheet> createState() => _FaceDetailSheetState();
}

class _FaceDetailSheetState extends State<FaceDetailSheet> {
  FaceRecord? _record;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gallery = await FaceGallery.open();
    final record = await gallery.get(widget.id);
    if (!mounted) return;
    if (record == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That face is no longer in the gallery.')),
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _record = record;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    final record = _record;
    if (record == null) return;
    final nameController = TextEditingController(text: record.name);
    final noteController = TextEditingController(text: record.note);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit person'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a name.' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final gallery = await FaceGallery.open();
    await gallery.update(
      record.id,
      nameController.text.trim(),
      noteController.text.trim(),
    );
    await _load();
  }

  Future<void> _confirmDelete() async {
    final record = _record;
    if (record == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          'Delete ${record.name}? The face and its photos are removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Ui.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final gallery = await FaceGallery.open();
    final ok = await gallery.delete(record.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${record.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final record = _record;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) {
        if (_loading || record == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final report = record.report;
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    record.name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                Pill(Ui.idTag(record.id)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: GalleryImage(path: record.cropPath),
                      ),
                      const SizedBox(height: 4),
                      Text('Face crop',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: GalleryImage(
                          path: record.originalPath,
                          onMissing: Container(
                            color: scheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Text(
                              'Original not stored',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Enrolled photo',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionRow(
                    label: 'Note',
                    value: record.note.isEmpty ? 'No note' : record.note,
                  ),
                  SectionRow(
                    label: 'Enrolled',
                    value: Ui.enrolledDateTime(record.createdAt),
                  ),
                  if (widget.similarity >= 0)
                    SectionRow(
                      label: 'Similarity',
                      value: Ui.score(widget.similarity),
                      score: widget.similarity,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (report != null)
              StatusCard(report: report, title: 'Enrollment status')
            else
              AppCard(
                child: Text(
                  'This face was enrolled before call reports were stored, so there is no '
                  'status to show.',
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _confirmDelete,
                    style:
                        OutlinedButton.styleFrom(foregroundColor: Ui.danger),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
