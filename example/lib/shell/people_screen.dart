import 'dart:async';

import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

import 'add_person_screen.dart';
import 'face_detail_sheet.dart';
import 'gallery_widgets.dart';
import 'import_screen.dart';
import 'ui.dart';

/// People: count tag, Add person, ⋮ (Delete all faces), search, and the paged list.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  static const int pageSize = 30;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final List<FaceRecord> _items = [];

  FaceGallery? _gallery;
  Timer? _debounce;
  String _query = '';
  int _total = 0;
  int _generation = 0;
  bool _loading = false;
  bool _endReached = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >=
          _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
    _open();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gallery?.removeListener(_reload);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final gallery = await FaceGallery.open();
    if (!mounted) return;
    _gallery = gallery..addListener(_reload);
    _reload();
  }

  void _onSearchChanged(String value) {
    _query = value.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _reload);
  }

  Future<void> _reload() async {
    final gallery = _gallery;
    if (gallery == null || !mounted) return;
    final generation = ++_generation;
    setState(() {
      _items.clear();
      _endReached = false;
      _loading = false;
    });
    final all = await gallery.count();
    final filtered = _query.isEmpty ? all : await gallery.count(_query);
    if (generation != _generation || !mounted) return;
    setState(() => _total = filtered);
    _countAll = all;
    await _loadMore();
  }

  int _countAll = 0;

  Future<void> _loadMore() async {
    final gallery = _gallery;
    if (gallery == null || _loading || _endReached || !mounted) return;
    _loading = true;
    final generation = _generation;
    final page = await gallery.page(_query, pageSize, _items.length);
    if (generation != _generation || !mounted) {
      _loading = false;
      return;
    }
    setState(() {
      _loading = false;
      if (page.length < pageSize) _endReached = true;
      _items.addAll(page);
    });
  }

  Future<void> _showAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Enroll with camera'),
              subtitle: const Text('Capture a face with the camera guide.'),
              onTap: () => Navigator.of(context).pop('one'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Bulk enroll from photos'),
              subtitle: const Text('One photo becomes one person.'),
              onTap: () => Navigator.of(context).pop('many'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'one') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddPersonScreen()),
      );
    } else if (choice == 'many') {
      await _chooseMultipleSource();
    }
  }

  /// Bulk enroll from photos: pick several photos or a folder, as on Android/iOS.
  Future<void> _chooseMultipleSource() async {
    final source = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Bulk enroll from photos'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('photos'),
            child: const Text('Select photos'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('folder'),
            child: const Text('Select a folder'),
          ),
        ],
      ),
    );
    if (!mounted || source == null) return;
    List<String> paths = const [];
    if (source == 'photos') {
      final picked = await ImagePicker().pickMultiImage();
      paths = picked.map((x) => x.path).toList(growable: false);
    } else if (source == 'folder') {
      final picked = await pickFolderImages();
      paths = picked.map((x) => x.uri).toList(growable: false);
    }
    if (paths.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImportScreen(paths: paths),
      ),
    );
  }

  Future<void> _confirmDeleteAll() async {
    final gallery = _gallery;
    if (gallery == null) return;
    final n = await gallery.count();
    if (!mounted) return;
    if (n == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There is nothing to delete.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all faces'),
        content: Text(
          'Delete all $n enrolled ${n == 1 ? 'face' : 'faces'} and their photos? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Ui.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await gallery.deleteAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted $deleted ${deleted == 1 ? 'face' : 'faces'}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showEmpty = _items.isEmpty && !_loading && _total == 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              const Text(
                'People',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Pill('$_countAll'),
              const Spacer(),
              FilledButton.icon(
                onPressed: _showAddMenu,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add person'),
              ),
              IconButton(
                tooltip: 'Delete all faces',
                onPressed: _confirmDeleteAll,
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search name or note',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: showEmpty
              ? _Empty(searching: _query.isNotEmpty)
              : ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: scheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) {
                    final r = _items[index];
                    final date = Ui.enrolledDate(r.createdAt);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading:
                          GalleryImage(path: r.cropPath, size: 48, radius: 24),
                      title: Text(r.name),
                      subtitle:
                          Text(r.note.isEmpty ? date : '${r.note} · $date'),
                      trailing: Pill(Ui.idTag(r.id), fontSize: 11),
                      onTap: () => FaceDetailSheet.show(context, r.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              searching ? 'No results' : 'No one is enrolled yet',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            if (!searching) ...[
              const SizedBox(height: 6),
              Text(
                'Add a person to search against. Identify compares a probe face with '
                'everyone here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
