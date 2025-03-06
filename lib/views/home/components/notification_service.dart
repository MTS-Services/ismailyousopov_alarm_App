import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz.initializeTimeZones();

    // Android Notification Settings
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('mipmap/ic_launcher');

    // iOS Notification Settings
    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    // Combined Initialization Settings
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // Initialize the plugin
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onNotificationTap,
    );
  }

  // Handle notification when app is in foreground for iOS
  static void onDidReceiveLocalNotification(
      int id,
      String? title,
      String? body,
      String? payload
      ) async {
    // Handle foreground notifications for iOS
    debugPrint('Notification Received: $title');
  }

  // Handle notification tap
  static void onNotificationTap(NotificationResponse notificationResponse) {
    // Navigate to specific screen based on notification
    debugPrint('Notification Tapped: ${notificationResponse.payload}');
  }


  static Future<void> scheduleAlarmNotification({
    required int id,
    required DateTime scheduledTime,
    required int soundId,
    String? title,
    String? body,
  }) async {
    try {
      print('Scheduling notification: ID $id at $scheduledTime');
      print('Current time: ${DateTime.now()}');
      print('Scheduled time: $scheduledTime');
      print('Time difference: ${scheduledTime.difference(DateTime.now())}');
      print('Using sound_$soundId');

      // Validate the scheduled time is in the future
      if (scheduledTime.isBefore(DateTime.now())) {
        print('Warning: Scheduled time is in the past');
        scheduledTime = scheduledTime.add(Duration(days: 1));
        print('Adjusted scheduled time: $scheduledTime');
      }

      // Enhanced Android Platform Specifics for Persistent Alarm Notification
      final androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'alarm_channel',
        'Alarm Notifications',
        channelDescription: 'Persistent Alarm Notifications Requiring NFC Verification',
        importance: Importance.max,
        priority: Priority.high,
        autoCancel: false,
        showWhen: false,
        category: AndroidNotificationCategory.alarm,

        // Correctly reference the raw resource sound file
        sound: RawResourceAndroidNotificationSound('sound_$soundId'),
        playSound: true,

        visibility: NotificationVisibility.public,
      );

      final platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title ?? 'Alarm Active',
        body ?? 'Scan NFC tag to stop alarm',
        tz.TZDateTime.from(scheduledTime, tz.local),
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: id.toString(),
      );

      print('Persistent Notification successfully scheduled');
    } catch (e) {
      print('Comprehensive Error scheduling notification:');
      print('Error Details: $e');
      print('Error Type: ${e.runtimeType}');
    }
  }

  // Cancel a specific notification
  static Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  // Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}