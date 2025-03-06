import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/alarm/alarm_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = await getDatabasesPath();
    return await openDatabase(
      join(path, 'alarm_database.db'),
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE alarms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT NOT NULL,
        is_enabled INTEGER NOT NULL,
        sound_id INTEGER NOT NULL,
        nfc_required INTEGER NOT NULL,
        days_active TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sleep_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        sleep_time TEXT NOT NULL,
        wake_time TEXT NOT NULL,
        total_hours REAL NOT NULL
      )
    ''');
  }

  Future<int> insertAlarm(AlarmModel alarm) async {
    final db = await database;
    return await db.insert(
      'alarms',
      alarm.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AlarmModel>> getAllAlarms() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('alarms');
    return List.generate(maps.length, (i) {
      return AlarmModel.fromMap(maps[i]);
    });
  }

  Future<int> updateAlarm(AlarmModel alarm) async {
    final db = await database;
    return await db.update(
      'alarms',
      alarm.toMap(),
      where: 'id = ?',
      whereArgs: [alarm.id],
    );
  }

  Future<int> deleteAlarm(int id) async {
    final db = await database;
    return await db.delete(
      'alarms',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> insertSleepHistory({
    required DateTime date,
    required DateTime sleepTime,
    required DateTime wakeTime,
  }) async {
    final db = await database;
    final totalHours = wakeTime.difference(sleepTime).inHours.toDouble();

    await db.insert(
      'sleep_history',
      {
        'date': date.toIso8601String(),
        'sleep_time': sleepTime.toIso8601String(),
        'wake_time': wakeTime.toIso8601String(),
        'total_hours': totalHours,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getSleepHistory() async {
    final db = await database;
    return await db.query('sleep_history', orderBy: 'date DESC');
  }
}