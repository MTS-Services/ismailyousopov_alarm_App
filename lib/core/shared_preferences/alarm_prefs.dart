import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AlarmPrefs {
  static const String _alarmDataKey = 'alarm_data';
  static const String _alarmSetTimeKey = 'alarm_set_time';
  static const String _alarmStopTimeKey = 'alarm_stop_time';

  /// Save alarm data to SharedPreferences
  static Future<void> saveAlarmData({
    required int alarmId,
    required DateTime setTime,
    required DateTime? stopTime,
    required bool isRepeating,
    required List<String> daysActive,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Store alarm data as JSON
      final alarmData = {
        'alarmId': alarmId,
        'setTime': setTime.toIso8601String(),
        'stopTime': stopTime?.toIso8601String(),
        'isRepeating': isRepeating,
        'daysActive': daysActive,
      };
      
      // Get existing alarms
      final existingData = prefs.getString('$_alarmDataKey$alarmId');
      List<Map<String, dynamic>> alarms = [];
      
      if (existingData != null) {
        final List<dynamic> jsonList = json.decode(existingData);
        alarms = jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
      }
      
      // Add or update this alarm
      bool found = false;
      for (int i = 0; i < alarms.length; i++) {
        if (alarms[i]['alarmId'] == alarmId) {
          alarms[i] = alarmData;
          found = true;
          break;
        }
      }
      
      if (!found) {
        alarms.add(alarmData);
      }
      
      // Save back to SharedPreferences
      await prefs.setString('$_alarmDataKey$alarmId', json.encode(alarms));
      
      // Also store set time separately for quick access
      await prefs.setString('$_alarmSetTimeKey$alarmId', setTime.toIso8601String());
      
      if (stopTime != null) {
        await prefs.setString('$_alarmStopTimeKey$alarmId', stopTime.toIso8601String());
      }
      
      print('Alarm data saved to SharedPreferences: $alarmId');
    } catch (e) {
      print('Error saving alarm data: $e');
    }
  }

  /// Get alarm data from SharedPreferences
  static Future<Map<String, dynamic>?> getAlarmData(int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('$_alarmDataKey$alarmId');
      
      if (data != null) {
        final List<dynamic> jsonList = json.decode(data);
        if (jsonList.isNotEmpty) {
          return Map<String, dynamic>.from(jsonList.last);
        }
      }
      
      return null;
    } catch (e) {
      print('Error getting alarm data: $e');
      return null;
    }
  }

  /// Get all alarms data from SharedPreferences
  static Future<List<Map<String, dynamic>>> getAllAlarmsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      List<Map<String, dynamic>> allAlarms = [];
      
      for (final key in keys) {
        if (key.startsWith(_alarmDataKey) && key != _alarmDataKey) {
          final data = prefs.getString(key);
          if (data != null) {
            final List<dynamic> jsonList = json.decode(data);
            for (final item in jsonList) {
              allAlarms.add(Map<String, dynamic>.from(item));
            }
          }
        }
      }
      
      return allAlarms;
    } catch (e) {
      print('Error getting all alarms data: $e');
      return [];
    }
  }

  /// Update alarm stop time
  static Future<void> updateAlarmStopTime(int alarmId, DateTime stopTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Update stop time
      await prefs.setString('$_alarmStopTimeKey$alarmId', stopTime.toIso8601String());
      
      // Update in alarm data
      final existingData = prefs.getString('$_alarmDataKey$alarmId');
      if (existingData != null) {
        final List<dynamic> jsonList = json.decode(existingData);
        List<Map<String, dynamic>> alarms = jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
        
        if (alarms.isNotEmpty) {
          alarms.last['stopTime'] = stopTime.toIso8601String();
          await prefs.setString('$_alarmDataKey$alarmId', json.encode(alarms));
        }
      }
      
      print('Alarm stop time updated: $alarmId');
    } catch (e) {
      print('Error updating alarm stop time: $e');
    }
  }

  /// Delete alarm data
  static Future<void> deleteAlarmData(int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.remove('$_alarmDataKey$alarmId');
      await prefs.remove('$_alarmSetTimeKey$alarmId');
      await prefs.remove('$_alarmStopTimeKey$alarmId');
      
      print('Alarm data deleted: $alarmId');
    } catch (e) {
      print('Error deleting alarm data: $e');
    }
  }

  /// Clear all alarm data
  static Future<void> clearAllAlarmData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_alarmDataKey) || key.startsWith(_alarmSetTimeKey) || key.startsWith(_alarmStopTimeKey)) {
          await prefs.remove(key);
        }
      }
      
      print('All alarm data cleared');
    } catch (e) {
      print('Error clearing alarm data: $e');
    }
  }
} 