import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:alarm/model/volume_settings.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:get/get.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarm/alarm.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/background_service.dart';
import '../../models/alarm/alarm_model.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/sound_manager.dart';
import '../../core/constants/asset_constants.dart';
import '../nfc/nfc_controller.dart';
import '../stats/stats_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';

class AlarmController extends GetxController {
  final DatabaseHelper _dbHelper;
  final AudioPlayer _audioPlayer;
  Timer? _refreshTimer;
  Timer? _alarmSoundTimer;

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
            if (alarm.daysActive.contains(currentWeekday)) {
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

      await recordAlarmStopTime(alarm);

      if (alarm.isRepeating && alarm.isEnabled) {
        final alarmSettings = _convertToAlarmSettings(alarm);
        await Alarm.set(alarmSettings: alarmSettings);
      }

      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;
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
      final today = DateTime(now.year, now.month, now.day);

      await _dbHelper.updateAlarmTimes(alarm.id!, setTime: now);

      alarm.isForToday = true;
      await _dbHelper.updateAlarm(alarm);

      DateTime sleepTime = now;
      DateTime wakeTime = alarm.time;

      final todayAlarms = await _dbHelper.getTodayAlarms();
      final alarmCount = todayAlarms.length;

      int totalDuration = 0;
      for (var alarmMap in todayAlarms) {
        final currentAlarm = AlarmModel.fromMap(alarmMap);
        if (currentAlarm.lastSetTime != null &&
            currentAlarm.lastStopTime != null) {
          totalDuration += currentAlarm.calculateActualDuration();
        } else if (currentAlarm.id == alarm.id) {
          totalDuration +=
              alarm.durationMinutes > 0 ? alarm.durationMinutes : 1;
        }
      }

      final existingData = await _dbHelper.getSleepHistoryRange(
        today,
        today.add(const Duration(days: 1)),
      );

      if (existingData.isNotEmpty) {
        final record = existingData.first;
        final existingSetTime = DateTime.parse(record['sleep_time']);
        final existingWakeTime = DateTime.parse(record['wake_time']);

        sleepTime = now.isBefore(existingSetTime) ? now : existingSetTime;

        wakeTime =
            wakeTime.isAfter(existingWakeTime) ? wakeTime : existingWakeTime;
      }

      double totalHours = totalDuration / 60.0;

      await _dbHelper.insertSleepHistory(
        date: today,
        sleepTime: sleepTime,
        wakeTime: wakeTime,
        totalHours: totalHours,
        alarmCount: alarmCount,
        totalAlarmDuration: totalDuration,
      );

      debugPrint('Recorded alarm set time: ${now.toIso8601String()}');
      debugPrint('Sleep time set to: ${sleepTime.toIso8601String()}');
      debugPrint('Wake time set to: ${wakeTime.toIso8601String()}');
      debugPrint('Total sleep hours: $totalHours');
      debugPrint('Current alarm count: $alarmCount');
      debugPrint('Total alarm duration: $totalDuration minutes');

      if (Get.isRegistered<SleepStatisticsController>()) {
        await Get.find<SleepStatisticsController>().refreshSleepStatistics();
      }
    } catch (e) {
      debugPrint('Error recording alarm set time: $e');
    }
  }

  /// alarm stop time
  Future<void> recordAlarmStopTime(AlarmModel alarm) async {
    if (alarm.id == null) return;

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      await _dbHelper.updateAlarmTimes(alarm.id!, stopTime: now);

      int actualDuration = 0;
      if (alarm.lastSetTime != null) {
        actualDuration = now.difference(alarm.lastSetTime!).inMinutes;

        actualDuration = actualDuration > 0 ? actualDuration : 1;

        await _dbHelper.updateAlarmDuration(alarm.id!, actualDuration);
        debugPrint(
          'Updated alarm ${alarm.id} with actual duration: $actualDuration minutes',
        );
      }

      final todayAlarms = await _dbHelper.getTodayAlarms();

      final alarmCount = todayAlarms.length;

      int totalDuration = 0;
      for (var alarmMap in todayAlarms) {
        final alarmModel = AlarmModel.fromMap(alarmMap);
        if (alarmModel.lastSetTime != null && alarmModel.lastStopTime != null) {
          int alarmDuration = alarmModel.calculateActualDuration();
          alarmDuration = alarmDuration > 0 ? alarmDuration : 1;
          totalDuration += alarmDuration;
          debugPrint(
            'Alarm ${alarmModel.id}: Actual Duration = $alarmDuration minutes',
          );
        } else {
          int configDuration =
              alarmModel.durationMinutes > 0 ? alarmModel.durationMinutes : 1;
          totalDuration += configDuration;
          debugPrint(
            'Alarm ${alarmModel.id}: Configured Duration = $configDuration minutes',
          );
        }
      }

      DateTime? earliestSetTime;
      DateTime? latestStopTime;

      for (var alarmMap in todayAlarms) {
        final alarmModel = AlarmModel.fromMap(alarmMap);

        if (alarmModel.lastSetTime != null) {
          if (earliestSetTime == null ||
              alarmModel.lastSetTime!.isBefore(earliestSetTime)) {
            earliestSetTime = alarmModel.lastSetTime;
          }
        }

        if (alarmModel.lastStopTime != null) {
          if (latestStopTime == null ||
              alarmModel.lastStopTime!.isAfter(latestStopTime)) {
            latestStopTime = alarmModel.lastStopTime;
          }
        }
      }

      earliestSetTime ??=
          alarm.lastSetTime ?? now.subtract(const Duration(minutes: 1));
      latestStopTime ??= now;

      final totalSleepHours = totalDuration / 60.0;

      debugPrint('Earliest set time: ${earliestSetTime.toIso8601String()}');
      debugPrint('Latest stop time: ${latestStopTime.toIso8601String()}');
      debugPrint('Total alarm duration: $totalDuration minutes');
      debugPrint('Calculated sleep duration: $totalSleepHours hours');
      debugPrint('Number of alarms: $alarmCount');

      await _dbHelper.insertSleepHistory(
        date: today,
        sleepTime: earliestSetTime,
        wakeTime: latestStopTime,
        totalHours: totalSleepHours,
        alarmCount: alarmCount,
        totalAlarmDuration: totalDuration,
      );

      if (Get.isRegistered<SleepStatisticsController>()) {
        await Get.find<SleepStatisticsController>().refreshSleepStatistics();
      }
    } catch (e) {
      debugPrint('Error recording alarm stop time: $e');
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
        final activeSoundId = prefs.getInt('flutter.active_alarm_sound') ?? 1;

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
}
