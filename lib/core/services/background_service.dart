import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import '../../controllers/alarm/alarm_controller.dart';
import 'notification_service.dart';
import 'sound_manager.dart';
import 'dart:typed_data';

@pragma('vm:entry-point')
class AlarmBackgroundService {
  static final FlutterLocalNotificationsPlugin
      _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static bool _isInitializing = false;
  static bool _isInitialized = false;
  static int? _activeAlarmId;
  static AudioPlayer? _fallbackPlayer;
  static Timer? _serviceCleanupTimer;
  static Timer? _serviceHealthCheckTimer;
  static const String stopActionId = 'stop_alarm_action';
  static const MethodChannel _platform =
      MethodChannel('com.example.alarm/background_channel');
  static const MethodChannel _wakeLockChannel =
      MethodChannel('com.your.package/wake_lock');
  static const MethodChannel _alarmManagerChannel =
      MethodChannel('com.your.package/alarm_manager');

  /// Initializes the background service in the main isolate with improved reliability
  static Future<bool> initializeService() async {
    try {
      if (_isInitializing) {
        debugPrint('Service initialization already in progress, waiting...');
        int attempts = 0;
        while (_isInitializing && attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 200));
          attempts++;
        }
        return _isInitialized;
      }

      _isInitializing = true;
      await _setupNotificationChannel();

