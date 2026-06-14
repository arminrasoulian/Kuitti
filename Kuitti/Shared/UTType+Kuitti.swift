import UniformTypeIdentifiers

extension UTType {
    /// Kuitti backup archive ("*.kuittibackup"). Declared as an exported type in Info.plist
    /// (UTExportedTypeDeclarations) so the system maps the extension to this type for the
    /// in-app restore file picker and ShareLink.
    static let kuittiBackup = UTType(filenameExtension: "kuittibackup") ?? .data
}
