import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/activity_record.dart';

/// Persistencia local del historial (RF-06).
class DatabaseService {
  static Database? _db;

  static Future<Database> get _database async => _db ??= await _init();

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'fitness.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE activities(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user TEXT NOT NULL,
          date TEXT NOT NULL,
          duration INTEGER NOT NULL,
          steps INTEGER NOT NULL,
          distance REAL NOT NULL,
          route TEXT NOT NULL
        )
      '''),
    );
  }

  static Future<void> insert(ActivityRecord record) async {
    final db = await _database;
    await db.insert('activities', record.toMap()..remove('id'));
  }

  static Future<List<ActivityRecord>> getByUser(String user) async {
    final db = await _database;
    final rows = await db.query(
      'activities',
      where: 'user = ?',
      whereArgs: [user],
      orderBy: 'date DESC',
    );
    return rows.map(ActivityRecord.fromMap).toList();
  }
}