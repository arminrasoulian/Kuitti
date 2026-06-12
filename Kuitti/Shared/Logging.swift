import os

/// Log sizes, statuses, and finish reasons — never receipt contents or the API key.
nonisolated enum Log {
    static let gemini = Logger(subsystem: "com.personal.kuitti", category: "gemini")
    static let off = Logger(subsystem: "com.personal.kuitti", category: "off")
    static let persistence = Logger(subsystem: "com.personal.kuitti", category: "persistence")
    static let ui = Logger(subsystem: "com.personal.kuitti", category: "ui")
}
