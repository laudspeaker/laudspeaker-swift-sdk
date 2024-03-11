//
//  utils
//
//
//  Created by Abheek Basu on 3/10/24.
//

import Foundation

public func deleteSafely(_ file: URL) {
    if FileManager.default.fileExists(atPath: file.path) {
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            print("Error trying to delete file \(file.path) \(error)")
        }
    }
}

struct InternalLaudspeakerError: Error, CustomStringConvertible {
    let description: String

    init(description: String, fileID: StaticString = #fileID, line: UInt = #line) {
        self.description = "\(description) (\(fileID):\(line))"
    }
}

struct FatalLaudspeakerError: Error, CustomStringConvertible {
    let description: String

    init(description: String, fileID: StaticString = #fileID, line: UInt = #line) {
        self.description = "Fatal Laudspeaker error: \(description) (\(fileID):\(line))"
    }
}

private func newDateFormatter() -> DateFormatter {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = TimeZone(abbreviation: "UTC")

    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return dateFormatter
}

public func toISO8601String(_ date: Date) -> String {
    let dateFormatter = newDateFormatter()
    return dateFormatter.string(from: date)
}

public func toISO8601Date(_ date: String) -> Date? {
    let dateFormatter = newDateFormatter()
    return dateFormatter.date(from: date)
}

public func sanitizeDicionary(_ dict: [String: Any]?) -> [String: Any]? {
    if dict == nil || dict!.isEmpty {
        return nil
    }

    var newDict = dict!

    for (key, value) in newDict where !isValidObject(value) {
        if value is URL {
            newDict[key] = (value as! URL).absoluteString
            continue
        }
        if value is Date {
            newDict[key] = ISO8601DateFormatter().string(from: (value as! Date))
            continue
        }

        newDict.removeValue(forKey: key)
        print("property: \(key) isn't serializable, dropping the item")
    }

    return newDict
}

private func isValidObject(_ object: Any) -> Bool {
    if object is String || object is Bool || object is any Numeric || object is NSNumber {
        return true
    }
    if object is [Any?] || object is [String: Any?] {
        return JSONSerialization.isValidJSONObject(object)
    }
    // workaround [object] since isValidJSONObject only accepts an Array or Dict
    return JSONSerialization.isValidJSONObject([object])
}

