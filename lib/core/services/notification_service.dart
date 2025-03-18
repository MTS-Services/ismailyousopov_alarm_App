// import 'dart:async';
// import 'package:alarm/core/constants/asset_constants.dart';
// import 'package:alarm/core/services/sound_manager.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:timezone/data/latest.dart' as tz;
// import 'package:timezone/timezone.dart' as tz;
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'dart:typed_data';
// import '../../controllers/alarm/alarm_controller.dart';
// import 'alarm_background_service.dart';
//
// class NotificationService {
//   static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
//       FlutterLocalNotificationsPlugin();
//   static const String stopActionId = 'stop_alarm_action';
//
//   /// Initialize the notification service
//   static Future<void> initialize() async {
//     tz.initializeTimeZones();
//     const AndroidInitializationSettings initializationSettingsAndroid =
//         AndroidInitializationSettings('mipmap/ic_launcher');
//     const DarwinInitializationSettings initializationSettingsIOS =
//         DarwinInitializationSettings(
//       requestSoundPermission: true,
//       requestBadgePermission: true,
//       requestAlertPermission: true,
//     );
//     const InitializationSettings initializationSettings =
//         InitializationSettings(
//       android: initializationSettingsAndroid,
//       iOS: initializationSettingsIOS,
//     );
//     await flutterLocalNotificationsPlugin.initialize(
//       initializationSettings,
//       onDidReceiveNotificationResponse: onNotificationTap,
//       onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
//     );
//     await _cleanupAllNotificationChannels();
//     await requestPermissions();
//     await setupNotificationTriggerListener();
//   }
//
//   /// Setup a listener to start the background service when notifications are triggered
//   static Future<void> setupNotificationTriggerListener() async {
//     final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
//         flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
//             AndroidFlutterLocalNotificationsPlugin>();
//
//     if (androidPlugin != null) {
//       final bool? granted = await androidPlugin.areNotificationsEnabled();
//       if (granted != true) {
//         await androidPlugin.requestNotificationsPermission();
//       }
//     }
//
//     final NotificationAppLaunchDetails? launchDetails =
//         await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
//
//     if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
//       final String? payload = launchDetails.notificationResponse?.payload;
//       if (payload != null) {
//         final List<String> payloadParts = payload.split(':');
//         final int alarmId = int.tryParse(payloadParts[0]) ?? 0;
//         final int soundId =
//             payloadParts.length > 1 ? int.tryParse(payloadParts[1]) ?? 1 : 1;
//         _startAlarmSoundService(alarmId, soundId);
//       }
//     }
//   }
//
//   /// Clean up all notification channels to prevent duplicates
//   static Future<void> _cleanupAllNotificationChannels() async {
//     final channels = await flutterLocalNotificationsPlugin
//         .resolvePlatformSpecificImplementation<
//             AndroidFlutterLocalNotificationsPlugin>()
//         ?.getNotificationChannels();
//
//     for (final channel in channels ?? []) {
//       await flutterLocalNotificationsPlugin
//           .resolvePlatformSpecificImplementation<
//               AndroidFlutterLocalNotificationsPlugin>()
//           ?.deleteNotificationChannel(channel.id);
//     }
//   }
//
//   /// Create a notification channel for a specific sound
//   static Future<String> _createNotificationChannelForSound(int soundId) async {
//     final String androidSoundName =
//         SoundManager.getNotificationSoundName(soundId);
//
//     final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
//     final String channelId = 'alarm_channel_sound_${soundId}_$timestamp';
//     final String channelName =
//         'Alarm Sound: ${SoundManager.getSoundName(soundId)}';
//
//     final AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
//       channelId,
//       channelName,
//       description:
//           'Alarm notifications with sound: ${SoundManager.getSoundName(soundId)}',
//       importance: Importance.max,
//       playSound: true,
//       sound: RawResourceAndroidNotificationSound(androidSoundName),
//       enableVibration: true,
//       enableLights: true,
//     );
//
//     await flutterLocalNotificationsPlugin
//         .resolvePlatformSpecificImplementation<
//             AndroidFlutterLocalNotificationsPlugin>()
//         ?.createNotificationChannel(alarmChannel);
//
//     return channelId;
//   }
//
//   /// Handle notification tap events
//   static void onNotificationTap(NotificationResponse notificationResponse) {
//     final String? payload = notificationResponse.payload;
//     final String? actionId = notificationResponse.actionId;
//
//     if (payload == null) return;
//
//     final List<String> payloadParts = payload.split(':');
//     final int alarmId = int.tryParse(payloadParts[0]) ?? 0;
//
//     final int soundId =
//         payloadParts.length > 1 ? int.tryParse(payloadParts[1]) ?? 1 : 1;
//
//     _startAlarmSoundService(alarmId, soundId);
//
//     if (actionId == stopActionId || payload.isNotEmpty) {
//       final alarmController = Get.find<AlarmController>();
//       final alarm = alarmController.getAlarmById(alarmId);
//
//       if (alarm != null && alarm.nfcRequired) {
//         Get.toNamed(
//           AppConstants.nfcScan,
//           arguments: {'alarmId': alarmId},
//         );
//       } else {
//         Get.toNamed(
//           AppConstants.stopAlarm,
//           arguments: {'alarmId': alarmId},
//         );
//       }
//     }
//   }
//
//   /// Handle background notification tap events
//   @pragma('vm:entry-point')
//   static void notificationTapBackground(
//       NotificationResponse notificationResponse) {
//     final String? payload = notificationResponse.payload;
//
//     if (payload != null) {
//       final List<String> payloadParts = payload.split(':');
//       final int alarmId = int.tryParse(payloadParts[0]) ?? 0;
//       final int soundId =
//           payloadParts.length > 1 ? int.tryParse(payloadParts[1]) ?? 1 : 1;
//
//       AlarmBackgroundService.startAlarm(alarmId, soundId);
//     }
//   }
//
//   /// Schedule an alarm notification
//   static Future<void> scheduleAlarmNotification({
//     required int id,
//     required DateTime scheduledTime,
//     required int soundId,
//     required bool nfcRequired,
//     String? title,
//     String? body,
//     String? subtitle,
//   }) async {
//     try {
//       final String channelId =
//           await _createNotificationChannelForSound(soundId);
//       final String androidSoundName =
//           SoundManager.getNotificationSoundName(soundId);
//       final String iosSoundName = SoundManager.getIOSNotificationSound(soundId);
//
//       final List<AndroidNotificationAction> actions = [
//         const AndroidNotificationAction(
//           stopActionId,
//           'Stop Alarm',
//           showsUserInterface: true,
//         ),
//       ];
//
//       final bodyText = nfcRequired
//           ? 'Time to wake up! Scan your NFC tag to stop the alarm.'
//           : 'Time to wake up! Tap to stop the alarm.';
//
//       final Duration timeUntilAlarm = scheduledTime.difference(DateTime.now());
//       if (timeUntilAlarm.inSeconds > 0) {
//         Timer(timeUntilAlarm, () {
//           AlarmBackgroundService.startAlarm(id, soundId);
//         });
//       }
//
//       await flutterLocalNotificationsPlugin.zonedSchedule(
//         id,
//         title ?? 'Alarm',
//         body ?? bodyText,
//         tz.TZDateTime.from(scheduledTime, tz.local),
//         NotificationDetails(
//           android: AndroidNotificationDetails(
//             channelId,
//             'Alarm Sound: ${SoundManager.getSoundName(soundId)}',
//             channelDescription:
//                 'Alarm notifications with sound: ${SoundManager.getSoundName(soundId)}',
//             importance: Importance.max,
//             priority: Priority.high,
//             autoCancel: false,
//             ongoing: true,
//             playSound: false,
//             sound: RawResourceAndroidNotificationSound(androidSoundName),
//             category: AndroidNotificationCategory.alarm,
//             fullScreenIntent: true,
//             styleInformation: BigTextStyleInformation(
//               bodyText,
//               htmlFormatBigText: true,
//               contentTitle: 'Alarm',
//               htmlFormatContentTitle: true,
//               summaryText: 'Alarm notification',
//               htmlFormatSummaryText: true,
//             ),
//             actions: actions,
//             color: Colors.red,
//             colorized: true,
//             visibility: NotificationVisibility.public,
//           ),
//           iOS: DarwinNotificationDetails(
//             presentAlert: true,
//             presentSound: false,
//             sound: iosSoundName,
//             interruptionLevel: InterruptionLevel.critical,
//             threadIdentifier: 'alarm_thread',
//             subtitle:
//                 subtitle ?? (nfcRequired ? 'Scan NFC to stop' : 'Tap to stop'),
//             categoryIdentifier: 'alarm_category',
//           ),
//         ),
//         androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
//         uiLocalNotificationDateInterpretation:
//             UILocalNotificationDateInterpretation.absoluteTime,
//         payload: "$id:$soundId",
//       );
//     } catch (e) {
//       debugPrint('Error scheduling notification: $e');
//     }
//   }
//
//   /// Starts the background service to play alarm sound with the specified ID and sound.
//   static Future<void> _startAlarmSoundService(int alarmId, int soundId) async {
//     try {
//       await AlarmBackgroundService.startAlarm(alarmId, soundId);
//     } catch (e) {
//       debugPrint('Error starting alarm sound service: $e');
//       await flutterLocalNotificationsPlugin.show(
//         alarmId,
//         'Alarm',
//         'Time to wake up!',
//         NotificationDetails(
//           android: AndroidNotificationDetails(
//             'alarm_fallback_channel',
//             'Alarm Fallback Channel',
//             channelDescription: 'Used when background service fails',
//             importance: Importance.max,
//             priority: Priority.high,
//             enableVibration: true,
//             vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
//             fullScreenIntent: true,
//           ),
//           iOS: const DarwinNotificationDetails(
//             presentAlert: true,
//             presentSound: true,
//             interruptionLevel: InterruptionLevel.critical,
//           ),
//         ),
//       );
//     }
//   }
//
//   /// Cancel a specific notification
//   static Future<void> cancelNotification(int id) async {
//     await flutterLocalNotificationsPlugin.cancel(id);
//   }
//
//   /// Cancel all notifications
//   static Future<void> cancelAllNotifications() async {
//     await flutterLocalNotificationsPlugin.cancelAll();
//   }
//
//   /// Check if notifications are permitted
//   static Future<bool> areNotificationsEnabled() async {
//     final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
//         flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
//             AndroidFlutterLocalNotificationsPlugin>();
//     final bool? permitted = await androidPlugin?.areNotificationsEnabled();
//     return permitted ?? false;
//   }
//
//   /// Request notification permissions
//   static Future<void> requestPermissions() async {
//     final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
//         flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
//             AndroidFlutterLocalNotificationsPlugin>();
//     await androidPlugin?.requestNotificationsPermission();
//     await flutterLocalNotificationsPlugin
//         .resolvePlatformSpecificImplementation<
//             IOSFlutterLocalNotificationsPlugin>()
//         ?.requestPermissions(
//           alert: true,
//           badge: true,
//           sound: true,
//           critical: true,
//         );
//   }
// }

