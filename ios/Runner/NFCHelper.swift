import Foundation
import CoreNFC

@available(iOS 13.0, *)
class NFCHelper: NSObject, NFCNDEFReaderSessionDelegate {
    
    // Singleton instance
    static let shared = NFCHelper()
    
    // Session for NFC reading
    private var session: NFCNDEFReaderSession?
    
    // Callback for when tag is scanned
    private var tagReadCallback: ((Bool, String?) -> Void)?
    
    // Private initializer for singleton
    private override init() {
        super.init()
    }
    
    // Start scanning for NFC tags
    func startScanning(callback: @escaping (Bool, String?) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            callback(false, "NFC reading not available on this device")
            return
        }
        
        // Store the callback
        tagReadCallback = callback
        
        // Create and start the session
        session = NFCNDEFReaderSession(delegate: self, queue: DispatchQueue.main, invalidateAfterFirstRead: true)
        session?.alertMessage = "Hold your device near an NFC tag to stop the alarm"
        session?.begin()
    }
    
    // Stop scanning
    func stopScanning() {
        session?.invalidate()
    }
    
    // MARK: - NFCNDEFReaderSessionDelegate
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Check if this is just a user-cancelled error
        if let readerError = error as? NFCReaderError, readerError.code == .readerSessionInvalidationErrorUserCanceled {
            tagReadCallback?(false, "Scanning cancelled")
        } else {
            tagReadCallback?(false, "Error scanning tag: \(error.localizedDescription)")
        }
        
        // Clear the callback
        tagReadCallback = nil
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        var tagContent = ""
        
        // Extract tag content from the messages
        for message in messages {
            for record in message.records {
                if let payload = String(data: record.payload, encoding: .utf8) {
                    tagContent += payload
                }
            }
        }
        
        // Call the callback with success
        tagReadCallback?(true, tagContent)
        
        // Clear the callback
        tagReadCallback = nil
    }
    
    // For iOS 13+, we need to implement this additional method
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        // Connect to the first tag found
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag found")
            return
        }
        
        // Connect to the tag
        session.connect(to: tag) { error in
            if let error = error {
                session.invalidate(errorMessage: "Connection error: \(error.localizedDescription)")
                return
            }
            
            // Read the tag
            tag.queryNDEFStatus { status, capacity, error in
                if let error = error {
                    session.invalidate(errorMessage: "Read error: \(error.localizedDescription)")
                    return
                }
                
                // Check if the tag has a valid NDEF message
                if status == .notSupported {
                    session.invalidate(errorMessage: "Tag is not NDEF compliant")
                    return
                }
                
                // Read the NDEF message
                tag.readNDEF { message, error in
                    if let error = error {
                        session.invalidate(errorMessage: "Read error: \(error.localizedDescription)")
                        return
                    }
                    
                    // Check if we have a message
                    guard let message = message else {
                        session.invalidate(errorMessage: "No NDEF message found")
                        return
                    }
                    
                    // Process the message
                    var tagContent = ""
                    for record in message.records {
                        if let payload = String(data: record.payload, encoding: .utf8) {
                            tagContent += payload
                        }
                    }
                    
                    // Show a success message
                    session.alertMessage = "Tag read successfully!"
                    session.invalidate()
                    
                    // Call the callback
                    self.tagReadCallback?(true, tagContent)
                    self.tagReadCallback = nil
                }
            }
        }
    }
    
    // Helper method for Flutter integration
    func checkTagToStopAlarm(alarmId: Int, completion: @escaping (Bool) -> Void) {
        if #available(iOS 13.0, *) {
            startScanning { success, _ in
                if success {
                    // Tag was read successfully
                    // Stop the alarm
                    AlarmManager.shared.stopAlarm(alarmId: alarmId)
                    completion(true)
                } else {
                    // Failed to read tag
                    completion(false)
                }
            }
        } else {
            // NFC not available on older iOS
            completion(false)
        }
    }
} 