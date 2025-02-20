import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/onboarding/onboarding_model.dart';
import 'onboarding_button.dart';

class OnboardingContent extends StatelessWidget {
  final OnboardingModel model;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final bool showBackButton;

  const OnboardingContent({
    super.key,
    required this.model,
    required this.onNext,
    required this.onBack,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            if (showBackButton)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, size: 35),
                  onPressed: onBack,
                  color: Colors.black,
                ),
              ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                model.image,
                width: model.imageWidth,
                height: model.imageHeight,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: model.containerColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (model.icon != null) ...[
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: model.buttonColor,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        model.icon,
                        size: 32,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (model.title.isNotEmpty) ...[
                    Text(
                      model.title,
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    model.description,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.black,
                      letterSpacing: 0.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            OnboardingButton(
              text: model.buttonText,
              onPressed: onNext,
              backgroundColor: model.buttonColor,
            ),
          ],
        ),
      ),
    );
  }
}
