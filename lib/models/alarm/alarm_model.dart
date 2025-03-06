import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AlarmModel {
  int? id;
  DateTime time;
  bool isEnabled;
  int soundId;
  bool nfcRequired;
  List<String> daysActive;
  RxBool isActive = RxBool(true);

  AlarmModel({
    this.id,
    required this.time,
    this.isEnabled = true,
    this.soundId = 1,
    this.nfcRequired = false,
    this.daysActive = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time.toIso8601String(),
      'is_enabled': isEnabled ? 1 : 0,
      'sound_id': soundId,
      'nfc_required': nfcRequired ? 1 : 0,
      'days_active': daysActive.join(','),
    };
  }

  factory AlarmModel.fromMap(Map<String, dynamic> map) {
    return AlarmModel(
      id: map['id'],
      time: DateTime.parse(map['time']),
      isEnabled: map['is_enabled'] == 1,
      soundId: map['sound_id'],
      nfcRequired: map['nfc_required'] == 1,
      daysActive: map['days_active'].split(','),
    );
  }


  bool get isRepeating => daysActive.isNotEmpty;
}