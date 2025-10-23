import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io';
import '../model/video_item.dart';

class VideoDb {
  static final VideoDb _instance = VideoDb._internal();
  factory VideoDb() => _instance;
  VideoDb._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docs.path, 'yudvatar.db');
    return await openDatabase(dbPath, version: 1, onCreate: (db, v) async {
      // videos table
      await db.execute('''
        CREATE TABLE videos (
          id INTEGER PRIMARY KEY,
          video_name TEXT NOT NULL,
          age_json TEXT,
          gender_json TEXT,
          downloaded INTEGER NOT NULL DEFAULT 0,
          saved_at TEXT
        )
      ''');
      // (you can also keep downloads table from previous example)
    });
  }

  Future<void> upsertVideos(List<VideoItem> items) async {
    final d = await db;
    final batch = d.batch();
    final now = DateTime.now().toIso8601String();
    for (final v in items) {
      // Convert lists/maps to JSON strings
      final ageJson = jsonEncode(v.age);
      final genderJson = jsonEncode(v.gender);

      // Use INSERT OR REPLACE to upsert by primary key (id)
      batch.rawInsert('''
        INSERT OR REPLACE INTO videos (id, video_name, age_json, gender_json, downloaded, saved_at)
        VALUES (?, ?, ?, ?, COALESCE((SELECT downloaded FROM videos WHERE id = ?), 0), ?)
      ''', [v.id, v.videoName, ageJson, genderJson, v.id, now]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<VideoItem>> getAllVideos() async {
    final d = await db;
    final rows = await d.query('videos', orderBy: 'id ASC');
    debugPrint('Fetched row item data: $rows');
    return rows.map((r) {
      final age = (r['age_json'] as String?) != null ? List<String>.from(jsonDecode(r['age_json'] as String)) : <String>[];
      final gender = (r['gender_json'] as String?) != null ? List<String>.from(jsonDecode(r['gender_json'] as String)) : <String>[];
      // Build VideoItem - adapt constructor if necessary
      return VideoItem(
        id: r['id'] as int,
        videoName: r['video_name'] as String,
        age: age,
        gender: gender,
      );
    }).toList();
  }

  Future<void> markAllDownloaded({int downloaded = 1}) async {
    final d = await db;
    await d.update('videos', {'downloaded': downloaded}, where: null);
  }

  Future<void> markDownloadedById(int id, {int downloaded = 1}) async {
    final d = await db;
    await d.update('videos', {'downloaded': downloaded}, where: 'id = ?', whereArgs: [id]);
  }
}
