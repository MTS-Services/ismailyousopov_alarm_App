import 'package:alarmapp/core/constants/asset_constants.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../controllers/home/home_controller.dart';

class CustomNavigationBar extends StatelessWidget {
  final controller = Get.put(HomeController());
  final VoidCallback onMenuTap;

  CustomNavigationBar({
    required this.onMenuTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    final horizontalPadding = screenWidth * 0.08;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 0),
      child: Material(
        color: Colors.transparent,
        elevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: Container(
          width: double.infinity,
          height: 70,
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                blurRadius: 4,
                color: Color(0x33000000),
                offset: Offset(0, 2),
              )
            ],
            borderRadius: BorderRadius.all(Radius.circular(20)),
            shape: BoxShape.rectangle,
          ),
          child: Align(
            alignment: const AlignmentDirectional(0, 0),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.04,
                vertical: 24,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  buildNavItem(
                    icon: Icons.access_time_outlined,
                    size: 26,
                    onTap: () => Get.toNamed(AppConstants.alarmHistory),
                  ),
                  buildNavItem(
                    icon: Icons.nfc_outlined,
                    size: 25,
                    onTap: () => Get.toNamed(AppConstants.nfcScan),
                  ),
                  buildNavItem(
                    icon: Icons.query_stats_outlined,
                    size: 28,
                    onTap: () => Get.toNamed(AppConstants.sleepHistory),
                  ),
                  buildNavItem(
                    icon: FontAwesomeIcons.bars,
                    size: 22,
                    onTap: () => controller.openDrawer(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildNavItem({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
  }) {
    return InkWell(
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: onTap,
      child: Icon(
        icon,
        color: Get.theme.textTheme.bodyLarge?.color,
        size: size,
      ),
    );
  }
}