import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:get/get.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/database_helper.dart';
import '../../models/alarm/alarm_model.dart';
import '../../views/home/components/notification_service.dart';
import '../../views/home/components/sound_manager.dart';

class AlarmController extends GetxController {
  final DatabaseHelper _dbHelper;
  final FlutterLocalNotificationsPlugin _notificationPlugin;
  final Rx<AlarmModel?> currentActiveAlarm = Rx<AlarmModel?>(null);
  final AudioPlayer _audioPlayer;

  AlarmController({
    DatabaseHelper? dbHelper,
    FlutterLocalNotificationsPlugin? notificationPlugin,
    AudioPlayer? audioPlayer,
  }) :
        _dbHelper = dbHelper ?? DatabaseHelper(),
        _notificationPlugin = notificationPlugin ?? FlutterLocalNotificationsPlugin(),
        _audioPlayer = audioPlayer ?? AudioPlayer();

  // Observables
  final RxList<AlarmModel> alarms = <AlarmModel>[].obs;
  final RxBool isNfcAvailable = false.obs;
  final RxBool isAlarmActive = false.obs;
  final RxInt currentAlarmVolume = 50.obs;

  // Sleep Tracking
  final Rx<DateTime?> lastSleepTime = Rx<DateTime?>(null);
  final Rx<DateTime?> lastWakeTime = Rx<DateTime?>(null);

  // Analytics
  final RxDouble averageSleepDuration = 0.0.obs;
  final RxInt totalAlarmsTriggered = 0.obs;

  // Preferences
  late SharedPreferences _prefs;

  @override
  void onInit() {
    super.onInit();
    _initializeController();
  }

  Future<void> _initializeController() async {
    try {
      // Initialize time zones
      tz.initializeTimeZones();

      // Initialize shared preferences
      _prefs = await SharedPreferences.getInstance();

      // Check NFC availability
      await _checkNfcAvailability();

      // Initialize notifications
      await _setupNotifications();

      // Load saved alarms
      await _loadSavedAlarms();

      // Load sleep statistics
      await _calculateSleepStatistics();

      // Restore app settings
      _restoreAppSettings();
    } catch (e) {
      _handleControllerInitError(e);
    }
  }

  Future<void> _checkNfcAvailability() async {
    try {
      isNfcAvailable.value = await NfcManager.instance.isAvailable();
    } catch (e) {
      debugPrint('NFC Availability Check Failed: $e');
      isNfcAvailable.value = false;
    }
  }

