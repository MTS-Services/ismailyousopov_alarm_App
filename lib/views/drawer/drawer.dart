import 'package:alarmapp/views/onboarding/onboarding_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/asset_constants.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 305,
      child: Drawer(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 14,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0, 59, 0, 0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(22, 0, 0, 0),
                    child: Container(
                      width: 120,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: InkWell(
                        onTap: () {
                          Get.toNamed(AppConstants.nfcSettings);
                        },
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0, 0, 0, 15),
                                child: Icon(
                                  Icons.nfc_rounded,
                                  color: Theme.of(context).primaryColor,
                                  size: 35,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0, 0, 0, 15),
                                child: Text(
                                  'NFC',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 0, 0),
                    child: Container(
                      width: 120,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: InkWell(
                        onTap: () {
                          Get.toNamed(AppConstants.alarmSounds);
                        },
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0, 0, 0, 15),
                                child: FaIcon(
                                  FontAwesomeIcons.music,
                                  color: Theme.of(context).primaryColor,
                                  size: 35,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0, 0, 0, 15),
                                child: Text(
                                  'Alarm',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0, 6, 0, 0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(22, 0, 0, 0),
                    child: Container(
                      width: 120,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: InkWell(
                        onTap: () {},
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0, 0, 0, 15),
                                child: Icon(
                                  Icons.public,
                                  color: Theme.of(context).primaryColor,
                                  size: 35,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0, 0, 0, 15),
                                child: Text(
                                  'Language',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 0, 0),
                    child: Container(
                      width: 120,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: InkWell(
                        onTap: () {
                          Get.toNamed(AppConstants.sleepHistory);
                        },
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0, 0, 0, 15),
                                child: Icon(
                                  Icons.query_stats_rounded,
                                  color: Theme.of(context).primaryColor,
                                  size: 35,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0, 0, 0, 15),
                                child: Text(
                                  'Statistics',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              thickness: 2,
              color: Color(0xFFCBCED6),
            ),
            ListTile(
              leading: const Icon(Icons.info_outlined),
              title: Text(
                'About the app',
                style: GoogleFonts.inter(
                  fontSize: 20,
                ),
              ),
              onTap: () {
                Get.to(const OnboardingScreen(
                  isFromAboutSection: true,
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: Text(
                'App version',
                style: GoogleFonts.inter(
                  fontSize: 20,
                ),
              ),
              onTap: () => Get.toNamed(AppConstants.appVersion),
            ),
            ListTile(
              leading: const Icon(Icons.polyline_sharp),
              title: Text(
                'Privacy Policy',
                style: GoogleFonts.inter(
                  fontSize: 20,
                ),
              ),
              onTap: () async {
                final Uri url = Uri.parse(
                    'https://earlyuptag.com/policies/privacy-policy');
                try {
                  if (!await launchUrl(
                    url,
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw Exception('Could not launch $url');
                  }
                } catch (e) {
                  if (kDebugMode) {
                    print('Error launching URL: $e');
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not open the Privacy Policy page'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.handsHelping),
              title: Text(
                'Help',
                style: GoogleFonts.inter(
                  fontSize: 20,
                ),
              ),
              onTap: () async {
                final Uri url = Uri.parse(
                    'https://earlyuptag.com/pages/contact');
                try {
                  if (!await launchUrl(
                    url,
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw Exception('Could not launch $url');
                  }
                } catch (e) {
                  if (kDebugMode) {
                    print('Error launching URL: $e');
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not open the Help page'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
