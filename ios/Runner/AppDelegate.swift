import Flutter
import UIKit
import AVFoundation
import UserNotifications

// Import the AlarmManager class to make it visible
// Since AlarmManager is defined in the same module, no import is needed,
// but we need to ensure it's accessible

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let CHANNEL = "com.example.alarm/background_channel"
  private let WAKE_LOCK_CHANNEL = "com.your.package/wake_lock"
  private let ALARM_MANAGER_CHANNEL = "com.your.package/alarm_manager"
  
  // Remove the AlarmManager property for now
  private var audioPlayer: AVAudioPlayer?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Setup audio session for background playback
    setupAudioSession()
    
    // Remove initialization of AlarmManager for now
    
    // Register for method channels
    let controller = window?.rootViewController as! FlutterViewController
    setupMethodChannels(controller: controller)
    
    // Request notification permissions
    requestNotificationPermissions()
    
    // Handle app launched from notification
    if let launchOptions = launchOptions,
       let notificationOption = launchOptions[UIApplication.LaunchOptionsKey.remoteNotification] as? [String: Any] {
      handleLaunchFromNotification(userInfo: notificationOption)
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func setupMethodChannels(controller: FlutterViewController) {
    // Setup the main alarm channel
    let alarmChannel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: controller.binaryMessenger)
    
    alarmChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      
      switch call.method {
      case "isNativeNotificationActive":
        // Simplified implementation
        result(false)
        
      case "cancelNotification":
        // Simplified implementation
        result(true)
        
      case "bringToForeground":
        self.bringToForeground()
        result(true)
        
      case "startForegroundService":
        // Simplified implementation
        result(true)
        
      case "stopVibration":
        // Simplified implementation
        result(true)
        
      case "cancelAllNotifications":
        // Simplified implementation
        result(true)
        
      case "forceStopService":
        // Simplified implementation
        result(true)
        
      case "isAlarmActive":
        // Simplified implementation
        result(false)
        
      case "getAlarmLaunchData":
        // Simplified implementation
        result(nil)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Setup wake lock channel
    let wakeLockChannel = FlutterMethodChannel(name: WAKE_LOCK_CHANNEL, binaryMessenger: controller.binaryMessenger)
    
    wakeLockChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      
      switch call.method {
      case "acquirePersistentWakeLock":
        self.beginBackgroundTask()
        result(true)
        
      case "releaseWakeLock":
        self.endBackgroundTask()
        result(true)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Setup alarm manager channel
    let alarmManagerChannel = FlutterMethodChannel(name: ALARM_MANAGER_CHANNEL, binaryMessenger: controller.binaryMessenger)
    
    alarmManagerChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      
      if call.method == "scheduleExactAlarm" {
        // Get parameters
        guard let alarmId = call.arguments as? [String: Any]?["alarmId"] as? Int,
              let triggerAtMillis = call.arguments as? [String: Any]?["triggerAtMillis"] as? Int64,
              let soundId = call.arguments as? [String: Any]?["soundId"] as? Int else {
          result(false)
          return
        }
        
        let nfcRequired = (call.arguments as? [String: Any]?["nfcRequired"] as? Bool) ?? false
        
        // Schedule the notification
        let triggerDate = Date(timeIntervalSince1970: Double(triggerAtMillis) / 1000.0)
        let content = UNMutableNotificationContent()
        content.title = "Alarm"
        content.body = nfcRequired ? "Scan NFC tag to stop alarm" : "Time to wake up!"
        content.sound = UNNotificationSound.defaultCritical
        content.categoryIdentifier = "ALARM_CATEGORY"
        content.userInfo = ["alarmId": alarmId, "soundId": soundId, "nfcRequired": nfcRequired]
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
          identifier: "alarm_\(alarmId)",
          content: content,
          trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
          if let error = error {
            print("Error scheduling notification: \(error)")
            result(false)
          } else {
            print("Successfully scheduled alarm notification for \(triggerDate)")
            
            // Store scheduled alarm info for recovery if needed
            let defaults = UserDefaults.standard
            var scheduledAlarms = defaults.array(forKey: "scheduledAlarms") as? [[String: Any]] ?? []
            
            // Remove any existing alarm with this ID
            scheduledAlarms.removeAll { ($0["alarmId"] as? Int) == alarmId }
            
            // Add new alarm info
            scheduledAlarms.append([
              "alarmId": alarmId,
              "triggerTime": triggerDate.timeIntervalSince1970,
              "soundId": soundId,
              "nfcRequired": nfcRequired
            ])
            
            defaults.set(scheduledAlarms, forKey: "scheduledAlarms")
            result(true)
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
  
  private func setupAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Failed to set up audio session: \(error)")
    }
  }
  
  private func requestNotificationPermissions() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, error in
      if granted {
        print("Notification permissions granted")
        
        // Configure notification categories after permissions are granted
        self.setupNotificationCategories()
      } else if let error = error {
        print("Notification permissions error: \(error)")
      }
    }
  }
  
  // Add a function to set up notification categories with actions
  private func setupNotificationCategories() {
    let stopAction = UNNotificationAction(
        identifier: "STOP_ACTION",
        title: "Stop Alarm",
        options: [.foreground]
    )
    
    let category = UNNotificationCategory(
        identifier: "ALARM_CATEGORY",
        actions: [stopAction],
        intentIdentifiers: [],
        options: [.customDismissAction]
    )
    
    UNUserNotificationCenter.current().setNotificationCategories([category])
    print("Notification categories configured")
  }
  
  private func handleLaunchFromNotification(userInfo: [String: Any]) {
    // Simplified implementation
    print("App launched from notification: \(userInfo)")
  }
  
  private func bringToForeground() {
    // This method is mostly for Android compatibility
    // iOS handles bringing the app to foreground via notification interactions
  }
  
  private func beginBackgroundTask() {
    // End any existing background task first
    endBackgroundTask()
    
    backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
      self?.endBackgroundTask()
    }
  }
  
  private func endBackgroundTask() {
    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }
  
  // Handle when the app is terminated but notifications are still active
  override func applicationWillTerminate(_ application: UIApplication) {
    // Simplified implementation
    super.applicationWillTerminate(application)
  }
  
  // Handle opening app from notification
  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    // Simplified implementation
    completionHandler()
  }
  
  // Called when notification is delivered while app is in foreground
  override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    // Show the notification even when app is in foreground
    completionHandler([.alert, .sound, .badge])
  }
}
