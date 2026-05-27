// DebugLog — Documents/kadastr_debug.log ga matn qo'shadi.
// NSLog'lar iOS'da <private> redact bo'lib syslog'da ko'rinmaydi. File-based
// log Files app yoki idevicefs orqali oson pull qilinadi.
//
// Format: timestamp + tag + message
//   2026-05-27T21:30:15.123 [TAG] message

import Foundation

enum DebugLog {
    private static let queue = DispatchQueue(label: "kadastr.debug.log", qos: .utility)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()

    static var logURL: URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask,
        ).first!
        return docs.appendingPathComponent("kadastr_debug.log")
    }

    static func log(_ tag: String, _ message: String) {
        let line = "\(dateFormatter.string(from: Date())) [\(tag)] \(message)\n"
        // Also NSLog so xcode console shows
        NSLog("KADASTR [\(tag)] \(message)")
        queue.async {
            let url = logURL
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) { handle.write(data) }
                try? handle.close()
            } else {
                try? line.data(using: .utf8)?.write(to: url)
            }
        }
    }

    static func reset() {
        try? FileManager.default.removeItem(at: logURL)
    }
}
