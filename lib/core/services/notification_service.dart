import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:alarmapp/core/constants/asset_constants.dart';
import 'package:alarmapp/core/services/sound_manager.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../controllers/alarm/alarm_controller.dart';
import '../../models/alarm/alarm_model.dart';
import 'background_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const String stopActionId = 'stop_alarm_action';
  static const List<String> reservedChannels = [
    'alarm_foreground_service',
    'alarm_fallback_channel'
  ];

  static final Set<int> _activeNotificationIds = {};
  static final Map<int, AudioPlayer> _fallbackPlayers = {};
  static Timer? _permissionRetryTimer;
  static final Map<int, int> _alarmActivationTimestamps = {};

  /// shows fallback alarm notification
  static Future<void> showFallbackAlarmNotification(
      int alarmId, int soundId) async {
    try {
      debugPrint('Showing fallback alarm notification for ID: $alarmId');
      if (Platform.isAndroid) {
        try {
          final bool isNativeActive =
              await const MethodChannel('com.example.alarm/background_channel')
                  .invokeMethod(
                      'isNativeNotificationActive', {'alarmId': alarmId});

          if (isNativeActive) {
            debugPrint(
                'Native notification active, skipping fallback notification');

            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('flutter.using_native_notification', true);
            await prefs.setString('flutter.notification_handler', 'native');

            return;
          }
        } catch (e) {
          debugPrint('Error checking native notification: $e');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final usingNativeNotification =
          prefs.getBool('flutter.using_native_notification') ?? false;
      final notificationHandler =
          prefs.getString('flutter.notification_handler') ?? '';

      if (usingNativeNotification || notificationHandler == 'native') {
        debugPrint(
            'Using native notification according to preferences, skipping fallback notification');
        return;
      }

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

      await flutterLocalNotificationsPlugin.cancelAll();

      final notificationId = 30000 + alarmId;

      AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'alarm_channel',
        'Alarm Notifications',
        channelDescription: 'Channel for alarm notifications',
        importance: Importance.max,
        priority: Priority.max,
        ongoing: true,
        autoCancel: false,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        showWhen: true,
        playSound: false, // We handle sound separately
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
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
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

      await flutterLocalNotificationsPlugin.show(
        notificationId,
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
      if (Platform.isAndroid) {
        try {
          await const MethodChannel('com.example.alarm/background_channel')
              .invokeMethod('cancelAllNotifications');
        } catch (e) {
          debugPrint('Error canceling native notifications: $e');
        }
      }

      debugPrint(
          'Fallback notification shown successfully with ID: $notificationId');
    } catch (e) {
      debugPrint('Error showing fallback notification: $e');
    }
  }

  ///  mark an alarm as activated to prevent duplicates
  static Future<bool> markAlarmAsActivated(int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeAlarmId = prefs.getInt('active_alarm_id');

      if (activeAlarmId == alarmId) {
        final startTime = prefs.getInt('alarm_start_time') ?? 0;
        final alarmAge = DateTime.now().millisecondsSinceEpoch - startTime;

        if (alarmAge < 10 * 1000) {
          debugPrint(
              'Skipping duplicate activation for alarm ID: $alarmId (activated ${alarmAge}ms ago)');
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error checking alarm activation status: $e');
      return true;
    }
  }

  /// clean old activation yimestamps
  static Future<void> cleanupOldActivationTimestamps() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();

      _alarmActivationTimestamps.removeWhere(
          (id, timestamp) => now - timestamp > 24 * 60 * 60 * 1000);

      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith('alarm_last_activated_'));
      for (final key in keys) {
        final timestamp = prefs.getInt(key) ?? 0;
        if (now - timestamp > 24 * 60 * 60 * 1000) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up activation timestamps: $e');
    }
  }

  /// Initializes the notification service with improved reliability
  static Future<void> initialize() async {
    try {
      tz.initializeTimeZones();
      await ensureNotificationVisibility();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestSoundPermission: true,
        requestBadgePermission: true,
        requestAlertPermission: true,
        requestCriticalPermission: true,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: onNotificationTap,
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      // Clear existing notifications to avoid conflicts
      await flutterLocalNotificationsPlugin.cancelAll();

      // Create required notification channels with proper settings
      await _createRequiredNotificationChannels();
      
      // Request all required permissions immediately
      await _requestAllRequiredPermissions();
      
      await _cleanupOldNotificationChannels();
      await requestBatteryOptimizationExemption();
      await setupNotificationTriggerListener();
      await _clearAllActiveAlarms();
      await checkAndRestoreAlarmsAfterReboot();
      await cleanupOldActivationTimestamps();
      
      Timer.periodic(const Duration(hours: 1), (_) {
        clearStaleNotifications();
      });

      Timer.periodic(const Duration(hours: 12), (_) {
        cleanupOldActivationTimestamps();
      });
      
      // Schedule a health check to ensure permissions stay active
      _schedulePermissionHealthChecks();
    } catch (e) {
      debugPrint('Notification service initialization error: $e');
      _scheduleRetryInitialization();
    }
  }

  /// Create all required notification channels with proper settings
  static Future<void> _createRequiredNotificationChannels() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
              
      if (androidPlugin != null) {
        // Main alarm channel
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'alarm_channel',
            'Alarm Notifications',
            description: 'Used for alarm notifications',
            importance: Importance.max,
            enableVibration: true,
            enableLights: true,
            ledColor: Colors.red,
            playSound: true,  // IMPORTANT: Enable sound
            sound: null,  // Use default sound
            showBadge: true,
          ),
        );
        
        // Foreground service channel
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'alarm_foreground_service',
            'Alarm Service',
            description: 'Used for running the alarm service',
            importance: Importance.high,
            enableVibration: true,
            showBadge: true,
          ),
        );
        
        debugPrint('Created all required notification channels');
      }
    }
  }
  
  /// Request all permissions needed for alarms to function
  static Future<void> _requestAllRequiredPermissions() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
      await Permission.scheduleExactAlarm.request();
      await Permission.ignoreBatteryOptimizations.request();
      
      // Request notification permissions from platform plugin too
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
              
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        
        // Also use method channel for additional permissions
        try {
          await const MethodChannel('com.example.alarm/background_channel')
              .invokeMethod('bringToForeground');
        } catch (e) {
          debugPrint('Error bringing app to foreground: $e');
        }
      }
    } else if (Platform.isIOS) {
      await Permission.notification.request();
    }
    
    debugPrint('Requested all required permissions');
  }
  
  /// Schedule regular checks of notification permissions
  static void _schedulePermissionHealthChecks() {
    Timer.periodic(const Duration(minutes: 30), (_) async {
      final hasPermissions = await areNotificationsEnabled();
      debugPrint('Permission health check: Notifications enabled = $hasPermissions');
      
      if (!hasPermissions) {
        await _requestAllRequiredPermissions();
      }
    });
  }

  /// Schedule a retry for initialization if it fails
  static void _scheduleRetryInitialization() {
    Timer(const Duration(seconds: 30), () {
      try {
        initialize();
      } catch (e) {
        debugPrint('Retry initialization failed: $e');
      }
    });
  }

  /// Handles gradual volume increase for alarms
  static Future<void> setupGradualVolumeIncrease(
      int alarmId, int soundId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final initialVolume = prefs.getInt('alarm_volume') ?? 50;
      int currentVolume = initialVolume;
      final hour = DateTime.now().hour;
      if (hour >= 22 || hour < 7) {
        currentVolume = (initialVolume * 0.5).round();
      }

      if (_fallbackPlayers.containsKey(alarmId)) {
        await _fallbackPlayers[alarmId]!.setVolume(currentVolume / 100);
      }

      Timer.periodic(const Duration(seconds: 30), (timer) async {
        if (!_activeNotificationIds.contains(alarmId)) {
          timer.cancel();
          return;
        }

        currentVolume = min(currentVolume + 10, 100);
        debugPrint('Increasing alarm volume to $currentVolume%');

        if (_fallbackPlayers.containsKey(alarmId)) {
          await _fallbackPlayers[alarmId]!.setVolume(currentVolume / 100);
        }

        final service = FlutterBackgroundService();
        if (await service.isRunning()) {
          service.invoke('updateVolume', {'volume': currentVolume});
        }
      });
    } catch (e) {
      debugPrint('Error setting up gradual volume increase: $e');
    }
  }

  /// Shows a notification for upcoming alarms
  static Future<void> showUpcomingAlarmNotification(AlarmModel alarm) async {
    if (!alarm.isEnabled || alarm.id == null) return;

    try {
      final timeUntilAlarm =
          alarm.getNextAlarmTime().difference(DateTime.now());

      if (timeUntilAlarm.inMinutes > 60 || timeUntilAlarm.inMinutes < 1) return;

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'upcoming_alarm_channel',
        'Upcoming Alarm Notifications',
        channelDescription: 'Notifications for upcoming alarms',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: true,
        autoCancel: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
        interruptionLevel: InterruptionLevel.passive,
      );

      final formattedTime = alarm.getFormattedTime();
      final timeRemaining = alarm.getTimeRemaining();

      await flutterLocalNotificationsPlugin.show(
        1000 + alarm.id!,
        'Upcoming Alarm',
        'Alarm set for $formattedTime (in $timeRemaining)',
        const NotificationDetails(android: androidDetails, iOS: iosDetails),
      );
    } catch (e) {
      debugPrint('Error showing upcoming alarm notification: $e');
    }
  }

  /// Handles device idle mode for Android
  static Future<void> handleDeviceIdleMode() async {
    if (!Platform.isAndroid) return;

    try {
      await const MethodChannel('com.your.package/device_idle')
          .invokeMethod('disableDeviceIdleMode');
    } catch (e) {
      debugPrint('Error handling device idle mode: $e');
    }
  }

  /// Sets up a listener to start the background service when notifications are triggered
  static Future<void> setupNotificationTriggerListener() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final bool? granted = await androidPlugin.areNotificationsEnabled();
        if (granted != true) {
          await androidPlugin.requestNotificationsPermission();
        }
      }

      final NotificationAppLaunchDetails? launchDetails =
          await flutterLocalNotificationsPlugin
              .getNotificationAppLaunchDetails();

      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final String? payload = launchDetails.notificationResponse?.payload;
        if (payload != null) {
          final List<String> payloadParts = payload.split(':');
          if (payloadParts.length >= 1) {
            final int alarmId = int.tryParse(payloadParts[0]) ?? 0;
            final int soundId = payloadParts.length > 1
                ? int.tryParse(payloadParts[1]) ?? 1
                : 1;

            await AlarmBackgroundService.forceStopService();
            await Future.delayed(const Duration(milliseconds: 500));
            _startAlarmSoundService(alarmId, soundId);
          }
        }
      }
    } catch (e) {
      debugPrint('Error setting up notification trigger listener: $e');
    }
  }

  /// Ensures all required notification channels exist with improved settings
  static Future<void> _ensureRequiredChannelsExist() async {
    try {
      AndroidNotificationChannel foregroundChannel = AndroidNotificationChannel(
        'alarm_foreground_service',
        'Alarm Service Channel',
        description: 'Used for alarm foreground service',
        importance: Importance.max,
        playSound: false,
        showBadge: true,
        enableLights: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
        ledColor: const Color.fromARGB(255, 255, 0, 0),
      );

      AndroidNotificationChannel fallbackChannel = AndroidNotificationChannel(
        'alarm_fallback_channel',
        'Alarm Fallback Channel',
        description: 'Used when background service fails',
        importance: Importance.max,
        playSound: false,
        enableVibration: true,
        enableLights: true,
        vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
        ledColor: const Color.fromARGB(255, 255, 0, 0),
      );

      final plugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (plugin != null) {
        await plugin.createNotificationChannel(foregroundChannel);
        await plugin.createNotificationChannel(fallbackChannel);
      }
    } catch (e) {
      debugPrint('Error creating notification channels: $e');
    }
  }

  /// Cleans up old notification channels safely while preserving important ones
  static Future<void> _cleanupOldNotificationChannels() async {
    try {
      final channels = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.getNotificationChannels();

      if (channels == null || channels.isEmpty) return;

      final alarmChannels = channels
          .where((channel) =>
              channel.id.startsWith('alarm_channel_sound_') &&
              !reservedChannels.contains(channel.id))
          .toList();

      if (alarmChannels.length > 10) {
        alarmChannels.sort((a, b) {
          final timestampA = int.tryParse(a.id.split('_').last) ?? 0;
          final timestampB = int.tryParse(b.id.split('_').last) ?? 0;
          return timestampB.compareTo(timestampA);
        });

        for (int i = 10; i < alarmChannels.length; i++) {
          try {
            await flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>()
                ?.deleteNotificationChannel(alarmChannels[i].id);
          } catch (e) {
            debugPrint('Could not delete channel ${alarmChannels[i].id}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up notification channels: $e');
    }
  }

  /// Creates a notification channel for a specific sound with improved settings
  static Future<String> _createNotificationChannelForSound(int soundId) async {
    try {
      final String androidSoundName =
          SoundManager.getNotificationSoundName(soundId);
      final String channelId = 'alarm_channel_sound_$soundId';
      final String channelName =
          'Alarm Sound: ${SoundManager.getSoundName(soundId)}';

      final plugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      final channels = await plugin?.getNotificationChannels();
      final channelExists =
          channels?.any((channel) => channel.id == channelId) ?? false;

      if (!channelExists && plugin != null) {
        final AndroidNotificationChannel alarmChannel =
            AndroidNotificationChannel(
          channelId,
          channelName,
          description:
              'Alarm notifications with sound: ${SoundManager.getSoundName(soundId)}',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(androidSoundName),
          enableVibration: true,
          enableLights: true,
          vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
          ledColor: const Color.fromARGB(255, 255, 0, 0),
        );

        await plugin.createNotificationChannel(alarmChannel);
      }

      return channelId;
    } catch (e) {
      debugPrint('Error creating notification channel: $e');
      return 'alarm_fallback_channel';
    }
  }

  /// Clears notifications that should have triggered but failed to do so
  static Future<void> clearStaleNotifications() async {
    try {
      final pendingNotificationRequests =
          await flutterLocalNotificationsPlugin.pendingNotificationRequests();

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();

      for (final request in pendingNotificationRequests) {
        final startTime = prefs.getInt('alarm_start_time') ?? 0;

        if (startTime > 0) {
          final scheduledTime = DateTime.fromMillisecondsSinceEpoch(startTime);

          if (now.difference(scheduledTime).inMinutes > 20) {
            await cancelNotification(request.id);
          }
        }
      }
    } catch (e) {
      debugPrint('Error clearing stale notifications: $e');
    }
  }

  /// Clears any stuck notifications and active alarms at app start
  static Future<void> _clearAllActiveAlarms() async {
    try {
      await AlarmBackgroundService.forceStopService();

      final pendingNotifications =
          await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      for (final notification in pendingNotifications) {
        await flutterLocalNotificationsPlugin.cancel(notification.id);
      }

      await flutterLocalNotificationsPlugin.cancelAll();
      _activeNotificationIds.clear();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_alarm_id');
      await prefs.remove('active_alarm_sound');
      await prefs.remove('alarm_start_time');
      await prefs.remove('using_fallback_alarm');
    } catch (e) {
      debugPrint('Error clearing active alarms: $e');
    }
  }

  /// Ensures notifications are visible even on locked screens with improved permission handling
  static Future<void> ensureNotificationVisibility() async {
    if (Platform.isAndroid) {
      try {
        final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
            flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin != null) {
          if (await _sdkVersionAtLeast(33)) {
            final granted = await androidPlugin.requestExactAlarmsPermission();
            debugPrint('Exact alarms permission granted: $granted');

            if (!granted!) {
              _schedulePermissionRetry();
            }
          }

          if (await _sdkVersionAtLeast(30)) {
            final granted = await androidPlugin.canScheduleExactNotifications();
            debugPrint('Can schedule exact notifications: $granted');

            if (!granted!) {
              // Try to request via permission handler
              await Permission.scheduleExactAlarm.request();
            }
          }
        }

        final notificationStatus = await Permission.notification.status;
        if (!notificationStatus.isGranted) {
          await Permission.notification.request();
        }
      } catch (e) {
        debugPrint('Error ensuring notification visibility: $e');
      }
    }
  }

  /// Schedule a retry for permission requests
  static void _schedulePermissionRetry() {
    _permissionRetryTimer?.cancel();
    _permissionRetryTimer = Timer(const Duration(minutes: 5), () async {
      try {
        await ensureNotificationVisibility();
      } catch (e) {
        debugPrint('Permission retry failed: $e');
      }
    });
  }

  /// Helper method to check Android SDK version
  static Future<bool> _sdkVersionAtLeast(int version) async {
    if (!Platform.isAndroid) return false;
    try {
      final sdkInt = await const MethodChannel('android_sdk_version')
              .invokeMethod<int>('getAndroidVersion') ??
          0;
      return sdkInt >= version;
    } catch (e) {
      debugPrint('Error getting Android SDK version: $e');
      return true; // Assume newer version to be safe
    }
  }

  /// Handles notification tap events and routes to appropriate actions
  static void onNotificationTap(NotificationResponse notificationResponse) {
    try {
      final String? payload = notificationResponse.payload;
      final String? actionId = notificationResponse.actionId;

      if (payload == null) return;

      final List<String> payloadParts = payload.split(':');
      if (payloadParts.isEmpty) return;

      final int alarmId = int.tryParse(payloadParts[0]) ?? 0;
      final int soundId =
          payloadParts.length > 1 ? int.tryParse(payloadParts[1]) ?? 1 : 1;

      debugPrint(
          'Notification tapped with payload: $payload, action: $actionId');

      if (actionId == stopActionId) {
        _handleAlarmStop(alarmId, soundId);
        return;
      }

      _startOrNavigateToAlarm(alarmId, soundId);
    } catch (e) {
      debugPrint('Error handling notification tap: $e');
    }
  }

  /// Handles stopping an active alarm and cleaning up resources
  static Future<void> _handleAlarmStop(int alarmId, int soundId) async {
    try {
      debugPrint('Handling alarm stop request for ID: $alarmId');

      if (Platform.isAndroid) {
        try {
          await const MethodChannel('com.your.package/background_channel')
              .invokeMethod('bringToForeground');
        } catch (e) {
          debugPrint('Error bringing app to foreground: $e');
        }
      }

      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          // Always navigate to stop alarm screen, regardless of NFC
          Get.toNamed(
            AppConstants.stopAlarm,
            arguments: {'alarmId': alarmId, 'soundId': soundId},
          );
        } catch (e) {
          debugPrint('Error navigating to alarm screen: $e');
        }
      });
    } catch (e) {
      debugPrint('Error handling alarm stop: $e');
    }
  }

  /// Starts the alarm service or navigates to the appropriate screen with improved reliability
  static Future<void> _startOrNavigateToAlarm(int alarmId, int soundId) async {
    try {
      final isRunning = await AlarmBackgroundService.isAlarmActive();
      if (!isRunning) {
        await AlarmBackgroundService.forceStartAlarmIfNeeded(alarmId, soundId);
      }

      if (Platform.isAndroid) {
        try {
          await const MethodChannel('com.your.package/background_channel')
              .invokeMethod('bringToForeground');
        } catch (e) {
          debugPrint('Error bringing app to foreground: $e');
        }
      }

      // Mark this alarm as active in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('flutter.active_alarm_id', alarmId);
      await prefs.setInt('flutter.active_alarm_sound', soundId);
      await prefs.setBool('flutter.direct_to_stop', true);

      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          // Navigate to the stop alarm screen
          Get.offAllNamed(
            AppConstants.stopAlarm,
            arguments: {'alarmId': alarmId, 'soundId': soundId},
          );
        } catch (e) {
          debugPrint('Error navigating to alarm screen: $e');
          // Fallback navigation
          Get.offAllNamed(AppConstants.home);
          Future.delayed(const Duration(milliseconds: 200), () {
            Get.toNamed(
              AppConstants.stopAlarm,
              arguments: {'alarmId': alarmId, 'soundId': soundId},
            );
          });
        }
      });
    } catch (e) {
      debugPrint('Error starting/navigating to alarm: $e');
      // Try fallback approach
      try {
        await _startAlarmSoundService(alarmId, soundId);
        // Still attempt to navigate to stop screen
        Get.offAllNamed(
          AppConstants.stopAlarm,
          arguments: {'alarmId': alarmId, 'soundId': soundId},
        );
      } catch (err) {
        debugPrint('Fallback navigation also failed: $err');
      }
    }
  }

  /// Handles background notification tap events with improved reliability
  @pragma('vm:entry-point')
  static void notificationTapBackground(
      NotificationResponse notificationResponse) {
    try {
      final String? payload = notificationResponse.payload;
      final String? actionId = notificationResponse.actionId;

      if (payload != null) {
        final List<String> payloadParts = payload.split(':');
        if (payloadParts.isNotEmpty) {
          final int alarmId = int.tryParse(payloadParts[0]) ?? 0;
          final int soundId =
              payloadParts.length > 1 ? int.tryParse(payloadParts[1]) ?? 1 : 1;

          // Use SharedPreferences to store information for app launch
          SharedPreferences.getInstance().then((prefs) {
            prefs.setInt('flutter.active_alarm_id', alarmId);
            prefs.setInt('flutter.active_alarm_sound', soundId);
            prefs.setBool('flutter.direct_to_stop', true);
            
            if (actionId == stopActionId) {
              AlarmBackgroundService.stopAlarm();
            } else {
              AlarmBackgroundService.forceStartAlarmIfNeeded(alarmId, soundId);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error in notification tap background: $e');
    }
  }

  /// Schedules an alarm notification for a future time
  static Future<void> scheduleAlarmNotification({
    required int id,
    required DateTime scheduledTime,
    required int soundId,
    required bool nfcRequired,
    String? title,
    String? body,
    String? subtitle,
  }) async {
    try {
      _activeNotificationIds.add(id);

      final String channelId =
          await _createNotificationChannelForSound(soundId);
      final String androidSoundName =
          SoundManager.getNotificationSoundName(soundId);
      final String iosSoundName = SoundManager.getIOSNotificationSound(soundId);

      final prefs = await SharedPreferences.getInstance();

      List<String> scheduledAlarms = [];
      try {
        scheduledAlarms = prefs.getStringList('scheduled_alarms') ?? [];
      } catch (e) {
        try {
          final String? alarmString = prefs.getString('scheduled_alarms');
          if (alarmString != null) {
            if (alarmString.startsWith('[') && alarmString.endsWith(']')) {
              try {
                final List<dynamic> jsonList = json.decode(alarmString);
                scheduledAlarms =
                    jsonList.map((item) => item.toString()).toList();
              } catch (_) {
                scheduledAlarms =
                    alarmString.split(',').where((s) => s.isNotEmpty).toList();
              }
            } else {
              scheduledAlarms =
                  alarmString.split(',').where((s) => s.isNotEmpty).toList();
            }
          }
        } catch (_) {
          scheduledAlarms = [];
        }
      }

      final filteredAlarms = scheduledAlarms.where((alarm) {
        final parts = alarm.split(':');
        return parts.isNotEmpty && parts[0] != id.toString();
      }).toList();

      filteredAlarms.add(
          '$id:$soundId:${scheduledTime.millisecondsSinceEpoch}:$nfcRequired');

      await prefs.setStringList('scheduled_alarms', filteredAlarms);

      if (Platform.isAndroid) {
        try {
          await AlarmBackgroundService.scheduleExactAlarm(
              id, scheduledTime, soundId, nfcRequired);

          debugPrint('Scheduled exact alarm with AlarmManager');
        } catch (e) {
          debugPrint('Error scheduling with AlarmManager: $e');
          await AndroidAlarmManager.oneShotAt(
            scheduledTime,
            id,
            AlarmBackgroundService.handleAlarmCallback,
            exact: true,
            wakeup: true,
            rescheduleOnReboot: true,
            alarmClock: true,
            allowWhileIdle: true,
            params: {
              'alarmId': id,
              'soundId': soundId,
              'nfcRequired': nfcRequired,
            },
          );
        }
      }

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title ?? 'Alarm',
        body ??
            (nfcRequired ? 'Scan NFC Tag to Stop Alarm' : 'Tap to Stop Alarm'),
        tz.TZDateTime.from(scheduledTime, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Alarm Sound: ${SoundManager.getSoundName(soundId)}',
            channelDescription:
                'Alarm notifications with sound: ${SoundManager.getSoundName(soundId)}',
            importance: Importance.max,
            priority: Priority.max,
            autoCancel: false,
            ongoing: true,
            playSound: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            showWhen: true,
            usesChronometer: true,
            enableLights: true,
            ledColor: Colors.red,
            ledOnMs: 1000,
            ledOffMs: 500,
            sound: RawResourceAndroidNotificationSound(androidSoundName),
            fullScreenIntent: true,
            vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
            styleInformation: BigTextStyleInformation(
              nfcRequired ? 'Scan NFC Tag to Stop Alarm' : 'Tap to Stop Alarm',
              htmlFormatBigText: true,
              contentTitle: 'Alarm',
              htmlFormatContentTitle: true,
              summaryText: 'Alarm notification',
              htmlFormatSummaryText: true,
            ),
            actions: [
              const AndroidNotificationAction(
                stopActionId,
                'Stop Alarm',
                showsUserInterface: true,
                cancelNotification: false,
              ),
            ],
            color: Colors.red,
            colorized: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: false,
            sound: iosSoundName,
            interruptionLevel: InterruptionLevel.critical,
            threadIdentifier: 'alarm_thread',
            subtitle:
                subtitle ?? (nfcRequired ? 'Scan NFC to stop' : 'Tap to stop'),
            categoryIdentifier: 'alarm_category',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: "$id:$soundId",
      );

      debugPrint('Alarm scheduled for ${scheduledTime.toString()} with ID $id');
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
      throw Exception('Failed to schedule alarm: $e');
    }
  }

  /// Starts the background service to play alarm sound with improved reliability
  static Future<void> _startAlarmSoundService(int alarmId, int soundId) async {
    try {
      if (!(await markAlarmAsActivated(alarmId))) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('active_alarm_id', alarmId);
      await prefs.setInt('active_alarm_sound', soundId);
      await prefs.setInt(
          'alarm_start_time', DateTime.now().millisecondsSinceEpoch);
      await prefs.setBool('using_fallback_alarm', false);

      await acquirePersistentWakeLock();

      final isRunning = await AlarmBackgroundService.isAlarmActive();
      if (isRunning) {
        await AlarmBackgroundService.stopAlarm();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (Platform.isAndroid) {
        try {
          await const MethodChannel('com.your.package/background_channel')
              .invokeMethod('startForegroundService', {
            'alarmId': alarmId,
            'soundId': soundId,
          });

          await Future.delayed(const Duration(milliseconds: 500));

          if (await AlarmBackgroundService.isAlarmActive()) {
            return;
          }
        } catch (e) {
          debugPrint('Native foreground service start failed: $e');
        }
      }

      await AlarmBackgroundService.forceStartAlarmIfNeeded(alarmId, soundId);

      final serviceActive = await AlarmBackgroundService.isAlarmActive();
      if (!serviceActive) {
        throw Exception('Service failed to start');
      }
    } catch (e) {
      debugPrint('Error starting alarm sound service: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('using_fallback_alarm', true);

      await showFallbackAlarmNotification(alarmId, soundId);
    }
  }

  /// Acquires a wake lock to keep the device awake during alarm
  static Future<void> acquirePersistentWakeLock() async {
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('com.your.package/wake_lock')
            .invokeMethod('acquirePersistentWakeLock');
      } catch (e) {
        debugPrint('Error acquiring persistent wake lock via channel: $e');
        try {
          await WakelockPlus.enable();
        } catch (e) {
          debugPrint('Error acquiring wake lock: $e');
        }
      }
    }
  }

  /// Releases wake lock after alarm is dismissed
  static Future<void> releaseWakeLock() async {
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('com.your.package/wake_lock')
            .invokeMethod('releaseWakeLock');
      } catch (e) {
        debugPrint('Error releasing wake lock via channel: $e');
        try {
          await WakelockPlus.disable();
        } catch (e) {
          debugPrint('Error releasing wake lock: $e');
        }
      }
    }
  }

  /// Requests exemption from battery optimization with improved implementation
  static Future<void> requestBatteryOptimizationExemption() async {
    if (Platform.isAndroid) {
      try {
        final status = await Permission.ignoreBatteryOptimizations.status;
        if (!status.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();

          if (!(await Permission.ignoreBatteryOptimizations.isGranted)) {
            try {
              await const MethodChannel('com.your.package/battery_optimization')
                  .invokeMethod('requestBatteryOptimizationExemption');
            } catch (e) {
              debugPrint(
                  'Error requesting battery optimization exemption via channel: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('Error requesting battery optimization exemption: $e');
      }
    }
  }

  /// Checks for alarms that need to be restored after device reboot with improved reliability

  static Future<void> checkAndRestoreAlarmsAfterReboot() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final activeAlarmId = prefs.getInt('active_alarm_id');
      if (activeAlarmId != null) {
        final soundId = prefs.getInt('active_alarm_sound') ?? 1;
        final startTime = prefs.getInt('alarm_start_time') ?? 0;

        final now = DateTime.now().millisecondsSinceEpoch;
        if (startTime > 0 && now - startTime < 30 * 60 * 1000) {
          _startAlarmSoundService(activeAlarmId, soundId);
          return;
        }
      }

      // Get scheduled alarms - ALWAYS as String first
      final String? existingAlarmsJson = prefs.getString('scheduled_alarms');
      List<String> scheduledAlarms = [];

      if (existingAlarmsJson != null && existingAlarmsJson.isNotEmpty) {
        try {
          if (existingAlarmsJson.startsWith('[') && existingAlarmsJson.endsWith(']')) {
            // It's JSON format
            final List<dynamic> jsonList = json.decode(existingAlarmsJson);
            scheduledAlarms = jsonList.map((item) => item.toString()).toList();
          } else {
            // It's legacy format
            scheduledAlarms = existingAlarmsJson.split(',').where((s) => s.isNotEmpty).toList();
          }
        } catch (e) {
          debugPrint('Error parsing scheduled alarms: $e');
          scheduledAlarms = [];
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      for (final alarmInfo in scheduledAlarms) {
        final parts = alarmInfo.split(':');
        if (parts.length >= 3) {
          final id = int.tryParse(parts[0]) ?? 0;
          final soundId = int.tryParse(parts[1]) ?? 1;
          final scheduledTime = int.tryParse(parts[2]) ?? 0;
          final nfcRequired = parts.length > 3 ? parts[3] == 'true' : false;

          if (scheduledTime < now && now - scheduledTime < 30 * 60 * 1000) {
            _startAlarmSoundService(id, soundId);

            if (Get.isRegistered<AlarmController>()) {
              final alarmController = Get.find<AlarmController>();
              alarmController.activeAlarmId.value = id;
            }

            break;
          } else if (scheduledTime > now) {
            final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
            scheduleAlarmNotification(
              id: id,
              scheduledTime: scheduledDateTime,
              soundId: soundId,
              nfcRequired: nfcRequired,
            );
          }
        }
      }

      final updatedScheduledAlarms = scheduledAlarms.where((alarmInfo) {
        final parts = alarmInfo.split(':');
        if (parts.length >= 3) {
          final scheduledTime = int.tryParse(parts[2]) ?? 0;
          return scheduledTime > now || (now - scheduledTime < 30 * 60 * 1000);
        }
        return false;
      }).toList();

      await prefs.setString('scheduled_alarms', json.encode(updatedScheduledAlarms));
    } catch (e) {
      debugPrint('Error checking for alarms after reboot: $e');
    }
  }


  /// Cancels a specific notification and cleans up associated resources

  static Future<void> cancelNotification(int id) async {
    try {
      _activeNotificationIds.remove(id);
      await flutterLocalNotificationsPlugin.cancel(id);
      await flutterLocalNotificationsPlugin.cancel(30000 + id);
      await flutterLocalNotificationsPlugin.cancel(20000 + id);

      if (Platform.isAndroid) {
        try {
          await const MethodChannel('com.example.alarm/background_channel')
              .invokeMethod('cancelNotification', {'alarmId': id});

          await const MethodChannel('com.example.alarm/background_channel')
              .invokeMethod('cancelExactAlarm', {'alarmId': id});

          await const MethodChannel('com.example.alarm/background_channel')
              .invokeMethod('forceStopService');
        } catch (e) {
          debugPrint('Error canceling native notification/alarm: $e');
        }
      }

      if (Platform.isAndroid) {
        try {
          await AndroidAlarmManager.cancel(id);
        } catch (e) {
          debugPrint('Error canceling AndroidAlarmManager alarm: $e');
        }
      }

      final player = _fallbackPlayers[id];
      if (player != null) {
        await player.stop();
        await player.dispose();
        _fallbackPlayers.remove(id);
      }

      if (Get.isRegistered<AlarmController>()) {
        final alarmController = Get.find<AlarmController>();
        if (alarmController.activeAlarmId.value == id) {
          await AlarmBackgroundService.stopAlarm();
        }
      }

      final prefs = await SharedPreferences.getInstance();

      final String? existingAlarmsJson = prefs.getString('scheduled_alarms');
      if (existingAlarmsJson != null && existingAlarmsJson.isNotEmpty) {
        try {
          List<String> alarms = [];

          if (existingAlarmsJson.startsWith('[') && existingAlarmsJson.endsWith(']')) {

            final List<dynamic> jsonList = json.decode(existingAlarmsJson);
            alarms = jsonList.map((item) => item.toString()).toList();
          } else {

            alarms = existingAlarmsJson.split(',').where((s) => s.isNotEmpty).toList();
          }

          final updatedAlarms = alarms.where((alarm) {
            final parts = alarm.split(':');
            return parts.isNotEmpty && parts[0] != id.toString();
          }).toList();

          await prefs.setString('scheduled_alarms', json.encode(updatedAlarms));
        } catch (e) {
          debugPrint('Error updating scheduled alarms: $e');
          await AlarmBackgroundService.removeScheduledAlarm(id);
        }
      }

      if (prefs.getInt('active_alarm_id') == id || prefs.getInt('flutter.active_alarm_id') == id) {
        await prefs.remove('active_alarm_id');
        await prefs.remove('active_alarm_sound');
        await prefs.remove('alarm_start_time');
        await prefs.remove('using_fallback_alarm');
        await prefs.remove('flutter.active_alarm_id');
        await prefs.remove('flutter.active_alarm_sound');
        await prefs.remove('flutter.alarm_start_time');
        await prefs.remove('flutter.using_fallback_alarm');
      }

      debugPrint('Successfully canceled notification and alarm with ID: $id');
    } catch (e) {
      debugPrint('Error canceling notification: $e');
    }
  }



  /// Cancels all notifications and cleans up resources
  static Future<void> cancelAllNotifications() async {
    try {
      _activeNotificationIds.clear();
      await flutterLocalNotificationsPlugin.cancelAll();

      for (final player in _fallbackPlayers.values) {
        await player.stop();
        await player.dispose();
      }
      _fallbackPlayers.clear();

      await AlarmBackgroundService.stopAlarm();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_alarm_id');
      await prefs.remove('active_alarm_sound');
      await prefs.remove('alarm_start_time');
      await prefs.remove('using_fallback_alarm');
      await prefs.setStringList('scheduled_alarms', []);
    } catch (e) {
      debugPrint('Error canceling all notifications: $e');
    }
  }

  /// Check if notifications are permitted
  static Future<bool> areNotificationsEnabled() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final bool? permitted = await androidPlugin.areNotificationsEnabled();
        return permitted ?? false;
      }

      if (Platform.isIOS) {
        final status = await Permission.notification.status;
        return status.isGranted;
      }

      return false;
    } catch (e) {
      debugPrint('Error checking notification permissions: $e');
      return false;
    }
  }

  /// Request notification permissions with improved implementation
  static Future<bool> requestPermissions() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      bool androidResult = false;
      if (androidPlugin != null) {
        androidResult =
            await androidPlugin.requestNotificationsPermission() ?? false;

        if (await _sdkVersionAtLeast(31)) {
          await androidPlugin.requestExactAlarmsPermission();
        }

        await Permission.notification.request();
        await Permission.scheduleExactAlarm.request();
        await Permission.ignoreBatteryOptimizations.request();
      }

      final iOSPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();

      final iosResult = await iOSPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            critical: true,
          ) ??
          false;

      final hasPermissions =
          androidResult || iosResult || await Permission.notification.isGranted;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_permissions', hasPermissions);

      return hasPermissions;
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
      return false;
    }
  }

  /// Check notification permissions and show dialog if needed
  static Future<bool> checkNotificationPermissions(BuildContext context) async {
    final hasPermissions = await areNotificationsEnabled();

    if (!hasPermissions) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Notification Permission Required'),
          content: const Text(
              'Alarms require notification permissions to work properly. Please enable notifications in your device settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await requestPermissions();
                if (Platform.isAndroid || Platform.isIOS) {
                  await openAppSettings();
                }
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }

    return hasPermissions;
  }
}