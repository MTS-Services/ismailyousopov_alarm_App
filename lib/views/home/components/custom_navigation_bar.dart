import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CustomNavigationBar extends StatelessWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const CustomNavigationBar({
    Key? key,
    this.scaffoldKey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(32, 10, 32, 0),
      child: Material(
        color: Colors.transparent,
        elevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 1.079,
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
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            shape: BoxShape.rectangle,
          ),
          child: Align(
            alignment: const AlignmentDirectional(0, 0),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 24),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildNavItem(
                    icon: Icons.access_time_outlined,
                    size: 26,
                    onTap: () => Get.toNamed('/main-page'),
                  ),
                  _buildNavItem(
                    icon: Icons.nfc_outlined,
                    size: 25,
                    onTap: () => Get.toNamed('/nfc-scan'),
                  ),
                  _buildNavItem(
                    icon: Icons.query_stats_outlined,
                    size: 28,
                    onTap: () => Get.toNamed('/statistics'),
                  ),
                  _buildNavItem(
                    icon: FontAwesomeIcons.bars,
                    size: 22,
                    onTap: () => scaffoldKey?.currentState?.openDrawer(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
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