import AppIntents
import SwiftUI
import WidgetKit

@main
struct ZuhauseWidgetBundle: WidgetBundle {
    var body: some Widget {
        FavoritesWidget()
    }
}

/// Home screen widget with the first four favorites; tapping a tile toggles it via App Intent.
struct FavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.favorites, provider: FavoritesProvider()) { entry in
            FavoritesWidgetView(entry: entry)
                .containerBackground(Color(.systemGroupedBackground), for: .widget)
        }
        .configurationDisplayName("Favoriten")
        .description("Deine ersten vier Favoriten – antippen zum Schalten.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FavoritesEntry: TimelineEntry {
    enum Content {
        case notConfigured
        case noFavorites
        case devices([CachedDevice])
    }

    let date: Date
    let content: Content
}

struct FavoritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavoritesEntry {
        FavoritesEntry(date: .now, content: .devices(Self.sample))
    }

    func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void) {
        if context.isPreview {
            completion(FavoritesEntry(date: .now, content: .devices(Self.sample)))
        } else {
            completion(FavoritesEntry(date: .now, content: Self.cachedContent()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesEntry>) -> Void) {
        // WidgetKit allows calling the completion handler from any thread, it is just not annotated as Sendable.
        let reply = UncheckedSendable(value: completion)
        Task {
            let content = await Self.liveContent()
            let entry = FavoritesEntry(date: .now, content: content)
            reply.value(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }

    /// Favorites from the shared cache, without network access.
    private static func cachedContent() -> FavoritesEntry.Content {
        guard SharedStorage.serverConfiguration != nil else { return .notConfigured }
        let favorites = Array(SharedStorage.favorites.prefix(4))
        guard !favorites.isEmpty else { return .noFavorites }
        let cache = Dictionary(SharedStorage.cachedDevices.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return .devices(favorites.compactMap { cache[$0] })
    }

    /// Fresh states from Home Assistant; falls back to the cache when HA is not reachable.
    private static func liveContent() async -> FavoritesEntry.Content {
        guard case .devices = cachedContent(), let states = try? await HARestClient.resolve().states() else {
            return cachedContent()
        }
        SharedStorage.updateCache(with: states)
        return cachedContent()
    }

    private static let sample: [CachedDevice] = [
        CachedDevice(entity: HAEntity(entityId: "light.stehlampe", state: "on", attributes: ["friendly_name": "Stehlampe", "brightness": 180]), areaName: "Wohnzimmer"),
        CachedDevice(entity: HAEntity(entityId: "light.flur", state: "off", attributes: ["friendly_name": "Flur"]), areaName: nil),
        CachedDevice(entity: HAEntity(entityId: "climate.heizung", state: "heat", attributes: ["friendly_name": "Heizung", "current_temperature": 20.8, "temperature": 22]), areaName: "Wohnzimmer"),
        CachedDevice(entity: HAEntity(entityId: "scene.lesen", state: "unknown", attributes: ["friendly_name": "Lesen"]), areaName: "Wohnzimmer"),
    ]
}

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

struct FavoritesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FavoritesEntry

    var body: some View {
        switch entry.content {
        case .notConfigured:
            message("Öffne Zuhause, um Home Assistant zu verbinden.", symbol: "house")
        case .noFavorites:
            message("Markiere Geräte in der App mit einem Stern.", symbol: "star")
        case .devices(let devices):
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    slot(devices, 0)
                    slot(devices, 1)
                }
                GridRow {
                    slot(devices, 2)
                    slot(devices, 3)
                }
            }
        }
    }

    @ViewBuilder
    private func slot(_ devices: [CachedDevice], _ index: Int) -> some View {
        if devices.indices.contains(index) {
            WidgetTile(device: devices[index], compact: family == .systemSmall)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground).opacity(0.5))
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint)
            Text(text).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

private struct WidgetTile: View {
    let device: CachedDevice
    let compact: Bool

    private var entity: HAEntity { device.entity }

    var body: some View {
        if entity.kind.isControllable {
            Button(intent: ToggleDeviceIntent(device: DeviceEntity(device))) { content }
                .buttonStyle(.plain)
        } else {
            // Sensors are display-only; tapping opens the app.
            content
        }
    }

    private var content: some View {
        let isOn = entity.isActive
        let tint = entity.tint
        return VStack(alignment: .leading, spacing: 2) {
            Image(systemName: entity.symbolName)
                .symbolVariant(isOn ? .fill : .none)
                .font(.system(size: compact ? 16 : 15, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .frame(width: compact ? 30 : 28, height: compact ? 30 : 28)
                .background(Circle().fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color(.tertiarySystemFill))))
            if !compact {
                Spacer(minLength: 0)
                Text(device.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(entity.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(compact ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .center : .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(isOn ? 0.16 : 0)))
        )
        .opacity(entity.isUnavailable ? 0.5 : 1)
        .invalidatableContent()
    }

}
