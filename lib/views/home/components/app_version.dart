import 'package:alarmapp/core/constants/asset_constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class VersionInfoWidget extends StatelessWidget {
  const VersionInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    final backIconSize = screenWidth * 0.08;
    final fontSize = screenWidth * 0.07;
    final edgePadding = screenWidth * 0.06;
    final bottomPadding = screenHeight * 0.06;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Positioned(
                    top: constraints.maxHeight * 0.02,
                    left: edgePadding,
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        size: backIconSize.clamp(24.0, 40.0), // Min/max sizes
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      onPressed: () => Get.toNamed(AppConstants.home),
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      padding: EdgeInsets.all(screenWidth * 0.01),
                      constraints: const BoxConstraints(
                        minWidth: 44.0,
                        minHeight: 44.0,
                      ),
                    ),
                  ),

                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [],
                    ),
                  ),

                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomPadding),
                      child: Text(
                        'App version 1.0',
                        style: GoogleFonts.inter(
                          fontSize: fontSize.clamp(18.0, 36.0),
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
