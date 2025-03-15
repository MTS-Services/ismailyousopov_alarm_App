import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/database/database_helper.dart';

class SleepStatisticsController extends GetxController {
  final DatabaseHelper _dbHelper;
  final RxList<Map<String, dynamic>> thisWeekSleepData =
      <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> lastWeekSleepData =
      <Map<String, dynamic>>[].obs;
  final RxString thisWeekTotalHours = "0.00".obs;
  final RxString lastWeekTotalHours = "0.00".obs;
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

      final sleepHistoryData =
          await _dbHelper.getSleepHistoryRange(startOfWeek, endOfWeek);
      for (var record in sleepHistoryData) {
        debugPrint(
            'Found record for date: ${record['date']} with hours: ${record['total_hours']} and alarm duration: ${record['total_alarm_duration']}');
      }

      final correctedData = _correctSleepHoursAndDuration(sleepHistoryData);
      final formattedData =
          _formatSleepDataForUI(correctedData, startOfWeek, endOfWeek);
      thisWeekSleepData.value = formattedData;

      double totalHours = 0;
      int totalAlarmDurationMinutes = 0;
      for (var data in correctedData) {
        totalHours += (data['total_hours'] as double);
        totalAlarmDurationMinutes +=
            (data['total_alarm_duration'] as int? ?? 0);
      }
      thisWeekTotalHours.value = _formatHoursMinutes(totalHours);
      thisWeekTotalAlarmDuration.value =
          _formatDurationMinutes(totalAlarmDurationMinutes);
      debugPrint('This week total hours calculated: $totalHours');
      debugPrint(
          'This week total alarm duration: $totalAlarmDurationMinutes minutes');
    } catch (e) {
      debugPrint('Error loading this week data: $e');
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

      final sleepHistoryData =
          await _dbHelper.getSleepHistoryRange(startOfLastWeek, endOfLastWeek);
      debugPrint('Last week sleep records found: ${sleepHistoryData.length}');

      final correctedData = _correctSleepHoursAndDuration(sleepHistoryData);
      final formattedData =
          _formatSleepDataForUI(correctedData, startOfLastWeek, endOfLastWeek);
      lastWeekSleepData.value = formattedData;
      double totalHours = 0;
      int totalAlarmDurationMinutes = 0;
      for (var data in correctedData) {
        totalHours += (data['total_hours'] as double);
        totalAlarmDurationMinutes +=
            (data['total_alarm_duration'] as int? ?? 0);
      }
      lastWeekTotalHours.value = _formatHoursMinutes(totalHours);
      lastWeekTotalAlarmDuration.value =
          _formatDurationMinutes(totalAlarmDurationMinutes);
      debugPrint('Last week total hours calculated: $totalHours');
      debugPrint(
          'Last week total alarm duration: $totalAlarmDurationMinutes minutes');
    } catch (e) {
      debugPrint('Error loading last week data: $e');
      lastWeekSleepData.value = _generatePlaceholderData(false);
    }
  }

  /// sleep hours and durations based on actual timestamps
  List<Map<String, dynamic>> _correctSleepHoursAndDuration(
      List<Map<String, dynamic>> sleepHistoryData) {
    List<Map<String, dynamic>> correctedData = [];

    for (var record in sleepHistoryData) {
      final correctedRecord = Map<String, dynamic>.from(record);
      final sleepTime = DateTime.parse(record['sleep_time']);
      final wakeTime = DateTime.parse(record['wake_time']);

      final durationInMinutes = wakeTime.difference(sleepTime).inMinutes;
      final durationInHours = durationInMinutes / 60.0;

      correctedRecord['total_alarm_duration'] = durationInMinutes;
      correctedRecord['total_hours'] = durationInHours;

      debugPrint(
          'Corrected record: Sleep ${sleepTime.toString().substring(11, 16)}, Wake ${wakeTime.toString().substring(11, 16)}, Hours: $durationInHours, Duration: $durationInMinutes min');

      correctedData.add(correctedRecord);
    }

    return correctedData;
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
      final wakeTime = DateTime.parse(record['wake_time']);
      final alarmCount = record['alarm_count'] ?? 0;
      final alarmDuration = record['total_alarm_duration'] ?? 0;
      final totalHours = record['total_hours'] as double;

      final formattedSleepTime = DateFormat('HH:mm').format(sleepTime);
      final formattedWakeTime = DateFormat('HH:mm').format(wakeTime);

      dayData[dateKey] = {
        'day': _getWeekdayName(date.weekday),
        'timeRange': 'Set $formattedSleepTime / Off $formattedWakeTime',
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
        'totalHours': totalHours,
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
        final hours = record['total_hours'] as double;
        final alarmDuration = record['total_alarm_duration'] as int? ?? 0;

        totalHours += hours;
        totalAlarmDuration += alarmDuration;

        debugPrint(
            'Date: ${date.toString().substring(0, 10)}, Sleep: ${sleepTime.toString().substring(11, 16)}, Wake: ${wakeTime.toString().substring(11, 16)}, Hours: $hours, Alarms: ${record['alarm_count']}, Alarm Duration: $alarmDuration min');
      }
      debugPrint('Total Hours: $totalHours');
      debugPrint(
          'Total Alarm Duration: ${_formatDurationMinutes(totalAlarmDuration)} (${totalAlarmDuration} min)');
      debugPrint('==========================');
    } catch (e) {
      debugPrint('Error debugging sleep records: $e');
    }
  }

  /// Force refresh the sleep statistics
  Future<void> refreshSleepStatistics() async {
    await loadSleepStatistics();
    update();
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