  Future<void> _setupNotifications() async {
    const androidSettings = AndroidInitializationSettings('mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notificationPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );
  }

  void _handleNotificationTap(NotificationResponse response) {
    final alarmId = int.tryParse(response.payload ?? '');
    if (alarmId != null) {
      _triggerAlarmById(alarmId);
    }
  }

  Future<void> _loadSavedAlarms() async {
    try {
      final savedAlarms = await _dbHelper.getAllAlarms();
      alarms.assignAll(savedAlarms);
    } catch (e) {
      debugPrint('Failed to load alarms: $e');
    }
  }

  void _restoreAppSettings() {
    currentAlarmVolume.value = _prefs.getInt('alarm_volume') ?? 50;
  }

  Future<void> _calculateSleepStatistics() async {
    try {
      final sleepHistory = await _dbHelper.getSleepHistory();

      if (sleepHistory.isNotEmpty) {
        final totalDuration = sleepHistory.fold<double>(
            0,
                (sum, record) => sum + (record['total_hours'] as double)
        );

        averageSleepDuration.value = totalDuration / sleepHistory.length;
        totalAlarmsTriggered.value = sleepHistory.length;
      }
    } catch (e) {
      debugPrint('Sleep statistics calculation failed: $e');
    }
  }

  // Alarm Management Methods
  Future<void> createAlarm(AlarmModel alarm) async {
    try {
      final id = await _dbHelper.insertAlarm(alarm);
      alarm.id = id;
      alarms.add(alarm);

      print('Alarm Created: ID $id, Time: ${alarm.time}');

      // Schedule the notification for this alarm
      await NotificationService.scheduleAlarmNotification(
        id: alarm.id!,
        scheduledTime: alarm.time,
        soundId: alarm.soundId,
        title: 'Alarm',
        body: 'Scan NFC Tag to Stop Alarm',
      );

      print('Notification Scheduled for Alarm $id at ${alarm.time}');

      await _prefs.setInt('last_alarm_id', id);
    } catch (e) {
      print('Alarm creation failed: $e');
    }
  }

  Future<void> updateAlarm(AlarmModel alarm) async {
    try {
      await _dbHelper.updateAlarm(alarm);
      final index = alarms.indexWhere((a) => a.id == alarm.id);
      if (index != -1) {
        alarms[index] = alarm;

        // Cancel previous notification and schedule a new one
        await NotificationService.cancelNotification(alarm.id!);
        await NotificationService.scheduleAlarmNotification(
            id: alarm.id!,
            scheduledTime: alarm.time,
            soundId: alarm.soundId,
            title: 'Alarm',
            body: 'Wake up time!'
        );
      }
    } catch (e) {
      debugPrint('Alarm update failed: $e');
    }
  }


  Future<void> deleteAlarm(AlarmModel alarm) async {
    try {
      await _dbHelper.deleteAlarm(alarm.id!);
      alarms.remove(alarm);

      // Cancel the notification for this alarm
      await NotificationService.cancelNotification(alarm.id!);
    } catch (e) {
      debugPrint('Alarm deletion failed: $e');
    }
  }

  Future<void> cancelAllAlarms() async {
    try {
      // Delete all alarms from database
      for (var alarm in alarms) {
        await _dbHelper.deleteAlarm(alarm.id!);
      }

      // Clear the alarms list
      alarms.clear();

      // Cancel all notifications
      await NotificationService.cancelAllNotifications();
    } catch (e) {
      debugPrint('Failed to cancel all alarms: $e');
    }
  }


  // Alarm Triggering
  void _triggerAlarmById(int alarmId) {
    final alarm = alarms.firstWhereOrNull((a) => a.id == alarmId);
    if (alarm != null) {
      _processAlarmTrigger(alarm);
    }
  }

  Future<void> _processAlarmTrigger(AlarmModel alarm) async {
    isAlarmActive.value = true;

    try {
      // Play alarm sound
      await playAlarmSound(alarm.soundId);

      // NFC verification if required
      if (alarm.nfcRequired && isNfcAvailable.value) {
        final nfcVerified = await _verifyNfcToStopAlarm();
        if (!nfcVerified) return;
      }

      // Stop alarm and record sleep data
      await _stopAlarmSound();
      await _recordSleepSession(alarm);
    } catch (e) {
      debugPrint('Alarm trigger process failed: $e');
    } finally {
      isAlarmActive.value = false;
    }
  }

  Future<void> playAlarmSound(int soundId, {bool isPreview = false}) async {
    try {
      // First, stop any currently playing sounds to prevent overlap
      await _stopAlarmSound();

      final soundPath = SoundManager.getSoundPath(soundId);

      // Set release mode based on whether this is a preview or actual alarm
      await _audioPlayer.setReleaseMode(
          isPreview ? ReleaseMode.release : ReleaseMode.loop
      );

      // Set volume (possibly lower for previews)
      final volume = isPreview ?
      (currentAlarmVolume.value / 100) * 0.5 : // Half volume for previews
      currentAlarmVolume.value / 100;

      await _audioPlayer.setVolume(volume);

      // Play the sound
      await _audioPlayer.play(AssetSource(soundPath));

      // Auto-stop for previews with a proper cancellable timer
      if (isPreview) {
        // Create a properly scoped timer for preview sounds
        Timer(const Duration(seconds: 3), () {
          // Check if we're still in preview mode before stopping
          if (isPreview) {
            _audioPlayer.stop();
          }
        });
      }
    } catch (e) {
      debugPrint('Sound playback error: $e');
      // Make sure to stop the player on error
      await _audioPlayer.stop();
    }
  }


  void cancelPreview() {
    _stopAlarmSound();
  }

  Future<void> _stopAlarmSound() async {
    await _audioPlayer.stop();
  }

  Future<bool> _verifyNfcToStopAlarm() async {
    // Ensure a boolean is always returned
    try {
      // Check NFC availability first
      bool isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) {
        return false;
      }

      // Use a completer with a timeout to handle NFC verification
      return await Future.any([
        _performNfcVerification(),
        Future.delayed(const Duration(seconds: 30), () => false)
      ]);
    } catch (e) {
      // Log the error and return false in case of any unexpected issues
      debugPrint('NFC Verification Error: $e');
      return false;
    }
  }

