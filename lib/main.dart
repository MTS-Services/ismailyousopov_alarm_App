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
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';
import 'core/constants/asset_constants.dart';
import 'core/database/database_helper.dart';
import 'core/services/alarm_background_service.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  final dbHelper = DatabaseHelper();
  await dbHelper.verifyDatabaseConnection();
  await AlarmBackgroundService.initializeService();
  await NotificationService.initialize();
  FlutterNativeSplash.remove();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      initialRoute: AppConstants.onboarding,
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
            final int alarmId =
                args['alarmId'] ?? 0; // Default value or handle missing case
            return AddNFCWidget(alarmId: alarmId);
          },
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.stopAlarm,
          page: () {
            final Map<String, dynamic> args = Get.arguments ?? {};
            final int alarmId = args['alarmId'] ?? 0;
            return AlarmStopWidget(alarmId: alarmId);
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
