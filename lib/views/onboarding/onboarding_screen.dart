import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/onboarding/onboarding_controller.dart';
import 'components/onboarding_content.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final OnboardingController controller = Get.put(OnboardingController());

    return Scaffold(
      backgroundColor: Colors.white,
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