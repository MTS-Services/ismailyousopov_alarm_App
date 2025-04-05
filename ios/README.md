# iOS Native Alarm Implementation

This directory contains the native iOS implementation for alarm functionality in the app.

## Features

- Background alarm playback
- Vibration support
- NFC scanning for alarm dismissal
- Critical alerts that bypass Do Not Disturb mode
- Background task handling to keep alarms working
- Persistence of scheduled alarms

## Files

- **AlarmManager.swift**: Singleton class that handles all alarm functionality (scheduling, playing sounds, managing notifications)
- **AlarmNotificationService.swift**: Handles notification extensions for alarms
- **NFCHelper.swift**: Handles NFC tag scanning for alarm dismissal
- **Info.plist**: Contains necessary permissions and background modes
- **Runner.entitlements**: Contains required entitlements for alarm functionality

## Integration with Flutter

The native code is integrated with Flutter through method channels defined in AppDelegate.swift:

- `com.example.alarm/background_channel`: Main channel for alarm functionality
- `com.your.package/wake_lock`: Handles background task management
- `com.your.package/alarm_manager`: Handles alarm scheduling

## Required Capabilities

The following capabilities need to be enabled in Xcode:
- Background Modes (Audio, Processing, Fetch, Remote Notifications)
- Push Notifications
- NFC Tag Reading (if using NFC functionality)
- Critical Alerts (requires special approval from Apple)

## Setup Instructions

1. Open the project in Xcode
2. Go to the "Signing & Capabilities" tab for the Runner target
3. Add the following capabilities:
   - Background Modes (check Audio, Processing, Fetch, Remote Notifications)
   - Push Notifications
   - NFC Tag Reading (if using NFC)
4. Add the Runner.entitlements file to the project
5. Ensure you have the sound files in the Resources/Sounds directory
6. Request Critical Alerts entitlement from Apple (if needed)

## Apple Review Notes

When submitting to the App Store, be prepared to explain your use of:
- Critical Alerts
- Background Audio
- NFC Tag Reading

Critical Alerts in particular requires special approval and you should explain why your alarm app needs to bypass Do Not Disturb mode. 