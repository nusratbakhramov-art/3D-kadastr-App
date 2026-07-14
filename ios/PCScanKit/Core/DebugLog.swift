import Foundation

/// Sessiya bo'yicha oddiy fayl-jurnali (debug.log) — qayta ishlash/debug uchun.
struct DebugLog {
    let url: URL

    func log(_ message: String) {
        let line = "[\(Self.stamp())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: url)
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
