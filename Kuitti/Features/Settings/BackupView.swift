import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Create, share, restore and delete full-data backups. Restore is replace-all (destructive,
/// confirmed). The Gemini API key is never included — it stays in the Keychain.
struct BackupView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var backups: [URL] = []
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var pendingDelete: URL?
    @State private var restoreTarget: RestoreTarget?
    @State private var showingRestoreConfirm = false
    @State private var showingFileImporter = false

    private struct RestoreTarget: Identifiable {
        let id = UUID()
        let url: URL
        let securityScoped: Bool
    }

    var body: some View {
        List {
            Section {
                Button {
                    createBackup()
                } label: {
                    Label("Create Backup", systemImage: "plus.circle.fill")
                }
                .disabled(isWorking)
            } footer: {
                Text("Backs up all your data except the Gemini API key.")
            }

            Section("Backups") {
                if backups.isEmpty {
                    Text("No backups yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(backups, id: \.self) { url in
                        backupRow(url)
                    }
                }
            }

            Section {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Restore from File…", systemImage: "tray.and.arrow.down")
                }
                .disabled(isWorking)
            } footer: {
                Text("Choose a .kuittibackup file from Files. Restoring replaces all current data.")
            }
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking {
                ProgressView().controlSize(.large).padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear { backups = BackupStore.list() }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.kuittiBackup]) { result in
            if case .success(let url) = result {
                restoreTarget = RestoreTarget(url: url, securityScoped: true)
                showingRestoreConfirm = true
            }
        }
        .confirmationDialog("Restore backup?", isPresented: $showingRestoreConfirm, titleVisibility: .visible, presenting: restoreTarget) { target in
            Button("Restore", role: .destructive) { performRestore(target) }
            Button("Cancel", role: .cancel) { restoreTarget = nil }
        } message: { _ in
            Text("This replaces all current data with the backup. This can't be undone.")
        }
        .confirmationDialog("Delete this backup?", isPresented: deleteDialogPresented, titleVisibility: .visible, presenting: pendingDelete) { url in
            Button("Delete", role: .destructive) { performDelete(url) }
        } message: { _ in
            Text("The backup file is removed from this device. This can't be undone.")
        }
        .alert("Couldn't complete", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Done", isPresented: statusPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private func backupRow(_ url: URL) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateString(for: url))
                Text(FileSize.string(BackupStore.size(of: url)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
        }
        .swipeActions(edge: .leading) {
            Button("Restore", systemImage: "arrow.clockwise") {
                restoreTarget = RestoreTarget(url: url, securityScoped: false)
                showingRestoreConfirm = true
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            // No .destructive role — that removes the row before the confirmation runs.
            Button("Delete", systemImage: "trash") { pendingDelete = url }
                .tint(.red)
        }
    }

    // MARK: - Actions

    private func createBackup() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let archive = try BackupService(context: modelContext).export()
                let data = try await Task.detached(priority: .userInitiated) {
                    try BackupService.encode(archive)
                }.value
                let url = try BackupStore.newBackupURL(date: archive.createdAt)
                try data.write(to: url, options: .atomic)
                backups = BackupStore.list()
                statusMessage = "Backup created."
            } catch {
                errorMessage = AppError(wrapping: error).userMessage
            }
        }
    }

    private func performRestore(_ target: RestoreTarget) {
        isWorking = true
        Task {
            defer { isWorking = false; restoreTarget = nil }
            do {
                let data = try readData(from: target)
                let archive = try await Task.detached(priority: .userInitiated) {
                    try BackupService.decode(data)
                }.value
                try BackupService(context: modelContext).restore(archive)
                backups = BackupStore.list()
                statusMessage = "Backup restored."
            } catch {
                errorMessage = AppError(wrapping: error).userMessage
            }
        }
    }

    private func readData(from target: RestoreTarget) throws -> Data {
        guard target.securityScoped else { return try Data(contentsOf: target.url) }
        let scoped = target.url.startAccessingSecurityScopedResource()
        defer { if scoped { target.url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: target.url)
    }

    private func performDelete(_ url: URL) {
        try? BackupStore.delete(url)
        pendingDelete = nil
        backups = BackupStore.list()
    }

    // MARK: - Helpers

    private static func dateString(for url: URL) -> String {
        guard let date = BackupStore.modified(url) else { return url.lastPathComponent }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    private var statusPresented: Binding<Bool> {
        Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })
    }
}
