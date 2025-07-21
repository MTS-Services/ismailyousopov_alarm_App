import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SleepHistoryPrefs {
  static const String _sleepHistoryKey = 'sleep_history';
  static const String _weekStatsKey = 'week_stats';

  /// Save sleep history data (complete entry)
  static Future<void> saveSleepHistory({
    required DateTime date,
    required DateTime sleepTime,
    required DateTime wakeTime,
    required double totalHours,
    required int alarmCount,
    required int totalAlarmDuration,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getDateKey(date);
      
      // Create sleep history entry
      final sleepEntry = {
        'date': date.toIso8601String(),
        'sleepTime': sleepTime.toIso8601String(),
        'wakeTime': wakeTime.toIso8601String(),
        'totalHours': totalHours,
        'alarmCount': alarmCount,
        'totalAlarmDuration': totalAlarmDuration,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Get existing sleep history
      final existingData = prefs.getString('$_sleepHistoryKey$dateKey');
      List<Map<String, dynamic>> history = [];
      
      if (existingData != null) {
        final List<dynamic> jsonList = json.decode(existingData);
        history = jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
      }
      
      // Add new entry
      history.add(sleepEntry);
      
      // Save back to SharedPreferences
      await prefs.setString('$_sleepHistoryKey$dateKey', json.encode(history));
      
      // Update week statistics
      await _updateWeekStatistics();
      
      print('Sleep history saved for ${date.toIso8601String()}: ${totalHours.toStringAsFixed(2)} hours');
    } catch (e) {
      print('Error saving sleep history: $e');
    }
  }

  /// Save partial sleep history data (when alarm is set but not stopped yet)
  static Future<void> savePartialSleepHistory({
    required DateTime date,
    required DateTime sleepTime,
    required int alarmCount,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getDateKey(date);
      
      // Create partial sleep history entry
      final sleepEntry = {
        'date': date.toIso8601String(),
        'sleepTime': sleepTime.toIso8601String(),
        'wakeTime': null, // Not set yet
        'totalHours': 0.0, // No duration yet
        'alarmCount': alarmCount,
        'totalAlarmDuration': 0, // No duration yet
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isPartial': true, // Mark as partial entry
      };
      
      // Get existing sleep history
      final existingData = prefs.getString('$_sleepHistoryKey$dateKey');
      List<Map<String, dynamic>> history = [];
      
      if (existingData != null) {
        final List<dynamic> jsonList = json.decode(existingData);
        history = jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
      }
      
      // Remove any existing partial entry for this date
      history.removeWhere((entry) => entry['isPartial'] == true);
      
      // Add new partial entry
      history.add(sleepEntry);
      
      // Save back to SharedPreferences
      await prefs.setString('$_sleepHistoryKey$dateKey', json.encode(history));
      
      print('Partial sleep history saved for ${date.toIso8601String()}: Sleep time ${sleepTime.toString().substring(11, 16)}');
    } catch (e) {
      print('Error saving partial sleep history: $e');
    }
  }

  /// Save partial sleep history data with wake time (when alarm is set with known wake time)
  static Future<void> savePartialSleepHistoryWithWakeTime({
    required DateTime date,
    required DateTime sleepTime,
    required DateTime wakeTime,
    required int alarmCount,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getDateKey(date);
      
      // Create partial sleep history entry with wake time
      final sleepEntry = {
        'date': date.toIso8601String(),
        'sleepTime': sleepTime.toIso8601String(),
        'wakeTime': wakeTime.toIso8601String(), // Actual wake time (alarm time)
        'totalHours': 0.0, // No actual duration yet (alarm not stopped)
        'alarmCount': alarmCount,
        'totalAlarmDuration': 0, // No duration yet
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isPartial': true, // Mark as partial entry
        'hasWakeTime': true, // Mark that we have wake time
      };
      
      // Get existing sleep history
      final existingData = prefs.getString('$_sleepHistoryKey$dateKey');
      List<Map<String, dynamic>> history = [];
      
      if (existingData != null) {
        final List<dynamic> jsonList = json.decode(existingData);
        history = jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
      }
      
      // Remove any existing partial entry for this date
      history.removeWhere((entry) => entry['isPartial'] == true);
      
      // Add new partial entry with wake time
      history.add(sleepEntry);
      
      // Save back to SharedPreferences
      await prefs.setString('$_sleepHistoryKey$dateKey', json.encode(history));
      
      print('Partial sleep history with wake time saved for ${date.toIso8601String()}: Sleep ${sleepTime.toString().substring(11, 16)}, Wake ${wakeTime.toString().substring(11, 16)}');
    } catch (e) {
      print('Error saving partial sleep history with wake time: $e');
    }
  }

  /// Update partial sleep history with wake time (when alarm is stopped)
  static Future<void> updatePartialSleepHistory({
    required DateTime date,
    required DateTime wakeTime,
    required double totalHours,
    required int totalAlarmDuration,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getDateKey(date);
      
      // Get existing sleep history
      final existingData = prefs.getString('$_sleepHistoryKey$dateKey');
      if (existingData == null) return;
      
      final List<dynamic> jsonList = json.decode(existingData);
      List<Map<String, dynamic>> history = jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
      
      // Find and update the partial entry
      for (int i = 0; i < history.length; i++) {
        if (history[i]['isPartial'] == true) {
          history[i]['wakeTime'] = wakeTime.toIso8601String();
          history[i]['totalHours'] = totalHours;
          history[i]['totalAlarmDuration'] = totalAlarmDuration;
          history[i]['isPartial'] = false; // Mark as complete
          history[i]['timestamp'] = DateTime.now().millisecondsSinceEpoch;
          break;
        }
      }
      
      // Save back to SharedPreferences
      await prefs.setString('$_sleepHistoryKey$dateKey', json.encode(history));
      
      print('Partial sleep history updated for ${date.toIso8601String()}: Wake time ${wakeTime.toString().substring(11, 16)}, Duration ${totalHours.toStringAsFixed(2)} hours');
    } catch (e) {
      print('Error updating partial sleep history: $e');
    }
  }

  /// Get sleep history for a specific date
  static Future<List<Map<String, dynamic>>> getSleepHistoryForDate(DateTime date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getDateKey(date);
      final data = prefs.getString('$_sleepHistoryKey$dateKey');
      
      if (data != null) {
        final List<dynamic> jsonList = json.decode(data);
        return jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
      }
      
      return [];
    } catch (e) {
      print('Error getting sleep history for date: $e');
      return [];
    }
  }

  /// Get sleep history for the last 7 days
  static Future<List<Map<String, dynamic>>> getSleepHistoryForWeek() async {
    try {
      final List<Map<String, dynamic>> weekHistory = [];
      final now = DateTime.now();
      
      for (int i = 6; i >= 0; i--) {
        final date = DateTime(now.year, now.month, now.day - i);
        final dayHistory = await getSleepHistoryForDate(date);
        
        if (dayHistory.isNotEmpty) {
          // Get the latest entry for this day
          weekHistory.add(dayHistory.last);
        } else {
          // Add empty entry for days with no data
          weekHistory.add({
            'date': date.toIso8601String(),
            'sleepTime': null,
            'wakeTime': null,
            'totalHours': 0.0,
            'alarmCount': 0,
            'totalAlarmDuration': 0,
            'timestamp': null,
          });
        }
      }
      
      return weekHistory;
    } catch (e) {
      print('Error getting week sleep history: $e');
      return [];
    }
  }

  /// Get week statistics
  static Future<Map<String, dynamic>> getWeekStatistics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_weekStatsKey);
      
      if (data != null) {
        return Map<String, dynamic>.from(json.decode(data));
      }
      
      // Calculate if not available
      return await _calculateWeekStatistics();
    } catch (e) {
      print('Error getting week statistics: $e');
      return await _calculateWeekStatistics();
    }
  }

  /// Calculate week statistics
  static Future<Map<String, dynamic>> _calculateWeekStatistics() async {
    try {
      final weekHistory = await getSleepHistoryForWeek();
      
      double totalHours = 0.0;
      int totalAlarms = 0;
      int totalAlarmDuration = 0;
      int validDays = 0;
      
      String bestDay = '';
      String worstDay = '';
      double bestHours = 0.0;
      double worstHours = 24.0;
      
      for (final entry in weekHistory) {
        final hours = entry['totalHours'] as double? ?? 0.0;
        final alarms = entry['alarmCount'] as int? ?? 0;
        final alarmDuration = entry['totalAlarmDuration'] as int? ?? 0;
        
        if (hours > 0) {
          totalHours += hours;
          totalAlarms += alarms;
          totalAlarmDuration += alarmDuration;
          validDays++;
          
          // Track best and worst days
          if (hours > bestHours) {
            bestHours = hours;
            bestDay = _formatDate(DateTime.parse(entry['date']));
          }
          
          if (hours < worstHours) {
            worstHours = hours;
            worstDay = _formatDate(DateTime.parse(entry['date']));
          }
        }
      }
      
      final averageHours = validDays > 0 ? totalHours / validDays : 0.0;
      
      final stats = {
        'averageHours': averageHours,
        'totalHours': totalHours,
        'totalAlarms': totalAlarms,
        'totalAlarmDuration': totalAlarmDuration,
        'validDays': validDays,
        'bestDay': bestDay,
        'worstDay': worstDay,
        'bestHours': bestHours,
        'worstHours': worstHours,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Save statistics
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_weekStatsKey, json.encode(stats));
      
      return stats;
    } catch (e) {
      print('Error calculating week statistics: $e');
      return {
        'averageHours': 0.0,
        'totalHours': 0.0,
        'totalAlarms': 0,
        'totalAlarmDuration': 0,
        'validDays': 0,
        'bestDay': '',
        'worstDay': '',
        'bestHours': 0.0,
        'worstHours': 0.0,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      };
    }
  }

  /// Update week statistics
  static Future<void> _updateWeekStatistics() async {
    try {
      await _calculateWeekStatistics();
    } catch (e) {
      print('Error updating week statistics: $e');
    }
  }

  /// Clear all sleep history
  static Future<void> clearAllSleepHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_sleepHistoryKey) || key == _weekStatsKey) {
          await prefs.remove(key);
        }
      }
      
      print('All sleep history cleared');
    } catch (e) {
      print('Error clearing sleep history: $e');
    }
  }

  /// Helper method to get date key
  static String _getDateKey(DateTime date) {
    return '${date.year}_${date.month.toString().padLeft(2, '0')}_${date.day.toString().padLeft(2, '0')}';
  }

  /// Helper method to format date
  static String _formatDate(DateTime date) {
    return '${date.month}/${date.day}';
  }
} 