  void stopAlarmSound() {
    // Stop any playing audio
    _audioPlayer.stop();
  }

  Future<bool> _performNfcVerification() async {
    final Completer<bool> completer = Completer<bool>();

    try {
      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            // Validate the NFC tag.
            final bool isValidTag = _validateNfcTag(tag);

            if (!completer.isCompleted) {
              await NfcManager.instance.stopSession();
              completer.complete(isValidTag);
            }
          } catch (e) {
            if (!completer.isCompleted) {
              await NfcManager.instance.stopSession(errorMessage: e.toString());
              completer.complete(false);
            }
          }
        },
        onError: (error) async {
          if (!completer.isCompleted) {
            await NfcManager.instance.stopSession(errorMessage: error.toString());
            completer.complete(false);
          }
          return;
        },
      );
    } catch (e) {
      if (!completer.isCompleted) {
        NfcManager.instance.stopSession(errorMessage: "Unexpected error occurred.");
        completer.complete(false);
      }
    }

    return completer.future;
  }


  bool _validateNfcTag(NfcTag tag) {
    // Multiple validation strategies
    return _checkTagType(tag) &&
        _validateTagIdentifier(tag) &&
        _performCustomTagCheck(tag);
  }

  bool _checkTagType(NfcTag tag) {
    // Validate NFC tag type
    final techList = tag.data['nfcA']?['identifier'];
    return techList != null && techList is List && techList.isNotEmpty;
  }

  bool _validateTagIdentifier(NfcTag tag) {
    // Extract and validate tag identifier
    final identifier = tag.data['nfcA']?['identifier'];

    if (identifier == null) return false;
    final identifierBytes = identifier as List<int>;

    final allowedIdentifiers = [
      [0x04, 0x12, 0x34, 0x56],
      [0x07, 0x89, 0xAB, 0xCD]
    ];

    return allowedIdentifiers.any((allowed) =>
        _bytesMatch(identifierBytes, allowed)
    );
  }

  bool _bytesMatch(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;

    for (int i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) return false;
    }

    return true;
  }

  bool _performCustomTagCheck(NfcTag tag) {

    try {
      final nfcAData = tag.data['nfcA'];
      final nfcBData = tag.data['nfcB'];

      return (nfcAData != null || nfcBData != null) &&
          _checkAdditionalTagMetadata(tag);
    } catch (e) {
      debugPrint('Custom tag check failed: $e');
      return false;
    }
  }

  bool _checkAdditionalTagMetadata(NfcTag tag) {
    final manufacturerData = tag.data['manufacturer'];
    return manufacturerData != null;
  }

  Future<void> _recordSleepSession(AlarmModel alarm) async {
    if (lastSleepTime.value != null) {
      final wakeTime = DateTime.now();
      final sleepDuration = wakeTime.difference(lastSleepTime.value!);

      await _dbHelper.insertSleepHistory(
        date: wakeTime,
        sleepTime: lastSleepTime.value!,
        wakeTime: wakeTime,
      );

      lastWakeTime.value = wakeTime;
      await _calculateSleepStatistics();
    }
  }

  // Error Handling
  void _handleControllerInitError(dynamic error) {
    debugPrint('Controller Initialization Error: $error');
  }

  // Utility Methods
  void setAlarmVolume(int volume) {
    currentAlarmVolume.value = volume.clamp(0, 100);
    _prefs.setInt('alarm_volume', volume);
  }

  List<AlarmModel> getActiveAlarms() {
    return alarms.where((alarm) => alarm.isEnabled).toList();
  }

  Future<List<Map<String, dynamic>>> getSleepHistory() async {
    return await _dbHelper.getSleepHistory();
  }

  @override
  void onClose() {
    _audioPlayer.dispose();
    super.onClose();
  }
}



