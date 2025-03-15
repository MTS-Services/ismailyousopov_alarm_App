import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class NfcSettingsWidget extends StatefulWidget {
  const NfcSettingsWidget({super.key});

  @override
  State<NfcSettingsWidget> createState() => _NfcSettingsWidgetState();
}

class _NfcSettingsWidgetState extends State<NfcSettingsWidget> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool isNfcAdded = true;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 360;

    final horizontalPadding = screenWidth * 0.06;
    final verticalSpacing = screenHeight * 0.02;
    final iconSize = isSmallScreen ? 28.0 : 35.0;
    final titleFontSize = isSmallScreen ? 20.0 : 24.0;
    final buttonHeight = screenHeight * 0.06;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          top: true,
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalSpacing,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    splashColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    onTap: () {
                      Get.back();
                    },
                    child: Icon(
                      Icons.arrow_back,
                      color: Colors.black,
                      size: iconSize,
                    ),
                  ),
                  SizedBox(height: verticalSpacing),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/images/nfc_settings.png',
                        width: screenWidth * 0.85,
                        height: screenWidth * 0.43,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  SizedBox(height: verticalSpacing * 0.5),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(screenWidth * 0.05),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.max,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Buy NFC tag',
                                        style: GoogleFonts.interTight(
                                            color: Colors.black,
                                            fontSize: titleFontSize,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        'Buy our official NFC tags',
                                        style: GoogleFonts.inter(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w400,
                                            fontSize: isSmallScreen ? 12 : 14),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: screenWidth * 0.03),
                                Container(
                                  width: screenWidth * 0.14,
                                  height: screenWidth * 0.14,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Icon(
                                    Icons.attach_money,
                                    color: Colors.black,
                                    size: screenWidth * 0.08,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: verticalSpacing),
                            SizedBox(
                              height: buttonHeight,
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (kDebugMode) {
                                    print('Navigating to purchase URL');
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFDE59),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                ),
                                child: Text(
                                  'Purchase',
                                  style: GoogleFonts.interTight(
                                      color: Colors.black,
                                      fontSize: isSmallScreen ? 16 : 18,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: verticalSpacing),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(screenWidth * 0.05),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.max,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isNfcAdded
                                            ? 'Remove NFC tag'
                                            : 'Add NFC tag',
                                        style: GoogleFonts.interTight(
                                            color: Colors.black,
                                            fontSize: titleFontSize,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        isNfcAdded
                                            ? 'Delete existing NFC tag'
                                            : 'Add new NFC tag',
                                        style: GoogleFonts.inter(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w400,
                                            fontSize: isSmallScreen ? 12 : 14),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: screenWidth * 0.03),
                                Container(
                                  width: screenWidth * 0.12,
                                  height: screenWidth * 0.12,
                                  decoration: BoxDecoration(
                                    color: isNfcAdded
                                        ? Theme.of(context).primaryColor
                                        : const Color(0xFFFFDE59),
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Icon(
                                    isNfcAdded
                                        ? Icons.remove_circle
                                        : Icons.add_circle,
                                    color: isNfcAdded
                                        ? Colors.white
                                        : Colors.black,
                                    size: screenWidth * 0.07,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: verticalSpacing),
                            SizedBox(
                              height: buttonHeight,
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    isNfcAdded = !isNfcAdded;
                                  });
                                  if (kDebugMode) {
                                    print(isNfcAdded
                                        ? 'NFC Added'
                                        : 'NFC Removed');
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isNfcAdded
                                      ? Theme.of(context).primaryColor
                                      : const Color(0xFFFFDE59),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                ),
                                child: Text(
                                  isNfcAdded ? 'Remove' : 'Add NFC',
                                  style: GoogleFonts.interTight(
                                      color: isNfcAdded
                                          ? Colors.white
                                          : Colors.black,
                                      fontSize: isSmallScreen ? 16 : 18,
                                      fontWeight: FontWeight.w600),
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
          ),
        ),
      ),
    );
  }
}
