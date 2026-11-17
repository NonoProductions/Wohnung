import AppIntents

/// Siri phrases. Apple requires the app name in every phrase, e.g. "Schalte Stehlampe mit Zuhause ein".
struct ZuhauseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TurnOnDeviceIntent(),
            phrases: [
                "Schalte \(\.$device) mit \(.applicationName) ein",
                "Schalte in \(.applicationName) \(\.$device) ein",
                "Mach \(\.$device) mit \(.applicationName) an",
            ],
            shortTitle: "Einschalten",
            systemImageName: "power"
        )
        AppShortcut(
            intent: TurnOffDeviceIntent(),
            phrases: [
                "Schalte \(\.$device) mit \(.applicationName) aus",
                "Schalte in \(.applicationName) \(\.$device) aus",
                "Mach \(\.$device) mit \(.applicationName) aus",
            ],
            shortTitle: "Ausschalten",
            systemImageName: "poweroff"
        )
        AppShortcut(
            intent: ToggleDeviceIntent(),
            phrases: [
                "Schalte \(\.$device) mit \(.applicationName) um",
            ],
            shortTitle: "Umschalten",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
