import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import '../../../controllers/alarm/alarm_controller.dart';
import '../../../controllers/nfc/nfc_controller.dart';

class AlarmStopWidget extends StatefulWidget {
  final int alarmId;

  const AlarmStopWidget({
    super.key,
    required this.alarmId,
  });

  @override
  State<AlarmStopWidget> createState() => _AlarmStopWidgetState();
}

class _AlarmStopWidgetState extends State<AlarmStopWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  final NFCController _nfcController = Get.put(NFCController());
  final AlarmController _alarmController = Get.put(AlarmController());
  final TextEditingController _backupCodeController = TextEditingController();

  final RxBool isVerifying = false.obs;
  final RxBool showErrorMessage = false.obs;
  final RxString errorMessage = ''.obs;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _startNfcVerification();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _nfcController.stopNfcScan();
    _backupCodeController.dispose();
    super.dispose();
  }

  /// start nfc verification
  Future<void> _startNfcVerification() async {
    isVerifying.value = true;
    showErrorMessage.value = false;

    if (!_nfcController.isNfcAvailable.value) {
      isVerifying.value = false;
      showErrorMessage.value = true;
      errorMessage.value =
          'NFC is not available on this device. Please use backup code.';
      return;
    }

    final success = await _nfcController.startAlarmVerification(widget.alarmId);

    if (success) {
      _alarmController.stopAlarm(widget.alarmId);
      Get.back();
    } else {
      isVerifying.value = false;
      showErrorMessage.value = true;
      errorMessage.value =
          'NFC verification failed. Please try again or use backup code.';
    }
  }

  /// verify backup code
  void _verifyBackupCode() {
    final code = _backupCodeController.text.trim();

    if (_nfcController.verifyBackupCode(code)) {
      _alarmController.stopAlarm(widget.alarmId);
      Navigator.of(context).pop(); // Close dialog
      Get.back();
    } else {
      showErrorMessage.value = true;
      errorMessage.value = 'Invalid backup code. Please try again.';

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid backup code. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// backup code info
  void _showBackupCodeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.85;

        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: SizedBox(
            width: dialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Can't turn off the alarm with the NFC tag? Enter your Turn Off KEY to disable the alarm.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You can also find this key on our website\nwww.example.com',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _backupCodeController,
                  decoration: InputDecoration(
                    hintText: 'Enter Turn Off Key',
                    hintStyle: GoogleFonts.inter(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _verifyBackupCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B1F41),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: Text(
                      'Turn Off Alarm',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {},
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: constraints.maxWidth * 0.06,
                    top: constraints.maxHeight * 0.02,
                  ),
                  child: GestureDetector(
                    onTap: _showBackupCodeDialog,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 36,
                          color: Colors.black,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Help!',
                          style: GoogleFonts.inter(
                            color: Colors.black,
                            fontSize: isSmallScreen ? 20 : 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: constraints.maxWidth * 0.6,
                                height: constraints.maxHeight * 0.4,
                                constraints: const BoxConstraints(
                                  maxWidth: 250,
                                  maxHeight: 320,
                                  minWidth: 180,
                                  minHeight: 240,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black,
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
                                      child: Obx(() => Icon(
                                            _nfcController
                                                    .verificationSuccess.value
                                                ? Icons.check_circle_outline
                                                : Icons.nfc_rounded,
                                            color: Colors.white,
                                            size: isSmallScreen ? 160 : 220,
                                          )),
                                    ),
                                    Align(
                                      alignment: Alignment.topCenter,
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                            top: constraints.maxHeight * 0.025),
                                        child: Obx(() => Text(
                                              _nfcController
                                                      .verificationSuccess.value
                                                  ? 'Success!'
                                                  : 'Scan to stop',
                                              style: GoogleFonts.inter(
                                                color: Colors.white,
                                                fontSize:
                                                    isSmallScreen ? 14 : 16,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            )),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Reactive shimmer effect
                              Obx(
                                () => _nfcController.verificationSuccess.value
                                    ? const SizedBox()
                                    : Positioned.fill(
                                        child: AnimatedBuilder(
                                          animation: _shimmerController,
                                          builder: (context, child) {
                                            return Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: const [
                                                    Colors.transparent,
                                                    Colors.white10,
                                                    Colors.white24,
                                                    Colors.white10,
                                                    Colors.transparent,
                                                  ],
                                                  stops: [
                                                    0.0,
                                                    _shimmerController.value -
                                                        0.2,
                                                    _shimmerController.value,
                                                    _shimmerController.value +
                                                        0.2,
                                                    1.0,
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: EdgeInsets.only(
                              top: constraints.maxHeight * 0.03,
                              left: constraints.maxWidth * 0.05,
                              right: constraints.maxWidth * 0.05,
                            ),
                            child: Container(
                              width: constraints.maxWidth * 0.9,
                              constraints: const BoxConstraints(
                                maxWidth: 320,
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Center(
                                child: Obx(() {
                                  return Text(
                                    showErrorMessage.value
                                        ? errorMessage.value
                                        : _nfcController.isVerifyingAlarm.value
                                            ? 'Hold your device near the NFC tag'
                                            : 'Press retry to scan again or use backup code',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: isSmallScreen ? 12 : 14,
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                          Obx(() {
                            if (!_nfcController.isVerifyingAlarm.value &&
                                !_nfcController.verificationSuccess.value) {
                              return Padding(
                                padding: EdgeInsets.only(
                                  top: constraints.maxHeight * 0.03,
                                ),
                                child: ElevatedButton(
                                  onPressed: _startNfcVerification,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isSmallScreen ? 20 : 30,
                                      vertical: isSmallScreen ? 12 : 15,
                                    ),
                                  ),
                                  child: Text(
                                    'Retry Scan',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: isSmallScreen ? 14 : 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              return const SizedBox();
                            }
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
