import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'gallery_types.dart';

/// id, name, note and the feature blob, for the in-memory search cache.
class GalleryTemplate {
  const GalleryTemplate(this.id, this.name, this.note, this.feature);

  final int id;
  final String name;
  final String note;
  final Uint8List feature;
}

/// SQLite gallery: `id INTEGER PRIMARY KEY AUTOINCREMENT` so ids are never reused,
/// even after Delete all. The schema matches the Android and iOS apps.
class GalleryDb {
  GalleryDb._(this._db);

  final Database _db;

  static const _columns =
      'id, name, note, created_at, crop_path, original_path, enroll_report';

  static Future<GalleryDb> open() async {
    final path = '${await getDatabasesPath()}/identity.sqlite';
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE faces (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL,
              feature BLOB NOT NULL,
              crop_path TEXT NOT NULL DEFAULT '',
              original_path TEXT NOT NULL DEFAULT '',
              enroll_report TEXT NOT NULL DEFAULT ''
          )
        ''');
        await db.execute('CREATE INDEX idx_faces_name ON faces(name)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE faces ADD COLUMN enroll_report TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
    return GalleryDb._(db);
  }

  Future<int> insert(
    String name,
    String note,
    String createdAt,
    Uint8List feature,
  ) {
    return _db.insert('faces', {
      'name': name,
      'note': note,
      'created_at': createdAt,
      'feature': feature,
    });
  }

  Future<void> setPaths(int id, String crop, String original) async {
    await _db.update(
      'faces',
      {'crop_path': crop, 'original_path': original},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setReport(int id, String json) async {
    await _db.update(
      'faces',
      {'enroll_report': json},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> update(int id, String name, String note) async {
    final n = await _db.update(
      'faces',
      {'name': name, 'note': note},
      where: 'id = ?',
      whereArgs: [id],
    );
    return n > 0;
  }

  Future<bool> delete(int id) async {
    final n = await _db.delete('faces', where: 'id = ?', whereArgs: [id]);
    return n > 0;
  }

  /// Empties the gallery and restarts ids at 1. Clearing `sqlite_sequence` is what resets
  /// AUTOINCREMENT; without it the next person carries on from the old maximum, which makes a
  /// freshly cleared demo gallery look like it still remembers the last one.
  Future<int> deleteAll() async {
    final removed = await _db.delete('faces');
    await _db.delete('sqlite_sequence', where: 'name = ?', whereArgs: ['faces']);
    return removed;
  }

  Future<int> count([String query = '']) async {
    final f = _filter(query);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM faces${f.where}',
      f.args,
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<FaceRecord?> get(int id) async {
    final rows = await _db.rawQuery(
      'SELECT $_columns FROM faces WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _record(rows.first);
  }

  /// Newest first.
  Future<List<FaceRecord>> page(String query, int limit, int offset) async {
    final f = _filter(query);
    final rows = await _db.rawQuery(
      'SELECT $_columns FROM faces${f.where} ORDER BY id DESC LIMIT ? OFFSET ?',
      [...?f.args, limit, offset],
    );
    return rows.map(_record).toList(growable: false);
  }

  Future<List<GalleryTemplate>> allTemplates() async {
    final rows = await _db.rawQuery('SELECT id, name, note, feature FROM faces');
    return rows
        .map((r) => GalleryTemplate(
              (r['id'] as num).toInt(),
              r['name']?.toString() ?? '',
              r['note']?.toString() ?? '',
              r['feature'] as Uint8List,
            ))
        .toList(growable: false);
  }

  Future<List<String>> allPaths() async {
    final rows = await _db.rawQuery('SELECT crop_path, original_path FROM faces');
    final out = <String>[];
    for (final r in rows) {
      final crop = r['crop_path']?.toString() ?? '';
      final original = r['original_path']?.toString() ?? '';
      if (crop.isNotEmpty) out.add(crop);
      if (original.isNotEmpty) out.add(original);
    }
    return out;
  }

  Future<void> close() => _db.close();

  ({String where, List<Object?>? args}) _filter(String query) {
    final q = query.trim();
    if (q.isEmpty) return (where: '', args: null);
    final like =
        '%${q.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    return (
      where: " WHERE name LIKE ? ESCAPE '\\' OR note LIKE ? ESCAPE '\\'",
      args: [like, like],
    );
  }

  FaceRecord _record(Map<String, Object?> r) => FaceRecord(
        id: (r['id'] as num).toInt(),
        name: r['name']?.toString() ?? '',
        note: r['note']?.toString() ?? '',
        createdAt: r['created_at']?.toString() ?? '',
        cropPath: r['crop_path']?.toString() ?? '',
        originalPath: r['original_path']?.toString() ?? '',
        enrollReport: r['enroll_report']?.toString() ?? '',
      );
}
