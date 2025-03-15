import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import '../../controllers/alarm/alarm_controller.dart';
import 'sound_manager.dart';

class AlarmBackgroundService {
  static final FlutterLocalNotificationsPlugin
      _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static bool _isInitializing = false;
  static bool _isInitialized = false;

  /// Initializes the background service in the main isolate
  static Future<void> initializeService() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;

    try {
      await _setupNotificationChannel();

      final service = FlutterBackgroundService();

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: 'alarm_foreground_service',
          initialNotificationTitle: 'Alarm Service',
          initialNotificationContent: 'Preparing alarm...',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );

      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing background service: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Sets up the notification channel for the service
  static Future<void> _setupNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'alarm_foreground_service',
      'Alarm Service Channel',
      description: 'Channel for Alarm Service',
      importance: Importance.high,
      playSound: false,
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Handles iOS background processing
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  /// Entry point for the background service
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    final audioPlayer = AudioPlayer();

    if (service is AndroidServiceInstance) {
      try {
        service.setAsForegroundService();
      } catch (e) {
        debugPrint('Error setting foreground service: $e');
      }
    }

    service.on('startAlarm').listen((event) async {
      if (event == null) return;

      final int alarmId = event['alarmId'] ?? -1;
      final int soundId = event['soundId'] ?? 1;

      try {
        final prefs = await SharedPreferences.getInstance();
        final volume = prefs.getDouble('alarm_volume') ??
            (prefs.getInt('alarm_volume')?.toDouble() ?? 0.5) / 100.0;

        await audioPlayer.setReleaseMode(ReleaseMode.loop);
        await audioPlayer.setVolume(volume);

        final soundPath = SoundManager.getSoundPath(soundId);
        await audioPlayer.play(AssetSource(soundPath));

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'Alarm Active',
            content: 'Tap to stop the alarm',
          );
        }
      } catch (e) {
        debugPrint('Error playing alarm in background: $e');
      }
    });

    service.on('stopAlarm').listen((event) async {
      try {
        await audioPlayer.stop();

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'Alarm Service',
            content: 'Alarm stopped',
          );
        }
      } catch (e) {
        debugPrint('Error stopping alarm: $e');
      }
    });

    service.on('stopService').listen((event) async {
      try {
        await audioPlayer.stop();
        await audioPlayer.dispose();
        service.stopSelf();
      } catch (e) {
        debugPrint('Error stopping service: $e');
      }
    });
  }

  /// Starts the alarm with specified ID and sound
  static Future<void> startAlarm(int alarmId, int soundId) async {
    try {
      final alarmController = Get.find<AlarmController>();
      final alarm = alarmController.getAlarmById(alarmId);

      if (alarm == null || !alarm.isEnabled) {
        debugPrint('Ignoring alarm start request for invalid alarm: $alarmId');
        return;
      }

      if (!_isInitialized) {
        await initializeService();
      }

      await _setupNotificationChannel();

      await Future.delayed(const Duration(milliseconds: 200));

      final service = FlutterBackgroundService();

      if (!await service.isRunning()) {
        await service.startService();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      service.invoke('startAlarm', {
        'alarmId': alarmId,
        'soundId': soundId,
      });

      alarmController.activeAlarmId.value = alarmId;

      debugPrint(
          'Background alarm service started for alarm: $alarmId with sound: $soundId');
    } catch (e) {
      debugPrint('Error starting alarm service: $e');
    }
  }

  /// Stops the currently active alarm
  static Future<void> stopAlarm() async {
    try {
      final service = FlutterBackgroundService();

      if (await service.isRunning()) {
        service.invoke('stopAlarm');
        await Future.delayed(const Duration(seconds: 1));
        service.invoke('stopService');
      }
    } catch (e) {
      debugPrint('Error stopping alarm service: $e');
    }
  }
}
