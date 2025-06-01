import Foundation
import CoreNFC

@available(iOS 13.0, *)
class NFCHelper: NSObject, NFCNDEFReaderSessionDelegate, NFCTagReaderSessionDelegate {
    
    // Singleton instance
    static let shared = NFCHelper()
    
    // Session for NFC reading
    private var ndefSession: NFCNDEFReaderSession?
    private var tagSession: NFCTagReaderSession?
    
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
        
        // Use tag reader session directly since we want to support both NDEF and non-NDEF tags
        tagSession = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self)
        tagSession?.alertMessage = "Hold your device near an NFC tag to stop the alarm"
        tagSession?.begin()
    }
    
    // Stop scanning
    func stopScanning() {
        ndefSession?.invalidate()
        tagSession?.invalidate()
    }
    
    // MARK: - NFCTagReaderSessionDelegate (iOS 13+)
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // Check if this is just a user-cancelled error
        if let readerError = error as? NFCReaderError, readerError.code == .readerSessionInvalidationErrorUserCanceled {
            tagReadCallback?(false, "Scanning cancelled")
        } else {
            print("Error scanning tag: \(error.localizedDescription)")
            tagReadCallback?(false, "Error scanning tag: \(error.localizedDescription)")
        }
        
        // Clear the callback
        tagReadCallback = nil
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print("Tag detected in tagReaderSession")
        
        // Connect to the first tag found
        guard let firstTag = tags.first else {
            session.invalidate(errorMessage: "No tag found")
            return
        }
        
        // Connect to the tag
        session.connect(to: firstTag) { error in
            if let error = error {
                print("Connection error: \(error.localizedDescription)")
                session.invalidate(errorMessage: "Connection error: \(error.localizedDescription)")
                return
            }
            
            // Process tag based on its type
            switch firstTag {
            case .miFare(let tag):
                print("MIFARE tag detected with ID: \(tag.identifier.map { String(format: "%02X", $0) }.joined())")
                
                // Special handling for NTAG215
                if tag.mifareFamily == .ultralight {
                    print("NTAG215/Ultralight detected")
                }
                
                let uid = tag.identifier.map { String(format: "%02x", $0) }.joined()
                session.alertMessage = "Tag detected: \(uid)"
                session.invalidate()
                self.tagReadCallback?(true, uid)
                self.tagReadCallback = nil
                
            case .iso15693(let tag):
                let uid = tag.identifier.map { String(format: "%02x", $0) }.joined()
                session.alertMessage = "Tag detected: \(uid)"
                session.invalidate()
                self.tagReadCallback?(true, uid)
                self.tagReadCallback = nil
                
            case .iso7816(let tag):
                let uid = tag.identifier.map { String(format: "%02x", $0) }.joined()
                session.alertMessage = "Tag detected: \(uid)"
                session.invalidate()
                self.tagReadCallback?(true, uid)
                self.tagReadCallback = nil
                
            case .feliCa(let tag):
                let uid = tag.currentIDm.map { String(format: "%02x", $0) }.joined()
                session.alertMessage = "Tag detected: \(uid)"
                session.invalidate()
                self.tagReadCallback?(true, uid)
                self.tagReadCallback = nil
                
            default:
                print("Unsupported tag type")
                session.invalidate(errorMessage: "Unsupported tag type")
            }
        }
    }
    
    // MARK: - NFCNDEFReaderSessionDelegate
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Check if this is just a user-cancelled error
        if let readerError = error as? NFCReaderError, readerError.code == .readerSessionInvalidationErrorUserCanceled {
            tagReadCallback?(false, "Scanning cancelled")
        } else {
            print("Error scanning tag: \(error.localizedDescription)")
            tagReadCallback?(false, "Error scanning tag: \(error.localizedDescription)")
        }
        
        // Clear the callback
        tagReadCallback = nil
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        print("NDEF messages detected")
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
        print("Tags detected in NDEF session")
        // Connect to the first tag found
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag found")
            return
        }
        
        // Connect to the tag
        session.connect(to: tag) { error in
            if let error = error {
                print("Connection error: \(error.localizedDescription)")
                session.invalidate(errorMessage: "Connection error: \(error.localizedDescription)")
                return
            }
            
            // Read the tag
            tag.queryNDEFStatus { status, capacity, error in
                if let error = error {
                    print("Read error: \(error.localizedDescription)")
                    session.invalidate(errorMessage: "Read error: \(error.localizedDescription)")
                    return
                }
                
                // Check if the tag has a valid NDEF message
                if status == .notSupported {
                    print("Tag is not NDEF compliant")
                    
                    // For non-NDEF tags, just try to read the ID
                    session.alertMessage = "Tag detected!"
                    session.invalidate()
                    self.tagReadCallback?(true, "tag-detected")
                    self.tagReadCallback = nil
                    return
                }
                
                // Read the NDEF message
                tag.readNDEF { message, error in
                    if let error = error {
                        print("Read error: \(error.localizedDescription)")
                        session.invalidate(errorMessage: "Read error: \(error.localizedDescription)")
                        return
                    }
                    
                    // Check if we have a message
                    guard let message = message else {
                        print("No NDEF message found")
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
                    print("Tag was scanned successfully, stopping alarm \(alarmId)")
                    AlarmManager.shared.stopAlarm(alarmId: alarmId)
                    completion(true)
                } else {
                    // Failed to read tag
                    print("Failed to read tag for alarm \(alarmId)")
                    completion(false)
                }
            }
        } else {
            // NFC not available on older iOS
            completion(false)
        }
    }
} 