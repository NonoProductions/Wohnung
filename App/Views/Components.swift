import SwiftUI

/// Tap to switch, long press for details – with a subtle press animation.
private struct TileGestures: ViewModifier {
    let onTap: () -> Void
    let onLongPress: () -> Void
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: isPressed)
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.4) {
                Haptics.longPress()
                onLongPress()
            } onPressingChanged: { pressing in
                isPressed = pressing
            }
    }
}

extension View {
    func tileGestures(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) -> some View {
        modifier(TileGestures(onTap: onTap, onLongPress: onLongPress))
    }
}

/// Large device tile used in rooms and favorites.
struct DeviceTile: View {
    let entity: HAEntity
    let name: String
    var subtitle: String?
    var isFavorite = false
    var isHighlighted = false
    let onTap: () -> Void
    let onLongPress: () -> Void

    private var isOn: Bool { entity.isActive || isHighlighted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: entity.symbolName)
                    .symbolVariant(isOn ? .fill : .none)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(isOn ? AnyShapeStyle(entity.tint.gradient) : AnyShapeStyle(Color(.tertiarySystemFill))))
                Spacer()
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            Spacer(minLength: 14)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(entity.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(entity.tint.opacity(isOn ? 0.16 : 0))
                }
        }
        .opacity(entity.isUnavailable ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.snappy, value: entity.state)
        .animation(.snappy, value: isHighlighted)
        .tileGestures(onTap: onTap, onLongPress: onLongPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(entity.statusText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Details", onLongPress)
    }
}

/// Shows connection problems and rejected commands at the top of the screen.
struct StatusBanner: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            if let error = store.transientError {
                banner(text: error, symbol: "exclamationmark.triangle.fill", tint: .red)
            }
            switch store.status {
            case .connecting where !store.entities.isEmpty && store.isConnectionProblemVisible:
                banner(text: "Verbinde …", symbol: nil, tint: .secondary)
            case .waiting(let retryAt) where store.isConnectionProblemVisible:
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(retryAt.timeIntervalSince(context.date).rounded(.up)))
                    banner(text: "Offline · neuer Versuch in \(seconds) s", symbol: "wifi.slash", tint: .orange)
                }
                .onTapGesture { store.restart() }
            case .failed(let message):
                banner(text: message, symbol: "xmark.octagon.fill", tint: .red)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .animation(.snappy, value: store.status)
        .animation(.snappy, value: store.transientError)
        .animation(.snappy, value: store.isConnectionProblemVisible)
    }

    private func banner(text: String, symbol: String?, tint: Color) -> some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(tint)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text).font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Identifiable wrapper for presenting the detail sheet.
struct DetailItem: Identifiable {
    let id: String
}

/// Two-column grid that lays out all tiles at once. Used instead of `LazyVGrid` inside the scroll views:
/// several lazy grids stacked in a `VStack` get re-measured while scrolling, so the page jumps and flickers
/// near the bottom. Tiles in a row get the height of the tallest one, like in `LazyVGrid`.
struct TileGrid: Layout {
    var columns = 2
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let heights = rowHeights(subviews: subviews, columnWidth: columnWidth(for: width))
        let total = heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = columnWidth(for: bounds.width)
        let heights = rowHeights(subviews: subviews, columnWidth: columnWidth)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (columnWidth + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: columnWidth, height: height)
                )
            }
            y += height + spacing
        }
    }

    private func columnWidth(for width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func rowHeights(subviews: Subviews, columnWidth: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
    }
}
