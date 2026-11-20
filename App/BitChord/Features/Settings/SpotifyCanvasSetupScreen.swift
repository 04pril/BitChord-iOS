import BitChordCore
import SwiftUI

// Ports ui/screens/SpotifyCanvasAuthScreen.kt, opened from Settings › Appearance › "Set up Spotify
// Canvas" (under Animated cover art).

/// The sp_dc cookie Spotify Canvas needs, plus the two Canvas behaviour switches. Save stores the
/// token and goes back, as Android's does.
struct SpotifyCanvasSetupScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var tokenInput = ""
    @State private var loaded = false
    @State private var checking = false
    @State private var checkResult: String?

    private var normalizedToken: String {
        let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let part = trimmed.components(separatedBy: ";").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("sp_dc=") }) {
            return String(part.trimmingCharacters(in: .whitespaces).dropFirst(6))
        }
        return trimmed
    }

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Text(L10n.spotifyCanvasSetupDescription)
                    .font(.body)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
            }
            Section {
                SettingsToggleRow(title: L10n.spotifyCanvasAutoHide, subtitle: L10n.spotifyCanvasAutoHideSubtitle,
                                  isOn: $settings.spotifyCanvasAutoHide)
                SettingsToggleRow(title: L10n.prioritizeSpotifyCanvas, subtitle: L10n.prioritizeSpotifyCanvasSubtitle,
                                  isOn: $settings.prioritizeSpotifyCanvas)
            } footer: {
                Text(L10n.spotifyCanvasSetupSteps)
            }
            Section {
                SecureField(L10n.spdcToken, text: $tokenInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .accessibilityIdentifier("spotifyCanvas.token")
            } header: {
                Text(L10n.spdcToken)
            }
            Section {
                Button(L10n.tr("spotify_canvas_check")) {
                    settings.spotifySpdcToken = normalizedToken
                    checking = true
                    checkResult = nil
                    Task {
                        await app.canvas.clearCache()
                        let token = await app.spotifyCanvasTokens.accessToken()
                        checkResult = L10n.tr(token == nil ? "spotify_canvas_check_failed" : "spotify_canvas_check_ok")
                        checking = false
                    }
                }
                .disabled(checking || normalizedToken.isEmpty)
                if checking { ProgressView() }
                if let checkResult { Text(checkResult).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                Button {
                    let value = normalizedToken
                    Task {
                        await app.canvas.clearCache()
                        settings.spotifySpdcToken = value
                        dismiss()
                    }
                } label: {
                    Text(L10n.save)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.spotifyCanvasSetup)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            tokenInput = settings.spotifySpdcToken
        }
    }
}
