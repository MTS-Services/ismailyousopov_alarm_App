import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OnboardingButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color backgroundColor;

  const OnboardingButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.interTight(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.0,
          ),
        ),
      ),
    );
  }
}
