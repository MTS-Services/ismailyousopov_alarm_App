// The filename has been changed to AAAlarmManager.swift to ensure it's compiled first
import Foundation
import AVFoundation
import UserNotifications
import AudioToolbox

class AlarmManager {
    // Singleton instance
    static let shared = AlarmManager()
    
    // Audio player for alarm sounds
    private var audioPlayer: AVAudioPlayer?
    
    // Active alarms tracking
    private var activeAlarms: [Int: AlarmInfo] = [:]
    
    // Launch data for when app is opened from a notification
    private var launchData: [String: Any]?
    
    // Audio session to allow background playback
    private var audioSession: AVAudioSession {
        return AVAudioSession.sharedInstance()
    }
    
    // UserDefaults for persistence
    private let userDefaults = UserDefaults(suiteName: "com.example.alarm") ?? UserDefaults.standard
    
    // Timer for vibration pattern
    private var vibrationTimer: Timer?
    
    // Background task ID for keeping app alive
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    
    // Private initializer for singleton
    private init() {
        // Setup notifications categories with actions
        setupNotificationCategories()
        
        // Load any previously active alarms
        loadSavedAlarms()
    }
    
    // Setup notification categories with actions (stop and snooze)
    private func setupNotificationCategories() {
        let stopAction = UNNotificationAction(
            identifier: "STOP_ACTION",
            title: "Stop",
            options: .foreground
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "Snooze",
            options: .foreground
        )
        
        let category = UNNotificationCategory(
            identifier: "ALARM_CATEGORY",
            actions: [stopAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    // Load any previously active alarms
    private func loadSavedAlarms() {
        if let savedAlarms = userDefaults.dictionary(forKey: "activeAlarms") as? [String: [String: Any]] {
            for (idStr, alarmData) in savedAlarms {
                if let id = Int(idStr),
                   let soundId = alarmData["soundId"] as? Int,
                   let isActive = alarmData["isActive"] as? Bool,
                   let triggerTime = alarmData["triggerTime"] as? Double,
                   let nfcRequired = alarmData["nfcRequired"] as? Bool {
                    
                    let alarmInfo = AlarmInfo(
                        soundId: soundId,
                        isActive: isActive,
                        triggerTime: triggerTime,
                        nfcRequired: nfcRequired
                    )
                    
                    activeAlarms[id] = alarmInfo
                    
                    // Only reschedule if it's in the future
                    if triggerTime > Date().timeIntervalSince1970 {
                        scheduleAlarm(alarmId: id, triggerTime: triggerTime, soundId: soundId, nfcRequired: nfcRequired)
                    }
                }
            }
        }
    }
    
    // Schedule a new alarm
    func scheduleAlarm(alarmId: Int, triggerTime: Double, soundId: Int, nfcRequired: Bool) {
        // Cancel any existing alarm with this ID
        cancelAlarm(alarmId: alarmId)
        
        // Create alarm info and store it
        let alarmInfo = AlarmInfo(
            soundId: soundId,
            isActive: false,
            triggerTime: triggerTime,
            nfcRequired: nfcRequired
        )
        activeAlarms[alarmId] = alarmInfo
        saveActiveAlarmState()
        
        // Create the trigger date
        let triggerDate = Date(timeIntervalSince1970: triggerTime)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // Create the notification content
        let content = UNMutableNotificationContent()
        content.title = "Alarm"
        content.body = nfcRequired ? "Scan NFC tag to stop alarm" : "Time to wake up!"
        content.sound = .default
        content.categoryIdentifier = "ALARM_CATEGORY"
        
        // Add user info for notification handling
        content.userInfo = [
            "alarmId": alarmId,
            "soundId": soundId,
            "nfcRequired": nfcRequired
        ]
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: "alarm_\(alarmId)",
            content: content,
            trigger: trigger
        )
        
        // Schedule the notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            } else {
                print("Alarm scheduled successfully for: \(triggerDate)")
                
                // Save this scheduled alarm for recovery if needed
                self.saveScheduledAlarm(alarmId: alarmId, triggerTime: triggerTime, soundId: soundId, nfcRequired: nfcRequired)
            }
        }
    }
    
