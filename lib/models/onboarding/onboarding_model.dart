import 'package:flutter/material.dart';

class OnboardingModel {
  final String image;
  final String title;
  final String description;
  final String buttonText;
  final Color containerColor;
  final Color buttonColor;
  final IconData? icon;
  final double imageWidth;
  final double imageHeight;

  OnboardingModel({
    required this.image,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.containerColor,
    required this.buttonColor,
    this.icon,
    required this.imageWidth,
    required this.imageHeight,
  });
}
