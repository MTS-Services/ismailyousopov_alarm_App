
import 'sleep_history_prefs.dart';
import 'alarm_prefs.dart';
import 'package:get/get.dart';
import '../../controllers/stats/stats_controller.dart';

class SharedPrefsManager {
  /// Get week sleep summary
  static Future<Map<String, dynamic>> getWeekSleepSummary() async {
    try {
      await SleepHistoryPrefs.getSleepHistoryForWeek();
      final weekStats = await SleepHistoryPrefs.getWeekStatistics();
      
      return {
        'dailyData': await SleepHistoryPrefs.getSleepHistoryForWeek(),
        'averageHours': weekStats['averageHours'] ?? 0.0,
        'totalHours': weekStats['totalHours'] ?? 0.0,
        'totalAlarms': weekStats['totalAlarms'] ?? 0,
        'totalAlarmDuration': weekStats['totalAlarmDuration'] ?? 0,
        'validDays': weekStats['validDays'] ?? 0,
        'bestDay': weekStats['bestDay'] ?? '',
        'worstDay': weekStats['worstDay'] ?? '',
        'bestHours': weekStats['bestHours'] ?? 0.0,
        'worstHours': weekStats['worstHours'] ?? 0.0,
        'lastUpdated': weekStats['lastUpdated'] ?? DateTime.now().millisecondsSinceEpoch,
      };
    } catch (e) {
      print('Error getting week sleep summary: $e');
      return {
        'dailyData': [],
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

  /// Get sleep history for a specific date
  static Future<List<Map<String, dynamic>>> getSleepHistoryForDate(DateTime date) async {
    try {
      return await SleepHistoryPrefs.getSleepHistoryForDate(date);
    } catch (e) {
      print('Error getting sleep history for date: $e');
      return [];
    }
  }

  /// Add sample sleep history data for testing
  static Future<void> addSampleSleepHistoryData() async {
    try {
      print('🔧 Adding sample sleep history data to SharedPreferences...');
      
      final now = DateTime.now();
      
      // Add sample data for the last 7 days
      for (int i = 0; i < 7; i++) {
        final date = DateTime(now.year, now.month, now.day - i);
        final sleepTime = DateTime(date.year, date.month, date.day, 23, 0); // 11:00 PM
        final wakeTime = DateTime(date.year, date.month, date.day + 1, 7, 30); // 7:30 AM next day
        
        await SleepHistoryPrefs.saveSleepHistory(
          date: date,
          sleepTime: sleepTime,
          wakeTime: wakeTime,
          totalHours: 8.5, // 8.5 hours
          alarmCount: 1,
          totalAlarmDuration: 5, // 5 minutes
        );
        
        print('🔧 Added sample data for ${date.toString().substring(0, 10)}:');
        print('   Sleep: ${sleepTime.toString().substring(11, 16)}');
        print('   Wake: ${wakeTime.toString().substring(11, 16)}');
        print('   Hours: 8.5');
      }
      
      print('🔧 Sample sleep history data added successfully!');
      print('🔧 You can now check the sleep history screen to see the data.');
      
      // 🔄 IMMEDIATE REFRESH: Sleep statistics refresh করুন
      print('🔄 Refreshing sleep statistics after adding sample data...');
      if (Get.isRegistered<SleepStatisticsController>()) {
        final statsController = Get.find<SleepStatisticsController>();
        await statsController.loadSleepStatistics();
        print('✅ Sleep statistics refreshed successfully');
      } else {
        print('⚠️ SleepStatisticsController not registered');
      }
      
    } catch (e) {
      print('❌ Error adding sample sleep history data: $e');
    }
  }

  /// Sync alarm data with database
  static Future<void> syncAlarmDataWithDatabase() async {
    try {
      print('Syncing alarm data with database...');
      
      // Get all alarms from SharedPreferences
      final sharedPrefsAlarms = await AlarmPrefs.getAllAlarmsData();
      
      // Get all alarms from database (you'll need to implement this)
      // final dbAlarms = await DatabaseHelper.getAllAlarms();
      
      // For now, just log the sync attempt
      print('Found ${sharedPrefsAlarms.length} alarms in SharedPreferences');
      
      // TODO: Implement actual sync logic when database helper is available
      // This would involve:
      // 1. Comparing SharedPreferences data with database data
      // 2. Adding missing alarms to SharedPreferences
      // 3. Removing orphaned SharedPreferences entries
      
    } catch (e) {
      print('Error syncing alarm data: $e');
    }
  }

  /// Validate and fix data integrity
  static Future<void> validateAndFixDataIntegrity() async {
    try {
      print('Validating and fixing data integrity...');
      
      // Get all alarm data
      final alarms = await AlarmPrefs.getAllAlarmsData();
      
      // Validate each alarm entry
      for (final alarm in alarms) {
        try {
          // Check if required fields exist
          if (alarm['alarmId'] == null || alarm['setTime'] == null) {
            print('Found invalid alarm data, removing: $alarm');
            await AlarmPrefs.deleteAlarmData(alarm['alarmId']);
            continue;
          }
          
          // Validate date formats
          DateTime.parse(alarm['setTime']);
          if (alarm['stopTime'] != null) {
            DateTime.parse(alarm['stopTime']);
          }
          
        } catch (e) {
          print('Found corrupted alarm data, removing: $alarm');
          await AlarmPrefs.deleteAlarmData(alarm['alarmId']);
        }
      }
      
      // Validate sleep history data
      final weekHistory = await SleepHistoryPrefs.getSleepHistoryForWeek();
      for (final entry in weekHistory) {
        try {
          if (entry['date'] != null) {
            DateTime.parse(entry['date']);
          }
          if (entry['sleepTime'] != null) {
            DateTime.parse(entry['sleepTime']);
          }
          if (entry['wakeTime'] != null) {
            DateTime.parse(entry['wakeTime']);
          }
        } catch (e) {
          print('Found corrupted sleep history entry, skipping: $entry');
        }
      }
      
      print('Data integrity validation completed');
      
    } catch (e) {
      print('Error validating data integrity: $e');
    }
  }

  /// Clear all data (for testing or reset)
  static Future<void> clearAllData() async {
    try {
      await SleepHistoryPrefs.clearAllSleepHistory();
      await AlarmPrefs.clearAllAlarmData();
      print('All SharedPreferences data cleared');
    } catch (e) {
      print('Error clearing all data: $e');
    }
  }
} 