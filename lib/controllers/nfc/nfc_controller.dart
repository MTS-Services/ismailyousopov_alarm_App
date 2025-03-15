import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NFCController extends GetxController {
  final RxBool isNfcAvailable = false.obs;
  final RxBool isScanning = false.obs;
  final RxString lastScannedTag = ''.obs;
  final RxString registeredAlarmTag = ''.obs;
  final RxBool isVerifyingAlarm = false.obs;
  final RxBool verificationSuccess = false.obs;

  /// Hard-coded backup code for now
  final String backupCode = '12345';

  @override
  void onInit() {
    super.onInit();
    checkNfcAvailability();
    loadRegisteredTag();
  }

  /// Check if NFC is available on the device
  Future<void> checkNfcAvailability() async {
    try {
      isNfcAvailable.value = await NfcManager.instance.isAvailable();
      debugPrint('NFC Available: ${isNfcAvailable.value}');
    } catch (e) {
      debugPrint('Error checking NFC availability: $e');
      isNfcAvailable.value = false;
    }
  }

  /// Save a registered tag for an alarm
  Future<void> saveTagForAlarm(String tagId, int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alarm_tag_$alarmId', tagId);
      registeredAlarmTag.value = tagId;
      debugPrint('Tag saved for alarm $alarmId: $tagId');
    } catch (e) {
      debugPrint('Error saving tag for alarm: $e');
    }
  }

  /// Load registered tag for a specific alarm
  Future<void> loadRegisteredTagForAlarm(int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      registeredAlarmTag.value = prefs.getString('alarm_tag_$alarmId') ?? '';
      debugPrint('Loaded tag for alarm $alarmId: ${registeredAlarmTag.value}');
    } catch (e) {
      debugPrint('Error loading registered tag for alarm $alarmId: $e');
    }
  }

  /// Load any registered tag (for initialization)
  Future<void> loadRegisteredTag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('alarm_tag_')) {
          registeredAlarmTag.value = prefs.getString(key) ?? '';
          debugPrint('Found registered tag: ${registeredAlarmTag.value}');
          break;
        }
      }
    } catch (e) {
      debugPrint('Error loading registered tag: $e');
    }
  }

  /// Start NFC scanning
  Future<void> startNfcScan({
    required Function(String) onTagDetected,
    required Function() onError,
  }) async {
    if (!isNfcAvailable.value) {
      debugPrint('NFC not available');
      onError();
      return;
    }

    isScanning.value = true;
    debugPrint('Starting NFC scan...');

    try {
      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          final id = _getTagId(tag);
          lastScannedTag.value = id;
          debugPrint('NFC tag detected: $id');
          onTagDetected(id);
          await NfcManager.instance.stopSession();
          isScanning.value = false;
        },
      );
    } catch (e) {
      debugPrint('Error starting NFC scan: $e');
      isScanning.value = false;
      onError();
    }
  }

  /// Stop NFC scanning
  Future<void> stopNfcScan() async {
    if (isScanning.value) {
      try {
        await NfcManager.instance.stopSession();
        isScanning.value = false;
        debugPrint('NFC scan stopped');
      } catch (e) {
        debugPrint('Error stopping NFC scan: $e');
      }
    }
  }

  /// Verify NFC tag for alarm
  Future<bool> verifyTagForAlarm(String scannedTagId, int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTagId = prefs.getString('alarm_tag_$alarmId') ?? '';
      final isVerified = savedTagId.isNotEmpty && savedTagId == scannedTagId;

      debugPrint('Verifying tag for alarm $alarmId:');
      debugPrint('  Scanned tag: $scannedTagId');
      debugPrint('  Saved tag: $savedTagId');
      debugPrint('  Verification result: $isVerified');

      return isVerified;
    } catch (e) {
      debugPrint('Error verifying tag for alarm: $e');
      return false;
    }
  }

  /// Verify backup code
  bool verifyBackupCode(String code) {
    final isValid = code == backupCode;
    debugPrint('Verifying backup code: $code, Valid: $isValid');
    return isValid;
  }

  /// Register a new NFC tag for an alarm
  Future<bool> registerTagForAlarm(int alarmId) async {
    if (!isNfcAvailable.value) {
      debugPrint('NFC not available for registration');
      return false;
    }

    try {
      isScanning.value = true;
      debugPrint('Starting NFC registration for alarm $alarmId...');

      final completer = Completer<bool>();

      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final id = _getTagId(tag);
            debugPrint('Tag detected during registration: $id');
            await saveTagForAlarm(id, alarmId);
            await NfcManager.instance.stopSession();
            isScanning.value = false;
            if (!completer.isCompleted) {
              completer.complete(true);
            }
          } catch (e) {
            debugPrint('Error processing tag during registration: $e');
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        },
      );

      /// Wait for tag detection or timeout after 60 seconds
      Timer(const Duration(seconds: 60), () {
        if (!completer.isCompleted) {
          stopNfcScan();
          debugPrint('NFC registration timed out');
          completer.complete(false);
        }
      });

      return completer.future;
    } catch (e) {
      debugPrint('Error registering NFC tag: $e');
      isScanning.value = false;
      return false;
    }
  }

  /// Start NFC verification process specifically for turning off an alarm
  Future<bool> startAlarmVerification(int alarmId) async {
    isVerifyingAlarm.value = true;
    verificationSuccess.value = false;
    await loadRegisteredTagForAlarm(alarmId);

    debugPrint('Starting alarm verification for alarm $alarmId');
    debugPrint('Looking for registered tag: ${registeredAlarmTag.value}');

    final completer = Completer<bool>();

    if (!isNfcAvailable.value) {
      debugPrint('NFC not available for verification');
      isVerifyingAlarm.value = false;
      completer.complete(false);
      return completer.future;
    }

    try {
      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final id = _getTagId(tag);
            lastScannedTag.value = id;
            debugPrint('Tag detected during verification: $id');

            final isVerified = await verifyTagForAlarm(id, alarmId);
            verificationSuccess.value = isVerified;

            await NfcManager.instance.stopSession();
            isScanning.value = false;
            isVerifyingAlarm.value = false;

            if (!completer.isCompleted) {
              completer.complete(isVerified);
            }
          } catch (e) {
            debugPrint('Error during tag verification: $e');
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        },
      );

      /// Set a timeout for the NFC scan
      Timer(const Duration(seconds: 60), () {
        if (!completer.isCompleted) {
          stopNfcScan();
          isVerifyingAlarm.value = false;
          debugPrint('NFC verification timed out');
          completer.complete(false);
        }
      });

      return completer.future;
    } catch (e) {
      debugPrint('Error verifying NFC tag for alarm: $e');
      isVerifyingAlarm.value = false;
      completer.complete(false);
      return completer.future;
    }
  }

  /// Helper method to extract tag ID from NFC tag
  String _getTagId(NfcTag tag) {
    /// Extract ID from different tag technologies
    if (tag.data.containsKey('nfca')) {
      final nfca = tag.data['nfca'];
      if (nfca != null && nfca['identifier'] != null) {
        return _bytesToHex(nfca['identifier']);
      }
    }

    if (tag.data.containsKey('nfcb')) {
      final nfcb = tag.data['nfcb'];
      if (nfcb != null && nfcb['applicationData'] != null) {
        return _bytesToHex(nfcb['applicationData']);
      }
    }

    if (tag.data.containsKey('ndef')) {
      final ndef = tag.data['ndef'];
      if (ndef != null && ndef['identifier'] != null) {
        return _bytesToHex(ndef['identifier']);
      }
    }

    /// Generate a unique tag ID from the raw data
    return tag.data.toString().hashCode.toString();
  }

  /// Helper method to convert bytes to hex string
  String _bytesToHex(List<int> bytes) {
    return bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':');
  }

  /// Method to reset verification state
  void resetVerification() {
    isVerifyingAlarm.value = false;
    verificationSuccess.value = false;
  }
}
