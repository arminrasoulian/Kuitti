import SwiftUI
import SwiftData

struct CategoryEditView: View {
    let existing: Category?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: CategoryKind = .expense
    @State private var iconName = "tag.fill"
    @State private var colorHex = "#34A853"
    @State private var customColor = Color(hex: "#34A853")

    private static let symbols = [
        "cart.fill", "fork.knife", "house.fill", "bolt.fill", "tram.fill", "fuelpump.fill",
        "cross.case.fill", "tshirt.fill", "figure.and.child.holdinghands", "pawprint.fill",
        "figure.run", "tv.fill", "lamp.table.fill", "gift.fill", "banknote.fill",
        "building.columns.fill", "plus.circle.fill", "ellipsis.circle.fill", "airplane",
        "book.fill", "gamecontroller.fill", "wineglass.fill", "pills.fill", "scissors",
        "wrench.and.screwdriver.fill", "leaf.fill", "bicycle", "bus.fill", "graduationcap.fill",
        "phone.fill", "wifi", "creditcard.fill", "theatermasks.fill", "music.note",
        "camera.fill", "pawprint.circle.fill",
    ]

    private static let palette = [
        "#34A853", "#FF9500", "#5856D6", "#FFCC00", "#007AFF", "#64D2FF",
        "#FF3B30", "#AF52DE", "#FF2D55", "#C7843D", "#30B0C7", "#8E8E93",
    ]

    private var kindLocked: Bool {
        guard let existing else { return false }
        return (existing.transactions?.isEmpty == false) || (existing.lineItems?.isEmpty == false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        Text("Expense").tag(CategoryKind.expense)
                        Text("Income").tag(CategoryKind.income)
                    }
                    .pickerStyle(.segmented)
                    .disabled(kindLocked)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.symbols, id: \.self) { symbol in
                            Button {
                                iconName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.body)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        iconName == symbol ? Color(hex: colorHex).opacity(0.25) : Color(.tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .foregroundStyle(iconName == symbol ? Color(hex: colorHex) : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.palette, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if colorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    ColorPicker("Custom color", selection: $customColor, supportsOpacity: false)
                        .onChange(of: customColor) { _, newValue in
                            if let hex = newValue.hexString { colorHex = hex }
                        }
                }
                Section {
                    HStack {
                        Spacer()
                        CategoryIcon(iconName: iconName, colorHex: colorHex, size: 44)
                        Text(name.isEmpty ? "Preview" : name)
                        Spacer()
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let existing else { return }
        name = existing.name
        kind = existing.kind
        iconName = existing.iconName
        colorHex = existing.colorHex
        customColor = Color(hex: existing.colorHex)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing {
            existing.name = trimmed
            existing.kind = kind
            existing.iconName = iconName
            existing.colorHex = colorHex
            existing.updatedAt = Date()
        } else {
            let maxOrder = (try? context.fetch(FetchDescriptor<Category>()))?.map(\.sortOrder).max() ?? 0
            let category = Category(name: trimmed, kind: kind, iconName: iconName, colorHex: colorHex)
            category.sortOrder = maxOrder + 1
            context.insert(category)
        }
        try? context.save()
        dismiss()
    }
}

private extension Color {
    var hexString: String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return nil }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
