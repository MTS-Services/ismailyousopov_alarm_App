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
import '../nfc/nfc_controller.dart';
import '../stats/stats_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
      verifyAlarmStates();
    });
    
    // Listen for ringing alarms from the Alarm package
    Alarm.ringing.listen((AlarmSet alarmSet) {
      for (final alarm in alarmSet.alarms) {
        debugPrint('Alarm ringing from Alarm package: ${alarm.id}');
        _handleAlarmPackageRinging(alarm.id);
      }
    });
  }

  /// Handle alarm ringing from the Alarm package
  Future<void> _handleAlarmPackageRinging(int packageAlarmId) async {
    try {
      // Find the corresponding alarm in our system
      final alarm = getAlarmById(packageAlarmId);
      if (alarm != null) {
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
  
  /// Convert our AlarmModel to Alarm package's AlarmSettings
  AlarmSettings _convertToAlarmSettings(AlarmModel alarm) {
    // Get the proper sound path for the alarm
    final soundPath = 'assets/${SoundManager.getSoundPath(alarm.soundId)}';
    
    return AlarmSettings(
      id: alarm.id ?? DateTime.now().millisecondsSinceEpoch,
      dateTime: alarm.getNextAlarmTime(),
      assetAudioPath: soundPath,
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: Platform.isIOS,
      androidFullScreenIntent: true,
      volumeSettings: VolumeSettings.fade(
        volume: currentAlarmVolume.value / 100,
        fadeDuration: const Duration(seconds: 30),
        volumeEnforced: true,
      ),
      notificationSettings: NotificationSettings(
        title: 'Alarm',
        body: alarm.nfcRequired ? 'Scan NFC Tag to Stop Alarm' : 'Tap to Stop Alarm',
        // stopButton: 'Stop',
      ),
      payload: alarm.nfcRequired ? 'nfc_required:true' : 'nfc_required:false'
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
        // Convert and set with the Alarm package
        final alarmSettings = _convertToAlarmSettings(alarm);
        await Alarm.set(alarmSettings: alarmSettings);
      }

      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;
      await _prefs.setInt('last_alarm_id', id);

      debugPrint(
          'Created new alarm with ID: $id, time: ${alarm.time}, next trigger: ${alarm.getNextAlarmTime()}');
      update();
    } catch (e) {
      debugPrint('Alarm creation failed: $e');
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
      
      // Cancel the old alarm
      await Alarm.stop(alarm.id!);

      if (alarm.isEnabled) {
        // Set the updated alarm with the Alarm package
        final alarmSettings = _convertToAlarmSettings(alarm);
        await Alarm.set(alarmSettings: alarmSettings);
      }

      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;
      update();
    } catch (e) {
      debugPrint('Error updating alarm: $e');
    }
  }

  /// Deletes an alarm and cancels it
  Future<void> deleteAlarm(int id) async {
    try {
      await Alarm.stop(id);
      await _dbHelper.deleteAlarm(id);
      await loadAlarms();
      refreshTimestamp.value = DateTime.now().millisecondsSinceEpoch;
      update();
    } catch (e) {
      debugPrint('Error deleting alarm: $e');
    }
  }

  /// Disables an alarm without deleting it from the database
  Future<void> cancelAlarm(AlarmModel alarm) async {
    if (alarm.id == null) return;

    try {
      alarm.isEnabled = false;
      await _dbHelper.updateAlarm(alarm);
      await Alarm.stop(alarm.id!);
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
      await prefs.setInt('snooze_count', (prefs.getInt('snooze_count') ?? 0) + 1);

      // Schedule the snooze alarm
      await createAlarm(snoozeAlarm);

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
            final lastActivated = prefs.getInt('alarm_last_activated_${alarm.id}') ?? 0;
            final timeSinceActivation = now.millisecondsSinceEpoch - lastActivated;

            // Only trigger if it hasn't been activated in the last 30 seconds
            if (timeSinceActivation > 30000) {
              debugPrint('Found alarm ${alarm.id} that should be ringing but isn\'t active');

              // Start the alarm
              await playAlarmSound(alarm.soundId, alarmId: alarm.id);

              // Only show notification if the sound playback was successful (not deduplicated)
              if (activeAlarmId.value == alarm.id) {
                await NotificationService.showFallbackAlarmNotification(alarm.id!, alarm.soundId);
              }
            } else {
              debugPrint('Alarm ${alarm.id} was recently activated, skipping duplicate trigger');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error verifying alarm states: $e');
    }
  }

  /// Load saved volume from shared preferences
  Future<void> _loadSavedVolume() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final savedVolume = _prefs.getInt('alarm_volume');
      if (savedVolume != null) {
        currentAlarmVolume.value = savedVolume;
      }
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

  /// Initializes required services and dependencies
  Future<void> _initializeController() async {
    try {
      tz.initializeTimeZones();
      _prefs = await SharedPreferences.getInstance();
      await NotificationService.initialize();
      await _preloadSounds();
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
  Future<void> playAlarmSound(int soundId, {bool isPreview = false, int? alarmId}) async {
    try {
      // For actual alarms (not previews), check for duplicates
      if (!isPreview && alarmId != null) {
        // Use the NotificationService's deduplication logic
        if (!(await NotificationService.markAlarmAsActivated(alarmId))) {
          debugPrint('Skipping duplicate alarm sound playback for ID: $alarmId');
          return; // Skip duplicate activation
        }
      }

      await _audioPlayer.stop();
      final soundPath = SoundManager.getSoundPath(soundId);
      debugPrint('Playing sound: $soundPath (Preview: $isPreview)');
      await _audioPlayer.setReleaseMode(isPreview ? ReleaseMode.release : ReleaseMode.loop);

      final volume = isPreview
          ? (currentAlarmVolume.value / 100) * 0.5
          : (currentAlarmVolume.value / 100);

      await _audioPlayer.setVolume(volume);
      await _audioPlayer.setSourceAsset(soundPath);
      await _audioPlayer.resume();

      if (isPreview) {
        Timer(const Duration(seconds: 3), () {
          _audioPlayer.stop();
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
          WakelockPlus.disable().catchError((e) => debugPrint('Error disabling wakelock: $e'));
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
      await _prefs.setInt('alarm_volume', currentAlarmVolume.value);
      if (_audioPlayer.state == PlayerState.playing) {
        await _audioPlayer.setVolume(currentAlarmVolume.value / 100);
      }
    } catch (e) {
      debugPrint('Error updating volume: $e');
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
  Future<bool> dismissAlarm(int alarmId, {String? backupCode, bool nfcVerified = false}) async {
    try {
      final alarm = getAlarmById(alarmId);
      if (alarm == null) {
        debugPrint('Cannot dismiss alarm: Alarm with ID $alarmId not found');
        return false;
      }

      bool isVerified = false;

      // Only verify with backup code "12345"
      if (backupCode != null && backupCode == "12345") {
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
          today, today.add(const Duration(days: 1)));

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
            'Updated alarm ${alarm.id} with actual duration: $actualDuration minutes');
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
              'Alarm ${alarmModel.id}: Actual Duration = $alarmDuration minutes');
        } else {
          int configDuration =
              alarmModel.durationMinutes > 0 ? alarmModel.durationMinutes : 1;
          totalDuration += configDuration;
          debugPrint(
              'Alarm ${alarmModel.id}: Configured Duration = $configDuration minutes');
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