    // Save a scheduled alarm for recovery
    private func saveScheduledAlarm(alarmId: Int, triggerTime: Double, soundId: Int, nfcRequired: Bool) {
        var scheduledAlarms = userDefaults.array(forKey: "scheduledAlarms") as? [[String: Any]] ?? []
        
        // Remove any existing scheduled alarm with this ID
        scheduledAlarms.removeAll { alarm in
            return alarm["alarmId"] as? Int == alarmId
        }
        
        // Add the new alarm
        let alarm: [String: Any] = [
            "alarmId": alarmId,
            "triggerTime": triggerTime,
            "soundId": soundId,
            "nfcRequired": nfcRequired
        ]
        
        scheduledAlarms.append(alarm)
        userDefaults.set(scheduledAlarms, forKey: "scheduledAlarms")
    }
    
    // Start playing an alarm sound
    func startAlarm(alarmId: Int, soundId: Int) {
        // Begin a background task to keep app running
        beginBackgroundTask()
        
        // Mark the alarm as active
        if var alarmInfo = activeAlarms[alarmId] {
            alarmInfo.isActive = true
            activeAlarms[alarmId] = alarmInfo
            saveActiveAlarmState()
        } else {
            // Create a new alarm info if it doesn't exist
            let alarmInfo = AlarmInfo(
                soundId: soundId,
                isActive: true,
                triggerTime: Date().timeIntervalSince1970,
                nfcRequired: false
            )
            activeAlarms[alarmId] = alarmInfo
            saveActiveAlarmState()
        }
        
        // Play the alarm sound
        playAlarmSound(soundId: soundId)
        
        // Start vibration
        startVibration()
        
        // Update user defaults with active alarm information
        userDefaults.set([
            "alarmId": alarmId,
            "soundId": soundId,
            "startTime": Date().timeIntervalSince1970
        ], forKey: "activeAlarmData")
        
        print("Started alarm with ID: \(alarmId), sound: \(soundId)")
    }
    
