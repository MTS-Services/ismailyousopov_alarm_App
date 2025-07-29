import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:get/get.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/background_service.dart';
import '../../models/alarm/alarm_model.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/sound_manager.dart';
import '../../core/constants/asset_constants.dart';
import '../../volume_lock_manager/volume_lock_manager.dart';
import '../nfc/nfc_controller.dart';
import '../stats/stats_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';
import '../../core/shared_preferences/alarm_prefs.dart';
import '../../core/shared_preferences/sleep_history_prefs.dart';

class AlarmController extends GetxController {
  final DatabaseHelper _dbHelper;
  final AudioPlayer _audioPlayer;
  Timer? _refreshTimer;
  Timer? _alarmSoundTimer;
  final VolumeLockManager _volumeManager = VolumeLockManager();

  AlarmController({
    DatabaseHelper? dbHelper,
    FlutterLocalNotificationsPlugin? notificationPlugin,
    AudioPlayer? audioPlayer,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _audioPlayer = audioPlayer ?? AudioPlayer();

  final RxList<AlarmModel> alarms = <AlarmModel>[].obs;
  final RxBool isAlarmActive = false.obs;
  final RxInt currentAlarmVolume = 50.obs;
  final RxInt refreshTimestamp = DateTime.now().millisecondsSinceEpoch.obs;
  final RxString currentTime = DateFormat('HH:mm').format(DateTime.now()).obs;
  final RxInt activeAlarmId = RxInt(-1);
  final RxBool hasActiveAlarm = false.obs;
  final RxBool shouldShowStopScreen = false.obs;
  final RxInt selectedSoundForNewAlarm = RxInt(1);
  final RxString selectedSoundName = RxString('Classic Alarm');

  late SharedPreferences _prefs;
  Timer? _clockTimer;

  @override
  void onInit() {
    super.onInit();
    _initializeController();
    _startRefreshTimer();
    _startClockTimer();
    loadAlarms();
    _loadSavedVolume();

    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    // Reset today's alarms flag at midnight
    _resetTodayAlarmsAtMidnight();

    // Check for active alarms immediately
    _checkForActiveAlarms();

    // Periodically check for active alarms
    Timer.periodic(const Duration(seconds: 15), (_) {
      _checkForActiveAlarms();
    });

    // Listen for ringing alarms from the Alarm package
    Alarm.ringing.listen((AlarmSet alarmSet) {
      for (final alarm in alarmSet.alarms) {
        debugPrint('Alarm ringing from Alarm package: ${alarm.id}');
        _handleAlarmPackageRinging(alarm.id);

        // IMMEDIATE NAVIGATION: Go directly to stop screen when alarm is detected
        _navigateToStopScreenImmediately(alarm.id);
      }
    });

    // Additional check for alarms that are already ringing when the app starts
    Timer(const Duration(milliseconds: 500), () {
      _checkForExistingRingingAlarms();
    });

    // IMMEDIATE CHECK: Check for currently ringing alarms right now
    Timer(const Duration(milliseconds: 100), () {
      _checkCurrentlyRingingAlarms();
    });
  }

  /// Reset the is_for_today flag at midnight to start fresh each day
  void _resetTodayAlarmsAtMidnight() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    Timer(timeUntilMidnight, () async {
      await _dbHelper.resetTodayAlarms();
      debugPrint('Reset is_for_today flag for all alarms at midnight');

      // Schedule next reset for tomorrow
      _resetTodayAlarmsAtMidnight();
    });
  }

  /// Handle alarm ringing from the Alarm package
  Future<void> _handleAlarmPackageRinging(int packageAlarmId) async {
    try {
      // Prevent duplicate handling of the same alarm
      if (activeAlarmId.value == packageAlarmId) {
        debugPrint(
          'Alarm $packageAlarmId already being handled, skipping duplicate',
        );
        return;
      }

      // Find the corresponding alarm in our system
      final alarm = getAlarmById(packageAlarmId);
      if (alarm != null) {
        debugPrint(
          'Flutter Alarm package triggered alarm: $packageAlarmId at ${DateTime.now().toIso8601String()}',
        );

        // Mark this alarm as triggered by Flutter Alarm package to prevent native duplicate
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(
            'alarm_last_trigger_$packageAlarmId',
            DateTime.now().millisecondsSinceEpoch,
          );
          debugPrint(
            'Marked alarm $packageAlarmId as triggered by Flutter Alarm package',
          );
        } catch (e) {
          debugPrint('Error marking alarm trigger: $e');
        }

        activeAlarmId.value = packageAlarmId;
        shouldShowStopScreen.value = true;
        hasActiveAlarm.value = true;

        // Store active alarm info
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('flutter.active_alarm_id', packageAlarmId);
        await prefs.setInt('flutter.active_alarm_sound', alarm.soundId);

        // Ensure device stays awake
        _enableAlarmWakeLock();
      }
    } catch (e) {
      debugPrint('Error handling alarm package ringing: $e');
    }
  }

  /// Check for currently ringing alarms immediately (used at app startup)
  void _checkCurrentlyRingingAlarms() {
    try {
      debugPrint('IMMEDIATE CHECK: Looking for currently ringing alarms');

      // Listen to the ringing stream once to check current state
      final subscription = Alarm.ringing.listen((AlarmSet alarmSet) {
        if (alarmSet.alarms.isNotEmpty) {
          debugPrint(
            'IMMEDIATE CHECK: Found ${alarmSet.alarms.length} ringing alarms',
          );
          for (final alarm in alarmSet.alarms) {
            debugPrint('IMMEDIATE CHECK: Processing ringing alarm ${alarm.id}');
            _handleAlarmPackageRinging(alarm.id);
            _navigateToStopScreenImmediately(alarm.id);
            break; // Only handle first alarm
          }
        } else {
          debugPrint('IMMEDIATE CHECK: No currently ringing alarms found');
        }
      });

      // Cancel subscription after checking
      Timer(const Duration(milliseconds: 500), () {
        subscription.cancel();
      });
    } catch (e) {
      debugPrint('Error in immediate alarm check: $e');
    }
  }

  /// Immediately navigate to stop screen when an alarm is detected ringing
  void _navigateToStopScreenImmediately(int alarmId) {
    try {
      // Small delay to ensure app is fully loaded
      Timer(const Duration(milliseconds: 300), () async {
        final alarm = getAlarmById(alarmId);
        if (alarm != null) {
          final prefs = await SharedPreferences.getInstance();
          final soundId =
              prefs.getInt('flutter.active_alarm_sound') ?? alarm.soundId;

          debugPrint(
            'IMMEDIATE NAVIGATION: Going to stop screen for alarm $alarmId',
          );

          // Force navigation to stop screen regardless of current route
          Get.offAllNamed(
            AppConstants.stopAlarm,
            arguments: {'alarmId': alarmId, 'soundId': soundId},
          );
        }
      });
    } catch (e) {
      debugPrint('Error in immediate navigation: $e');
    }
  }

