import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io';

import 'package:yudvatar/model/campaign.dart';

class CampaignDb {
  static final CampaignDb _instance = CampaignDb._internal();
  factory CampaignDb() => _instance;
  CampaignDb._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docs.path, 'yudvatar.db');
    debugPrint('CampaignDb: opening DB at: $dbPath');

    // open with a version (use onUpgrade for migrations)
    final d = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        // fresh installs: create tables
        await db.execute('''
          CREATE TABLE campaigns (
            id INTEGER PRIMARY KEY,
            campaign_json TEXT NOT NULL,
            saved_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS campaigns (
              id INTEGER PRIMARY KEY,
              campaign_json TEXT NOT NULL,
              saved_at TEXT NOT NULL
            )
          ''');
        }
      },
    );

    // Extra safety: ensure table exists even if DB file pre-existed
    await d.execute('''
      CREATE TABLE IF NOT EXISTS campaigns (
        id INTEGER PRIMARY KEY,
        campaign_json TEXT NOT NULL,
        saved_at TEXT NOT NULL
      )
    ''');

    // debug: list existing tables
    final res = await d.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='campaigns'",
    );
    debugPrint('CampaignDb: campaigns table present? ${res.isNotEmpty}');

    return d;
  }

  // Upsert helper (safe insert with text encoding)
  Future<void> upsertCampaigns(List<Map<String, dynamic>> items) async {
    final d = await db;
    final batch = d.batch();
    final now = DateTime.now().toIso8601String();

    for (final raw in items) {
      final Map<String, dynamic> m = Map<String, dynamic>.from(raw);
      dynamic rawId = m['campaign_id'] ?? m['id'];
      int? id;
      if (rawId is int)
        id = rawId;
      else if (rawId is String)
        id = int.tryParse(rawId);

      final jsonStr = jsonEncode(m);
      if (id == null) {
        batch.insert('campaigns', {'campaign_json': jsonStr, 'saved_at': now});
      } else {
        batch.insert('campaigns', {
          'id': id,
          'campaign_json': jsonStr,
          'saved_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  // Safe reader: returns [] if table missing or other error
  Future<List<Campaign>> getAllCampaigns() async {
    try {
      final d = await db;
      // optional: verify table exists before querying
      final tables = await d.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='campaigns'",
      );
      if (tables.isEmpty) {
        debugPrint(
          'CampaignDb: campaigns table missing when reading — returning empty list',
        );
        return <Campaign>[];
      }

      final rows = await d.query('campaigns', orderBy: 'id ASC');
      return rows.map((r) {
        final jsonStr = r['campaign_json'] as String;
        return Campaign.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      }).toList();
    } catch (e, st) {
      debugPrint('CampaignDb.getAllCampaigns failure: $e\n$st');
      return <Campaign>[]; // fail-safe
    }
  }

  // Dev helper - delete DB file (only for local dev)
  Future<void> deleteDatabaseFileForDev() async {
    final docs = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docs.path, 'yudvatar.db');
    await deleteDatabase(dbPath);
    _db = null;
    debugPrint('CampaignDb: deleted DB at $dbPath');
  }
}