    // Play an alarm sound
    private func playAlarmSound(soundId: Int) {
        // Set up audio session for alarm playback
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        
        // Load and play the sound
        let soundName: String
        switch soundId {
        case 1: soundName = "sound_1"
        case 2: soundName = "sound_2"
        case 3: soundName = "sound_3"
        case 4: soundName = "sound_4"
        case 5: soundName = "sound_5"
        case 6: soundName = "sound_6"
        case 7: soundName = "sound_7"
        case 8: soundName = "sound_8"
        default: soundName = "sound_1"
        }
        
        if let soundURL = Bundle.main.url(forResource: soundName, withExtension: "mp3") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.numberOfLoops = -1 // Loop indefinitely
                
                // Load volume from user defaults
                let volume = loadVolumeSetting()
                audioPlayer?.volume = volume
                
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                
                print("Playing alarm sound: \(soundName) with volume: \(volume)")
            } catch {
                print("Error playing alarm sound: \(error)")
            }
        } else {
            print("Sound file not found: \(soundName)")
        }
    }
    
    // Load volume setting from user defaults
    private func loadVolumeSetting() -> Float {
        let volume = userDefaults.float(forKey: "alarm_volume")
        return volume > 0 ? volume / 100.0 : 0.7 // Default to 70% if not set
    }
    
    // Start device vibration
    private func startVibration() {
        // Cancel any existing vibration timer
        vibrationTimer?.invalidate()
        
        // Create a vibration pattern
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        
        // Start the first vibration immediately
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
    // Stop device vibration
    func stopVibration() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }
    
    // Stop a specific alarm
    func stopAlarm(alarmId: Int) {
        if activeAlarms[alarmId] != nil {
            activeAlarms[alarmId]?.isActive = false
            
            // Check if there are any other active alarms
            let anyActive = activeAlarms.values.contains { $0.isActive }
            
            if !anyActive {
                // If no other alarms are active, stop audio and vibration
                stopAllAudioAndVibration()
            }
            
            // Save state
            saveActiveAlarmState()
            
            // Cancel notification
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["alarm_\(alarmId)"])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarm_\(alarmId)"])
            
            print("Stopped alarm with ID: \(alarmId)")
        }
    }
    
    // Stop all alarms
    func stopAllAlarms() {
        // Mark all alarms as inactive
        for alarmId in activeAlarms.keys {
            activeAlarms[alarmId]?.isActive = false
        }
        
        // Stop audio and vibration
        stopAllAudioAndVibration()
        
        // Save state
        saveActiveAlarmState()
        
        // End background task
        endBackgroundTask()
        
        print("Stopped all alarms")
    }
    
    // Stop all audio playback and vibration
    private func stopAllAudioAndVibration() {
        // Stop audio
        audioPlayer?.stop()
        audioPlayer = nil
        
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error deactivating audio session: \(error)")
        }
        
        // Stop vibration
        stopVibration()
    }
    
    // Snooze an alarm
    func snoozeAlarm(alarmId: Int, soundId: Int) {
        // Cancel the current alarm
        stopAlarm(alarmId: alarmId)
        
        // Schedule a new alarm in 5 minutes
        let snoozeTime = Date().timeIntervalSince1970 + (5 * 60) // 5 minutes
        scheduleAlarm(alarmId: alarmId, triggerTime: snoozeTime, soundId: soundId, nfcRequired: false)
        
        print("Snoozed alarm with ID: \(alarmId) for 5 minutes")
    }
    
    // Cancel a specific alarm
    func cancelAlarm(alarmId: Int) {
        // Stop the alarm if it's active
        stopAlarm(alarmId: alarmId)
        
        // Remove from active alarms
        activeAlarms.removeValue(forKey: alarmId)
        
        // Save state
        saveActiveAlarmState()
        
        // Remove pending notifications
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["alarm_\(alarmId)"])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarm_\(alarmId)"])
        
        print("Cancelled alarm with ID: \(alarmId)")
    }
    
    // Cancel all alarms
    func cancelAllAlarms() {
        // Stop all active alarms
        stopAllAlarms()
        
        // Clear active alarms
        activeAlarms.removeAll()
        
        // Save state
        saveActiveAlarmState()
        
        // Remove all notifications
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        print("Cancelled all alarms")
    }
    
    // Check if a specific alarm is active
    func isAlarmActive(alarmId: Int) -> Bool {
        return activeAlarms[alarmId]?.isActive ?? false
    }
    
    // Check if any alarm is active
    func isAnyAlarmActive() -> Bool {
        return activeAlarms.values.contains { $0.isActive }
    }
    
    // Save active alarm state to UserDefaults
    func saveActiveAlarmState() {
        var alarmsDict: [String: [String: Any]] = [:]
        
        for (alarmId, alarmInfo) in activeAlarms {
            alarmsDict["\(alarmId)"] = [
                "soundId": alarmInfo.soundId,
                "isActive": alarmInfo.isActive,
                "triggerTime": alarmInfo.triggerTime,
                "nfcRequired": alarmInfo.nfcRequired
            ]
        }
        
        userDefaults.set(alarmsDict, forKey: "activeAlarms")
    }
    
    // Set launch data for when the app is opened from a notification
    func setLaunchData(alarmId: Int, soundId: Int) {
        launchData = [
            "alarmId": alarmId,
            "soundId": soundId,
            "fromAlarm": true
        ]
    }
    
    // Get launch data for when the app is opened from a notification
    func getLaunchData() -> [String: Any]? {
        let data = launchData
        // Clear the data after retrieval
        launchData = nil
        return data
    }
    
    // Begin a background task to keep the app running
    private func beginBackgroundTask() {
        // End any existing background task
        endBackgroundTask()
        
        backgroundTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        // Set up a timeout to end the task after 25 minutes (iOS allows maximum 30 minutes)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25 * 60) { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    // End the background task
    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }
}

// Structure to hold alarm information
struct AlarmInfo {
    var soundId: Int
    var isActive: Bool
    var triggerTime: Double
    var nfcRequired: Bool
} 