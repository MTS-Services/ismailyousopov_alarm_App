import 'package:alarm/views/home/components/alarm_edit.dart';
import 'package:alarm/views/home/components/alarm_history.dart';
import 'package:alarm/views/home/components/alarm_set_screen.dart';
import 'package:alarm/views/home/components/alarm_sounds.dart';
import 'package:alarm/views/home/components/app_version.dart';
import 'package:alarm/views/home/components/key.dart';
import 'package:alarm/views/home/components/stop_alarm.dart';
import 'package:alarm/views/home/components/nfc_settings.dart';
import 'package:alarm/core/services/notification_service.dart';
import 'package:alarm/views/home/components/sleep_history.dart';
import 'package:alarm/views/home/components/scan_nfc.dart';
import 'package:alarm/views/home/home_screen.dart';
import 'package:alarm/views/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'controllers/alarm/alarm_controller.dart';
import 'core/constants/asset_constants.dart';
import 'core/database/database_helper.dart';
import 'core/services/background_service.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlarmBackgroundService.fixCorruptedScheduledAlarms();

  await AndroidAlarmManager.initialize();

  await NotificationService.initialize();

  await AlarmBackgroundService.initializeService();

  String initialRoute = AppConstants.onboarding;
  int? launchAlarmId;
  int? launchSoundId;
  bool directToStop = false;
  bool hadActiveAlarm = await checkAndCleanupStaleAlarms();

  if (!hadActiveAlarm) {
    await NotificationService.clearStaleNotifications();
    await AlarmBackgroundService.recoverActiveAlarmsOnRestart();
  }

  AlarmBackgroundService.startServiceHealthCheck();
  final prefs = await SharedPreferences.getInstance();
  final fromAction = prefs.getBool('flutter.from_notification_action') ?? false;
  final pendingAlarmId = prefs.getInt('flutter.pending_alarm_id');
  final pendingSoundId = prefs.getInt('flutter.pending_sound_id');
  final pendingDirectToStop = prefs.getBool('flutter.direct_to_stop') ?? false;

  if (fromAction && pendingAlarmId != null) {
    initialRoute = AppConstants.stopAlarm;
    launchAlarmId = pendingAlarmId;
    launchSoundId = pendingSoundId ?? 1;
    directToStop = pendingDirectToStop;

    await prefs.remove('flutter.from_notification_action');
    await prefs.remove('flutter.pending_alarm_id');
    await prefs.remove('flutter.pending_sound_id');
    await prefs.remove('flutter.direct_to_stop');

    await AlarmBackgroundService.forceStartAlarmIfNeeded(pendingAlarmId, pendingSoundId ?? 1);

    debugPrint('App launched from notification action: ID=$pendingAlarmId, Sound=$pendingSoundId, DirectToStop=$pendingDirectToStop');
  }

  final notificationAppLaunchDetails = await NotificationService
      .flutterLocalNotificationsPlugin
      .getNotificationAppLaunchDetails();

  if (notificationAppLaunchDetails?.didNotificationLaunchApp == true && launchAlarmId == null) {
    final payload = notificationAppLaunchDetails?.notificationResponse?.payload;
    if (payload != null) {
      final parts = payload.split(':');
      if (parts.length >= 2) {
        final alarmId = int.tryParse(parts[0]) ?? 0;
        final soundId = int.tryParse(parts[1]) ?? 1;

        initialRoute = AppConstants.stopAlarm;
        launchAlarmId = alarmId;
        launchSoundId = soundId;
        directToStop = true;

        await AlarmBackgroundService.forceStartAlarmIfNeeded(alarmId, soundId);

        debugPrint('App launched from notification: ID=$alarmId, Sound=$soundId');
      }
    }
  }

  const platform = MethodChannel('com.example.alarm/background_channel');
  try {
    final Map<dynamic, dynamic>? alarmData =
    await platform.invokeMethod('getAlarmLaunchData');

    if (alarmData != null && alarmData.containsKey('alarmId') && alarmData['fromAlarm'] == true && launchAlarmId == null) {
      final int alarmId = alarmData['alarmId'];
      final int soundId = alarmData['soundId'] ?? 1;
      final bool directToStopScreen = alarmData['directToStop'] ?? false;

      initialRoute = AppConstants.stopAlarm;
      launchAlarmId = alarmId;
      launchSoundId = soundId;
      directToStop = directToStopScreen;

      await AlarmBackgroundService.forceStartAlarmIfNeeded(alarmId, soundId);

      debugPrint('App launched from alarm: ID=$alarmId, Sound=$soundId, DirectToStop=$directToStopScreen');
    }
  } catch (e) {
    debugPrint('Error getting alarm launch data: $e');
  }

  FlutterNativeSplash.preserve(
      widgetsBinding: WidgetsFlutterBinding.ensureInitialized());

  final dbHelper = DatabaseHelper();
  await dbHelper.verifyDatabaseConnection();

  FlutterNativeSplash.remove();
  runApp(MyApp(
    initialRoute: initialRoute,
    launchAlarmId: launchAlarmId,
    launchSoundId: launchSoundId,
    directToStop: directToStop,
  ));
}


