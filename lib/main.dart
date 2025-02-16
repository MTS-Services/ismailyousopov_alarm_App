import 'package:alarm/views/home/components/alarm_history.dart';
import 'package:alarm/views/home/components/alarm_set_screen.dart';
import 'package:alarm/views/home/components/alarm_sounds.dart';
import 'package:alarm/views/home/home_screen.dart';
import 'package:alarm/views/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/asset_constants.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final bool hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

  runApp(MyApp(hasSeenOnboarding: hasSeenOnboarding));
}

class MyApp extends StatelessWidget {
  final bool hasSeenOnboarding;

  const MyApp({
    super.key,
    required this.hasSeenOnboarding,
  });

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      initialRoute: AppConstants.onboarding,

      getPages: [
        GetPage(
          name: AppConstants.onboarding,
          page: () => const OnboardingScreen(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppConstants.home,
          page: () => const HomeScreen(),
          transition: Transition.fadeIn,
        ),
        GetPage(
          name: '/alarm-set',
          page: () => const AlarmSetScreen(),
          transition: Transition.rightToLeft,
          transitionDuration: const Duration(milliseconds: 250),
        ),
        GetPage(
          name: '/alarm-history',
          page: () => const AlarmHistoryWidget(),
          transition: Transition.rightToLeft,
          transitionDuration: const Duration(milliseconds: 250),
        ),
        GetPage(
          name: '/alarm-sound',
          page: () => const AlarmSoundsWidget(),
          transition: Transition.rightToLeft,
          transitionDuration: const Duration(milliseconds: 250),
        ),
        // GetPage(
        //   name: AppConstants.settings,
        //   page: () => const SettingsScreen(),
        //   transition: Transition.rightToLeft,
        // ),
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}
