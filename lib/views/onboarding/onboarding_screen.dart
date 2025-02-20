import 'package:alarm/core/constants/asset_constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/onboarding/onboarding_controller.dart';
import 'components/onboarding_content.dart';

class OnboardingScreen extends StatelessWidget {
  final bool isFromAboutSection;

  const OnboardingScreen({
    super.key,
    this.isFromAboutSection = false,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OnboardingController(
      onLastPageComplete: () {
        if (isFromAboutSection) {
          Get.back();
          Get.toNamed(AppConstants.nfcSettings);
        } else {
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