  /// Check for alarms that are already ringing when the controller initializes
  /// This handles cases where the app is reopened while an alarm is active
  Future<void> _checkForExistingRingingAlarms() async {
    try {
      debugPrint('Checking for existing ringing alarms on controller init');

      // Check SharedPreferences for stored active alarm info first
      final prefs = await SharedPreferences.getInstance();
      final storedActiveAlarmId = prefs.getInt('flutter.active_alarm_id');

      if (storedActiveAlarmId != null && storedActiveAlarmId > 0) {
        debugPrint('Found stored active alarm ID: $storedActiveAlarmId');

        // Find the corresponding alarm in our system
        final alarm = getAlarmById(storedActiveAlarmId);
        if (alarm != null && alarm.isEnabled) {
          // Check if this alarm should still be ringing
          final now = DateTime.now();

          // For repeating alarms, check if they should be active based on current time
          // For one-time alarms, check if they're within a reasonable window (e.g., last 30 minutes)
          bool shouldBeRinging = false;

          if (alarm.isRepeating) {
            // Check if the current day/time matches the alarm schedule
            final currentWeekday = now.weekday == 7
                ? 0
                : now.weekday; // Convert Sunday from 7 to 0
            if (alarm.daysActive.contains(currentWeekday.toString())) {
              final alarmTime = DateTime(
                now.year,
                now.month,
                now.day,
                alarm.time.hour,
                alarm.time.minute,
              );
              final timeDiff = now.difference(alarmTime).inMinutes;
              // If we're within 30 minutes after the alarm time, it should still be ringing
              shouldBeRinging = timeDiff >= 0 && timeDiff <= 30;
            }
          } else {
            // For one-time alarms, check if it's within 30 minutes of the alarm time
            final timeDiff = now.difference(alarm.time).inMinutes;
            shouldBeRinging = timeDiff >= 0 && timeDiff <= 30;
          }

          if (shouldBeRinging) {
            debugPrint(
              'Alarm $storedActiveAlarmId should still be ringing, restoring active state',
            );

            activeAlarmId.value = storedActiveAlarmId;
            shouldShowStopScreen.value = true;
            hasActiveAlarm.value = true;

            // Ensure device stays awake
            _enableAlarmWakeLock();

            debugPrint(
              'Set shouldShowStopScreen to true for existing alarm: $storedActiveAlarmId',
            );
          } else {
            debugPrint(
              'Stored alarm $storedActiveAlarmId should no longer be ringing, clearing stored data',
            );
            // Clear stale data
            await prefs.remove('flutter.active_alarm_id');
            await prefs.remove('flutter.active_alarm_sound');
          }
        } else {
          debugPrint(
            'Stored alarm $storedActiveAlarmId not found or disabled, clearing stored data',
          );
          // Clear stale data for non-existent or disabled alarms
          await prefs.remove('flutter.active_alarm_id');
          await prefs.remove('flutter.active_alarm_sound');
        }
      } else {
        debugPrint('No stored active alarm data found');
      }
    } catch (e) {
      debugPrint('Error checking for existing ringing alarms: $e');
    }
  }

  /// Convert our AlarmModel to Alarm package's AlarmSettings
  AlarmSettings _convertToAlarmSettings(AlarmModel alarm) {
    // Get the proper sound path for the alarm
    final soundPath = 'assets/${SoundManager.getSoundPath(alarm.soundId)}';

    // Ensure volume is properly set - convert from 0-100 to 0.0-1.0
    final volumeLevel = currentAlarmVolume.value / 100.0;

    final nextAlarmTime = alarm.getNextAlarmTime();

    debugPrint(
      'Setting alarm volume to: ${currentAlarmVolume.value}% ($volumeLevel)',
    );
    debugPrint(
      'Scheduling alarm for EXACT time: ${nextAlarmTime.toIso8601String()} (${nextAlarmTime.hour}:${nextAlarmTime.minute.toString().padLeft(2, '0')})',
    );

    return AlarmSettings(
      id: alarm.id ?? DateTime.now().millisecondsSinceEpoch,
      dateTime: nextAlarmTime,
      assetAudioPath: soundPath,
      loopAudio: true,
      vibrate: false,
      warningNotificationOnKill: Platform.isIOS,
      androidFullScreenIntent: true,
      // CRITICAL: Prevent alarm from stopping when app is terminated/reopened
      androidStopAlarmOnTermination: false,
      volumeSettings: VolumeSettings.fade(
        volume: volumeLevel,
        fadeDuration: const Duration(
          seconds: 5,
        ), // Shorter fade for immediate volume
        volumeEnforced: true,
      ),
      notificationSettings: NotificationSettings(
        title: 'Alarm',
        body: alarm.nfcRequired
            ? 'Scan NFC Tag to Stop Alarm'
            : 'Tap to Stop Alarm',
        // stopButton: 'Stop',
      ),
      payload: alarm.nfcRequired ? 'nfc_required:true' : 'nfc_required:false',
    );
  }

  /// Creates a new alarm and schedules it using the Alarm package
  Future<void> createAlarm(AlarmModel alarm) async {
    try {
      final DateTime now = DateTime.now();
      if (!alarm.isRepeating && alarm.time.isBefore(now)) {
        alarm.time = alarm.time.add(const Duration(days: 1));
        debugPrint('Adjusted alarm time to: ${alarm.time}');
      }

      // Save to database first
      final id = await _dbHelper.insertAlarm(alarm);

      alarm.id = id;
      await recordAlarmSetTime(alarm);

      // 🔄 IMMEDIATE SHAREDPREFS SAVE: Alarm data immediately save করুন
      debugPrint('🔄 Saving alarm data to SharedPreferences immediately...');
      await AlarmPrefs.saveAlarmData(
        alarmId: alarm.id!,
        setTime: DateTime.now(),
        stopTime: null,
        isRepeating: alarm.isRepeating,
        daysActive: alarm.daysActive,
      );
      debugPrint('✅ Alarm data saved to SharedPreferences');

      if (alarm.isEnabled) {
        // PRIMARY: Use the Flutter Alarm package for when app is running
        final alarmSettings = _convertToAlarmSettings(alarm);
        await Alarm.set(alarmSettings: alarmSettings);

        debugPrint(
          'Alarm scheduled with Flutter Alarm package - ID: $id, Time: ${alarm.getNextAlarmTime().toIso8601String()}',
        );

        // BACKUP: Also schedule with native system for when app is closed
        try {
          await AlarmBackgroundService.scheduleExactAlarm(
            id,
            alarm.getNextAlarmTime(),
            alarm.soundId,
            alarm.nfcRequired,
          );
          debugPrint('Backup native alarm scheduled for when app is closed');
        } catch (e) {
          debugPrint('Error scheduling backup native alarm: $e');
        }
      }

      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;
      await _prefs.setInt('last_alarm_id', id);

      debugPrint(
        'Created new alarm with ID: $id, time: ${alarm.time}, next trigger: ${alarm.getNextAlarmTime()}',
      );

      // 🔄 REFRESH SLEEP STATISTICS: Immediately refresh sleep statistics
      debugPrint('🔄 Refreshing sleep statistics after alarm creation...');
      if (Get.isRegistered<SleepStatisticsController>()) {
        final statsController = Get.find<SleepStatisticsController>();
        await statsController.loadSleepStatistics();
        debugPrint('✅ Sleep statistics refreshed after alarm creation');
      }

      update();
    } catch (e) {
      debugPrint('Alarm creation failed: $e');
      rethrow;
    }
  }

