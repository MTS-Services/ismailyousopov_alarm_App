import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

class LocalNotificationController extends GetxController {
  static LocalNotificationController get to => Get.find();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final RxBool _hasPermission = false.obs;
  bool get hasPermission => _hasPermission.value;

  @override
  void onInit() {
    super.onInit();
    initializeIOSNotifications();
  }

  // 📌 iOS Notification Setup
  Future<void> initializeIOSNotifications() async {
    debugPrint("Initializing iOS Notifications...");

    const DarwinInitializationSettings iosInitialization = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      iOS: iosInitialization,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onNotificationResponse,
    );

    await requestIOSPermissions();
  }

  void onNotificationResponse(NotificationResponse response) {
    debugPrint('🔔 Notification tapped: ${response.payload}');
  }

  // 📌 iOS Notification Permission Request
  Future<void> requestIOSPermissions() async {
    if (Platform.isIOS) {
      final iosPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint("🔐 Notification permission granted: $granted");
      _hasPermission.value = granted ?? false;
    }
  }

  // 📌 Show Notification
  Future<void> showSimpleNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    debugPrint("🎯 Showing notification with title: $title");

    if (!hasPermission) {
      debugPrint("⚠️ No permission. Requesting...");
      await requestIOSPermissions();
      if (!hasPermission) {
        debugPrint("❌ Permission still not granted.");
        return;
      }
    }

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      iOS: iosDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    debugPrint("📤 Notification ID: $id");

    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
    debugPrint("🗑️ All notifications cancelled.");
  }
}
