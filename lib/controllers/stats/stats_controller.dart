import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/database/database_helper.dart';
import '../../core/shared_preferences/shared_prefs_manager.dart';

class SleepStatisticsController extends GetxController {
  final DatabaseHelper _dbHelper;
  final RxList<Map<String, dynamic>> thisWeekSleepData =
      <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> lastWeekSleepData =
      <Map<String, dynamic>>[].obs;
  final RxString thisWeekTotalHours = "0:00".obs;
  final RxString lastWeekTotalHours = "0:00".obs;
  final RxString thisWeekTotalAlarmDuration = "0:00".obs;
  final RxString lastWeekTotalAlarmDuration = "0:00".obs;

  SleepStatisticsController({
    DatabaseHelper? dbHelper,
  }) : _dbHelper = dbHelper ?? DatabaseHelper();

  @override
  void onInit() {
    super.onInit();
    loadSleepStatistics().then((_) {
      debugPrintAllSleepRecords();
      printWeeklyStats();
    });
  }

  /// Loads sleep data for current and previous week
  Future<void> loadSleepStatistics() async {
    await Future.wait([
      loadThisWeekData(),
      loadLastWeekData(),
    ]);
    update();
  }

  /// Calculate the start date of the current week (Monday)
  DateTime _getStartOfWeek(DateTime date) {
    int difference = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - difference);
  }

  /// Load sleep data for the current week
  Future<void> loadThisWeekData() async {
    try {
      final now = DateTime.now();
      final startOfWeek = _getStartOfWeek(now);
      final endOfWeek = startOfWeek
          .add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

      debugPrint('Current date and time: ${now.toIso8601String()}');
      debugPrint(
          'This week from: ${startOfWeek.toIso8601String()} to: ${endOfWeek.toIso8601String()}');

      // 🔄 SHAREDPREFERENCES থেকে data load করছি
      debugPrint('🔄 Loading data from SharedPreferences for this week...');
      final sleepHistoryData = await _loadSharedPrefsDataForWeek(startOfWeek, endOfWeek);
      
      debugPrint('🔄 SHAREDPREFS DATA COUNT: ${sleepHistoryData.length}');
      for (var record in sleepHistoryData) {
        debugPrint('🔄 SHAREDPREFS RECORD: ${record.toString()}');
        debugPrint('🔄 Sleep Time: ${record['sleep_time']}');
        debugPrint('🔄 Wake Time: ${record['wake_time']}');
        debugPrint('🔄 Total Hours: ${record['total_hours']}');
      }
      
      for (var record in sleepHistoryData) {
        debugPrint(
            'Found record for date: ${record['date']} with hours: ${record['total_hours']} and alarm duration: ${record['total_alarm_duration']}');
      }

      final correctedData = _correctSleepHoursAndDuration(sleepHistoryData);
      
      debugPrint('🔄 CORRECTED DATA COUNT: ${correctedData.length}');
      for (var data in correctedData) {
        debugPrint('🔄 CORRECTED RECORD: ${data.toString()}');
      }
      
      final formattedData =
          _formatSleepDataForUI(correctedData, startOfWeek, endOfWeek);
      
      debugPrint('🔄 FORMATTED DATA COUNT: ${formattedData.length}');
      for (var data in formattedData) {
        debugPrint('🔄 FORMATTED RECORD: ${data.toString()}');
        debugPrint('🔄 Time Range: ${data['timeRange']}');
      }
      
      thisWeekSleepData.value = formattedData;

      double totalHours = 0;
      int totalAlarmDurationMinutes = 0;
      for (var data in correctedData) {
        totalHours += (data['calculated_sleep_hours'] as double);
        totalAlarmDurationMinutes +=
            (data['total_alarm_duration'] as int? ?? 0);
      }
      thisWeekTotalHours.value = _formatHoursMinutes(totalHours);
      thisWeekTotalAlarmDuration.value =
          _formatDurationMinutes(totalAlarmDurationMinutes);
      debugPrint('🔄 This week total hours calculated: $totalHours');
      debugPrint(
          '🔄 This week total alarm duration: $totalAlarmDurationMinutes minutes');
    } catch (e) {
      debugPrint('❌ Error loading this week data: $e');
      thisWeekSleepData.value = _generatePlaceholderData(true);
    }
  }

  /// load last week data
  Future<void> loadLastWeekData() async {
    try {
      final now = DateTime.now();
      final startOfThisWeek = _getStartOfWeek(now);
      final startOfLastWeek = startOfThisWeek.subtract(const Duration(days: 7));
      final endOfLastWeek =
          startOfThisWeek.subtract(const Duration(seconds: 1));

      debugPrint(
          'Loading last week data from ${startOfLastWeek.toIso8601String()} to ${endOfLastWeek.toIso8601String()}');

      // 🔄 SHAREDPREFERENCES থেকে data load করছি
      debugPrint('🔄 Loading data from SharedPreferences for last week...');
      final sleepHistoryData = await _loadSharedPrefsDataForWeek(startOfLastWeek, endOfLastWeek);
      debugPrint('🔄 SHAREDPREFS LAST WEEK DATA COUNT: ${sleepHistoryData.length}');

      final correctedData = _correctSleepHoursAndDuration(sleepHistoryData);
      final formattedData =
          _formatSleepDataForUI(correctedData, startOfLastWeek, endOfLastWeek);
      lastWeekSleepData.value = formattedData;
      double totalHours = 0;
      int totalAlarmDurationMinutes = 0;
      for (var data in correctedData) {
        totalHours += (data['calculated_sleep_hours'] as double);
        totalAlarmDurationMinutes +=
            (data['total_alarm_duration'] as int? ?? 0);
      }
      lastWeekTotalHours.value = _formatHoursMinutes(totalHours);
      lastWeekTotalAlarmDuration.value =
          _formatDurationMinutes(totalAlarmDurationMinutes);
      debugPrint('🔄 Last week total hours calculated: $totalHours');
      debugPrint(
          '🔄 Last week total alarm duration: $totalAlarmDurationMinutes minutes');
    } catch (e) {
      debugPrint('❌ Error loading last week data: $e');
      lastWeekSleepData.value = _generatePlaceholderData(false);
    }
  }

  /// Load SharedPreferences data for a specific week range
  Future<List<Map<String, dynamic>>> _loadSharedPrefsDataForWeek(DateTime startDate, DateTime endDate) async {
    try {
      debugPrint('🔄 Loading SharedPreferences data from ${startDate.toIso8601String()} to ${endDate.toIso8601String()}');
      
      final List<Map<String, dynamic>> weekData = [];
      
      // Get data for each day in the week
      for (int i = 0; i < 7; i++) {
        final currentDate = startDate.add(Duration(days: i));
        final dayHistory = await SharedPrefsManager.getSleepHistoryForDate(currentDate);
        
        if (dayHistory.isNotEmpty) {
          // Get the latest entry for this day
          final latestEntry = dayHistory.last;
          
          // Convert SharedPreferences format to database format
          final convertedEntry = {
            'date': latestEntry['date'],
            'sleep_time': latestEntry['sleepTime'],
            'wake_time': latestEntry['wakeTime'], // Can be null for partial entries
            'total_hours': latestEntry['totalHours'],
            'alarm_count': latestEntry['alarmCount'],
            'total_alarm_duration': latestEntry['totalAlarmDuration'],
            'is_partial': latestEntry['isPartial'] ?? false,
          };
          
          weekData.add(convertedEntry);
          debugPrint('🔄 SHAREDPREFS ENTRY: ${convertedEntry.toString()}');
        }
      }
      
      // 🔄 ALSO LOAD FROM DATABASE AS BACKUP
      debugPrint('🔄 Also loading from database as backup...');
      final databaseData = await _dbHelper.getSleepHistoryRange(startDate, endDate);
      debugPrint('🔄 DATABASE DATA COUNT: ${databaseData.length}');
      
      // Merge database data with SharedPreferences data
      for (var dbRecord in databaseData) {
        final dbDate = DateTime.parse(dbRecord['date']);
        final dbDateKey = _formatDateKey(dbDate);
        
        // Check if we already have this date from SharedPreferences
        bool alreadyExists = false;
        for (var spRecord in weekData) {
          final spDate = DateTime.parse(spRecord['date']);
          final spDateKey = _formatDateKey(spDate);
          if (spDateKey == dbDateKey) {
            alreadyExists = true;
            break;
          }
        }
        
        if (!alreadyExists) {
          // Add database record if not already in SharedPreferences
          final convertedDbEntry = {
            'date': dbRecord['date'],
            'sleep_time': dbRecord['sleep_time'],
            'wake_time': dbRecord['wake_time'],
            'total_hours': dbRecord['total_hours'],
            'alarm_count': dbRecord['alarm_count'],
            'total_alarm_duration': dbRecord['total_alarm_duration'],
            'is_partial': false, // Database entries are always complete
          };
          
          weekData.add(convertedDbEntry);
          debugPrint('🔄 ADDED DATABASE ENTRY: ${convertedDbEntry.toString()}');
        }
      }
      
      debugPrint('🔄 Total entries found (SharedPreferences + Database): ${weekData.length}');
      return weekData;
    } catch (e) {
      debugPrint('❌ Error loading SharedPreferences data: $e');
      return [];
    }
  }

  /// Calculate sleep hours and durations based on actual timestamps with proper midnight crossing
  List<Map<String, dynamic>> _correctSleepHoursAndDuration(
      List<Map<String, dynamic>> sleepHistoryData) {
    List<Map<String, dynamic>> correctedData = [];

    for (var record in sleepHistoryData) {
      final correctedRecord = Map<String, dynamic>.from(record);
      final sleepTime = DateTime.parse(record['sleep_time']);
      final wakeTime = record['wake_time'] != null ? DateTime.parse(record['wake_time']) : null;
      final isPartial = record['is_partial'] ?? false;

      // Calculate sleep duration with proper midnight crossing handling
      double sleepDurationHours = _calculateSleepDuration(sleepTime, wakeTime);
      
      // Keep the original alarm duration separate from sleep duration
      final alarmDuration = record['total_alarm_duration'] ?? 0;

      correctedRecord['calculated_sleep_hours'] = sleepDurationHours;
      correctedRecord['total_alarm_duration'] = alarmDuration; // Keep original alarm duration

      if (isPartial) {
        debugPrint(
            'Partial record: Sleep ${sleepTime.toString().substring(11, 16)}, Wake: Not set yet, Sleep Hours: $sleepDurationHours, Alarm Duration: $alarmDuration min');
      } else {
        debugPrint(
            'Complete record: Sleep ${sleepTime.toString().substring(11, 16)}, Wake ${wakeTime?.toString().substring(11, 16) ?? 'null'}, Sleep Hours: $sleepDurationHours, Alarm Duration: $alarmDuration min');
      }

      correctedData.add(correctedRecord);
    }

    return correctedData;
  }

  /// Calculate sleep duration with proper midnight crossing handling
  double _calculateSleepDuration(DateTime sleepTime, DateTime? wakeTime) {
    // If wake time is null (partial entry), return 0
    if (wakeTime == null) {
      return 0.0;
    }
    
    DateTime adjustedWakeTime = wakeTime;
    
    // If wake time is before sleep time, it means we crossed midnight
    if (wakeTime.isBefore(sleepTime)) {
      adjustedWakeTime = wakeTime.add(const Duration(days: 1));
    }
    
    final durationInMinutes = adjustedWakeTime.difference(sleepTime).inMinutes;
    final durationInHours = durationInMinutes / 60.0;
    
    // Ensure we don't have negative or unreasonable values
    if (durationInHours < 0 || durationInHours > 24) {
      debugPrint('Warning: Unreasonable sleep duration calculated: $durationInHours hours');
      return 0.0;
    }
    
    return durationInHours;
  }

  /// format sleep data to be used in ui
  List<Map<String, dynamic>> _formatSleepDataForUI(
      List<Map<String, dynamic>> sleepHistoryData,
      DateTime startDate,
      DateTime endDate) {
    Map<String, Map<String, dynamic>> dayData = {};
    for (int i = 0; i < 7; i++) {
      final day = startDate.add(Duration(days: i));
      final dateKey = _formatDateKey(day);

      dayData[dateKey] = {
        'day': _getWeekdayName(day.weekday),
        'timeRange': 'No data for this day',
        'date': day,
        'backgroundColor': day.day == DateTime.now().day
            ? Get.theme.primaryColor
            : Colors.white,
        'textColor': day.day == DateTime.now().day
            ? Colors.white
            : const Color(0xFF606A85),
        'alarmCount': 0,
        'alarmDuration': 0,
        'formattedAlarmDuration': '0:00',
        'sleepHours': 0.0,
      };
    }

    for (var record in sleepHistoryData) {
      final date = DateTime.parse(record['date']);
      final dateKey = _formatDateKey(date);

      if (date.isBefore(startDate) || date.isAfter(endDate)) {
        debugPrint(
            'Skipping record for ${date.toIso8601String()} - outside range');
        continue;
      }

      final sleepTime = DateTime.parse(record['sleep_time']);
      final wakeTime = record['wake_time'] != null ? DateTime.parse(record['wake_time']) : null;
      final alarmCount = record['alarm_count'] ?? 0;
      final alarmDuration = record['total_alarm_duration'] ?? 0;
      final sleepHours = record['calculated_sleep_hours'] as double? ?? 0.0;
      final isPartial = record['is_partial'] ?? false;

      final formattedSleepTime = DateFormat('HH:mm').format(sleepTime);
      final formattedWakeTime = wakeTime != null ? DateFormat('HH:mm').format(wakeTime) : 'Not set';

      dayData[dateKey] = {
        'day': _getWeekdayName(date.weekday),
        'timeRange': isPartial 
            ? 'Set $formattedSleepTime / Wake $formattedWakeTime = ${_formatHoursMinutes(sleepHours)}h (Alarm Active)'
            : 'Set $formattedSleepTime / Off $formattedWakeTime = ${_formatHoursMinutes(sleepHours)}h',
        'date': date,
        'backgroundColor': date.day == DateTime.now().day
            ? Get.theme.primaryColor
            : Colors.white,
        'textColor': date.day == DateTime.now().day
            ? Colors.white
            : const Color(0xFF606A85),
        'alarmCount': alarmCount,
        'alarmDuration': alarmDuration,
        'formattedAlarmDuration': _formatDurationMinutes(alarmDuration),
        'sleepHours': sleepHours,
      };
    }

    List<Map<String, dynamic>> result = dayData.values.toList();

    result.sort(
        (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    // Handle upcoming days
    final now = DateTime.now();
    for (var item in result) {
      final itemDate = item['date'] as DateTime;
      if (itemDate.isAfter(now)) {
        item['timeRange'] = 'Upcoming day';
      }
    }

    return result;
  }

  /// Format a date as a consistent string key
  String _formatDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Utility to get weekday name
  String _getWeekdayName(int weekday) {
    switch (weekday) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return 'Unknown';
    }
  }

  /// Format hours in hours:minutes format
  String _formatHoursMinutes(double hours) {
    if (hours < 0.001) {
      return '0:00';
    }

    int totalMinutes = (hours * 60).round();
    int wholeHours = totalMinutes ~/ 60;
    int minutes = totalMinutes % 60;

    return '$wholeHours:${minutes.toString().padLeft(2, '0')}';
  }

  /// Format duration in hours:minutes format from total minutes
  String _formatDurationMinutes(int totalMinutes) {
    int hours = totalMinutes ~/ 60;
    int minutes = totalMinutes % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }

  /// Generate placeholder data in case of error
  List<Map<String, dynamic>> _generatePlaceholderData(bool isThisWeek) {
    final now = DateTime.now();
    final startOfWeek = _getStartOfWeek(
        isThisWeek ? now : now.subtract(const Duration(days: 7)));

    List<Map<String, dynamic>> placeholder = [];
    for (int i = 0; i < 7; i++) {
      final day = startOfWeek.add(Duration(days: i));

      placeholder.add({
        'day': _getWeekdayName(day.weekday),
        'timeRange': isThisWeek && day.isAfter(now)
            ? 'Upcoming day'
            : 'No data for this day',
        'date': day,
        'backgroundColor': day.day == now.day && isThisWeek
            ? Get.theme.primaryColor
            : Colors.white,
        'textColor': day.day == now.day && isThisWeek
            ? Colors.white
            : const Color(0xFF606A85),
        'alarmCount': 0,
        'alarmDuration': 0,
        'formattedAlarmDuration': '0:00',
        'sleepHours': 0.0,
      });
    }

    return placeholder;
  }

  /// print weekly stats
  void printWeeklyStats() {
    debugPrint('==== WEEKLY STATS ====');
    debugPrint('This Week Total Hours: ${thisWeekTotalHours.value}');
    debugPrint('Last Week Total Hours: ${lastWeekTotalHours.value}');
    debugPrint(
        'This Week Total Alarm Duration: ${thisWeekTotalAlarmDuration.value}');
    debugPrint(
        'Last Week Total Alarm Duration: ${lastWeekTotalAlarmDuration.value}');
    debugPrint('This Week Data Count: ${thisWeekSleepData.length}');
    debugPrint('Last Week Data Count: ${lastWeekSleepData.length}');
    debugPrint('=====================');
  }

  ///print all sleep records
  Future<void> debugPrintAllSleepRecords() async {
    try {
      final allRecords = await _dbHelper.getSleepHistory();
      debugPrint('==== ALL SLEEP RECORDS (${allRecords.length}) ====');

      final correctedRecords = _correctSleepHoursAndDuration(allRecords);

      double totalHours = 0;
      int totalAlarmDuration = 0;

      for (var record in correctedRecords) {
        final date = DateTime.parse(record['date']);
        final sleepTime = DateTime.parse(record['sleep_time']);
        final wakeTime = DateTime.parse(record['wake_time']);
        final hours = record['calculated_sleep_hours'] as double? ?? 0.0;
        final alarmDuration = record['total_alarm_duration'] as int? ?? 0;

        totalHours += hours;
        totalAlarmDuration += alarmDuration;

        debugPrint(
            'Date: ${date.toString().substring(0, 10)}, Sleep: ${sleepTime.toString().substring(11, 16)}, Wake: ${wakeTime.toString().substring(11, 16)}, Sleep Hours: $hours, Alarms: ${record['alarm_count']}, Alarm Duration: $alarmDuration min');
      }
      debugPrint('Total Sleep Hours: $totalHours');
      debugPrint(
          'Total Alarm Duration: ${_formatDurationMinutes(totalAlarmDuration)} ($totalAlarmDuration min)');
      debugPrint('==========================');
    } catch (e) {
      debugPrint('Error debugging sleep records: $e');
    }
  }

  /// Force refresh the sleep statistics
  Future<void> refreshSleepStatistics() async {
    try {
      // ✅ SharedPreferences থেকে সপ্তাহের ডেটা নিন
      final weekSummary = await SharedPrefsManager.getWeekSleepSummary();
      
      // UI আপডেট করুন
      final averageHours = weekSummary['averageHours'] ?? 0.0;
      final totalHours = weekSummary['totalHours'] ?? 0.0;
      final bestDay = weekSummary['bestDay'] ?? '';
      final worstDay = weekSummary['worstDay'] ?? '';
      
      debugPrint('Sleep statistics refreshed from SharedPreferences:');
      debugPrint('   Average Hours: $averageHours');
      debugPrint('   Total Hours: $totalHours');
      debugPrint('   Best Day: $bestDay');
      debugPrint('   Worst Day: $worstDay');
      
      // Also load from database for backward compatibility
      await loadSleepStatistics();
      update();
    } catch (e) {
      debugPrint('Error refreshing sleep statistics: $e');
      // Fallback to database only
      await loadSleepStatistics();
      update();
    }
  }

  /// Force refresh UI with immediate update
  Future<void> forceRefreshUI() async {
    debugPrint('🔄 FORCE REFRESHING UI...');
    
    // Clear current data
    thisWeekSleepData.clear();
    lastWeekSleepData.clear();
    
    // Reload data
    await loadSleepStatistics();
    
    // Force UI update
    update();
    
    debugPrint('✅ UI FORCE REFRESHED');
  }

  /// Get formatted alarm duration for display
  String getFormattedAlarmDuration(int minutes) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (hours > 0) {
      return '$hours hr ${remainingMinutes > 0 ? '$remainingMinutes min' : ''}';
    } else {
      return '$minutes min';
    }
  }
}