Future<bool> checkAndCleanupStaleAlarms() async {
  final prefs = await SharedPreferences.getInstance();
  final activeAlarmId = prefs.getInt('active_alarm_id');
  final startTime = prefs.getInt('alarm_start_time');

  if (activeAlarmId != null && startTime != null) {
    final alarmAge = DateTime.now().millisecondsSinceEpoch - startTime;

    if (alarmAge > 30 * 60 * 1000) {
      debugPrint('Found stale alarm, performing emergency cleanup');
      await AlarmBackgroundService.emergencyStopAllAlarms();
      return true;
    }

    final alarmController = Get.put(AlarmController());
    final alarm = alarmController.getAlarmById(activeAlarmId);

    if (alarm == null || !alarm.isEnabled) {
      debugPrint('Found invalid alarm, performing emergency cleanup');
      await AlarmBackgroundService.emergencyStopAllAlarms();
      return true;
    }
  }

  return false;
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  final int? launchAlarmId;
  final int? launchSoundId;
  final bool directToStop;

  const MyApp({
    super.key,
    this.initialRoute = AppConstants.onboarding,
    this.launchAlarmId,
    this.launchSoundId,
    this.directToStop = false,
  });

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      initialRoute: initialRoute,
      getPages: [
        GetPage(
          name: AppConstants.onboarding,
          page: () => const OnboardingScreen(isFromAboutSection: false),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.home,
          page: () => HomeScreen(),
          transition: Transition.fadeIn,
        ),
        GetPage(
          name: AppConstants.setAlarm,
          page: () => const AlarmSetScreen(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.alarmHistory,
          page: () => const AlarmHistoryWidget(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.alarmEdit,
          page: () => const AlarmEditScreen(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.alarmSounds,
          page: () => const AlarmSoundsWidget(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.sleepHistory,
          page: () => const SleepHistoryWidget(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.nfcScan,
          page: () {
            final Map<String, dynamic> args = Get.arguments ?? {};
            final int alarmId = args['alarmId'] ?? 0;
            return AddNFCWidget(alarmId: alarmId);
          },
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.stopAlarm,
          page: () {
            final Map<String, dynamic> args = Get.arguments ?? {};
            final int alarmId = args['alarmId'] ?? launchAlarmId ?? 0;
            final int soundId = args['soundId'] ?? launchSoundId ?? 1;
            return AlarmStopWidget(
              alarmId: alarmId,
              soundId: soundId,
            );
          },
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.key,
          page: () => const KeyWidget(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.nfcSettings,
          page: () => const NfcSettingsWidget(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.appVersion,
          page: () => const VersionInfoWidget(),
          transition: Transition.rightToLeft,
        ),
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}
