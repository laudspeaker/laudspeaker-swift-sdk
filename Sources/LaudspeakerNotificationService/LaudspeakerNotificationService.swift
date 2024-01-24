//
//  NotificationService.swift
//  richpush
//
//  Created by Abheek Basu on 1/19/24.
//

import UserNotifications
import UIKit

class LaudspeakerNotificationService: UNNotificationServiceExtension {
    
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let bestAttemptContent = bestAttemptContent {
            // Extract the image URL from the notification payload
            if let fcmOptions = bestAttemptContent.userInfo["fcm_options"] as? [String: AnyObject],
               
               let imageURLString = fcmOptions["image"] as? String,
               let imageURL = URL(string: imageURLString) {
                // Download the image
                downloadImage(from: imageURL) { [weak self] image in
                    if let attachment = self?.createAttachment(from: image) {
                        bestAttemptContent.attachments = [attachment]
                    }
                    contentHandler(bestAttemptContent)
                }
                //this is basically a print statement in this case
                //bestAttemptContent.title = "\(bestAttemptContent.title) [modified]"
            }
            
             else {
                //this is basically a print statement in this case
                //bestAttemptContent.title = "\(bestAttemptContent.title) [modified]"
                contentHandler(bestAttemptContent)
            }
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            //this is basically a print statement in this case
            //bestAttemptContent.title = "\(bestAttemptContent.title) [m modified]"
            contentHandler(bestAttemptContent)
        }
    }
    
    // Download image from URL
    private func downloadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        print("** 3 **")
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data {
                completion(UIImage(data: data))
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    // Create attachment from UIImage
    private func createAttachment(from image: UIImage?) -> UNNotificationAttachment? {
        print("** 4 **")
        guard let image = image else { return nil }
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let imageFileIdentifier = UUID().uuidString + ".jpg"
        let fileURL = temporaryDirectory.appendingPathComponent(imageFileIdentifier)
        
        do {
            try image.jpegData(compressionQuality: 1.0)?.write(to: fileURL)
            return try UNNotificationAttachment(identifier: imageFileIdentifier, url: fileURL, options: nil)
        } catch {
            return nil
        }
    }
    
}

