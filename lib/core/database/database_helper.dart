import 'package:flutter/material.dart';
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

  /// Initializes the SQLite database with proper versioning
  Future<Database> _initDatabase() async {
    String path = await getDatabasesPath();
    return await openDatabase(
      join(path, 'alarm_database_earlyUp.db'),
      version: 1,
      onCreate: _onCreate,
    );
  }

  /// Creates database tables on first initialization
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE alarms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT NOT NULL,
        is_enabled INTEGER NOT NULL,
        sound_id INTEGER NOT NULL,
        nfc_required INTEGER NOT NULL,
        days_active TEXT,
        is_for_today INTEGER NOT NULL DEFAULT 0,
        last_set_time TEXT,
        last_stop_time TEXT,
        duration_minutes INTEGER DEFAULT 30
      )
    ''');

    await db.execute('''
      CREATE TABLE sleep_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        sleep_time TEXT NOT NULL,
        wake_time TEXT NOT NULL,
        total_hours REAL NOT NULL,
        alarm_count INTEGER DEFAULT 1,
        total_alarm_duration INTEGER DEFAULT 30
      )
    ''');
  }


  /// Inserts a new alarm into the database
  Future<int> insertAlarm(AlarmModel alarm) async {
    try {
      final db = await database;
      print("from db helper: ${alarm.time}");
      print("from db helper alarmID: ${alarm.id}");
      return await db.insert(
        'alarms',
        alarm.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error inserting alarm: $e');
      rethrow;
    }
  }

  /// Retrieves all alarms from the database
  Future<List<AlarmModel>> getAllAlarms() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query('alarms');
      return List.generate(maps.length, (i) {
        return AlarmModel.fromMap(maps[i]);
      });
    } catch (e) {
      debugPrint('Error retrieving alarms: $e');
      return [];
    }
  }

  /// Updates an existing alarm's properties
  Future<int> updateAlarm(AlarmModel alarm) async {
    try {
      if (alarm.id == null) {
        throw Exception('Cannot update alarm without an ID');
      }

      print("from db helper--alarmID: ${alarm.id}");
      print("from db helper--alarmTime: ${alarm.time}");

      final db = await database;
      return await db.update(
        'alarms',
        alarm.toMap(),
        where: 'id = ?',
        whereArgs: [alarm.id],
      );
    } catch (e) {
      debugPrint('Error updating alarm: $e');
      return 0;
    }
  }

  /// Deletes an alarm by its ID
  Future<int> deleteAlarm(int id) async {
    try {
      print("from db helper deletedAlarm alarmID: $id");
      final db = await database;
      return await db.delete(
        'alarms',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Error deleting alarm: $e');
      return 0;
    }
  }

  /// Records or updates sleep history data for a specific date
  Future<void> insertSleepHistory({
    required DateTime date,
    required DateTime sleepTime,
    required DateTime wakeTime,
    required double totalHours,
    int alarmCount = 1,
    required int totalAlarmDuration,
  }) async {
    try {
      final db = await database;

      final formattedDate =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      debugPrint('💾 SLEEP HISTORY INSERT:');
      debugPrint('   Date: $formattedDate');
      debugPrint('   Sleep Time: ${sleepTime.toIso8601String()}');
      debugPrint('   Wake Time: ${wakeTime.toIso8601String()}');
      debugPrint('   Total Hours: $totalHours');
      debugPrint('   Alarm Count: $alarmCount');
      debugPrint('   Total Alarm Duration: $totalAlarmDuration minutes');
      
      // Check for existing records for this date
      final existingRecords = await db.query(
        'sleep_history',
        where: 'date LIKE ?',
        whereArgs: ['$formattedDate%'],
      );

      debugPrint('🔍 EXISTING RECORDS: ${existingRecords.length}');

      if (existingRecords.isNotEmpty) {
        // Update existing record with new data
        final record = existingRecords.first;
        debugPrint('🔄 UPDATING EXISTING RECORD ID: ${record['id']}');
        
        await db.update(
          'sleep_history',
          {
            'sleep_time': sleepTime.toIso8601String(),
            'wake_time': wakeTime.toIso8601String(),
            'total_hours': totalHours,
            'alarm_count': alarmCount,
            'total_alarm_duration': totalAlarmDuration,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [record['id']],
        );
        
        debugPrint('✅ SLEEP HISTORY UPDATED');
      } else {
        // Insert new record
        debugPrint('➕ INSERTING NEW RECORD');
        
        await db.insert('sleep_history', {
          'date': formattedDate,
          'sleep_time': sleepTime.toIso8601String(),
          'wake_time': wakeTime.toIso8601String(),
          'total_hours': totalHours,
          'alarm_count': alarmCount,
          'total_alarm_duration': totalAlarmDuration,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        
        debugPrint('✅ SLEEP HISTORY INSERTED');
      }
    } catch (e) {
      debugPrint('❌ Error inserting sleep history: $e');
      rethrow;
    }
  }

  /// update alarm duration
  Future<void> updateAlarmDuration(int alarmId, int actualDuration) async {
    final db = await database;
    await db.update(
      'alarms',
      {'duration_minutes': actualDuration},
      where: 'id = ?',
      whereArgs: [alarmId],
    );
  }

  /// Retrieves all sleep history records ordered by date
  Future<List<Map<String, dynamic>>> getSleepHistory() async {
    try {
      final db = await database;
      final result = await db.query('sleep_history', orderBy: 'date DESC');
      return result;
    } catch (e) {
      debugPrint('Database error in getSleepHistory(): $e');
      return [];
    }
  }

  /// Retrieves sleep history for a specific date range
  Future<List<Map<String, dynamic>>> getSleepHistoryRange(
      DateTime startDate, DateTime endDate) async {
    try {
      final db = await database;

      final startIso = startDate.toIso8601String();
      final endIso = endDate.toIso8601String();

      debugPrint('Querying sleep history range from $startIso to $endIso');

      final result = await db.query('sleep_history',
          where: 'date >= ? AND date <= ?',
          whereArgs: [startIso, endIso],
          orderBy: 'date DESC');

      debugPrint('Found ${result.length} records in date range');
      return result;
    } catch (e) {
      debugPrint('Error retrieving sleep history range: $e');
      return [];
    }
  }

  /// Update alarm set and stop times
  Future<int> updateAlarmTimes(int alarmId,
      {DateTime? setTime, DateTime? stopTime}) async {
    try {
      final db = await database;
      Map<String, dynamic> updates = {};

      if (setTime != null) {
        updates['last_set_time'] = setTime.toIso8601String();
        debugPrint('🔧 DATABASE: Updating alarm $alarmId set time to: ${setTime.toIso8601String()}');
      }

      if (stopTime != null) {
        updates['last_stop_time'] = stopTime.toIso8601String();
        debugPrint('🔧 DATABASE: Updating alarm $alarmId stop time to: ${stopTime.toIso8601String()}');
      }

      if (updates.isEmpty) return 0;

      final result = await db.update(
        'alarms',
        updates,
        where: 'id = ?',
        whereArgs: [alarmId],
      );
      
      debugPrint('🔧 DATABASE: Updated $result rows for alarm $alarmId');
      return result;
    } catch (e) {
      debugPrint('❌ Error updating alarm times: $e');
      return 0;
    }
  }

  /// Get all alarms that were set for today
  Future<List<Map<String, dynamic>>> getTodayAlarms() async {
    try {
      final db = await database;
      return await db
          .query('alarms', where: 'is_for_today = ?', whereArgs: [1]);
    } catch (e) {
      debugPrint('Error getting today\'s alarms: $e');
      return [];
    }
  }

  /// Deletes a sleep history record by its ID
  Future<int> deleteSleepHistoryRecord(int id) async {
    try {
      final db = await database;
      return await db.delete(
        'sleep_history',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Error deleting sleep history record: $e');
      return 0;
    }
  }

  /// Deletes all sleep history records from database
  Future<int> clearAllSleepHistory() async {
    try {
      final db = await database;
      final result = await db.delete('sleep_history');
      debugPrint('✅ Deleted all sleep history records from database: $result records');
      return result;
    } catch (e) {
      debugPrint('❌ Error clearing all sleep history: $e');
      return 0;
    }
  }

  /// Resets the "is_for_today" flag for all alarms
  Future<void> resetTodayAlarms() async {
    try {
      final db = await database;
      await db.update(
        'alarms',
        {'is_for_today': 0},
        where: 'is_for_today = ?',
        whereArgs: [1],
      );
    } catch (e) {
      debugPrint('Error resetting today\'s alarms: $e');
    }
  }

  /// Validates and reports on the database connection and structure
  Future<Map<String, dynamic>> verifyDatabaseConnection() async {
    debugPrint('\n=== DATABASE CONNECTION VERIFICATION ===');
    Map<String, dynamic> status = {
      'success': false,
      'message': '',
      'details': {}
    };

    try {
      final db = await database;
      final dbVersion = await db.getVersion();

      status['success'] = true;
      status['message'] = 'Database connection successful';
      status['details']['path'] = db.path;
      status['details']['version'] = dbVersion;

      final tables = await db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      List<String> tableNames = [];
      for (var table in tables) {
        tableNames.add(table['name'] as String);
      }
      status['details']['tables'] = tableNames;

      Map<String, dynamic> tableStructures = {};

      try {
        final alarmStructure = await db.rawQuery("PRAGMA table_info(alarms)");
        final alarmCount = Sqflite.firstIntValue(
            await db.rawQuery("SELECT COUNT(*) FROM alarms"));

        tableStructures['alarms'] = {
          'structure': alarmStructure,
          'recordCount': alarmCount
        };
      } catch (e) {
        tableStructures['alarms'] = {'error': e.toString()};
      }

      try {
        final sleepHistoryStructure =
            await db.rawQuery("PRAGMA table_info(sleep_history)");
        final sleepHistoryCount = Sqflite.firstIntValue(
            await db.rawQuery("SELECT COUNT(*) FROM sleep_history"));

        tableStructures['sleep_history'] = {
          'structure': sleepHistoryStructure,
          'recordCount': sleepHistoryCount
        };
      } catch (e) {
        tableStructures['sleep_history'] = {'error': e.toString()};
      }

      status['details']['tableStructures'] = tableStructures;

      debugPrint('\n=== DATABASE VERIFICATION COMPLETE ===');
      return status;
    } catch (e) {
      status['success'] = false;
      status['message'] = 'Database connection failed: $e';
      debugPrint('❌ DATABASE CONNECTION FAILED: $e');
      return status;
    }
  }
}
