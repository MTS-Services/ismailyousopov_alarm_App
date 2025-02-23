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
          child: Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
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
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.black,
                      size: 35,
                    ),
                  ),
              const SizedBox(height: 20,),

              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/nfc_settings.png',
                  width: 320,
                  height: 162,
                  fit: BoxFit.cover,
                ),
              ),

                  const SizedBox(height: 10,),

                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      width: MediaQuery.of(context).size.width,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  mainAxisSize: MainAxisSize.max,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Buy NFC tag',
                                      style: GoogleFonts.interTight(
                                        color: Colors.black,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600
                                      ),
                                    ),
                                    Text(
                                      'Buy our official NFC tags',
                                      style: GoogleFonts.inter(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w400,
                                        fontSize: 14
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: const Icon(
                                    Icons.attach_money,
                                    color: Colors.black,
                                    size: 30,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () async {
                                if (kDebugMode) {
                                  print('Navigating to purchase URL');
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFDE59),
                                minimumSize: Size(MediaQuery.of(context).size.width, 50),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                              child: Text(
                                'Purchase',
                                style: GoogleFonts.interTight(
                                  color: Colors.black,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20,),

                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      width: MediaQuery.of(context).size.width,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  mainAxisSize: MainAxisSize.max,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isNfcAdded ? 'Remove NFC tag' : 'Add NFC tag',
                                      style: GoogleFonts.interTight(
                                        color: Colors.black,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600
                                      ),
                                    ),
                                    Text(
                                      isNfcAdded ? 'Delete existing NFC tag' : 'Add new NFC tag',
                                      style: GoogleFonts.inter(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w400,
                                        fontSize: 14
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: isNfcAdded ? Theme.of(context).primaryColor : const Color(0xFFFFDE59),
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Icon(
                                    isNfcAdded ? Icons.remove_circle : Icons.add_circle,
                                    color: isNfcAdded ? Colors.white : Colors.black,
                                    size: 30,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  isNfcAdded = !isNfcAdded;
                                });
                                if (kDebugMode) {
                                  print(isNfcAdded ? 'NFC Added' : 'NFC Removed');
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isNfcAdded ? Theme.of(context).primaryColor : const Color(0xFFFFDE59),
                                minimumSize: Size(MediaQuery.of(context).size.width, 50),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                              child: Text(
                                isNfcAdded ? 'Remove' : 'Add NFC',
                                style: GoogleFonts.interTight(
                                  color: isNfcAdded ? Colors.white : Colors.black,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600
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