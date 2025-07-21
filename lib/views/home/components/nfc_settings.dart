import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../controllers/nfc/nfc_controller.dart';
import 'scan_nfc.dart';

class NfcSettingsWidget extends StatefulWidget {
  const NfcSettingsWidget({super.key});

  @override
  State<NfcSettingsWidget> createState() => _NfcSettingsWidgetState();
}

class _NfcSettingsWidgetState extends State<NfcSettingsWidget> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final NFCController _nfcController = Get.put(NFCController());

  @override
  void initState() {
    super.initState();
    _nfcController.checkIfNfcRegistered();
  }

  /// Handle add/remove NFC button tap
  void _handleNfcAction() async {
    if (_nfcController.hasRegisteredNfcTag.value) {
      // Show confirmation dialog before removing
      final confirmed = await _showRemoveConfirmationDialog();
      if (confirmed == true) {
        await _nfcController.removeAllNfcTags();
      }
    } else {
      // Check if NFC is available
      if (!_nfcController.isNfcAvailable.value) {
        Get.snackbar(
          'NFC Not Available',
          'Your device does not support NFC or NFC is disabled.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      // Double-check that no tag is registered
      await _nfcController.checkIfNfcRegistered();
      if (_nfcController.hasRegisteredNfcTag.value) {
        Get.snackbar(
          'NFC Tag Already Registered',
          'Please remove the existing NFC tag before registering a new one.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.amber[100],
          duration: const Duration(seconds: 3),
        );
        return;
      }

      // Navigate to add NFC screen using direct navigation with argument as int
      int tempAlarmId = DateTime.now().millisecondsSinceEpoch;

      // Using direct navigation to avoid type issues
      await Get.to(() => AddNFCWidget(alarmId: tempAlarmId));

      // Refresh state after returning
      _nfcController.checkIfNfcRegistered();
    }
  }

  /// Show confirmation dialog for removing NFC tag
  Future<bool?> _showRemoveConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Remove NFC Tag',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to remove all registered NFC tags? This will affect any alarms that require NFC to stop.',
            style: GoogleFonts.inter(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  color: Colors.grey,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Remove',
                style: GoogleFonts.inter(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 360;

    final horizontalPadding = screenWidth * 0.06;
    final verticalSpacing = screenHeight * 0.02;
    final iconSize = isSmallScreen ? 28.0 : 35.0;
    final titleFontSize = isSmallScreen ? 20.0 : 24.0;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.05, 1.0],
              colors: [
                Color(0xFFAF5B73), // Blue for top 10%
                Color(0xFFF5F5F5), // Light blue transition
                Color(0xFFF5F5F5), // Light grey for the rest
              ],
            ),
          ),
          child: SafeArea(
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
                          'assets/images/buy_nfc.png',
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                                              fontSize:
                                                  isSmallScreen ? 12 : 14),
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
                                height: 60,
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    final Uri url = Uri.parse(
                                        'https://earlyuptag.com/products/the-early-up%E2%84%A2-nfc-tag');
                                    try {
                                      if (!await launchUrl(
                                        url,
                                        mode: LaunchMode.externalApplication,
                                      )) {
                                        throw Exception(
                                            'Could not launch $url');
                                      }
                                    } catch (e) {
                                      if (kDebugMode) {
                                        print('Error launching URL: $e');
                                      }
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Could not open the store page'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 16),
                                  ),
                                  child: Text(
                                    'Purchase',
                                    style: GoogleFonts.interTight(
                                      color: Colors.white,
                                      fontSize: isSmallScreen ? 14 : 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: verticalSpacing),
                    Obx(() => Card(
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
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.max,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _nfcController
                                                      .hasRegisteredNfcTag.value
                                                  ? 'Remove NFC tag'
                                                  : 'Add NFC tag',
                                              style: GoogleFonts.interTight(
                                                  color: Colors.black,
                                                  fontSize: titleFontSize,
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            Text(
                                              _nfcController
                                                      .hasRegisteredNfcTag.value
                                                  ? 'Delete existing NFC tag'
                                                  : 'Add new NFC tag',
                                              style: GoogleFonts.inter(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.w400,
                                                  fontSize:
                                                      isSmallScreen ? 12 : 14),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(width: screenWidth * 0.03),
                                      Container(
                                        width: screenWidth * 0.12,
                                        height: screenWidth * 0.12,
                                        decoration: BoxDecoration(
                                          color: _nfcController
                                                  .hasRegisteredNfcTag.value
                                              ? Theme.of(context).primaryColor
                                              : const Color(0xFFFFDE59),
                                          borderRadius:
                                              BorderRadius.circular(30),
                                        ),
                                        child: Icon(
                                          _nfcController
                                                  .hasRegisteredNfcTag.value
                                              ? Icons.remove_circle
                                              : Icons.add_circle,
                                          color: _nfcController
                                                  .hasRegisteredNfcTag.value
                                              ? Colors.white
                                              : Colors.black,
                                          size: screenWidth * 0.07,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: verticalSpacing),
                                  SizedBox(
                                    height: 60,
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _handleNfcAction,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _nfcController
                                                .hasRegisteredNfcTag.value
                                            ? Theme.of(context).primaryColor
                                            : const Color(0xFFFFDE59),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(25),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12, horizontal: 16),
                                      ),
                                      child: Text(
                                        _nfcController.hasRegisteredNfcTag.value
                                            ? 'Remove'
                                            : 'Add NFC',
                                        style: GoogleFonts.interTight(
                                          color: _nfcController
                                                  .hasRegisteredNfcTag.value
                                              ? Colors.white
                                              : Colors.black87,
                                          fontSize: isSmallScreen ? 14 : 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
