import Foundation
import UserNotifications
import UIKit

class AlarmNotificationService: UNNotificationServiceExtension {
    
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let bestAttemptContent = bestAttemptContent {
            // Modify the notification content if needed
            
            // Check if this is an alarm notification
            if let alarmId = bestAttemptContent.userInfo["alarmId"] as? Int {
                // Apply critical alert settings if supported
                if #available(iOS 12.0, *) {
                    bestAttemptContent.sound = UNNotificationSound.defaultCritical
                }
                
                // Ensure we have the alarm category
                bestAttemptContent.categoryIdentifier = "ALARM_CATEGORY"
                
                // Attempt to wake up the device
                wakeScreen()
            }
            
            contentHandler(bestAttemptContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
    
    // Helper function to try to wake the screen
    private func wakeScreen() {
        // On iOS, we can't directly wake the screen like on Android
        // Instead, we rely on the notification settings and critical alerts
        
        // However, we can attempt to start a background task to increase the chances of the app
        // being able to respond quickly when the notification is tapped
        let application = UIApplication.shared
        var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
        
        backgroundTaskId = application.beginBackgroundTask {
            // Clean up the task
            if backgroundTaskId != .invalid {
                application.endBackgroundTask(backgroundTaskId)
                backgroundTaskId = .invalid
            }
        }
        
        // Schedule a task to end the background task after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if backgroundTaskId != .invalid {
                application.endBackgroundTask(backgroundTaskId)
                backgroundTaskId = .invalid
            }
        }
    }
} 