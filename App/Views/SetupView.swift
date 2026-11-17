import SwiftUI

/// First-run setup and "edit connection": local URL, optional external URL and access token.
struct SetupView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var isEditing = false

    @State private var localURL = ""
    @State private var externalURL = ""
    @State private var token = ""
    @State private var isChecking = false
    @State private var errorText: String?
    @State private var canSaveAnyway = false

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.tint)
                            Text("Verbinde die App mit deinem Home Assistant.")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Adresse im WLAN", text: $localURL, prompt: Text(verbatim: "http://homeassistant.local:8123"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Adresse im WLAN")
                } footer: {
                    Text("Wird genutzt, solange das iPhone im WLAN ist.")
                }

                Section {
                    TextField("Adresse von unterwegs", text: $externalURL, prompt: Text(verbatim: "https://…ui.nabu.casa"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Adresse von unterwegs (optional)")
                } footer: {
                    Text("Zum Beispiel Nabu Casa oder deine eigene Domain. Wird ohne WLAN genutzt.")
                }

                Section {
                    SecureField(isEditing ? "Leer lassen, um ihn zu behalten" : "Token einfügen", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard") {
                        token = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    }
                } header: {
                    Text("Langlebiges Zugriffstoken")
                } footer: {
                    Text("In Home Assistant: Profil → Sicherheit → Langlebige Zugriffstoken → Token erstellen. Der Token wird nur im iOS-Schlüsselbund gespeichert.")
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        if canSaveAnyway {
                            Button("Trotzdem speichern") { save(validated: true) }
                        }
                    }
                }

                Section {
                    Button {
                        save(validated: false)
                    } label: {
                        HStack {
                            Spacer()
                            if isChecking {
                                ProgressView()
                            } else {
                                Text("Verbinden").font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isChecking)
                }
            }
            .navigationTitle(isEditing ? "Verbindung" : "Willkommen")
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
            }
            .onAppear {
                localURL = store.configuration?.localURL?.absoluteString ?? ""
                externalURL = store.configuration?.externalURL?.absoluteString ?? ""
            }
        }
    }

    /// Validates the input, checks the connection and stores everything.
    /// - Parameter validated: `true` skips the reachability check ("Trotzdem speichern").
    private func save(validated: Bool) {
        errorText = nil
        canSaveAnyway = false

        let trimmedLocal = localURL.trimmingCharacters(in: .whitespaces)
        let trimmedExternal = externalURL.trimmingCharacters(in: .whitespaces)
        let local = ServerConfiguration.normalize(trimmedLocal)
        let external = ServerConfiguration.normalize(trimmedExternal)
        if (!trimmedLocal.isEmpty && local == nil) || (!trimmedExternal.isEmpty && external == nil) {
            errorText = HAError.invalidURL.localizedDescription
            return
        }
        let configuration = ServerConfiguration(localURL: local, externalURL: external)
        guard configuration.isComplete else {
            errorText = "Bitte mindestens eine Adresse angeben."
            return
        }
        let newToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let effectiveToken = newToken.isEmpty ? TokenStore.load() : newToken else {
            errorText = "Bitte den Token einfügen."
            return
        }

        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                if !validated {
                    _ = try await HARestClient.resolve(configuration: configuration, token: effectiveToken)
                }
                try store.configure(configuration, token: newToken.isEmpty ? nil : newToken)
                if isEditing { dismiss() }
            } catch {
                errorText = error.localizedDescription
                canSaveAnyway = (error as? HAError) != .unauthorized
            }
        }
    }
}