  /// Creates a new alarm without sleep tracking (for reused alarms from history)
  Future<void> createAlarmWithoutSleepTracking(AlarmModel alarm) async {
    try {
      final DateTime now = DateTime.now();
      if (!alarm.isRepeating && alarm.time.isBefore(now)) {
        alarm.time = alarm.time.add(const Duration(days: 1));
        debugPrint('Adjusted alarm time to: ${alarm.time}');
      }

      // Save to database first (without calling recordAlarmSetTime)
      final id = await _dbHelper.insertAlarm(alarm);
      alarm.id = id;

      if (alarm.isEnabled) {
        // PRIMARY: Use the Flutter Alarm package for when app is running
        final alarmSettings = _convertToAlarmSettings(alarm);
        await Alarm.set(alarmSettings: alarmSettings);

        debugPrint(
          'Alarm scheduled with Flutter Alarm package (no sleep tracking) - ID: $id, Time: ${alarm.getNextAlarmTime().toIso8601String()}',
        );

        // BACKUP: Also schedule with native system for when app is closed
        try {
          await AlarmBackgroundService.scheduleExactAlarm(
            id,
            alarm.getNextAlarmTime(),
            alarm.soundId,
            alarm.nfcRequired,
          );
          debugPrint('Backup native alarm scheduled for when app is closed');
        } catch (e) {
          debugPrint('Error scheduling backup native alarm: $e');
        }
      }

      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;
      await _prefs.setInt('last_alarm_id', id);

      debugPrint(
        'Created reused alarm with ID: $id, time: ${alarm.time}, next trigger: ${alarm.getNextAlarmTime()} (without sleep tracking)',
      );
      update();
    } catch (e) {
      debugPrint('Reused alarm creation failed: $e');
      rethrow;
    }
  }

  /// Updates an existing alarm's properties and reschedules it
  Future<void> updateAlarm(AlarmModel alarm) async {
    try {
      if (alarm.id == null) {
        throw Exception('Cannot update alarm without an ID');
      }

      await _dbHelper.updateAlarm(alarm);

      // Cancel the old alarm from both systems
      await Alarm.stop(alarm.id!);
      await AlarmBackgroundService.removeScheduledAlarm(alarm.id!);

      // Also cancel the notification to ensure all alarm systems are stopped
      await NotificationService.cancelNotification(alarm.id!);

      if (alarm.isEnabled) {
        // PRIMARY: Use the Flutter Alarm package for when app is running
        final alarmSettings = _convertToAlarmSettings(alarm);
        await Alarm.set(alarmSettings: alarmSettings);

        debugPrint(
          'Alarm updated with Flutter Alarm package - ID: ${alarm.id}, Time: ${alarm.getNextAlarmTime().toIso8601String()}',
        );

        // BACKUP: Also schedule with native system for when app is closed
        try {
          await AlarmBackgroundService.scheduleExactAlarm(
            alarm.id!,
            alarm.getNextAlarmTime(),
            alarm.soundId,
            alarm.nfcRequired,
          );
          debugPrint('Backup native alarm updated for when app is closed');
        } catch (e) {
          debugPrint('Error updating backup native alarm: $e');
        }
      }

      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;

      // Refresh sleep statistics after alarm update
      if (Get.isRegistered<SleepStatisticsController>()) {
        await Get.find<SleepStatisticsController>().refreshSleepStatistics();
      }

      update();
    } catch (e) {
      debugPrint('Error updating alarm: $e');
    }
  }

  /// Deletes an alarm from the database and cancels its scheduled notifications
  Future<void> deleteAlarm(int id) async {
    try {
      // Cancel the alarm in the Flutter Alarm package
      await Alarm.stop(id);

      // Cancel native scheduled alarm
      await AlarmBackgroundService.cancelExactAlarm(id);
      await AlarmBackgroundService.removeScheduledAlarm(id);

      // Enhanced cleanup: Remove any stored active alarm data if this is the active alarm
      final prefs = await SharedPreferences.getInstance();
      final activeAlarmId = prefs.getInt('flutter.active_alarm_id');
      if (activeAlarmId == id) {
        await AlarmBackgroundService.clearAllStoredAlarmData();
        debugPrint('Cleared active alarm data for deleted alarm: $id');
      }

      // Clear any trigger timestamps for this alarm
      await prefs.remove('alarm_last_trigger_$id');

      // Delete from database
      await _dbHelper.deleteAlarm(id);

      // Update the UI
      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;

      // Refresh sleep statistics after alarm deletion
      if (Get.isRegistered<SleepStatisticsController>()) {
        await Get.find<SleepStatisticsController>().refreshSleepStatistics();
      }

      update();

      debugPrint('Deleted alarm with ID: $id');
    } catch (e) {
      debugPrint('Error deleting alarm: $e');
      rethrow;
    }
  }

