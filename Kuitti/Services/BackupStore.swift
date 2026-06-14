import Foundation

/// Manages the in-app backup files under Documents/Backups. The directory is excluded from
/// iCloud/device backup — the live SwiftData store is already covered by the OS backup, so
/// keeping these archive copies in would only double its size. Users still share them out.
enum BackupStore {
    static func directory() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        var dir = docs.appendingPathComponent("Backups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }

    /// Existing backups, newest first.
    static func list() -> [URL] {
        guard let dir = try? directory() else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "kuittibackup" }
            .sorted { (modified($0) ?? .distantPast) > (modified($1) ?? .distantPast) }
    }

    /// A filesystem-safe destination URL for a new backup ("Kuitti-Backup-2026-06-14-153012.kuittibackup").
    static func newBackupURL(date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "Kuitti-Backup-\(formatter.string(from: date)).kuittibackup"
        return try directory().appendingPathComponent(name)
    }

    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
