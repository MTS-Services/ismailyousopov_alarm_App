import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/onboarding/onboarding_model.dart';

class OnboardingController extends GetxController {
  final RxInt currentPage = 0.obs;
  final VoidCallback onLastPageComplete;

  OnboardingController({
    required this.onLastPageComplete,
  });

  final List<OnboardingModel> pages = [
    OnboardingModel(
      image: 'assets/images/onboarding_1.png',
      description:
          'The app helps users to wake up by requiring them to scan an NFC tag to turn off the alarm. Encourages you to physically get out of bed and move, making it more effective in waking up.The app also includes a statistics feature that tracks the number of hours slept. Additionally, it offers other small functions to enhance the overall user experience',
      buttonText: 'Next',
      containerColor: const Color(0xffe0e3e7),
      buttonColor: const Color(0xFFEE8B60),
      title: '',
      imageWidth: 346,
      imageHeight: 346,
    ),
    OnboardingModel(
      image: 'assets/images/onboarding_2.png',
      title: 'NFC Technology',
      description:
          "Place an NFC tag wherever you need to go when you wake up, like the bathroom. Your alarm won't stop until you scan it!",
      buttonText: 'Next',
      containerColor: const Color(0xffe0e3e7),
      buttonColor: const Color(0xFFFFDE59),
      icon: Icons.nfc,
      imageWidth: 346,
      imageHeight: 300.5,
    ),
    OnboardingModel(
      image: 'assets/images/onboarding_3.png',
      title: 'Sleep Statistics',
      description:
          'Track your sleep effortlessly and gain insights into your sleep routine! View detailed statistics for the day, week, and last week, including total hours slept.',
      buttonText: 'Next',
      containerColor: const Color(0xfff1f4f8),
      buttonColor: const Color(0xFFFFB6C1),
      icon: Icons.nightlight_round_sharp,
      imageWidth: 346,
      imageHeight: 300.5,
    ),
    OnboardingModel(
      image: 'assets/images/onboarding_4.png',
      title: '',
      description:
          '1. All you need is an NFC tag, which you can order from our official website, find our website by going to settings and NFC.\n2. Once you have your NFC tag, On the main screen, tap the NFC icon to connect the tag.\n3. Set your alarm time: Choose the time you want to wake up and enable NFC.\nNow, when your alarm goes off in the morning, simply scan your NFC tag, and the alarm will stop.\nIts that simple!',
      buttonText: "Let's get started",
      containerColor: const Color(0xfff1f4f8),
      buttonColor: const Color(0xFFD9AC87),
      imageWidth: 346,
      imageHeight: 300,
    ),
  ];

  Future<void> nextPage() async {
    if (currentPage.value < pages.length - 1) {
      currentPage.value++;
    } else {
      onLastPageComplete();
    }
  }

  void previousPage() {
    if (currentPage.value > 0) {
      currentPage.value--;
    }
  }
}
