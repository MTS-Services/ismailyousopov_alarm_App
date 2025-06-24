import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../controllers/nfc/nfc_controller.dart';

class AddNFCWidget extends StatefulWidget {
  final int alarmId;

  const AddNFCWidget({
    super.key,
    required this.alarmId,
  });

  @override
  State<AddNFCWidget> createState() => _AddNFCWidgetState();
}

class _AddNFCWidgetState extends State<AddNFCWidget>
    with SingleTickerProviderStateMixin {
  final NFCController _nfcController = Get.put(NFCController());
  late AnimationController _shimmerController;
  bool _registrationSuccess = false;
  bool _showError = false;
  String _errorMessage = '';
  bool _isAlreadyRegistered = false;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _checkExistingTag();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _nfcController.stopNfcScan();
    super.dispose();
  }

  /// Check if a tag is already registered for this alarm
  Future<void> _checkExistingTag() async {
    // Check if any NFC tag is registered system-wide
    await _nfcController.checkIfNfcRegistered();

    if (_nfcController.hasRegisteredNfcTag.value) {
      setState(() {
        _isAlreadyRegistered = true;
        _registrationSuccess = true;
      });
    } else {
      _startNfcRegistration();
    }
  }

  /// nfc registration
  Future<void> _startNfcRegistration() async {
    setState(() {
      _registrationSuccess = false;
      _showError = false;
    });

    if (!_nfcController.isNfcAvailable.value) {
      // setState(() {
      //   _showError = true;
      //   _errorMessage = 'NFC is not available on this device.';
      // });
      return;
    }

    try {
      final success = await _nfcController.registerTagForAlarm(widget.alarmId);

      if (success) {
        setState(() {
          _registrationSuccess = true;
        });

        // Update the global registered tag status
        _nfcController.hasRegisteredNfcTag.value = true;

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Get.back(result: true);
          }
        });
      } else {
        setState(() {
          _showError = true;
          _errorMessage = 'Failed to register NFC tag. Please try again.';
        });
      }
    } catch (e) {
      debugPrint('Exception during NFC registration: $e');
      setState(() {
        _showError = true;
        _errorMessage = 'An error occurred. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
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
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                _nfcController.stopNfcScan();
                Get.back();
              },
            ),
            title: Text(
              _isAlreadyRegistered ? 'NFC Tag Registered' : 'Register NFC Tag',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // NFC icon container
                        Stack(
                          children: [
                            Container(
                              width: 224,
                              height: 300,
                              decoration: BoxDecoration(
                                color: _registrationSuccess
                                    ? Colors.green
                                    : Colors.white,
                                boxShadow: const [
                                  BoxShadow(
                                    blurRadius: 4,
                                    color: Color(0xFF040000),
                                    offset: Offset(0, 2),
                                  )
                                ],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Stack(
                                children: [
                                  Align(
                                    alignment: Alignment.center,
                                    child: Icon(
                                      _registrationSuccess
                                          ? Icons.check_circle_outline
                                          : Icons.nfc_rounded,
                                      color: _registrationSuccess
                                          ? Colors.white
                                          : Colors.black,
                                      size: 220,
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.topCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 22),
                                      child: Text(
                                        _registrationSuccess
                                            ? _isAlreadyRegistered
                                                ? 'NFC Tag Already Registered!'
                                                : 'Tag Registered!'
                                            : 'Ready to scan',
                                        style: GoogleFonts.inter(
                                          color: _registrationSuccess
                                              ? Colors.white
                                              : Colors.black,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_registrationSuccess)
                              Positioned.fill(
                                child: AnimatedBuilder(
                                  animation: _shimmerController,
                                  builder: (context, child) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: const [
                                            Colors.transparent,
                                            Colors.black12,
                                            Colors.black26,
                                            Colors.black12,
                                            Colors.transparent,
                                          ],
                                          stops: [
                                            0.0,
                                            _shimmerController.value - 0.2,
                                            _shimmerController.value,
                                            _shimmerController.value + 0.2,
                                            1.0,
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),

                        Padding(
                          padding: const EdgeInsets.only(top: 22),
                          child: Container(
                            width: 300,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _showError ? Colors.red : Colors.black,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                    right: 15, left: 5, top: 5, bottom: 5),
                                child: Text(
                                  _showError
                                      ? _errorMessage
                                      : _registrationSuccess
                                          ? _isAlreadyRegistered
                                              ? 'An NFC tag is already registered'
                                              : 'NFC tag registered successfully!'
                                          : 'Hold your device near the NFC tag to register',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        if (_showError)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: ElevatedButton(
                              onPressed: _startNfcRegistration,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 50, vertical: 15),
                              ),
                              child: Text(
                                'Try Again',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                        // if (_isAlreadyRegistered)
                        //   Padding(
                        //     padding: const EdgeInsets.only(top: 20),
                        //     child: ElevatedButton(
                        //       onPressed: () {
                        //         _nfcController.stopNfcScan();
                        //         Get.back();
                        //       },
                        //       style: ElevatedButton.styleFrom(
                        //         backgroundColor: Colors.blue,
                        //         shape: RoundedRectangleBorder(
                        //           borderRadius: BorderRadius.circular(25),
                        //         ),
                        //         padding: const EdgeInsets.symmetric(
                        //             horizontal: 30, vertical: 15),
                        //       ),
                        //       child: Text(
                        //         'OK',
                        //         style: GoogleFonts.inter(
                        //           color: Colors.white,
                        //           fontSize: 16,
                        //           fontWeight: FontWeight.w600,
                        //         ),
                        //       ),
                        //     ),
                        //   ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
