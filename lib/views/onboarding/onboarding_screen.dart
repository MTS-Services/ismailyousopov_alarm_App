import 'package:alarm/core/constants/asset_constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/onboarding/onboarding_controller.dart';
import 'components/onboarding_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatelessWidget {
  final bool isFromAboutSection;

  const OnboardingScreen({
    super.key,
    this.isFromAboutSection = false,
  });

  Future<void> _completeOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('hasCompletedOnboarding', true);
  Get.offAllNamed(AppConstants.home); // Navigate to home screen
}

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OnboardingController(
      onLastPageComplete: () {
        if (isFromAboutSection) {
          Get.back();
          Get.toNamed(AppConstants.nfcSettings);
        } else {
          _completeOnboarding();
          Get.offAllNamed(AppConstants.home);
        }
      },
    ));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Obx(
              () => OnboardingContent(
            model: controller.pages[controller.currentPage.value],
            onNext: () => controller.nextPage(),
            onBack: () => controller.previousPage(),
            showBackButton: controller.currentPage.value > 0,
          ),
        ),
      ),
    );
  }
}