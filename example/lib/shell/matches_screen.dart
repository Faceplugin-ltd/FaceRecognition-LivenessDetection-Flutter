import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';

import 'face_detail_sheet.dart';
import 'gallery_widgets.dart';
import 'ui.dart';

/// The "N more ›" target: every match at or above the threshold.
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key, required this.result});

  final IdentifyResult result;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  Map<int, FaceRecord?> _records = {};
  FaceGallery? _gallery;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _gallery?.removeListener(_load);
    super.dispose();
  }

  Future<void> _open() async {
    final gallery = await FaceGallery.open();
    if (!mounted) return;
    _gallery = gallery..addListener(_load);
    await _load();
  }

  Future<void> _load() async {
    final gallery = _gallery;
    if (gallery == null) return;
    final map = <int, FaceRecord?>{};
    for (final c in widget.result.matches) {
      map[c.id] = await gallery.get(c.id);
    }
    if (mounted) setState(() => _records = map);
  }

  @override
  Widget build(BuildContext context) {
    // A person deleted while this screen is open drops out of the list.
    final matches = widget.result.matches
        .where((c) => !_records.containsKey(c.id) || _records[c.id] != null)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                Ui.matchesCount(matches.length),
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final c = matches[index];
          return MatchRow(
            rank: index + 1,
            candidate: c,
            record: _records[c.id],
            onTap: () =>
                FaceDetailSheet.show(context, c.id, similarity: c.similarity),
          );
        },
      ),
    );
  }
}
