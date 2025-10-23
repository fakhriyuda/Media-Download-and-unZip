import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBProvider {
  static final DBProvider _instance = DBProvider._internal();
  factory DBProvider() => _instance;
  DBProvider._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await initDB();
    return _db!;
  }

  Future<Database> initDB() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'videos.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE downloads(
          id INTEGER PRIMARY KEY,
          remote_url TEXT NOT NULL,
          local_path TEXT,
          status TEXT NOT NULL,
          size INTEGER,
          downloaded_at TEXT
        )
        ''');
      },
    );
  }

  Future<void> upsertRecord(Map<String, dynamic> record) async {
    final db = await database;
    await db.insert('downloads', record,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getRecord(int id) async {
    final db = await database;
    final res = await db.query('downloads', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return null;
    return res.first;
  }

  Future<List<Map<String, dynamic>>> getAllRecords() async {
    final db = await database;
    return await db.query('downloads', orderBy: 'id');
  }

  Future<void> deleteRecord(int id) async {
    final db = await database;
    await db.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }
}