  /// Toggles an alarm's enabled state
  Future<void> toggleAlarm(int id, bool isEnabled) async {
    try {
      if (isEnabled) {
        // If enabling the alarm, schedule it normally
        final alarm = getAlarmById(id);
        if (alarm != null) {
          alarm.isEnabled = true;
          await updateAlarm(alarm);
        }
      } else {
        // If disabling the alarm, ensure complete cleanup
        await Alarm.stop(id);
        await AlarmBackgroundService.cancelExactAlarm(id);
        await AlarmBackgroundService.removeScheduledAlarm(id);

        // Enhanced cleanup: Remove any stored active alarm data if this is the active alarm
        final prefs = await SharedPreferences.getInstance();
        final activeAlarmId = prefs.getInt('flutter.active_alarm_id');
        if (activeAlarmId == id) {
          await AlarmBackgroundService.clearAllStoredAlarmData();
          debugPrint('Cleared active alarm data for disabled alarm: $id');
        }

        // Clear any trigger timestamps for this alarm
        await prefs.remove('alarm_last_trigger_$id');

        // Update the database
        final alarm = getAlarmById(id);
        if (alarm != null) {
          alarm.isEnabled = false;
          await _dbHelper.updateAlarm(alarm);
        }
      }

      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;

      // Refresh sleep statistics after alarm toggle
      if (Get.isRegistered<SleepStatisticsController>()) {
        await Get.find<SleepStatisticsController>().refreshSleepStatistics();
      }

      update();

      debugPrint('Toggled alarm $id to ${isEnabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('Error toggling alarm: $e');
      rethrow;
    }
  }

  /// Disables an alarm without deleting it from the database
  Future<void> cancelAlarm(AlarmModel alarm) async {
    if (alarm.id == null) return;

    try {
      alarm.isEnabled = false;
      await _dbHelper.updateAlarm(alarm);

      // Cancel from both systems
      await Alarm.stop(alarm.id!);
      await AlarmBackgroundService.removeScheduledAlarm(alarm.id!);

      // Also cancel the notification to ensure all alarm systems are stopped
      await NotificationService.cancelNotification(alarm.id!);

      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;

      // Refresh sleep statistics after alarm cancellation
      if (Get.isRegistered<SleepStatisticsController>()) {
        await Get.find<SleepStatisticsController>().refreshSleepStatistics();
      }

      update();
    } catch (e) {
      debugPrint('Error canceling alarm: $e');
    }
  }

  /// Stops the alarm sound and updates the alarm state
  Future<void> stopAlarmAndUpdateState(AlarmModel alarm) async {
    try {
      if (alarm.id != null) {
        await Alarm.stop(alarm.id!);
      }

      stopAlarmSound();

      // Explicitly stop vibration using method channel
      if (Platform.isAndroid) {
        try {
          await const MethodChannel(
            'com.example.alarm/background_channel',
          ).invokeMethod('stopVibration');
          debugPrint('Explicitly stopped vibration via method channel');
        } catch (e) {
          debugPrint('Error stopping vibration via method channel: $e');
        }
      }

      await AlarmBackgroundService.stopAlarm();
      try {
        await WakelockPlus.disable();
      } catch (e) {
        debugPrint('Error disabling wakelock: $e');
      }

      if (!alarm.isRepeating) {
        alarm.isEnabled = false;
        await _dbHelper.updateAlarm(alarm);
      }

      // ✅ SINGLE SLEEP HISTORY UPDATE: Only update once in recordAlarmStopTime
      await recordAlarmStopTime(alarm);

      if (alarm.isRepeating && alarm.isEnabled) {
        final alarmSettings = _convertToAlarmSettings(alarm);
        await Alarm.set(alarmSettings: alarmSettings);
      }

      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;

      // 🔄 IMMEDIATE REFRESH: Refresh sleep statistics
      debugPrint('🔄 Refreshing sleep statistics after alarm stop...');
      if (Get.isRegistered<SleepStatisticsController>()) {
        final statsController = Get.find<SleepStatisticsController>();
        await statsController.loadSleepStatistics();
        debugPrint('✅ Sleep statistics refreshed after alarm stop');
      }

      update();
    } catch (e) {
      debugPrint('Error stopping alarm and updating state: $e');
      await AlarmBackgroundService.forceStopService();
    }
  }

  /// Stop alarm
  Future<void> stopAlarm(int alarmId, {int soundId = 1}) async {
    try {
      final alarm = getAlarmById(alarmId);
      if (alarm == null) {
        debugPrint('Cannot stop alarm: Alarm with ID $alarmId not found');
        return;
      }

      // Explicitly stop vibration first
      if (Platform.isAndroid) {
        try {
          await const MethodChannel(
            'com.example.alarm/background_channel',
          ).invokeMethod('stopVibration');
          debugPrint(
            'Explicitly stopped vibration via method channel in stopAlarm',
          );
        } catch (e) {
          debugPrint(
            'Error stopping vibration via method channel in stopAlarm: $e',
          );
        }
      }

      await stopAlarmAndUpdateState(alarm);

      // If we need to stop using the Alarm package directly
      await Alarm.stop(alarmId);

      final nfcController = Get.put(NFCController());
      nfcController.verificationSuccess.value = true;

      debugPrint('Alarm $alarmId stopped successfully');
    } catch (e) {
      debugPrint('Error stopping alarm: $e');
    }
  }

  /// Snooze the current alarm
  Future<void> snoozeAlarm(int alarmId, {int snoozeMinutes = 5}) async {
    try {
      final alarm = getAlarmById(alarmId);
      if (alarm == null) return;

      // Stop the current alarm
      await stopAlarmAndUpdateState(alarm);

      // Calculate snooze time
      final now = DateTime.now();
      final snoozeTime = now.add(Duration(minutes: snoozeMinutes));

      // Create a temporary one-time alarm for the snooze
      final snoozeAlarm = alarm.copyWith(
        time: snoozeTime,
        isEnabled: true,
        daysActive: [], // No repeat
      );

      // Store snooze information
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('snoozed_from_alarm_id', alarmId);
      await prefs.setInt(
        'snooze_count',
        (prefs.getInt('snooze_count') ?? 0) + 1,
      );

      // Schedule the snooze alarm without sleep tracking
      await createAlarmWithoutSleepTracking(snoozeAlarm);

      Get.snackbar(
        'Alarm Snoozed',
        'Alarm will ring again in $snoozeMinutes minutes',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      debugPrint('Error snoozing alarm: $e');
    }
  }

  /// Checks for alarms that should be ringing but aren't
  /// DISABLED: This method was causing duplicate alarm triggers
  /// The Flutter Alarm package handles alarm state verification automatically
  /*
  Future<void> verifyAlarmStates() async {
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();

      // Check each enabled alarm
      for (final alarm in alarms.where((a) => a.isEnabled)) {
        // If alarm should be ringing based on its time
        if (alarm.isRinging(now) && alarm.id != null) {
          // But our active alarm ID doesn't match
          if (activeAlarmId.value != alarm.id) {
            // Check when this alarm was last activated
            final lastActivated =
                prefs.getInt('alarm_last_activated_${alarm.id}') ?? 0;
            final timeSinceActivation =
                now.millisecondsSinceEpoch - lastActivated;

            // Only trigger if it hasn't been activated in the last 30 seconds
            if (timeSinceActivation > 30000) {
              debugPrint(
                  'Found alarm ${alarm.id} that should be ringing but isn\'t active');

              // Start the alarm
              await playAlarmSound(alarm.soundId, alarmId: alarm.id);

              // Only show notification if the sound playback was successful (not deduplicated)
              if (activeAlarmId.value == alarm.id) {
                await NotificationService.showFallbackAlarmNotification(
                    alarm.id!, alarm.soundId);
              }
            } else {
              debugPrint(
                  'Alarm ${alarm.id} was recently activated, skipping duplicate trigger');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error verifying alarm states: $e');
    }
  }
  */

  /// Load saved volume from shared preferences
  Future<void> _loadSavedVolume() async {
    try {
      final savedVolume = _prefs.getInt('alarm_volume') ?? 50;
      currentAlarmVolume.value = savedVolume;
      debugPrint('Loaded saved volume: $savedVolume%');
    } catch (e) {
      debugPrint('Error loading saved volume: $e');
    }
  }

  /// Starts a timer to update the current time
  void _startClockTimer() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentTime.value = DateFormat('HH:mm:ss').format(DateTime.now());
    });
  }

  /// Starts a periodic timer to refresh alarm states and UI
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;
      loadAlarms();
    });
  }

  /// Initialize the controller and its dependencies
  Future<void> _initializeController() async {
    try {
      tz.initializeTimeZones();
      _prefs = await SharedPreferences.getInstance();
      await NotificationService.initialize();
      await _preloadSounds();
      await _loadSelectedSound(); // Load saved sound preference
    } catch (e) {
      debugPrint('Controller Initialization Error: $e');
    }
  }

  /// Preload all alarm sounds to reduce playback delay
  Future<void> _preloadSounds() async {
    try {
      for (int i = 1; i <= SoundManager.soundCount(); i++) {
        final soundPath = SoundManager.getSoundPath(i);
        await _audioPlayer.setSource(AssetSource(soundPath));
      }
    } catch (e) {
      debugPrint('Error preloading sounds: $e');
    }
  }

  /// Fetches all alarms from the database and updates the observable state
  Future<void> loadAlarms() async {
    try {
      final loadedAlarms = await _dbHelper.getAllAlarms();
      alarms.value = loadedAlarms;
      isAlarmActive.value = getActiveAlarms().isNotEmpty;
    } catch (e) {
      debugPrint('Error loading alarms: $e');
    }
  }

  /// Returns a filtered list of currently active alarms
  List<AlarmModel> getActiveAlarms() {
    final now = DateTime.now();

    return alarms.where((alarm) {
      if (!alarm.isEnabled) return false;
      if (alarm.isRepeating) return true;
      return alarm.time.isAfter(now);
    }).toList();
  }

  /// Get an alarm by ID
  AlarmModel? getAlarmById(int id) {
    try {
      return alarms.firstWhere((alarm) => alarm.id == id);
    } catch (e) {
      debugPrint('Alarm with ID $id not found');
      return null;
    }
  }

  /// Plays the selected alarm sound, either as a preview or full alarm
  Future<void> playAlarmSound(
    int soundId, {
    bool isPreview = false,
    int? alarmId,
  }) async {
    try {
      // For actual alarms (not previews), check for duplicates
      if (!isPreview && alarmId != null) {
        _volumeManager.startLockingVolume(volume: 1.0);
        // Use the NotificationService's deduplication logic
        if (!(await NotificationService.markAlarmAsActivated(alarmId))) {
          debugPrint(
            'Skipping duplicate alarm sound playback for ID: $alarmId',
          );
          return; // Skip duplicate activation
        }
      }

      await _audioPlayer.stop();
      final soundPath = SoundManager.getSoundPath(soundId);
      debugPrint('Playing sound: $soundPath (Preview: $isPreview)');
      await _audioPlayer.setReleaseMode(
        isPreview ? ReleaseMode.release : ReleaseMode.loop,
      );

      final volume = isPreview
          ? (currentAlarmVolume.value / 100) * 0.5
          : (currentAlarmVolume.value / 100);

      // Ensure minimum volume for alarms (not previews)
      final finalVolume = isPreview ? volume : volume.clamp(0.1, 1.0);

      debugPrint(
        'Setting audio player volume to: ${currentAlarmVolume.value}% -> $finalVolume (Preview: $isPreview)',
      );

      await _audioPlayer.setVolume(finalVolume);
      await _audioPlayer.setSourceAsset(soundPath);
      await _audioPlayer.resume();

      if (isPreview) {
        // For previews, let the sound play naturally but with a safety timeout
        // Check periodically if the sound is still playing and stop when complete
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
          if (_audioPlayer.state != PlayerState.playing || timer.tick > 20) {
            // Stop if not playing or after 10 seconds (20 * 500ms)
            timer.cancel();
            if (_audioPlayer.state == PlayerState.playing) {
              _audioPlayer.stop();
            }
          }
        });
      } else if (alarmId != null) {
        activeAlarmId.value = alarmId;
        _alarmSoundTimer?.cancel();
        _alarmSoundTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
          _increaseAlarmVolumeGradually();
        });

        // Update the shouldShowStopScreen value to indicate that the stop alarm screen should be shown
        shouldShowStopScreen.value = true;
        hasActiveAlarm.value = true;

        // Store the active alarm ID in shared preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('flutter.active_alarm_id', alarmId);
        await prefs.setInt('flutter.active_alarm_sound', soundId);

        _enableAlarmWakeLock();
      }
    } catch (e) {
      debugPrint('Sound playback error: $e');
      Get.snackbar(
        'Playback Error',
        'Unable to play alarm sound. Please check your device settings.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
      await _audioPlayer.stop();
    }
  }

  /// Increase volume
  void _increaseAlarmVolumeGradually() {
    try {
      if (currentAlarmVolume.value < 100) {
        int newVolume = min(currentAlarmVolume.value + 10, 100);
        updateAlarmVolume(newVolume);
        debugPrint('Gradually increased alarm volume to $newVolume%');
      }
    } catch (e) {
      debugPrint('Error increasing alarm volume: $e');
    }
  }

  Future<void> _resetToFixedVolume() async {
    await _audioPlayer.setVolume(.8);
    // await volumeController.setVolume(fixedVolume);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
          event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
        _resetToFixedVolume();
        return true; // Prevent default behavior
      }
    }
    return false;
  }

  Future<void> initAudioSettings() async {
    try {
      if (Platform.isAndroid) {
        await _configureAndroidAudio();
      } else if (Platform.isIOS) {
        await _configureIOSAudio();
      }
    } catch (e) {
      debugPrint('Audio configuration error: $e');
    }
  }

  Future<void> _configureAndroidAudio() async {
    try {
      await const MethodChannel('audio_service').invokeMethod('setAudioMode', {
        'contentType': 'sonification',
        'usage': 'alarm',
        'handleAudioFocus': false,
        'streamType': 'alarm',
      });
    } catch (e) {
      debugPrint('Android audio config error: $e');
    }
  }

  Future<void> _configureIOSAudio() async {
    try {
      await const MethodChannel('audio_service')
          .invokeMethod('setAudioCategory', {
        'category': 'playback',
        'options': ['mixWithOthers'],
      });
    } catch (e) {
      debugPrint('iOS audio config error: $e');
    }
  }

  /// Acquires a wake lock to prevent the device from sleeping during alarm playback
  Future<void> _enableAlarmWakeLock() async {
    try {
      await WakelockPlus.enable();
      debugPrint('Wake lock enabled for alarm');
    } catch (e) {
      debugPrint('Error enabling wake lock: $e');
      // Fallback mechanism if wakelock fails
      Timer.periodic(const Duration(seconds: 5), (timer) {
        if (activeAlarmId.value == -1) {
          timer.cancel();
          WakelockPlus.disable().catchError(
            (e) => debugPrint('Error disabling wakelock: $e'),
          );
        }
      });
    }
  }

  /// Stops any currently playing alarm sound
  void stopAlarmSound() {
    _audioPlayer.stop();
    _alarmSoundTimer?.cancel();
    activeAlarmId.value = -1;
    shouldShowStopScreen.value = false;
    hasActiveAlarm.value = false;
  }

  /// Updates volume setting for alarm playback
  Future<void> updateAlarmVolume(int volume) async {
    try {
      currentAlarmVolume.value = volume.clamp(0, 100);

      // Save to multiple keys to ensure consistency across all components
      await _prefs.setInt('alarm_volume', currentAlarmVolume.value);
      await _prefs.setInt('flutter.alarm_volume', currentAlarmVolume.value);
      await _prefs.setDouble(
        'alarm_volume_double',
        currentAlarmVolume.value / 100.0,
      );

      debugPrint(
        'Updated alarm volume to: ${currentAlarmVolume.value}% (${currentAlarmVolume.value / 100.0})',
      );

      if (_audioPlayer.state == PlayerState.playing) {
        await _audioPlayer.setVolume(currentAlarmVolume.value / 100);
      }
    } catch (e) {
      debugPrint('Error updating volume: $e');
    }
  }

  /// Updates the selected sound for new alarms
  Future<void> updateSelectedSound(int soundId) async {
    try {
      selectedSoundForNewAlarm.value = soundId;
      selectedSoundName.value = SoundManager.getSoundName(soundId);

      // Save to SharedPreferences
      await _prefs.setInt('selected_sound_for_new_alarm', soundId);
      debugPrint(
        'Updated selected sound to: $soundId (${selectedSoundName.value})',
      );
    } catch (e) {
      debugPrint('Error updating selected sound: $e');
    }
  }

  /// Loads the saved sound preference from SharedPreferences
  Future<void> _loadSelectedSound() async {
    try {
      final savedSoundId = _prefs.getInt('selected_sound_for_new_alarm') ?? 1;
      selectedSoundForNewAlarm.value = savedSoundId;
      selectedSoundName.value = SoundManager.getSoundName(savedSoundId);
      debugPrint(
        'Loaded selected sound: $savedSoundId (${selectedSoundName.value})',
      );
    } catch (e) {
      debugPrint('Error loading selected sound: $e');
    }
  }

  /// Verifies backup code entered by the user
  bool verifyBackupCode(String enteredCode) {
    final nfcController = Get.put(NFCController());
    return nfcController.verifyBackupCode(enteredCode);
  }

  /// Starts NFC verification for the specified alarm
  Future<bool> verifyNfcForAlarm(int alarmId) async {
    try {
      final nfcController = Get.put(NFCController());
      final result = await nfcController.startAlarmVerification(alarmId);
      return result;
    } catch (e) {
      debugPrint('Error verifying NFC for alarm: $e');
      return false;
    }
  }

  /// Processes alarm dismissal based on verification method
  Future<bool> dismissAlarm(
    int alarmId, {
    String? backupCode,
    bool nfcVerified = false,
  }) async {
    try {
      final alarm = getAlarmById(alarmId);
      if (alarm == null) {
        debugPrint('Cannot dismiss alarm: Alarm with ID $alarmId not found');
        return false;
      }

      bool isVerified = false;

      // Only verify with backup code "12345"
      if (backupCode != null && backupCode == "RH2ASJKJ2394J") {
        isVerified = true;
      } else if (nfcVerified) {
        // If using NFC verification, keep that functionality
        isVerified = true;
      }

      if (isVerified) {
        await stopAlarmAndUpdateState(alarm);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error dismissing alarm: $e');
      return false;
    }
  }

  /// Forces a refresh of the UI and alarm data
  void forceRefreshUI() {
    refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;
    loadAlarms();
    _checkForActiveAlarms();
    update();
  }

  /// record alarm set time
  Future<void> recordAlarmSetTime(AlarmModel alarm) async {
    if (alarm.id == null) return;

    try {
      final now = DateTime.now();

      // 🔍 DEBUG: Track set time recording
      debugPrint('🕐 ALARM SET TIME RECORDING:');
      debugPrint('   Alarm ID: ${alarm.id}');
      debugPrint(
          '   Set Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}');
      debugPrint('   Alarm Time: ${DateFormat('HH:mm').format(alarm.time)}');
      debugPrint('   Is Repeating: ${alarm.isRepeating}');
      debugPrint('   Days Active: ${alarm.daysActive}');

      // Update alarm's set time in database
      await _dbHelper.updateAlarmTimes(alarm.id!, setTime: now);

      // Update the alarm model with current set time and mark for today
      alarm.lastSetTime = now;
      alarm.isForToday = true;

      // Update the alarm in database to mark it as for today
      await _dbHelper.updateAlarm(alarm);

      // ✅ SharedPreferences এ সেভ করুন
      await AlarmPrefs.saveAlarmData(
        alarmId: alarm.id!,
        setTime: now, // যখন alarm set করছেন (যেমন: 10:30)
        stopTime: null, // এখনও বন্ধ হয়নি
        isRepeating: alarm.isRepeating,
        daysActive: alarm.daysActive,
      );

      // 🔄 ADDITIONAL: Save wake time (alarm time) separately
      await _saveWakeTime(alarm.id!, alarm.time);

      // 🔄 PARTIAL SLEEP HISTORY: Create partial entry when alarm is set
      debugPrint('🔄 Creating partial sleep history entry...');
      final today = DateTime(now.year, now.month, now.day);

      // Calculate estimated sleep time for partial entry
      final estimatedSleepTime =
          alarm.time.subtract(const Duration(hours: 7, minutes: 30));
      final sleepTime = estimatedSleepTime.isBefore(now)
          ? estimatedSleepTime
          : now.subtract(const Duration(hours: 7, minutes: 30));

      // 🔄 IMPROVED: Use actual wake time (alarm time) instead of null
      await SleepHistoryPrefs.savePartialSleepHistoryWithWakeTime(
        date: today,
        sleepTime: sleepTime,
        wakeTime: alarm.time, // Actual wake time (alarm time)
        alarmCount: 1,
      );

      // 🔍 DEBUG: Verify database update
      debugPrint('✅ DATABASE & SHAREDPREFS UPDATED:');
      debugPrint('   last_set_time: ${alarm.lastSetTime?.toIso8601String()}');
      debugPrint('   is_for_today: ${alarm.isForToday}');
      debugPrint(
          '   partial_sleep_time: ${DateFormat('HH:mm').format(sleepTime)}');

      debugPrint(
          'Alarm set time recorded: ${DateFormat('HH:mm:ss').format(now)}');
      debugPrint(
          'Partial sleep history created with sleep time: ${DateFormat('HH:mm').format(sleepTime)}');
    } catch (e) {
      debugPrint('❌ Error recording alarm set time: $e');
    }
  }

  /// alarm stop time
  Future<void> recordAlarmStopTime(AlarmModel alarm) async {
    if (alarm.id == null) return;

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // 🔍 DEBUG: Track stop time recording
      debugPrint('⏰ ALARM STOP TIME RECORDING:');
      debugPrint('   Alarm ID: ${alarm.id}');
      debugPrint(
          '   Stop Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}');
      debugPrint('   Today Date: ${DateFormat('yyyy-MM-dd').format(today)}');

      // Update alarm's stop time in database
      await _dbHelper.updateAlarmTimes(alarm.id!, stopTime: now);

      // Update the alarm model
      alarm.lastStopTime = now;
      alarm.isForToday = false;
      await _dbHelper.updateAlarm(alarm);

      // ✅ SharedPreferences এ আপডেট করুন
      await AlarmPrefs.updateAlarmStopTime(alarm.id!, now);

      // 🔍 DEBUG: Verify alarm model update
      debugPrint('✅ ALARM MODEL & SHAREDPREFS UPDATED:');
      debugPrint('   last_stop_time: ${alarm.lastStopTime?.toIso8601String()}');
      debugPrint('   is_for_today: ${alarm.isForToday}');

      // 🔧 IMPROVED SLEEP TIME CALCULATION
      // Method 1: Try to get user's actual sleep time from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userSleepTimeKey =
          'user_sleep_time_${DateFormat('yyyy-MM-dd').format(today)}';
      final userSleepTimeString = prefs.getString(userSleepTimeKey);

      DateTime? sleepTime;

      if (userSleepTimeString != null) {
        // Use user's actual sleep time if available
        try {
          sleepTime = DateTime.parse(userSleepTimeString);
          debugPrint(
              '✅ Using user-provided sleep time: ${DateFormat('HH:mm').format(sleepTime!)}');
        } catch (e) {
          debugPrint('❌ Error parsing user sleep time: $e');
        }
      }

      if (sleepTime == null) {
        // Method 2: Intelligent estimation based on alarm time
        // Calculate sleep time as 7.5 hours before alarm time
        final estimatedSleepTime =
            alarm.time.subtract(const Duration(hours: 7, minutes: 30));

        // 🔧 FIXED LOGIC: Use the earlier of estimated sleep time or actual set time
        // This ensures we don't have sleep time after wake time
        if (alarm.lastSetTime != null) {
          sleepTime = estimatedSleepTime.isBefore(alarm.lastSetTime!)
              ? estimatedSleepTime
              : alarm.lastSetTime!;
        } else {
          sleepTime = estimatedSleepTime;
        }

        debugPrint(
            '📊 Using estimated sleep time: ${DateFormat('HH:mm').format(sleepTime)}');
      }

      // 🔧 ADDITIONAL VALIDATION: Ensure sleep time is before wake time
      if (sleepTime.isAfter(now)) {
        debugPrint('⚠️ WARNING: Sleep time is after wake time, adjusting...');
        // If sleep time is after wake time, use a reasonable default
        sleepTime = now.subtract(const Duration(hours: 7, minutes: 30));
        debugPrint(
            '📊 Adjusted sleep time to: ${DateFormat('HH:mm').format(sleepTime)}');
      }

      // 🔧 FINAL VALIDATION: Ensure we have a reasonable sleep duration
      final initialSleepDurationMinutes = now.difference(sleepTime).inMinutes;
      if (initialSleepDurationMinutes <= 0 ||
          initialSleepDurationMinutes > 24 * 60) {
        debugPrint(
            '⚠️ WARNING: Unreasonable sleep duration ($initialSleepDurationMinutes minutes), using default...');
        // Use a reasonable default: 7.5 hours before wake time
        sleepTime = now.subtract(const Duration(hours: 7, minutes: 30));
        debugPrint(
            '📊 Using default sleep time: ${DateFormat('HH:mm').format(sleepTime)}');
      }

      // 🔍 DEBUG: Calculate sleep duration
      debugPrint('📊 SLEEP DURATION CALCULATION (IMPROVED):');
      debugPrint(
          '   Alarm Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(alarm.time)}');
      debugPrint(
          '   Set Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(alarm.lastSetTime!)}');
      debugPrint(
          '   Final Sleep Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(sleepTime)}');
      debugPrint(
          '   Wake Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}');

      // Calculate actual sleep duration
      final sleepDurationMinutes = now.difference(sleepTime).inMinutes;
      final sleepDurationHours = sleepDurationMinutes / 60.0;

      debugPrint('   Duration Minutes: $sleepDurationMinutes');
      debugPrint('   Duration Hours: ${sleepDurationHours.toStringAsFixed(2)}');

      // Get today's alarm count
      final todayAlarms = await _dbHelper.getTodayAlarms();
      final alarmCount = todayAlarms.length;

      debugPrint('📅 TODAY ALARMS:');
      debugPrint('   Total Alarms Today: $alarmCount');

      // Calculate total alarm duration for today
      int totalAlarmDuration = 0;
      for (var alarmMap in todayAlarms) {
        final currentAlarm = AlarmModel.fromMap(alarmMap);
        if (currentAlarm.lastSetTime != null &&
            currentAlarm.lastStopTime != null) {
          totalAlarmDuration += currentAlarm.calculateActualDuration();
        }
      }

      debugPrint('   Total Alarm Duration: $totalAlarmDuration minutes');

      // Insert or update sleep history with actual times
      await _dbHelper.insertSleepHistory(
        date: today,
        sleepTime: sleepTime,
        wakeTime: now,
        totalHours: sleepDurationHours,
        alarmCount: alarmCount,
        totalAlarmDuration: totalAlarmDuration,
      );

      // ✅ Sleep history SharedPreferences এ সেভ করুন
      // Check if we have a partial entry to update
      final existingHistory =
          await SleepHistoryPrefs.getSleepHistoryForDate(today);
      final hasPartialEntry =
          existingHistory.any((entry) => entry['isPartial'] == true);

      if (hasPartialEntry) {
        // Update existing partial entry
        debugPrint('🔄 Updating existing partial sleep history entry...');
        await SleepHistoryPrefs.updatePartialSleepHistory(
          date: today,
          wakeTime: now,
          totalHours: sleepDurationHours,
          totalAlarmDuration: totalAlarmDuration,
        );
      } else {
        // Create new complete entry
        debugPrint('🔄 Creating new complete sleep history entry...');
        await SleepHistoryPrefs.saveSleepHistory(
          date: today,
          sleepTime: sleepTime,
          wakeTime: now,
          totalHours: sleepDurationHours,
          alarmCount: alarmCount,
          totalAlarmDuration: totalAlarmDuration,
        );
      }

      // 🔍 DEBUG: Verify sleep history creation
      debugPrint('💾 SLEEP HISTORY CREATED (DB & SHAREDPREFS):');
      debugPrint('   Date: ${DateFormat('yyyy-MM-dd').format(today)}');
      debugPrint('   Sleep Time: ${sleepTime.toIso8601String()}');
      debugPrint('   Wake Time: ${now.toIso8601String()}');
      debugPrint('   Total Hours: ${sleepDurationHours.toStringAsFixed(2)}');
      debugPrint('   Alarm Count: $alarmCount');
      debugPrint('   Total Alarm Duration: $totalAlarmDuration minutes');

      debugPrint('✅ Sleep History Updated:');
      debugPrint('   Set: ${DateFormat('HH:mm:ss').format(sleepTime)}');
      debugPrint('   Off: ${DateFormat('HH:mm:ss').format(now)}');
      debugPrint('   Duration: ${sleepDurationHours.toStringAsFixed(2)} hours');
      debugPrint('   Alarm Count: $alarmCount');

      // 🔄 IMMEDIATE REFRESH: Sleep statistics refresh করুন
      debugPrint('🔄 Refreshing sleep statistics immediately...');
      if (Get.isRegistered<SleepStatisticsController>()) {
        final statsController = Get.find<SleepStatisticsController>();
        await statsController.forceRefreshUI();
        debugPrint('✅ Sleep statistics refreshed successfully');
      } else {
        debugPrint('⚠️ SleepStatisticsController not registered');
      }
    } catch (e) {
      debugPrint('❌ Error recording alarm stop time: $e');
    }
  }

  /// Check for active alarms and update the hasActiveAlarm value
  /// Also updates shouldShowStopScreen to indicate if the stop alarm screen should be shown
  Future<void> _checkForActiveAlarms() async {
    try {
      final isActive = await AlarmBackgroundService.isAlarmActive();
      if (isActive != hasActiveAlarm.value) {
        hasActiveAlarm.value = isActive;
        update();
      }

      // If there's an active alarm, we should show the stop screen
      if (isActive) {
        final prefs = await SharedPreferences.getInstance();
        final activeAlarmId = prefs.getInt('flutter.active_alarm_id');

        if (activeAlarmId != null && activeAlarmId > 0) {
          this.activeAlarmId.value = activeAlarmId;
          shouldShowStopScreen.value = true;

          // Ensure the app stays awake while alarm is active
          try {
            await WakelockPlus.enable();
          } catch (e) {
            debugPrint('Error enabling wakelock: $e');
          }
        }
      } else {
        shouldShowStopScreen.value = false;
        // Release wakelock if no active alarm
        try {
          await WakelockPlus.disable();
        } catch (e) {
          debugPrint('Error disabling wakelock: $e');
        }
      }
    } catch (e) {
      debugPrint('Error checking for active alarms: $e');
    }
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    _audioPlayer.dispose();
    super.onClose();
  }

  /// 🔧 SIMPLE RESET FUNCTION - Fixes all alarm issues
  /// Call this function when alarms are not working properly
  Future<void> resetAlarmSystem() async {
    try {
      debugPrint('🔄 RESETTING ALARM SYSTEM - Fixing all issues...');

      // 1. Stop all current alarms
      stopAlarmSound();
      await AlarmBackgroundService.emergencyStopAllAlarms();

      // 2. Clear all stored data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('flutter.active_alarm_id');
      await prefs.remove('flutter.active_alarm_sound');
      await prefs.remove('flutter.alarm_start_time');
      await prefs.remove('flutter.using_fallback_alarm');
      await prefs.remove('flutter.direct_to_stop');
      await prefs.remove('flutter.using_native_notification');
      await prefs.remove('flutter.notification_handler');
      await prefs.remove('scheduled_alarms');

      // 3. Clear alarm trigger timestamps
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('alarm_last_trigger_') ||
            key.startsWith('alarm_last_activated_')) {
          await prefs.remove(key);
        }
      }

      // 4. Reset controller state
      activeAlarmId.value = -1;
      shouldShowStopScreen.value = false;
      hasActiveAlarm.value = false;
      isAlarmActive.value = false;

      // 5. Stop all Flutter Alarm package alarms
      try {
        Alarm.stopAll();
        debugPrint('✅ Stopped all Flutter Alarm package alarms');
      } catch (e) {
        debugPrint('⚠️ Error stopping Flutter alarms: $e');
      }

      // 6. Reload alarms from database
      await loadAlarms();

      // 7. Show success message
      Get.snackbar(
        '✅ Alarm System Reset',
        'All alarm issues have been fixed. You can now set new alarms.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green[100],
        duration: const Duration(seconds: 5),
      );

      debugPrint('✅ ALARM SYSTEM RESET COMPLETED - All issues fixed!');
    } catch (e) {
      debugPrint('❌ Error resetting alarm system: $e');
      Get.snackbar(
        '❌ Reset Failed',
        'Please try again or restart the app.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
      );
    }
  }

  /// 🔧 QUICK FIX - Simple function to fix common alarm issues
  Future<void> quickFixAlarms() async {
    try {
      debugPrint('🔧 Applying quick fix for alarm issues...');

      // Stop current alarm if any
      if (activeAlarmId.value > 0) {
        await stopAlarm(activeAlarmId.value);
      }

      // Clear active alarm data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('flutter.active_alarm_id');
      await prefs.remove('flutter.active_alarm_sound');

      // Reset controller state
      activeAlarmId.value = -1;
      shouldShowStopScreen.value = false;
      hasActiveAlarm.value = false;

      // Reload alarms
      await loadAlarms();

      Get.snackbar(
        '🔧 Quick Fix Applied',
        'Alarm issues have been resolved.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.blue[100],
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      debugPrint('❌ Quick fix failed: $e');
    }
  }

  /// 🕐 SET USER SLEEP TIME - Allow user to set their actual sleep time
  Future<void> setUserSleepTime(DateTime sleepTime) async {
    try {
      final today = DateTime(sleepTime.year, sleepTime.month, sleepTime.day);
      final prefs = await SharedPreferences.getInstance();
      final userSleepTimeKey =
          'user_sleep_time_${DateFormat('yyyy-MM-dd').format(today)}';

      await prefs.setString(userSleepTimeKey, sleepTime.toIso8601String());

      debugPrint(
          '✅ User sleep time set for ${DateFormat('yyyy-MM-dd').format(today)}: ${DateFormat('HH:mm').format(sleepTime)}');

      Get.snackbar(
        '✅ Sleep Time Set',
        'Your sleep time has been recorded: ${DateFormat('HH:mm').format(sleepTime)}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green[100],
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      debugPrint('❌ Error setting user sleep time: $e');
      Get.snackbar(
        '❌ Error',
        'Failed to set sleep time. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
      );
    }
  }

  /// 🕐 GET USER SLEEP TIME - Get user's set sleep time for a specific date
  Future<DateTime?> getUserSleepTime(DateTime date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userSleepTimeKey =
          'user_sleep_time_${DateFormat('yyyy-MM-dd').format(date)}';
      final userSleepTimeString = prefs.getString(userSleepTimeKey);

      if (userSleepTimeString != null) {
        return DateTime.parse(userSleepTimeString);
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error getting user sleep time: $e');
      return null;
    }
  }

  /// 🔄 SAVE WAKE TIME - Save the alarm time (when alarm will ring)
  Future<void> _saveWakeTime(int alarmId, DateTime wakeTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wakeTimeKey = 'alarm_wake_time_$alarmId';

      await prefs.setString(wakeTimeKey, wakeTime.toIso8601String());

      debugPrint(
          '✅ Wake time saved for alarm $alarmId: ${DateFormat('HH:mm').format(wakeTime)}');
    } catch (e) {
      debugPrint('❌ Error saving wake time: $e');
    }
  }

  /// 🔄 GET WAKE TIME - Get the alarm time (when alarm will ring)
  Future<DateTime?> _getWakeTime(int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wakeTimeKey = 'alarm_wake_time_$alarmId';

      final wakeTimeString = prefs.getString(wakeTimeKey);
      if (wakeTimeString != null) {
        return DateTime.parse(wakeTimeString);
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error getting wake time: $e');
      return null;
    }
  }

  /// 🧹 CLEAR CORRUPTED SLEEP HISTORY - Clear corrupted sleep history data
  Future<void> clearCorruptedSleepHistory() async {
    try {
      debugPrint('🧹 Clearing corrupted sleep history data...');

      // Clear from SharedPreferences
      await SleepHistoryPrefs.clearAllSleepHistory();

      // Clear from database
      await _dbHelper.clearAllSleepHistory();

      // Refresh sleep statistics
      if (Get.isRegistered<SleepStatisticsController>()) {
        final statsController = Get.find<SleepStatisticsController>();
        await statsController.forceRefreshUI();
      }

      debugPrint('✅ Corrupted sleep history cleared successfully');

      Get.snackbar(
        '✅ Data Cleared',
        'Corrupted sleep history has been cleared.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green[100],
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      debugPrint('❌ Error clearing corrupted sleep history: $e');
      Get.snackbar(
        '❌ Error',
        'Failed to clear corrupted data. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
      );
    }
  }

  @override
  void dispose() {
    // TODO: implement dispose
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }
}