import 'dart:async';
import 'package:alarm/core/constants/asset_constants.dart';
import 'package:alarm/core/services/sound_manager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:typed_data';
import '../../controllers/alarm/alarm_controller.dart';
import 'alarm_background_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();
  static const String stopActionId = 'stop_alarm_action';
  // Add a list of channels that should not be deleted
  static const List<String> reservedChannels = ['alarm_foreground_service'];

  /// Initialize the notification service
  static Future<void> initialize() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
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
    // Clean up channels safely
    await _cleanupAllNotificationChannels();
    await requestPermissions();
    await setupNotificationTriggerListener();
  }

  /// Setup a listener to start the background service when notifications are triggered
  static Future<void> setupNotificationTriggerListener() async {
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
    await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();

    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      final String? payload = launchDetails.notificationResponse?.payload;
      if (payload != null) {
        final List<String> payloadParts = payload.split(':');
        final int alarmId = int.tryParse(payloadParts[0]) ?? 0;
        final int soundId =
        payloadParts.length > 1 ? int.tryParse(payloadParts[1]) ?? 1 : 1;
        _startAlarmSoundService(alarmId, soundId);
      }
    }
  }

  /// Clean up notification channels to prevent duplicates, but preserve active ones
  static Future<void> _cleanupAllNotificationChannels() async {
    try {
      final channels = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.getNotificationChannels();

      if (channels == null || channels.isEmpty) return;

      for (final channel in channels) {
        // Skip reserved channels to avoid the security exception
        if (reservedChannels.contains(channel.id)) {
          debugPrint('Skipping deletion of reserved channel: ${channel.id}');
          continue;
        }

        try {
          await flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
              ?.deleteNotificationChannel(channel.id);
        } catch (e) {
          // Log the error but continue with other channels
          debugPrint('Could not delete channel ${channel.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error in cleaning up notification channels: $e');
    }
  }

  /// Create a notification channel for a specific sound
  static Future<String> _createNotificationChannelForSound(int soundId) async {
    final String androidSoundName =
    SoundManager.getNotificationSoundName(soundId);

    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String channelId = 'alarm_channel_sound_${soundId}_$timestamp';
    final String channelName =
        'Alarm Sound: ${SoundManager.getSoundName(soundId)}';

    final AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
      channelId,
      channelName,
      description:
      'Alarm notifications with sound: ${SoundManager.getSoundName(soundId)}',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(androidSoundName),
      enableVibration: true,
      enableLights: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(alarmChannel);

    return channelId;
  }

  /// Handle notification tap events
  static void onNotificationTap(NotificationResponse notificationResponse) {
    final String? payload = notificationResponse.payload;
    final String? actionId = notificationResponse.actionId;

    if (payload == null) return;

    final List<String> payloadParts = payload.split(':');
    final int alarmId = int.tryParse(payloadParts[0]) ?? 0;

    final int soundId =
    payloadParts.length > 1 ? int.tryParse(payloadParts[1]) ?? 1 : 1;

    _startAlarmSoundService(alarmId, soundId);

    if (actionId == stopActionId || payload.isNotEmpty) {
      final alarmController = Get.find<AlarmController>();
      final alarm = alarmController.getAlarmById(alarmId);

      if (alarm != null && alarm.nfcRequired) {
        Get.toNamed(
          AppConstants.nfcScan,
          arguments: {'alarmId': alarmId},
        );
      } else {
        Get.toNamed(
          AppConstants.stopAlarm,
          arguments: {'alarmId': alarmId},
        );
      }
    }
  }

  /// Handle background notification tap events
  @pragma('vm:entry-point')
  static void notificationTapBackground(
      NotificationResponse notificationResponse) {
    final String? payload = notificationResponse.payload;

    if (payload != null) {
      final List<String> payloadParts = payload.split(':');
      final int alarmId = int.tryParse(payloadParts[0]) ?? 0;
      final int soundId =
      payloadParts.length > 1 ? int.tryParse(payloadParts[1]) ?? 1 : 1;

      AlarmBackgroundService.startAlarm(alarmId, soundId);
    }
  }

  /// Schedule an alarm notification
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
      final String channelId =
      await _createNotificationChannelForSound(soundId);
      final String androidSoundName =
      SoundManager.getNotificationSoundName(soundId);
      final String iosSoundName = SoundManager.getIOSNotificationSound(soundId);

      final List<AndroidNotificationAction> actions = [
        const AndroidNotificationAction(
          stopActionId,
          'Stop Alarm',
          showsUserInterface: true,
        ),
      ];

      final bodyText = nfcRequired
          ? 'Time to wake up! Scan your NFC tag to stop the alarm.'
          : 'Time to wake up! Tap to stop the alarm.';

      final Duration timeUntilAlarm = scheduledTime.difference(DateTime.now());
      if (timeUntilAlarm.inSeconds > 0) {
        Timer(timeUntilAlarm, () {
          AlarmBackgroundService.startAlarm(id, soundId);
        });
      }

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title ?? 'Alarm',
        body ?? bodyText,
        tz.TZDateTime.from(scheduledTime, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Alarm Sound: ${SoundManager.getSoundName(soundId)}',
            channelDescription:
            'Alarm notifications with sound: ${SoundManager.getSoundName(soundId)}',
            importance: Importance.max,
            priority: Priority.high,
            autoCancel: false,
            ongoing: true,
            playSound: false,
            sound: RawResourceAndroidNotificationSound(androidSoundName),
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            styleInformation: BigTextStyleInformation(
              bodyText,
              htmlFormatBigText: true,
              contentTitle: 'Alarm',
              htmlFormatContentTitle: true,
              summaryText: 'Alarm notification',
              htmlFormatSummaryText: true,
            ),
            actions: actions,
            color: Colors.red,
            colorized: true,
            visibility: NotificationVisibility.public,
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
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
    }
  }

  /// Starts the background service to play alarm sound with the specified ID and sound.
  static Future<void> _startAlarmSoundService(int alarmId, int soundId) async {
    try {
      await AlarmBackgroundService.startAlarm(alarmId, soundId);
    } catch (e) {
      debugPrint('Error starting alarm sound service: $e');
      await flutterLocalNotificationsPlugin.show(
        alarmId,
        'Alarm',
        'Time to wake up!',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'alarm_fallback_channel',
            'Alarm Fallback Channel',
            channelDescription: 'Used when background service fails',
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
            fullScreenIntent: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.critical,
          ),
        ),
      );
    }
  }

  /// Cancel a specific notification
  static Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  /// Check if notifications are permitted
  static Future<bool> areNotificationsEnabled() async {
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
    flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final bool? permitted = await androidPlugin?.areNotificationsEnabled();
    return permitted ?? false;
  }

  /// Request notification permissions
  static Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
    flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
      critical: true,
    );
  }
}