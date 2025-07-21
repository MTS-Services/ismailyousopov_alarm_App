import 'package:alarmapp/controllers/stats/stats_controller.dart';
import 'package:alarmapp/controllers/alarm/alarm_controller.dart';
import 'package:alarmapp/core/services/background_service.dart';
import 'package:alarmapp/core/shared_preferences/shared_prefs_manager.dart';
import 'package:alarmapp/views/home/components/alarm_edit.dart';
import 'package:alarmapp/views/home/components/alarm_history.dart';
import 'package:alarmapp/views/home/components/alarm_set_screen.dart';
import 'package:alarmapp/views/home/components/alarm_sounds.dart';
import 'package:alarmapp/views/home/components/app_version.dart';
import 'package:alarmapp/views/home/components/key.dart';
import 'package:alarmapp/views/home/components/scan_nfc.dart' show AddNFCWidget;
import 'package:alarmapp/views/home/components/stop_alarm.dart';
import 'package:alarmapp/views/home/components/nfc_settings.dart';
import 'package:alarmapp/core/services/notification_service.dart';
import 'package:alarmapp/views/home/components/sleep_history.dart';
import 'package:alarmapp/views/home/home_screen.dart';
import 'package:alarmapp/views/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarm/alarm.dart';
import 'core/constants/asset_constants.dart';
import 'core/database/database_helper.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  Get.put(SleepStatisticsController());
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Initialize the Alarm package
  await Alarm.init();

  final dbHelper = DatabaseHelper();
  await dbHelper.verifyDatabaseConnection();

  // ✅ SharedPreferences ডেটা সিঙ্ক করুন
  await SharedPrefsManager.syncAlarmDataWithDatabase();
  await SharedPrefsManager.validateAndFixDataIntegrity();

  // First check if there's an active alarm before initializing service
  final prefs = await SharedPreferences.getInstance();
  final activeAlarmId = prefs.getInt('flutter.active_alarm_id');

  // Only initialize service if there is an active alarm or we're launching from an alarm
  final bool shouldInitializeService = activeAlarmId != null;

  if (shouldInitializeService) {
    await AlarmBackgroundService.initializeService();
    await AlarmBackgroundService.initializeOnAppStart();
  }

  await NotificationService.initialize();

  // Check if onboarding is completed
  final hasCompletedOnboarding =
      prefs.getBool('hasCompletedOnboarding') ?? false;

  // Check if there's an active alarm - we'll handle navigation in HomeScreen
  final isAlarmActive = await AlarmBackgroundService.isAlarmActive();

  FlutterNativeSplash.remove();
  runApp(MyApp(
      hasCompletedOnboarding: hasCompletedOnboarding,
      hasActiveAlarm: isAlarmActive));
}

class MyApp extends StatelessWidget {
  final bool hasCompletedOnboarding;
  final bool hasActiveAlarm;

  const MyApp({
    super.key,
    this.hasCompletedOnboarding = false,
    this.hasActiveAlarm = false,
  });

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      initialBinding: BindingsBuilder(() {
        Get.put(DatabaseHelper());
        Get.put(AlarmBackgroundService());
        Get.put(NotificationService());
        Get.put(AlarmController());
      }),
      initialRoute:
          hasCompletedOnboarding ? AppConstants.home : AppConstants.home,
      getPages: [
        GetPage(
          name: AppConstants.onboarding,
          page: () => const OnboardingScreen(isFromAboutSection: false),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.home,
          page: () => const HomeScreen(),
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
            // Check for direct navigation from notification
            final Map<String, dynamic> args = Get.arguments ?? {};
            final int alarmId = args['alarmId'] ?? 0;
            final int soundId = args['soundId'] ?? 1;

            return AlarmStopScreen.fromArguments(
                args.isEmpty ? {'alarmId': alarmId, 'soundId': soundId} : args);
          },
          transition: Transition.fadeIn,
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
