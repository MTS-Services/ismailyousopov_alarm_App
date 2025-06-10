import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NFCController extends GetxController {
  final RxBool isNfcAvailable = false.obs;
  final RxBool isScanning = false.obs;
  final RxBool hasNfcPermission = false.obs;
  final RxString lastScannedTag = ''.obs;
  final RxString registeredAlarmTag = ''.obs;
  final RxBool isVerifyingAlarm = false.obs;
  final RxBool verificationSuccess = false.obs;
  final RxBool hasRegisteredNfcTag = false.obs;

  /// Hard-coded backup code for now
  final String backupCode = 'RH2ASJKJ2394J';

  /// Add reference to the last scanned full tag for verification
  NfcTag? lastScannedFullTag;

  @override
  void onInit() {
    super.onInit();
    checkNfcAvailability();
    loadRegisteredTag();
    checkIfNfcRegistered();
  }

  /// Check if NFC is available on the device
  Future<void> checkNfcAvailability() async {
    try {
      isNfcAvailable.value = await NfcManager.instance.isAvailable();
      hasNfcPermission.value =
          true; // Assume permissions are good if we got here

      if (!isNfcAvailable.value) {
        // Get.snackbar('NFC Status', 'NFC is not available on this device',
        //   snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      // Check if this is a permission error
      if (e.toString().contains('permission')) {
        hasNfcPermission.value = false;
        Get.snackbar(
          'Permission Error',
          'NFC permission denied. Please grant NFC permission in settings.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.red[100],
        );
      } else {
        Get.snackbar('NFC Error', 'Error checking NFC availability: $e',
            snackPosition: SnackPosition.BOTTOM);
      }
      isNfcAvailable.value = false;
    }
  }

  /// Save a registered tag for an alarm
  Future<void> saveTagForAlarm(String tagId, int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Store the tag globally without linking to a specific alarm ID
      await prefs.setString('global_nfc_tag', tagId);
      registeredAlarmTag.value = tagId;
      hasRegisteredNfcTag.value = true;
      Get.snackbar('Tag Saved', 'NFC tag registered successfully',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Error', 'Failed to save NFC tag: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Load registered tag for a specific alarm
  Future<void> loadRegisteredTagForAlarm(int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Load the global tag instead of alarm-specific tag
      registeredAlarmTag.value = prefs.getString('global_nfc_tag') ?? '';
      if (registeredAlarmTag.value.isNotEmpty) {
        hasRegisteredNfcTag.value = true;
      }
      if (registeredAlarmTag.value.isEmpty) {
        Get.snackbar('Tag Status', 'No NFC tag registered',
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to load NFC tag: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Load any registered tag (for initialization)
  Future<void> loadRegisteredTag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Check for global tag first
      final globalTag = prefs.getString('global_nfc_tag');
      if (globalTag != null && globalTag.isNotEmpty) {
        registeredAlarmTag.value = globalTag;
        hasRegisteredNfcTag.value = true;
        debugPrint('Found registered global tag: ${registeredAlarmTag.value}');
        return;
      }

      // For migration: check for any old alarm-specific tags
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('alarm_tag_')) {
          final oldTag = prefs.getString(key) ?? '';
          if (oldTag.isNotEmpty) {
            // Migrate to global tag
            await prefs.setString('global_nfc_tag', oldTag);
            // Remove old alarm-specific tag
            await prefs.remove(key);

            registeredAlarmTag.value = oldTag;
            hasRegisteredNfcTag.value = true;
            debugPrint(
                'Migrated alarm-specific tag to global: ${registeredAlarmTag.value}');
            break;
          }
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
      Get.snackbar('NFC Error', 'NFC not available on this device',
          snackPosition: SnackPosition.BOTTOM);
      onError();
      return;
    }

    isScanning.value = true;
    // Get.snackbar('NFC', 'Starting NFC scan...', snackPosition: SnackPosition.BOTTOM);

    try {
      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          final id = _getTagId(tag);
          lastScannedTag.value = id;
          lastScannedFullTag =
              tag; // Store the full tag for possible verification
          // Get.snackbar('NFC', 'Tag detected: $id', snackPosition: SnackPosition.BOTTOM);
          onTagDetected(id);
          await NfcManager.instance.stopSession();
          isScanning.value = false;
        },
      );
    } catch (e) {
      Get.snackbar('NFC Error', 'Failed to start NFC scan: $e',
          snackPosition: SnackPosition.BOTTOM);
      isScanning.value = false;
      onError();
    }
  }

  /// Stop NFC scanning
  Future<void> stopNfcScan() async {
    if (isScanning.value) {
      try {
        await NfcManager.instance.stopSession();
        lastScannedFullTag = null; // Reset the stored tag
        // Get.snackbar('NFC', 'NFC scan stopped',
        //     snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        Get.snackbar('NFC Error', 'Error stopping NFC scan: $e',
            snackPosition: SnackPosition.BOTTOM);
      } finally {
        isScanning.value = false;
      }
    }
  }

  /// Verify NFC tag for alarm
  Future<bool> verifyTagForAlarm(String scannedTagId, int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Use the global tag instead of alarm-specific tag
      final savedTagId = prefs.getString('global_nfc_tag') ?? '';

      // Get the full tag from the verifyTag reference
      final tagToVerify = lastScannedFullTag;

      // First, check if the tag contains 'earlyup' data
      if (tagToVerify != null) {
        final data = _readNfcData(tagToVerify);
        // if (data != 'earlyup') {
        //   Get.snackbar(
        //       'Invalid Tag', 'This tag does not contain the required data',
        //       snackPosition: SnackPosition.BOTTOM,
        //       backgroundColor: Colors.red[100]);
        //   return false;
        // }
      }

      // Then check if the ID matches the registered tag
      final isVerified = savedTagId.isNotEmpty && savedTagId == scannedTagId;

      if (isVerified) {
        Get.snackbar('Verification', 'Tag matched successfully',
            snackPosition: SnackPosition.BOTTOM);
      } else {
        Get.snackbar('Verification', 'Tag does not match the registered tag',
            snackPosition: SnackPosition.BOTTOM);
      }

      return isVerified;
    } catch (e) {
      Get.snackbar('Error', 'Error verifying tag: $e',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
  }

  /// Verify backup code
  bool verifyBackupCode(String code) {
    final isValid = code == backupCode;
    if (isValid) {
      Get.snackbar('Success', 'Backup code verified',
          snackPosition: SnackPosition.BOTTOM);
    } else {
      Get.snackbar('Failed', 'Invalid backup code',
          snackPosition: SnackPosition.BOTTOM);
    }
    return isValid;
  }

  /// Register a new NFC tag for an alarm
  Future<bool> registerTagForAlarm(int alarmId) async {
    if (!hasNfcPermission.value) {
      Get.snackbar(
        'Permission Error',
        'NFC permission required. Please grant NFC permission in settings.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
        duration: const Duration(seconds: 5),
      );
      return false;
    }

    if (!isNfcAvailable.value) {
      Get.snackbar('NFC Error', 'NFC not available for registration',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    // Check if any NFC tag is already registered in the system
    await checkIfNfcRegistered();
    if (hasRegisteredNfcTag.value) {
      Get.snackbar(
        'NFC Tag Already Registered',
        'Please remove the existing NFC tag before registering a new one.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.amber[100],
        duration: const Duration(seconds: 5),
      );
      return false;
    }

    try {
      isScanning.value = true;

      final completer = Completer<bool>();

      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final id = _getTagId(tag);
            final data = _readNfcData(tag);

            // Check if the tag contains 'earlyup' data
            // if (data == 'earlyup') {
              // Tag contains correct data, proceed with registration
              await saveTagForAlarm(id, alarmId);

              try {
                await NfcManager.instance.stopSession();
              } catch (stopError) {
                //   Get.snackbar(
                //       'NFC Warning', 'Error stopping NFC session: $stopError',
                //       snackPosition: SnackPosition.BOTTOM);
                debugPrint('Error stopping NFC session: $stopError');
              }

              isScanning.value = false;
              if (!completer.isCompleted) {
                Get.snackbar('Success', 'Tag registered successfully',
                    snackPosition: SnackPosition.BOTTOM);
                completer.complete(true);
              }
            // } else {
            //   // Tag does not contain 'earlyup' data
            //   try {
            //     await NfcManager.instance.stopSession();
            //   } catch (stopError) {
            //     // Get.snackbar(
            //     //     'NFC Warning', 'Error stopping NFC session: $stopError',
            //     //     snackPosition: SnackPosition.BOTTOM);
            //     debugPrint('Error stopping NFC session: $stopError');
            //   }
            //
            //   isScanning.value = false;
            //   Get.snackbar(
            //     'Invalid NFC Tag',
            //     'This tag does not a valid EarlyUp NFC tag.',
            //     snackPosition: SnackPosition.BOTTOM,
            //     backgroundColor: Colors.grey[800],
            //     duration: const Duration(seconds: 5),
            //   );
            //
            //   if (!completer.isCompleted) {
            //     completer.complete(false);
            //   }
            // }
          } catch (e) {
            // Get.snackbar('Error', 'Failed to register tag: $e',
            //     snackPosition: SnackPosition.BOTTOM);
            debugPrint('Error during tag registration: $e');

            try {
              await NfcManager.instance.stopSession();
            } catch (stopError) {
              // Get.snackbar(
              //     'NFC Warning', 'Error stopping NFC session: $stopError',
              //     snackPosition: SnackPosition.BOTTOM);
            }

            isScanning.value = false;
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        },
      );

      Timer(const Duration(seconds: 60), () {
        if (!completer.isCompleted) {
          stopNfcScan();
          // Get.snackbar('Timeout', 'NFC registration timed out',
          //     snackPosition: SnackPosition.BOTTOM);
          completer.complete(false);
        }
      });

      return completer.future;
    } catch (e) {
      Get.snackbar('Error', 'Failed to register NFC tag: $e',
          snackPosition: SnackPosition.BOTTOM);
      isScanning.value = false;
      return false;
    }
  }

  /// Start NFC verification process specifically for turning off an alarm
  Future<bool> startAlarmVerification(int alarmId) async {
    isVerifyingAlarm.value = true;
    verificationSuccess.value = false;
    await loadRegisteredTagForAlarm(alarmId);
    lastScannedFullTag = null;

    // Get.snackbar('Verification', 'Scan the NFC tag to turn off alarm',
    //   snackPosition: SnackPosition.BOTTOM,
    //   duration: const Duration(seconds: 3));

    final completer = Completer<bool>();

    if (!isNfcAvailable.value) {
      // Get.snackbar('NFC Error', 'NFC not available for verification',
      //     snackPosition: SnackPosition.BOTTOM);
      isVerifyingAlarm.value = false;
      completer.complete(false);
      return completer.future;
    }

    try {
      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            // Store the full tag for data verification
            lastScannedFullTag = tag;

            final id = _getTagId(tag);
            lastScannedTag.value = id;
            // Get.snackbar('NFC', 'Tag detected during verification',
            //   snackPosition: SnackPosition.BOTTOM);

            final isVerified = await verifyTagForAlarm(id, alarmId);
            verificationSuccess.value = isVerified;

            await NfcManager.instance.stopSession();
            isScanning.value = false;
            isVerifyingAlarm.value = false;

            if (isVerified) {
              Get.snackbar('Success', 'Tag verified successfully',
                  snackPosition: SnackPosition.BOTTOM);
            } else {
              Get.snackbar('Failed', 'Incorrect tag scanned',
                  snackPosition: SnackPosition.BOTTOM);
            }

            if (!completer.isCompleted) {
              completer.complete(isVerified);
            }
          } catch (e) {
            Get.snackbar('Error', 'Error during tag verification: $e',
                snackPosition: SnackPosition.BOTTOM);
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        },
      );

      Timer(const Duration(seconds: 60), () {
        if (!completer.isCompleted) {
          stopNfcScan();
          isVerifyingAlarm.value = false;
          // Get.snackbar('Timeout', 'NFC verification timed out',
          //     snackPosition: SnackPosition.BOTTOM);
          completer.complete(false);
        }
      });

      return completer.future;
    } catch (e) {
      // Get.snackbar('Error', 'Failed to verify NFC tag: $e',
      //     snackPosition: SnackPosition.BOTTOM);
      isVerifyingAlarm.value = false;
      completer.complete(false);
      return completer.future;
    }
  }

  /// Helper method to extract tag ID from NFC tag
  String _getTagId(NfcTag tag) {
    try {
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
        if (ndef != null &&
            ndef['identifier'] != null &&
            ndef['identifier'] is List<int>) {
          return _bytesToHex(ndef['identifier']);
        }
      }

      /// If we can't extract a specific ID, create a fallback ID from the hash
      debugPrint(
          'Using fallback tag ID generation: ${tag.data.toString().hashCode}');
      return 'tag-${tag.data.toString().hashCode.abs()}';
    } catch (e) {
      debugPrint('Error extracting tag ID: $e');

      /// Safe fallback for any exceptions
      return 'unknown-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Helper method to convert bytes to hex string with safe handling
  String _bytesToHex(List<dynamic> bytes) {
    try {
      if (bytes is! List) {
        return 'invalid-data';
      }

      return bytes.map((e) {
        if (e is int) {
          return e.toRadixString(16).padLeft(2, '0');
        } else {
          return 'xx';
        }
      }).join(':');
    } catch (e) {
      debugPrint('Error in bytesToHex: $e');
      return 'conversion-error';
    }
  }

  /// Method to reset verification state
  void resetVerification() {
    isVerifyingAlarm.value = false;
    verificationSuccess.value = false;
  }

  /// Check if at least one NFC tag is registered
  Future<bool> checkIfNfcRegistered() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check for global tag
      final globalTag = prefs.getString('global_nfc_tag') ?? '';
      if (globalTag.isNotEmpty) {
        hasRegisteredNfcTag.value = true;
        return true;
      }

      // For backward compatibility - check old storage format
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('alarm_tag_')) {
          final tagId = prefs.getString(key) ?? '';
          if (tagId.isNotEmpty) {
            // Migrate to global tag
            await prefs.setString('global_nfc_tag', tagId);
            await prefs.remove(key);

            hasRegisteredNfcTag.value = true;
            return true;
          }
        }
      }

      hasRegisteredNfcTag.value = false;
      return false;
    } catch (e) {
      debugPrint('Error checking if NFC is registered: $e');
      hasRegisteredNfcTag.value = false;
      return false;
    }
  }

  /// Remove all registered NFC tags
  Future<bool> removeAllNfcTags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool anyRemoved = false;

      // Remove global tag
      if (prefs.containsKey('global_nfc_tag')) {
        await prefs.remove('global_nfc_tag');
        anyRemoved = true;
      }

      // Also clean up any old alarm-specific tags
      final keys = prefs.getKeys().toList();
      for (final key in keys) {
        if (key.startsWith('alarm_tag_')) {
          await prefs.remove(key);
          anyRemoved = true;
        }
      }

      if (anyRemoved) {
        hasRegisteredNfcTag.value = false;
        registeredAlarmTag.value = '';
        Get.snackbar('Success', 'NFC tag removed successfully',
            snackPosition: SnackPosition.BOTTOM);
      } else {
        Get.snackbar('Info', 'No NFC tag found to remove',
            snackPosition: SnackPosition.BOTTOM);
      }

      return anyRemoved;
    } catch (e) {
      Get.snackbar('Error', 'Failed to remove NFC tag: $e',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
  }

  /// Helper method to read data from NFC tag
  String? _readNfcData(NfcTag tag) {
    try {
      // Try to read NDEF formatted data first
      if (tag.data.containsKey('ndef')) {
        final ndef = tag.data['ndef'];
        if (ndef != null && ndef['cachedMessage'] != null) {
          final cachedMessage = ndef['cachedMessage'];
          if (cachedMessage != null &&
              cachedMessage['records'] != null &&
              cachedMessage['records'] is List &&
              (cachedMessage['records'] as List).isNotEmpty) {
            final records = cachedMessage['records'] as List;
            for (final record in records) {
              if (record != null && record['payload'] != null) {
                // Try to convert the payload to a string
                final payload = record['payload'] as List<int>;
                // Skip NDEF prefix bytes if present (usually first 3-5 bytes)
                final startIndex =
                    payload.length > 5 ? 3 : (payload.length > 3 ? 3 : 0);
                if (payload.length > startIndex) {
                  try {
                    final text =
                        String.fromCharCodes(payload.sublist(startIndex));
                    if (text.isNotEmpty) {
                      debugPrint('Read NDEF text: $text');
                      return text;
                    }
                  } catch (e) {
                    debugPrint('Error converting payload to text: $e');
                  }
                }
              }
            }
          }
        }
      }

      // If no NDEF data, try other tag technologies
      // MIFARE Classic
      if (tag.data.containsKey('mifareClassic')) {
        final mifareClassic = tag.data['mifareClassic'];
        if (mifareClassic != null && mifareClassic['blockData'] != null) {
          // Attempt to read block data
          try {
            final blockData = mifareClassic['blockData'] as List<int>;
            final text = String.fromCharCodes(blockData);
            if (text.isNotEmpty) {
              debugPrint('Read MIFARE Classic text: $text');
              return text;
            }
          } catch (e) {
            debugPrint('Error reading MIFARE Classic data: $e');
          }
        }
      }

      // ISO 15693
      if (tag.data.containsKey('iso15693')) {
        final iso15693 = tag.data['iso15693'];
        if (iso15693 != null &&
            iso15693['systemInfo'] != null &&
            iso15693['systemInfo']['dsfid'] != null) {
          // Just a basic check for any data
          return 'iso15693-data-present';
        }
      }

      // If we couldn't read any meaningful data
      debugPrint('No readable data found in NFC tag');
      return null;
    } catch (e) {
      debugPrint('Error reading NFC data: $e');
      return null;
    }
  }
}
