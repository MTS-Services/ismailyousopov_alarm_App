import 'package:get/get.dart';

/// Model representing an alarm with all its properties and related functionality
class AlarmModel {
  int? id;
  DateTime time;
  bool isEnabled;
  int soundId;
  bool nfcRequired;
  List<String> daysActive;
  RxBool isActive = RxBool(true);
  bool isForToday;
  DateTime? lastSetTime;
  DateTime? lastStopTime;
  int durationMinutes;



  /// Creates a new alarm with specified properties
  AlarmModel({
    this.id,
    required this.time,
    this.isEnabled = true,
    this.soundId = 1,
    this.nfcRequired = false,
    this.daysActive = const [],
    this.isForToday = false,
    this.lastSetTime,
    this.lastStopTime,
    this.durationMinutes = 30,
  });


  /// Converts the alarm model to a map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time.toIso8601String(),
      'is_enabled': isEnabled ? 1 : 0,
      'sound_id': soundId,
      'nfc_required': nfcRequired ? 1 : 0,
      'days_active': daysActive.isEmpty ? '' : daysActive.join(','),
      'is_for_today': isForToday ? 1 : 0,
      'last_set_time': lastSetTime?.toIso8601String(),
      'last_stop_time': lastStopTime?.toIso8601String(),
      'duration_minutes': durationMinutes,
    };
  }

  /// Creates an alarm model from a database map
  factory AlarmModel.fromMap(Map<String, dynamic> map) {
    return AlarmModel(
      id: map['id'],
      time: DateTime.parse(map['time']),
      isEnabled: map['is_enabled'] == 1,
      soundId: map['sound_id'],
      nfcRequired: map['nfc_required'] == 1,
      daysActive: map['days_active']?.isEmpty ?? true
          ? []
          : map['days_active'].split(','),
      isForToday: map['is_for_today'] == 1,
      lastSetTime: map['last_set_time'] != null ? DateTime.parse(map['last_set_time']) : null,
      lastStopTime: map['last_stop_time'] != null ? DateTime.parse(map['last_stop_time']) : null,
      durationMinutes: map['duration_minutes'] ?? 30,
    );
  }

  // Add these methods to AlarmModel

  /// Checks if the alarm is currently ringing or should be ringing
  bool isRinging(DateTime now) {
    if (!isEnabled) return false;

    // If we have a last set time but no stop time, the alarm is ringing
    if (lastSetTime != null && lastStopTime == null) {
      return true;
    }

    // Check if the alarm time is within the last minute (to catch alarms that just triggered)
    final alarmTimeToday = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    return now.difference(alarmTimeToday).inMinutes.abs() < 1;
  }

  /// Determines if this alarm will trigger today
  bool willTriggerToday() {
    final now = DateTime.now();

    if (!isEnabled) return false;

    if (isRepeating) {
      String currentDay = now.weekday.toString();
      if (!daysActive.contains(currentDay)) return false;
    }

    final alarmTimeToday = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    return alarmTimeToday.isAfter(now);
  }

  /// Gets time remaining until alarm triggers
  String getTimeRemaining() {
    final now = DateTime.now();
    final nextTrigger = getNextAlarmTime();
    final difference = nextTrigger.difference(now);

    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;

    if (hours > 0) {
      return '$hours hr ${minutes > 0 ? '$minutes min' : ''}';
    } else {
      return '$minutes min';
    }
  }


  /// Determines if the alarm should be active based on current time and settings
  bool shouldBeActive() {
    if (!isEnabled) return false;

    final now = DateTime.now();

    if (isRepeating) {
      String currentDay = now.weekday.toString();
      bool isActiveToday = daysActive.contains(currentDay);

      final alarmTimeToday = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );

      return isActiveToday && alarmTimeToday.isAfter(now);
    } else {
      if (isForToday) {
        final alarmTimeToday = DateTime(
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        );
        return alarmTimeToday.isAfter(now);
      } else {
        return time.isAfter(now);
      }
    }
  }


 /// calculate actual alarm duration
  int calculateActualDuration() {
    if (lastSetTime == null || lastStopTime == null) {
      return durationMinutes > 0 ? durationMinutes : 1;
    }

    int duration = lastStopTime!.difference(lastSetTime!).inMinutes;

    return duration > 0 ? duration : 1;
  }


  /// Gets the expected end time of the alarm based on its duration
  DateTime getEndTime() {
    return time.add(Duration(minutes: durationMinutes));
  }

  /// Calculates when this alarm will next trigger based on current settings
  DateTime getNextAlarmTime() {
    final now = DateTime.now();

    if (isRepeating) {
      List<int> activeDays = daysActive.map((day) => int.parse(day)).toList();

      if (activeDays.isEmpty) {
        return now;
      }

      activeDays.sort();

      int? nextDay;
      for (var day in activeDays) {
        if (day > now.weekday ||
            (day == now.weekday &&
                DateTime(now.year, now.month, now.day, time.hour, time.minute)
                    .isAfter(now))) {
          nextDay = day;
          break;
        }
      }

      nextDay ??= activeDays.first;

      int daysToAdd = 0;
      if (nextDay < now.weekday ||
          (nextDay == now.weekday &&
              DateTime(now.year, now.month, now.day, time.hour, time.minute)
                  .isBefore(now))) {
        daysToAdd = 7 - now.weekday + nextDay;
      } else {
        daysToAdd = nextDay - now.weekday;
      }

      return DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      ).add(Duration(days: daysToAdd));
    } else {
      if (isForToday) {
        final alarmTime = DateTime(
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        );

        if (alarmTime.isBefore(now)) {
          return alarmTime.add(const Duration(days: 1));
        }
        return alarmTime;
      } else {
        return time;
      }
    }
  }

  /// Checks if the alarm is set to repeat on specific days
  bool get isRepeating => daysActive.isNotEmpty;


  /// Gets a formatted string representation of active days
  String getFormattedDays() {
    if (daysActive.isEmpty) return "Once";

    final dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final activeDayIndices = daysActive.map((day) => int.parse(day)).toList()
      ..sort();

    if (activeDayIndices.length == 5 &&
        activeDayIndices.contains(1) &&
        activeDayIndices.contains(2) &&
        activeDayIndices.contains(3) &&
        activeDayIndices.contains(4) &&
        activeDayIndices.contains(5)) {
      return "Weekdays";
    }

    if (activeDayIndices.length == 2 &&
        activeDayIndices.contains(6) &&
        activeDayIndices.contains(7)) {
      return "Weekend";
    }

    if (activeDayIndices.length == 7) {
      return "Every day";
    }

    return activeDayIndices.map((index) => dayNames[index]).join(', ');
  }


  /// Returns a formatted time string (e.g., "08:30 AM")
  String getFormattedTime() {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final displayMinute = minute.toString().padLeft(2, '0');

    return '$displayHour:$displayMinute $period';
  }

  /// Returns a formatted duration string (e.g. "1h 30m")
  String getFormattedDuration() {
    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes > 0 ? '${minutes}m' : ''}';
    } else {
      return '${minutes}m';
    }
  }

  /// Returns a human-readable description of when the alarm will next trigger
  String getNextAlarmDescription() {
    final nextTime = getNextAlarmTime();
    final now = DateTime.now();

    if (nextTime.year == now.year &&
        nextTime.month == now.month &&
        nextTime.day == now.day) {
      return "Today at ${getFormattedTime()}";
    } else if (nextTime.year == now.year &&
        nextTime.month == now.month &&
        nextTime.day == now.day + 1) {
      return "Tomorrow at ${getFormattedTime()}";
    } else {
      final dayNames = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ];
      return "${dayNames[nextTime.weekday - 1]} at ${getFormattedTime()}";
    }
  }

  /// Creates a copy of this alarm with updated values
  AlarmModel copyWith({
    int? id,
    DateTime? time,
    bool? isEnabled,
    int? soundId,
    bool? nfcRequired,
    List<String>? daysActive,
    bool? isForToday,
    DateTime? lastSetTime,
    DateTime? lastStopTime,
    int? durationMinutes,
  }) {
    return AlarmModel(
      id: id ?? this.id,
      time: time ?? this.time,
      isEnabled: isEnabled ?? this.isEnabled,
      soundId: soundId ?? this.soundId,
      nfcRequired: nfcRequired ?? this.nfcRequired,
      daysActive: daysActive ?? List.from(this.daysActive),
      isForToday: isForToday ?? this.isForToday,
      lastSetTime: lastSetTime ?? this.lastSetTime,
      lastStopTime: lastStopTime ?? this.lastStopTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  /// Determines if two alarms are equivalent based on their properties
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlarmModel &&
        other.id == id &&
        other.time.hour == time.hour &&
        other.time.minute == time.minute &&
        other.isEnabled == isEnabled &&
        other.soundId == soundId &&
        other.nfcRequired == nfcRequired &&
        listEquals(other.daysActive, daysActive) &&
        other.isForToday == isForToday &&
        other.durationMinutes == durationMinutes;
  }

  /// Generates a hash code for this alarm based on its properties
  @override
  int get hashCode => Object.hash(
    id,
    time.hour,
    time.minute,
    isEnabled,
    soundId,
    nfcRequired,
    Object.hashAll(daysActive),
    isForToday,
    durationMinutes,
  );
}

/// Extension to compare lists (used in equality check)
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}