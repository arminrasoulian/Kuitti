import SwiftUI

/// Euro amount in rounded monospaced digits so columns align. Income tints accent;
/// expenses stay primary (red is reserved for warnings/over-budget).
struct AmountText: View {
    let minor: Int
    var kind: TransactionKind = .expense

    var body: some View {
        Text(Money.euros(minor))
            .font(.system(.body, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(kind == .income ? Color.accentColor : .primary)
    }
}

/// Category icon in its color disc — used in lists, pickers, and chips.
struct CategoryIcon: View {
    let iconName: String
    let colorHex: String
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex), in: Circle())
    }
}

struct CategoryChipLabel: View {
    let name: String
    let iconName: String
    let colorHex: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(Color(hex: colorHex))
        .background(Color(hex: colorHex).opacity(0.15), in: Capsule())
    }
}

/// The one intentional attention color: orange "?" on uncertain parsed lines.
struct UncertaintyBadge: View {
    var body: some View {
        Image(systemName: "questionmark.circle.fill")
            .foregroundStyle(.orange)
            .accessibilityLabel("Uncertain — check this value")
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}