      final service = FlutterBackgroundService();

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: 'alarm_foreground_service',
          initialNotificationTitle: 'Alarm',
          initialNotificationContent: '',
          foregroundServiceNotificationId: 888,
          autoStartOnBoot: false,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );

      _isInitialized = true;
      _isInitializing = false;

      debugPrint('Background service configured successfully');
      return true;
    } catch (e) {
      debugPrint('Error initializing background service: $e');
      _isInitialized = false;
      _isInitializing = false;
      return false;
    }
  }

  /// Sets up the notification channel for the service with improved visibility
  static Future<void> _setupNotificationChannel() async {
    try {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'alarm_foreground_service',
        'Alarm Service Channel',
        description: 'Channel for Alarm Service',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
        enableLights: true,
        ledColor: Color.fromARGB(255, 255, 0, 0),
        showBadge: true,
      );

      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      debugPrint('Notification channel created successfully');
    } catch (e) {
      debugPrint('Error creating notification channel: $e');
    }
  }

  /// Handles iOS background processing
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  /// Entry point for the background service with improved reliability
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    final audioPlayer = AudioPlayer();
    bool isAlarmActive = false;
    int? activeAlarmId;
    int? activeSoundId;

    if (service is AndroidServiceInstance) {
      try {
        service.setAsForegroundService();
        service.setAutoStartOnBootMode(false);
        // Don't show notification until an alarm is actually running
        debugPrint('Background service started and ready');
      } catch (e) {
        debugPrint('Error setting foreground service: $e');
      }
    }

    // Check more frequently for inactive alarms to stop the service sooner
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!isAlarmActive) {
        debugPrint('No active alarm, stopping service');
        service.stopSelf();
        timer.cancel();
      }
    });

    Timer? soundCheckTimer;

    service.on('startAlarm').listen((event) async {
      if (event == null) return;

      final int alarmId = event['alarmId'] ?? -1;
      final int soundId = event['soundId'] ?? 1;
      final bool forceStart = event['forceStart'] ?? false;

      debugPrint(
          'Received startAlarm command: ID=$alarmId, Sound=$soundId, Force=$forceStart');

      activeAlarmId = alarmId;
      activeSoundId = soundId;

      try {
        isAlarmActive = true;
        final prefs = await SharedPreferences.getInstance();

        // Load the saved alarm volume - prioritize the specific alarm volume setting
        double volume = 0.8; // Default fallback

        // Try to get the volume from different sources in order of preference
        final savedVolumeInt = prefs.getInt('alarm_volume');
        final savedVolumeDouble = prefs.getDouble('alarm_volume');
        final flutterVolumeInt = prefs.getInt('flutter.alarm_volume');

        if (savedVolumeInt != null) {
          volume = savedVolumeInt / 100.0; // Convert percentage to decimal
          debugPrint('Using saved volume (int): $savedVolumeInt% -> $volume');
        } else if (flutterVolumeInt != null) {
          volume = flutterVolumeInt / 100.0; // Convert percentage to decimal
          debugPrint(
              'Using flutter volume (int): $flutterVolumeInt% -> $volume');
        } else if (savedVolumeDouble != null) {
          volume = savedVolumeDouble;
          debugPrint('Using saved volume (double): $volume');
        } else {
          debugPrint('No saved volume found, using default: $volume');
        }

        // Ensure volume is within valid range
        volume = volume.clamp(0.1, 1.0); // Minimum 10% to ensure audibility
        debugPrint('Final alarm volume set to: $volume');

        await audioPlayer.stop();
        await audioPlayer.setReleaseMode(ReleaseMode.loop);
        await audioPlayer.setVolume(volume);

        if (Platform.isAndroid) {
          try {
            debugPrint('Starting native foreground service');
            await _platform.invokeMethod('startForegroundService', {
              'alarmId': alarmId,
              'soundId': soundId,
            });

            service
                .invoke('alarmStarted', {'alarmId': alarmId, 'success': true});
            return;
          } catch (e) {
            debugPrint('Error starting native foreground service: $e');
          }
        }

        final soundPath = SoundManager.getSoundPath(soundId);
        await audioPlayer.play(AssetSource(soundPath));
        debugPrint('Started playing sound: $soundPath');

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'Alarm Active',
            content: 'Tap to stop the alarm',
          );
        }

        soundCheckTimer?.cancel();
        soundCheckTimer =
            Timer.periodic(const Duration(seconds: 5), (timer) async {
          try {
            final isPlaying =
                await audioPlayer.getCurrentPosition() != Duration.zero;
            if (!isPlaying && isAlarmActive) {
              debugPrint('Restarting alarm sound that stopped unexpectedly');
              final soundPath = SoundManager.getSoundPath(soundId);
              await audioPlayer.play(AssetSource(soundPath));
            }
          } catch (e) {
            debugPrint('Error checking audio playback: $e');
            try {
              final soundPath = SoundManager.getSoundPath(soundId);
              await audioPlayer.play(AssetSource(soundPath));
            } catch (_) {}
          }
        });

        service.invoke('alarmStarted', {'alarmId': alarmId, 'success': true});
      } catch (e) {
        debugPrint('Error playing alarm in background: $e');
        service.invoke('alarmStarted', {'alarmId': alarmId, 'success': false});
      }
    });

    service.on('stopAlarm').listen((event) async {
      try {
        debugPrint('Received stopAlarm command');
        isAlarmActive = false;
        soundCheckTimer?.cancel();

        await audioPlayer.stop();
        if (Platform.isAndroid) {
          try {
            await _platform.invokeMethod('forceStopService');
          } catch (e) {
            debugPrint('Error stopping native service: $e');
          }
        }

        if (service is AndroidServiceInstance) {
          // Don't show the stopping notification, just log it
          debugPrint('Stopping alarm service');
        }

        Timer(const Duration(seconds: 2), () {
          if (!isAlarmActive) {
            service.stopSelf();
          }
        });

        service.invoke('alarmStopped', {'success': true});
      } catch (e) {
        debugPrint('Error stopping alarm: $e');
        service.invoke('alarmStopped', {'success': false});
      }
    });

    service.on('updateVolume').listen((event) async {
      if (event != null && event['volume'] != null) {
        try {
          final volume = (event['volume'] as int) / 100.0;
          await audioPlayer.setVolume(volume);
          debugPrint('Updated volume to: $volume');
        } catch (e) {
          debugPrint('Error updating volume: $e');
        }
      }
    });

    service.on('checkAlarmActive').listen((event) {
      service.invoke('alarmStatus', {
        'isActive': isAlarmActive,
        'alarmId': activeAlarmId,
        'soundId': activeSoundId
      });
    });

    service.on('stopService').listen((event) async {
      try {
        debugPrint('Received stopService command');
        isAlarmActive = false;
        soundCheckTimer?.cancel();
        await audioPlayer.stop();
        await audioPlayer.dispose();
        service.stopSelf();
      } catch (e) {
        debugPrint('Error stopping service: $e');
      }
    });
  }

  /// Starts the alarm with specified ID and sound
  static Future<bool> startAlarm(int alarmId, int soundId) async {
    try {
      if (!(await NotificationService.markAlarmAsActivated(alarmId))) {
        debugPrint('Skipping duplicate alarm activation for ID: $alarmId');
        return true;
      }

      if (await isNativeNotificationActive(alarmId)) {
        debugPrint('Native notification already active for alarm ID: $alarmId');
        _activeAlarmId = alarmId;
        if (Get.isRegistered<AlarmController>()) {
          final alarmController = Get.find<AlarmController>();
          alarmController.activeAlarmId.value = alarmId;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('flutter.active_alarm_id', alarmId);
        await prefs.setInt('flutter.active_alarm_sound', soundId);
        await prefs.setInt(
            'flutter.alarm_start_time', DateTime.now().millisecondsSinceEpoch);
        await prefs.setBool('flutter.using_native_notification', true);
        await prefs.setString('flutter.notification_handler', 'native');

        await acquirePersistentWakeLock();

        startServiceHealthCheck();

        return true;
      }

      if (Platform.isAndroid) {
        try {
          final bool success =
              await _platform.invokeMethod('startForegroundService', {
            'alarmId': alarmId,
            'soundId': soundId,
          });

          if (success) {
            _activeAlarmId = alarmId;
            if (Get.isRegistered<AlarmController>()) {
              final alarmController = Get.find<AlarmController>();
              alarmController.activeAlarmId.value = alarmId;
            }

            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('flutter.using_native_notification', true);
            await prefs.setString('flutter.notification_handler', 'native');

            await acquirePersistentWakeLock();

            startServiceHealthCheck();

            return true;
          }
        } catch (e) {
          debugPrint('Error starting native foreground service: $e');
        }
      }

      if (Platform.isAndroid) {
        try {
          await acquirePersistentWakeLock();
        } catch (e) {
          debugPrint('Error acquiring wake lock: $e');
        }
      }

      _serviceCleanupTimer?.cancel();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('flutter.active_alarm_id', alarmId);
      await prefs.setInt('flutter.active_alarm_sound', soundId);
      await prefs.setInt(
          'flutter.alarm_start_time', DateTime.now().millisecondsSinceEpoch);
      await prefs.setBool('flutter.using_native_notification', false);
      await prefs.setString('flutter.notification_handler', 'flutter');

      final alarmController = Get.isRegistered<AlarmController>()
          ? Get.find<AlarmController>()
          : Get.put(AlarmController());

      final alarm = alarmController.getAlarmById(alarmId);

      if (alarm == null || !alarm.isEnabled) {
        debugPrint('Ignoring alarm start request for invalid alarm: $alarmId');
        return false;
      }

      final service = FlutterBackgroundService();

      await forceStopService();

      await Future.delayed(const Duration(milliseconds: 500));
      if (!_isInitialized) {
        final initialized = await initializeService();
        if (!initialized) {
          debugPrint('Failed to initialize service, using fallback');
          await _startFallbackAlarm(alarmId, soundId);
          return false;
        }
      }

      await service.startService();

      await Future.delayed(const Duration(milliseconds: 1000));

      if (!(await service.isRunning())) {
        debugPrint('Background service failed to start, using fallback');
        await _startFallbackAlarm(alarmId, soundId);
        return false;
      }

      final completer = Completer<bool>();
      Timer? responseTimer;

      StreamSubscription? subscription;
      subscription = service.on('alarmStarted').listen((event) {
        if (event != null && event['alarmId'] == alarmId) {
          final success = event['success'] == true;
          responseTimer?.cancel();
          subscription?.cancel();

          if (!completer.isCompleted) {
            completer.complete(success);
          }

          if (!success) {
            _startFallbackAlarm(alarmId, soundId);
          }
        }
      });

      responseTimer = Timer(const Duration(seconds: 3), () {
        subscription?.cancel();
        if (!completer.isCompleted) {
          debugPrint('No response from service after timeout, using fallback');
          completer.complete(false);
          _startFallbackAlarm(alarmId, soundId);
        }
      });

      service.invoke('startAlarm', {
        'alarmId': alarmId,
        'soundId': soundId,
        'forceStart': true,
      });

      _activeAlarmId = alarmId;
      alarmController.activeAlarmId.value = alarmId;

      startServiceHealthCheck();

      if (Platform.isAndroid) {
        await ensureAlarmNotificationVisible(alarmId, soundId);
      }

      final success = await completer.future;
      if (success) {
        debugPrint(
            'Background alarm service started successfully for alarm: $alarmId');
      }
      return success;
    } catch (e) {
      debugPrint('Error starting alarm service: $e');
      await _startFallbackAlarm(alarmId, soundId);
      return false;
    }
  }

  /// fallback alarm implementation

  static Future<bool> _startFallbackAlarm(int alarmId, int soundId) async {
    try {
      debugPrint('Using fallback alarm notification for alarm: $alarmId');

      if (await isNativeNotificationActive(alarmId)) {
        debugPrint(
            'Native notification active, skipping fallback notification');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('flutter.using_native_notification', true);
        await prefs.setString('flutter.notification_handler', 'native');

        _activeAlarmId = alarmId;
        if (Get.isRegistered<AlarmController>()) {
          final alarmController = Get.find<AlarmController>();
          alarmController.activeAlarmId.value = alarmId;
        }
        return true;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flutter.using_fallback_alarm', true);
      await prefs.setBool('flutter.using_native_notification', false);
      await prefs.setString('flutter.notification_handler', 'flutter');
      await prefs.setInt('flutter.active_alarm_id', alarmId);
      await prefs.setInt('flutter.active_alarm_sound', soundId);
      await prefs.setInt(
          'flutter.alarm_start_time', DateTime.now().millisecondsSinceEpoch);

      if (Platform.isAndroid) {
        try {
          debugPrint('Attempting to start native fallback service');
          final bool success =
              await _platform.invokeMethod('startForegroundService', {
            'alarmId': alarmId,
            'soundId': soundId,
          });

          if (success) {
            debugPrint('Native fallback service started successfully');
            _activeAlarmId = alarmId;
            if (Get.isRegistered<AlarmController>()) {
              final alarmController = Get.find<AlarmController>();
              alarmController.activeAlarmId.value = alarmId;
            }

            await prefs.setBool('flutter.using_native_notification', true);
            await prefs.setString('flutter.notification_handler', 'native');

            return true;
          }
        } catch (e) {
          debugPrint('Error starting native fallback service: $e');
        }
      }

      await NotificationService.showFallbackAlarmNotification(alarmId, soundId);

      _activeAlarmId = alarmId;
      if (Get.isRegistered<AlarmController>()) {
        final alarmController = Get.find<AlarmController>();
        alarmController.activeAlarmId.value = alarmId;
      }

      try {
        if (_fallbackPlayer != null) {
          await _fallbackPlayer!.stop();
          await _fallbackPlayer!.dispose();
          _fallbackPlayer = null;
        }

        final player = AudioPlayer();

        // Load the saved alarm volume with proper fallback
        double volume = 0.8; // Default fallback

        // Try to get the volume from different sources in order of preference
        final savedVolumeInt = prefs.getInt('alarm_volume');
        final savedVolumeDouble = prefs.getDouble('alarm_volume');
        final flutterVolumeInt = prefs.getInt('flutter.alarm_volume');

        if (savedVolumeInt != null) {
          volume = savedVolumeInt / 100.0; // Convert percentage to decimal
          debugPrint(
              'Fallback using saved volume (int): $savedVolumeInt% -> $volume');
        } else if (flutterVolumeInt != null) {
          volume = flutterVolumeInt / 100.0; // Convert percentage to decimal
          debugPrint(
              'Fallback using flutter volume (int): $flutterVolumeInt% -> $volume');
        } else if (savedVolumeDouble != null) {
          volume = savedVolumeDouble;
          debugPrint('Fallback using saved volume (double): $volume');
        } else {
          debugPrint('Fallback: No saved volume found, using default: $volume');
        }

        // Ensure volume is within valid range
        volume = volume.clamp(0.1, 1.0); // Minimum 10% to ensure audibility
        debugPrint('Final fallback alarm volume set to: $volume');

        await player.setReleaseMode(ReleaseMode.loop);
        await player.setVolume(volume);

        final soundPath = SoundManager.getSoundPath(soundId);
        debugPrint('Playing fallback sound: $soundPath');
        await player.play(AssetSource(soundPath));

        _fallbackPlayer = player;

        Timer.periodic(const Duration(seconds: 5), (timer) async {
          if (_fallbackPlayer == null) {
            timer.cancel();
            return;
          }

          try {
            final isPlaying = _fallbackPlayer!.state == PlayerState.playing;
            if (!isPlaying) {
              debugPrint('Fallback sound stopped, restarting');
              await _fallbackPlayer!.play(AssetSource(soundPath));
            }
          } catch (e) {
            debugPrint('Error checking fallback player: $e');
            try {
              await _fallbackPlayer!.play(AssetSource(soundPath));
            } catch (_) {}
          }
        });
      } catch (e) {
        debugPrint('Error starting fallback audio: $e');
      }

      return true;
    } catch (e) {
      debugPrint('Error starting fallback alarm: $e');
      return false;
    }
  }

  /// Stop the alarm service and clean up resources
  static Future<void> stopAlarm() async {
    try {
      debugPrint('Stopping alarm service and all resources');

      if (Platform.isAndroid) {
        try {
          // FIRST: Stop the native alarm receiver which handles vibration
          await _platform.invokeMethod('stopAlarmReceiver');
          debugPrint('Stopped native alarm receiver');

          // SECOND: Stop vibration explicitly
          await _platform.invokeMethod('stopVibration');
          debugPrint('Stopped vibration via method channel');

          // THIRD: Stop the alarm service
          await _platform.invokeMethod('stopAlarmService');
          debugPrint('Stopped native alarm service');
        } catch (e) {
          debugPrint('Error calling native stop methods: $e');
        }
      }

      // Stop the background service
      try {
        final service = FlutterBackgroundService();
        service.invoke('stopAlarm');
        service.invoke('stopService');
        debugPrint('Background service stopped');
      } catch (e) {
        debugPrint('Error stopping background service: $e');
      }

      // Clear the service health check timer
      _serviceHealthCheckTimer?.cancel();
      _serviceHealthCheckTimer = null;

      // Stop any fallback audio
      try {
        await _fallbackPlayer?.stop();
        _fallbackPlayer = null;
        debugPrint('Stopped fallback audio player');
      } catch (e) {
        debugPrint('Error stopping fallback player: $e');
      }

      // Clear active alarm data
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('flutter.active_alarm_id');
        await prefs.remove('flutter.active_alarm_sound');
        await prefs.remove('flutter.alarm_start_time');
        await prefs.remove('flutter.using_fallback_alarm');
        await prefs.remove('flutter.direct_to_stop');
        debugPrint('Cleared active alarm data from SharedPreferences');
      } catch (e) {
        debugPrint('Error clearing SharedPreferences: $e');
      }

      // Additional safety delay and another vibration stop attempt
      await Future.delayed(const Duration(milliseconds: 500));
      if (Platform.isAndroid) {
        try {
          await _platform.invokeMethod('stopVibration');
          debugPrint('Final vibration stop attempt completed');
        } catch (e) {
          debugPrint('Error in final vibration stop: $e');
        }
      }

      debugPrint('Alarm stop sequence completed');
    } catch (e) {
      debugPrint('Error stopping alarm service: $e');
      // Even if there's an error, try emergency stop
      await emergencyStopAllAlarms();
    }
  }

  /// Acquires a persistent wake lock
  static Future<void> acquirePersistentWakeLock() async {
    if (Platform.isAndroid) {
      try {
        await _wakeLockChannel.invokeMethod('acquirePersistentWakeLock');
        debugPrint('Acquired persistent wake lock via native channel');
      } catch (e) {
        debugPrint('Error acquiring wake lock via channel: $e');
        try {
          await WakelockPlus.enable();
          debugPrint('Acquired wake lock via WakelockPlus');
        } catch (e) {
          debugPrint('Error acquiring wake lock: $e');
        }
      }
    }
  }

  /// Releases the wake lock
  static Future<void> releaseWakeLock() async {
    if (Platform.isAndroid) {
      try {
        await _wakeLockChannel.invokeMethod('releaseWakeLock');
        debugPrint('Released wake lock via native channel');
      } catch (e) {
        debugPrint('Error releasing wake lock via channel: $e');
        try {
          await WakelockPlus.disable();
          debugPrint('Released wake lock via WakelockPlus');
        } catch (e) {
          debugPrint('Error releasing wake lock: $e');
        }
      }
    }
  }

  /// Schedule an exact alarm using Android's AlarmManager
  static Future<bool> scheduleExactAlarm(int alarmId, DateTime scheduledTime,
      int soundId, bool nfcRequired) async {
    if (Platform.isAndroid) {
      try {
        debugPrint(
            'Scheduling exact alarm: ID=$alarmId, Time=${scheduledTime.toIso8601String()}, Sound=$soundId');

        await storeScheduledAlarm(alarmId, soundId,
            scheduledTime.millisecondsSinceEpoch, nfcRequired);

        final bool success =
            await _alarmManagerChannel.invokeMethod('scheduleExactAlarm', {
          'alarmId': alarmId,
          'triggerAtMillis': scheduledTime.millisecondsSinceEpoch,
          'soundId': soundId,
          'nfcRequired': nfcRequired,
        });

        if (success) {
          debugPrint('Exact alarm scheduled successfully via native channel');
          return true;
        } else {
          debugPrint(
              'Failed to schedule exact alarm via native channel, falling back to Android Alarm Manager Plus');
        }
      } catch (e) {
        debugPrint('Error scheduling exact alarm via channel: $e');
      }

      // RE-ENABLED: AndroidAlarmManager as backup for when app is closed
      // This ensures alarms work even when the app is completely closed
      try {
        final success = await AndroidAlarmManager.oneShotAt(
          scheduledTime,
          alarmId,
          handleAlarmCallback,
          exact: true,
          wakeup: true,
          rescheduleOnReboot: true,
          alarmClock: true,
          allowWhileIdle: true,
          params: {
            'alarmId': alarmId,
            'soundId': soundId,
            'nfcRequired': nfcRequired,
          },
        );

        debugPrint(
            'Backup alarm scheduled with AndroidAlarmManager.oneShotAt: $success');
        return success;
      } catch (e) {
        debugPrint(
            'Error scheduling backup alarm with AndroidAlarmManager: $e');
        return false;
      }
    }
    return false;
  }

  /// Callback for Android Alarm Manager
  @pragma('vm:entry-point')
  static Future<void> handleAlarmCallback(
      int id, Map<String, dynamic>? params) async {
    if (params == null) {
      debugPrint(
          'Alarm callback received with null params, using default values');
      await startAlarm(id, 1);
      return;
    }

    final int alarmId = params['alarmId'] ?? id;
    final int soundId = params['soundId'] ?? 1;
    final bool nfcRequired = params['nfcRequired'] ?? false;

    debugPrint(
        'Native alarm callback received: ID=$alarmId, Sound=$soundId, NFC=$nfcRequired');

    // Check if Flutter Alarm package is already handling this alarm
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeFlutterAlarmId = prefs.getInt('flutter.active_alarm_id');

      if (activeFlutterAlarmId == alarmId) {
        debugPrint(
            'Flutter Alarm package already handling alarm $alarmId, skipping native callback');
        return;
      }

      // Check if alarm was triggered very recently (within 30 seconds) to avoid duplicates
      final lastTriggerTime = prefs.getInt('alarm_last_trigger_$alarmId') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now - lastTriggerTime < 30000) {
        // 30 seconds
        debugPrint('Alarm $alarmId was triggered recently, skipping duplicate');
        return;
      }

      // Mark this alarm as triggered
      await prefs.setInt('alarm_last_trigger_$alarmId', now);
    } catch (e) {
      debugPrint('Error checking for duplicate alarm triggers: $e');
    }

    // This is a backup trigger (app was closed), so start the alarm
    debugPrint('Starting backup alarm (app was closed): $alarmId');
    await startAlarm(alarmId, soundId);
  }

  /// Emergency stop all alarm-related services and processes
  static Future<void> emergencyStopAllAlarms() async {
    try {
      debugPrint('EMERGENCY STOP: Stopping all alarm services');

      if (Platform.isAndroid) {
        try {
          // FIRST: Stop the native alarm receiver which manages vibration
          await _platform.invokeMethod('stopAlarmReceiver');
          debugPrint('Emergency: Stopped AlarmReceiver');

          // SECOND: Multiple vibration stop attempts
          for (int i = 0; i < 3; i++) {
            await _platform.invokeMethod('stopVibration');
            await Future.delayed(const Duration(milliseconds: 100));
          }
          debugPrint('Emergency: Stopped vibration (multiple attempts)');

          // THIRD: Stop the alarm service
          await _platform.invokeMethod('stopAlarmService');
          debugPrint('Emergency: Stopped alarm service');

          // FOURTH: Cancel all notifications
          await _platform.invokeMethod('cancelAllNotifications');
          debugPrint('Emergency: Cancelled all notifications');
        } catch (e) {
          debugPrint('Error in emergency native stop: $e');
        }
      }

      // Stop Flutter background service
      try {
        final service = FlutterBackgroundService();
        service.invoke('stopAlarm');
        service.invoke('stopService');
        debugPrint('Emergency: Stopped Flutter background service');
      } catch (e) {
        debugPrint('Error stopping Flutter service: $e');
      }

      // Stop audio player
      try {
        await _fallbackPlayer?.stop();
        _fallbackPlayer = null;
        debugPrint('Emergency: Stopped audio player');
      } catch (e) {
        debugPrint('Error stopping audio player: $e');
      }

      // Clear shared preferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('flutter.active_alarm_id');
        await prefs.remove('flutter.active_alarm_sound');
        await prefs.remove('flutter.alarm_start_time');
        await prefs.remove('flutter.using_fallback_alarm');
        await prefs.remove('flutter.direct_to_stop');
        debugPrint('Emergency: Cleared SharedPreferences');
      } catch (e) {
        debugPrint('Error clearing SharedPreferences: $e');
      }

      // Cancel timers
      _serviceCleanupTimer?.cancel();
      _serviceHealthCheckTimer?.cancel();
      _serviceCleanupTimer = null;
      _serviceHealthCheckTimer = null;

      // One final vibration stop attempt after a delay
      if (Platform.isAndroid) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          await _platform.invokeMethod('stopVibration');
          debugPrint('Emergency: Final vibration stop attempt');
        } catch (e) {
          debugPrint('Error in final vibration stop: $e');
        }
      }

      debugPrint('Emergency stop completed');
    } catch (e) {
      debugPrint('Error in emergency stop: $e');
    }
  }

  /// Ensures alarm notification is visible
  static Future<void> ensureAlarmNotificationVisible(
      int alarmId, int soundId) async {
    try {
      if (await isNativeNotificationActive(alarmId)) {
        debugPrint('Native notification active, skipping Flutter notification');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final usingNativeNotification =
          prefs.getBool('flutter.using_native_notification') ?? false;
      final notificationHandler =
          prefs.getString('flutter.notification_handler') ?? '';

      if (usingNativeNotification || notificationHandler == 'native') {
        debugPrint('Using native notification, skipping Flutter notification');
        return;
      }

      final pendingNotifications =
          await _flutterLocalNotificationsPlugin.pendingNotificationRequests();
      final exists = pendingNotifications.any((n) =>
          n.id == 30000 + alarmId); // Use 30000 range for Flutter notifications

      if (!exists) {
        String title = 'Alarm';
        String body = 'Time to wake up! Tap to stop the alarm.';
        bool nfcRequired = false;

        try {
          if (Get.isRegistered<AlarmController>()) {
            final alarmController = Get.find<AlarmController>();
            final alarm = alarmController.getAlarmById(alarmId);
            if (alarm != null) {
              nfcRequired = alarm.nfcRequired;
              body = nfcRequired
                  ? 'Time to wake up! Scan your NFC tag to stop the alarm.'
                  : 'Time to wake up! Tap to stop the alarm.';
            }
          }
        } catch (e) {
          debugPrint('Error getting alarm details: $e');
        }

        AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'alarm_foreground_service',
          'Alarm Service Channel',
          channelDescription: 'Channel for Alarm Service',
          importance: Importance.max,
          priority: Priority.max,
          ongoing: true,
          autoCancel: false,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          showWhen: true,
          playSound: false,
          // We handle sound separately
          sound: null,
          actions: [
            const AndroidNotificationAction(
              'stop_alarm_action',
              'Stop Alarm',
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
          color: Colors.red,
          colorized: true,
          enableVibration: false,
          // vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
          enableLights: true,
          ledColor: Colors.red,
          ledOnMs: 1000,
          ledOffMs: 500,
        );

        const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: false,
          sound: null,
          interruptionLevel: InterruptionLevel.timeSensitive,
        );

        await _flutterLocalNotificationsPlugin.cancel(30000 + alarmId);

        await _flutterLocalNotificationsPlugin.show(
          30000 + alarmId,
          title,
          body,
          NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          ),
          payload: "$alarmId:$soundId",
        );

        await prefs.setBool('flutter.using_native_notification', false);
        await prefs.setString('flutter.notification_handler', 'flutter');
      }
    } catch (e) {
      debugPrint('Error ensuring alarm notification is visible: $e');
    }
  }

  /// check for active notifications
  static Future<bool> isNativeNotificationActive(int alarmId) async {
    if (Platform.isAndroid) {
      try {
        final bool isActive =
            await _platform.invokeMethod('isNativeNotificationActive', {
          'alarmId': alarmId,
        });
        return isActive;
      } catch (e) {
        debugPrint('Error checking native notification: $e');
      }
    }
    return false;
  }

  /// Perform a complete cleanup of all alarm-related resources
  static Future<void> performCompleteCleanup() async {
    try {
      debugPrint('Performing complete cleanup');

      if (_fallbackPlayer != null) {
        try {
          await _fallbackPlayer!.stop();
          await _fallbackPlayer!.dispose();
        } catch (e) {
          debugPrint('Error stopping fallback player: $e');
        } finally {
          _fallbackPlayer = null;
        }
      }

      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke('stopService');
      }

      await NotificationService.flutterLocalNotificationsPlugin.cancelAll();

      await releaseWakeLock();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_alarm_id');
      await prefs.remove('active_alarm_sound');
      await prefs.remove('alarm_start_time');
      await prefs.remove('using_fallback_alarm');

      if (Get.isRegistered<AlarmController>()) {
        final alarmController = Get.find<AlarmController>();
        alarmController.activeAlarmId.value = -1;
      }

      if (Platform.isAndroid) {
        try {
          await _platform.invokeMethod('forceStopService');
          await _platform.invokeMethod('stopVibration');
          await _platform.invokeMethod('cancelAllNotifications');
        } catch (e) {
          debugPrint('Error stopping native services: $e');
        }
      }

      _serviceCleanupTimer?.cancel();
      _serviceHealthCheckTimer?.cancel();

      debugPrint('Complete cleanup finished');
    } catch (e) {
      debugPrint('Error in complete cleanup: $e');
    }
  }

  /// Health check for service reliability
  static void startServiceHealthCheck() {
    _serviceHealthCheckTimer?.cancel();

    _serviceHealthCheckTimer =
        Timer.periodic(const Duration(minutes: 2), (timer) async {
      try {
        debugPrint('Performing service health check');

        final service = FlutterBackgroundService();
        final isRunning = await service.isRunning();

        final prefs = await SharedPreferences.getInstance();
        final storedAlarmId = prefs.getInt('active_alarm_id');
        final usingFallback = prefs.getBool('using_fallback_alarm') ?? false;

        if (isRunning && storedAlarmId == null) {
          debugPrint('Health check: Stopping unnecessary background service');
          await forceStopService();
        } else if (!isRunning && storedAlarmId != null && !usingFallback) {
          final startTime = prefs.getInt('alarm_start_time') ?? 0;
          final alarmAge = DateTime.now().millisecondsSinceEpoch - startTime;

          if (alarmAge < 15 * 60 * 1000) {
            debugPrint('Health check: Service died unexpectedly, recovering');
            final soundId = prefs.getInt('active_alarm_sound') ?? 1;

            if (Get.isRegistered<AlarmController>()) {
              final alarmController = Get.find<AlarmController>();
              final alarm = alarmController.getAlarmById(storedAlarmId);

              if (alarm != null) {
                await forceStartAlarmIfNeeded(storedAlarmId, soundId);
              } else {
                debugPrint(
                    'Health check: Alarm no longer exists in controller, cleaning up');
                await forceStopService();
              }
            } else {
              await forceStartAlarmIfNeeded(storedAlarmId, soundId);
            }
          } else {
            debugPrint('Health check: Found stale alarm data, cleaning up');
            await forceStopService();
          }
        }

        if (usingFallback && _fallbackPlayer != null) {
          try {
            final isPlaying = _fallbackPlayer!.state == PlayerState.playing;
            if (!isPlaying && storedAlarmId != null) {
              debugPrint(
                  'Health check: Fallback player not playing, restarting');
              final soundId = prefs.getInt('active_alarm_sound') ?? 1;
              final soundPath = SoundManager.getSoundPath(soundId);
              await _fallbackPlayer!.play(AssetSource(soundPath));
            }
          } catch (e) {
            debugPrint('Error checking fallback player: $e');
          }
        }
      } catch (e) {
        debugPrint('Error in service health check: $e');
      }
    });
  }

  /// Force start alarm if needed
  static Future<void> forceStartAlarmIfNeeded(int alarmId, int soundId) async {
    try {
      debugPrint('Force starting alarm if needed: ID=$alarmId, Sound=$soundId');

      final bool isActive = await isAlarmActive();
      if (isActive) {
        debugPrint('Alarm is already active, skipping force start');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('flutter.active_alarm_id', alarmId);
      await prefs.setInt('flutter.active_alarm_sound', soundId);
      await prefs.setInt(
          'flutter.alarm_start_time', DateTime.now().millisecondsSinceEpoch);
      await prefs.setBool('flutter.using_native_notification', true);

      if (Platform.isAndroid) {
        try {
          debugPrint('Attempting to start native alarm service');
          final bool success =
              await _platform.invokeMethod('startForegroundService', {
            'alarmId': alarmId,
            'soundId': soundId,
          });

          if (success) {
            debugPrint('Native alarm service started successfully');
            _activeAlarmId = alarmId;
            if (Get.isRegistered<AlarmController>()) {
              final alarmController = Get.find<AlarmController>();
              alarmController.activeAlarmId.value = alarmId;
            }

            await acquirePersistentWakeLock();

            startServiceHealthCheck();

            return;
          }
        } catch (e) {
          debugPrint('Error starting native alarm service: $e');
        }
      }

      debugPrint('Falling back to Flutter alarm implementation');

      final service = FlutterBackgroundService();

      if (!_isInitialized) {
        final initialized = await initializeService();
        if (!initialized) {
          debugPrint('Failed to initialize service, using fallback');
          await _startFallbackAlarm(alarmId, soundId);
          return;
        }
      }

      await service.startService();

      await Future.delayed(const Duration(milliseconds: 1000));

      if (!(await service.isRunning())) {
        debugPrint('Background service failed to start, using fallback');
        await _startFallbackAlarm(alarmId, soundId);
        return;
      }

      service.invoke('startAlarm', {
        'alarmId': alarmId,
        'soundId': soundId,
        'forceStart': true,
      });

      _activeAlarmId = alarmId;
      if (Get.isRegistered<AlarmController>()) {
        final alarmController = Get.find<AlarmController>();
        alarmController.activeAlarmId.value = alarmId;
      }

      if (!(prefs.getBool('flutter.using_native_notification') ?? false)) {
        await _startFallbackAlarm(alarmId, soundId);
      }

      await ensureAlarmNotificationVisible(alarmId, soundId);
    } catch (e) {
      debugPrint('Error in forceStartAlarmIfNeeded: $e');
      await _startFallbackAlarm(alarmId, soundId);
    }
  }

  /// Force stops the service with improved reliability
  static Future<void> forceStopService() async {
    try {
      debugPrint('Force stopping all alarm services');

      if (Platform.isAndroid) {
        try {
          await _platform.invokeMethod('forceStopService');
          debugPrint('Native service stopped via platform channel');
        } catch (e) {
          debugPrint('Error stopping native service: $e');
        }
      }

      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (isRunning) {
        service.invoke('stopService');
        debugPrint('Stop command sent to background service');

        int attempts = 0;
        while (await service.isRunning() && attempts < 5) {
          await Future.delayed(const Duration(milliseconds: 300));
          attempts++;
        }

        if (await service.isRunning()) {
          debugPrint(
              'Service still running after stop attempts, forcing termination');
          try {
            if (Platform.isAndroid) {
              await _platform.invokeMethod('forceStopService');
            }
          } catch (e) {
            debugPrint('Error force stopping service via platform channel: $e');
          }
        }
      }

      if (_fallbackPlayer != null) {
        try {
          await _fallbackPlayer!.stop();
          await _fallbackPlayer!.dispose();
        } catch (e) {
          debugPrint('Error stopping fallback player: $e');
        } finally {
          _fallbackPlayer = null;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('flutter.active_alarm_id');
      await prefs.remove('flutter.active_alarm_sound');
      await prefs.remove('flutter.alarm_start_time');
      await prefs.remove('flutter.using_fallback_alarm');
      await prefs.remove('flutter.using_native_notification');

      _activeAlarmId = null;

      try {
        if (Get.isRegistered<AlarmController>()) {
          final alarmController = Get.find<AlarmController>();
          alarmController.activeAlarmId.value = -1;
        }
      } catch (e) {
        debugPrint('Error updating alarm controller: $e');
      }

      _serviceHealthCheckTimer?.cancel();

      await releaseWakeLock();

      await _flutterLocalNotificationsPlugin.cancelAll();

      debugPrint('Force stop completed');
    } catch (e) {
      debugPrint('Error force stopping service: $e');
    }
  }

  /// Properly store scheduled alarm information

  static Future<void> storeScheduledAlarm(
      int alarmId, int soundId, int timestamp, bool nfcRequired) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing alarms - ALWAYS as String first
      final String? existingAlarmsJson = prefs.getString('scheduled_alarms');
      List<String> alarms = [];

      if (existingAlarmsJson != null && existingAlarmsJson.isNotEmpty) {
        try {
          if (existingAlarmsJson.startsWith('[') &&
              existingAlarmsJson.endsWith(']')) {
            // It's JSON format
            final List<dynamic> jsonList = json.decode(existingAlarmsJson);
            alarms = jsonList.map((item) => item.toString()).toList();
          } else {
            // It's legacy format
            alarms = existingAlarmsJson
                .split(',')
                .where((s) => s.isNotEmpty)
                .toList();
          }
        } catch (e) {
          debugPrint('Error parsing scheduled alarms: $e');
          alarms = [];
        }
      }

      // Filter out any existing alarm with this ID
      alarms.removeWhere((alarm) {
        final parts = alarm.split(':');
        return parts.isNotEmpty && parts[0] == alarmId.toString();
      });

      // Add the new alarm
      final String alarmEntry = "$alarmId:$soundId:$timestamp:$nfcRequired";
      alarms.add(alarmEntry);

      // ALWAYS store as JSON string
      await prefs.setString('scheduled_alarms', json.encode(alarms));

      debugPrint('Stored scheduled alarm: $alarmEntry');
      debugPrint('Total scheduled alarms: ${alarms.length}');
    } catch (e) {
      debugPrint('Error storing scheduled alarm: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        final String alarmEntry = "$alarmId:$soundId:$timestamp:$nfcRequired";
        await prefs.setString('scheduled_alarms', json.encode([alarmEntry]));
      } catch (_) {}
    }
  }

  /// Remove a scheduled alarm
  static Future<void> removeScheduledAlarm(int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final String? existingAlarmsJson = prefs.getString('scheduled_alarms');
      if (existingAlarmsJson == null || existingAlarmsJson.isEmpty) return;

      try {
        List<String> alarms = [];

        if (existingAlarmsJson.startsWith('[') &&
            existingAlarmsJson.endsWith(']')) {
          final List<dynamic> jsonList = json.decode(existingAlarmsJson);
          alarms = jsonList.map((item) => item.toString()).toList();
        } else {
          alarms =
              existingAlarmsJson.split(',').where((s) => s.isNotEmpty).toList();
        }

        final initialCount = alarms.length;
        final updatedAlarms = alarms.where((alarm) {
          final parts = alarm.split(':');
          return parts.isNotEmpty && parts[0] != alarmId.toString();
        }).toList();

        await prefs.setString('scheduled_alarms', json.encode(updatedAlarms));

        await cancelExactAlarm(alarmId);

        debugPrint('Removed scheduled alarm ID: $alarmId');
        debugPrint(
            'Alarms before: $initialCount, after: ${updatedAlarms.length}');
      } catch (e) {
        debugPrint('Error parsing alarms during removal: $e');
        await prefs.remove('scheduled_alarms');

        await cancelExactAlarm(alarmId);
      }
    } catch (e) {
      debugPrint('Error removing scheduled alarm: $e');
    }
  }

  /// Recover active alarms on app restart

  static Future<void> recoverActiveAlarmsOnRestart() async {
    try {
      debugPrint('Checking for active alarms to recover on app restart');

      final prefs = await SharedPreferences.getInstance();
      final activeAlarmId = prefs.getInt('flutter.active_alarm_id');
      final activeAlarmSound = prefs.getInt('flutter.active_alarm_sound');
      final startTime = prefs.getInt('flutter.alarm_start_time');

      if (activeAlarmId != null &&
          activeAlarmSound != null &&
          startTime != null) {
        debugPrint(
            'Found active alarm data: ID=$activeAlarmId, Sound=$activeAlarmSound');

        final alarmAge = DateTime.now().millisecondsSinceEpoch - startTime;

        if (alarmAge < 30 * 60 * 1000) {
          final alarmController = Get.find<AlarmController>();
          final alarm = alarmController.getAlarmById(activeAlarmId);

          if (alarm != null && alarm.isEnabled) {
            debugPrint('Recovering active alarm: $activeAlarmId');

            final service = FlutterBackgroundService();
            if (!(await service.isRunning())) {
              await forceStartAlarmIfNeeded(activeAlarmId, activeAlarmSound);
            }
          } else {
            debugPrint('Alarm no longer exists or is disabled, cleaning up');
            await forceStopService();
          }
        } else {
          debugPrint(
              'Found stale alarm data (${alarmAge / 60000} minutes old), cleaning up');
          await forceStopService();
        }
      } else {
        debugPrint('No active alarm data found');
      }

      await _checkForMissedAlarms();
      await fixCorruptedScheduledAlarms();
    } catch (e) {
      debugPrint('Error recovering alarms: $e');
    }
  }

  static Future<bool> cancelExactAlarm(int alarmId) async {
    if (Platform.isAndroid) {
      try {
        final bool success =
            await _alarmManagerChannel.invokeMethod('cancelExactAlarm', {
          'alarmId': alarmId,
        });

        debugPrint('Canceled exact alarm via native channel: $success');

        await AndroidAlarmManager.cancel(alarmId);

        return success;
      } catch (e) {
        debugPrint('Error canceling exact alarm via channel: $e');
      }

      try {
        final success = await AndroidAlarmManager.cancel(alarmId);
        debugPrint('Canceled alarm with AndroidAlarmManager: $success');
        return success;
      } catch (e) {
        debugPrint('Error canceling alarm with AndroidAlarmManager: $e');
      }
    }
    return false;
  }

  /// Check for missed alarms

  static Future<void> _checkForMissedAlarms() async {
    try {
      debugPrint('Checking for missed alarms');

      final prefs = await SharedPreferences.getInstance();
      final scheduledAlarmsString = prefs.getString('scheduled_alarms');

      if (scheduledAlarmsString != null && scheduledAlarmsString.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;

        try {
          List<String> alarms = [];

          if (scheduledAlarmsString.startsWith('[') &&
              scheduledAlarmsString.endsWith(']')) {
            // It's JSON format
            final List<dynamic> jsonList = json.decode(scheduledAlarmsString);
            alarms = jsonList.map((item) => item.toString()).toList();
          } else {
            // It's legacy format
            alarms = scheduledAlarmsString
                .split(',')
                .where((s) => s.isNotEmpty)
                .toList();
          }

          debugPrint(
              'Checking ${alarms.length} scheduled alarms for missed alarms');

          for (final alarmInfo in alarms) {
            final parts = alarmInfo.split(':');
            if (parts.length >= 3) {
              final id = int.tryParse(parts[0]) ?? -1;
              final soundId = int.tryParse(parts[1]) ?? 1;
              final scheduledTime = int.tryParse(parts[2]) ?? 0;

              if (id != -1 &&
                  scheduledTime < now &&
                  scheduledTime > now - (5 * 60 * 1000)) {
                debugPrint(
                    'Found missed alarm: $id scheduled for ${DateTime.fromMillisecondsSinceEpoch(scheduledTime)}');

                final alarmController = Get.find<AlarmController>();
                final alarm = alarmController.getAlarmById(id);

                if (alarm != null && alarm.isEnabled) {
                  debugPrint('Triggering missed alarm: $id');

                  await forceStartAlarmIfNeeded(id, soundId);

                  break;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error parsing scheduled alarms JSON: $e');
          await prefs.remove('scheduled_alarms');
        }
      }
    } catch (e) {
      debugPrint('Error checking for missed alarms: $e');
    }
  }

  /// Fix corrupted scheduled alarms data

  static Future<void> fixCorruptedScheduledAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? existingData = prefs.getString('scheduled_alarms');

      if (existingData == null || existingData.isEmpty) return;

      try {
        // Try to parse as JSON to check if it's valid
        json.decode(existingData);
      } catch (e) {
        debugPrint('Fixing corrupted scheduled alarms data');

        // Remove corrupted data
        await prefs.remove('scheduled_alarms');

        // Try to recover data if it has the expected format
        if (existingData.contains(':')) {
          List<String> recoveredAlarms = [];
          final parts = existingData
              .replaceAll('[', '')
              .replaceAll(']', '')
              .replaceAll('"', '')
              .split(',');

          for (final part in parts) {
            final trimmed = part.trim();
            if (trimmed.split(':').length >= 3) {
              recoveredAlarms.add(trimmed);
            }
          }

          if (recoveredAlarms.isNotEmpty) {
            // Store recovered data as JSON
            await prefs.setString(
                'scheduled_alarms', json.encode(recoveredAlarms));
            debugPrint(
                'Recovered ${recoveredAlarms.length} alarms from corrupted data');
          }
        }
      }
    } catch (e) {
      debugPrint('Error fixing corrupted scheduled alarms: $e');
    }
  }

  /// Check if service is currently running an alarm
  static Future<bool> isAlarmActive() async {
    try {
      if (Platform.isAndroid) {
        try {
          final bool isNativeAlarmActive =
              await _platform.invokeMethod('isAlarmActive');
          if (isNativeAlarmActive) {
            debugPrint('Native alarm is active');
            return true;
          }
        } catch (e) {
          debugPrint('Error checking native alarm status: $e');
        }
      }

      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (isRunning) {
        debugPrint('Flutter background service is running');
        return true;
      }

      final prefs = await SharedPreferences.getInstance();
      final usingFallback =
          prefs.getBool('flutter.using_fallback_alarm') ?? false;
      final activeAlarmId = prefs.getInt('flutter.active_alarm_id');

      if (usingFallback && activeAlarmId != null) {
        debugPrint('Using fallback alarm with ID: $activeAlarmId');
        return true;
      }

      if (_fallbackPlayer != null &&
          _fallbackPlayer!.state == PlayerState.playing) {
        debugPrint('Fallback player is active');
        return true;
      }

      debugPrint('No active alarm detected');
      return false;
    } catch (e) {
      debugPrint('Error checking if alarm is active: $e');
      return false;
    }
  }

  /// Get active alarm data
  static Future<Map<String, dynamic>?> getActiveAlarmData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeAlarmId = prefs.getInt('flutter.active_alarm_id');

      if (activeAlarmId == null) return null;

      final activeSoundId = prefs.getInt('flutter.active_alarm_sound') ?? 1;
      final startTime = prefs.getInt('flutter.alarm_start_time') ?? 0;

      return {
        'alarmId': activeAlarmId,
        'soundId': activeSoundId,
        'startTime': startTime,
        'elapsedSeconds':
            (DateTime.now().millisecondsSinceEpoch - startTime) ~/ 1000,
      };
    } catch (e) {
      debugPrint('Error getting active alarm data: $e');
      return null;
    }
  }

  /// Bring app to foreground
  static Future<void> bringAppToForeground() async {
    try {
      if (Platform.isAndroid) {
        await _platform.invokeMethod('bringToForeground');
        debugPrint('Requested to bring app to foreground');
      }
    } catch (e) {
      debugPrint('Error bringing app to foreground: $e');
    }
  }

  /// Get alarm launch data from native side
  static Future<Map<String, dynamic>?> getAlarmLaunchData() async {
    try {
      if (Platform.isAndroid) {
        final Map<dynamic, dynamic>? data =
            await _platform.invokeMethod('getAlarmLaunchData');
        if (data != null) {
          return Map<String, dynamic>.from(data);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error getting alarm launch data: $e');
      return null;
    }
  }

  /// Initialize on app start
  static Future<void> initializeOnAppStart() async {
    try {
      // Don't automatically initialize service - main.dart will handle this
      // We only want services running when an alarm is active

      await fixCorruptedScheduledAlarms();

      final isActive = await isAlarmActive();

      if (isActive) {
        debugPrint('Found active alarm on app start');

        final alarmData = await getActiveAlarmData();
        if (alarmData != null) {
          final int alarmId = alarmData['alarmId'];
          final int soundId = alarmData['soundId'];

          if (Get.isRegistered<AlarmController>()) {
            final alarmController = Get.find<AlarmController>();
            alarmController.activeAlarmId.value = alarmId;
          }

          startServiceHealthCheck();
        }
      } else {
        final launchData = await getAlarmLaunchData();
        if (launchData != null && launchData['fromAlarm'] == true) {
          debugPrint('App launched from alarm notification: $launchData');

          final int alarmId = launchData['alarmId'] ?? -1;
          final int soundId = launchData['soundId'] ?? 1;
          final bool directToStop = launchData['directToStop'] ?? false;

          if (alarmId != -1) {
            if (!directToStop) {
              await forceStartAlarmIfNeeded(alarmId, soundId);
            }

            // We'll let the HomeScreen handle navigation based on this data
            // The HomeScreen will check for the directToStop flag in _checkAlarmLaunchIntent
          } else {
            // No active alarm or launch intent, make sure service is stopped
            await forceStopService();
          }
        }
      }
    } catch (e) {
      debugPrint('Error recovering alarms: $e');
    }
  }

  /// Emergency stop for vibration only
  static Future<void> emergencyStopVibration() async {
    try {
      debugPrint('EMERGENCY VIBRATION STOP: Stopping all vibration');

      if (Platform.isAndroid) {
        try {
          // Multiple attempts to stop vibration
          await _platform.invokeMethod('stopVibration');
          await Future.delayed(const Duration(milliseconds: 100));
          await _platform.invokeMethod('stopVibration');
          await Future.delayed(const Duration(milliseconds: 100));
          await _platform.invokeMethod('stopVibration');

          debugPrint('Emergency vibration stop completed');
        } catch (e) {
          debugPrint('Error in emergency vibration stop: $e');
        }
      }
    } catch (e) {
      debugPrint('Error in emergency vibration stop: $e');
    }
  }
}
