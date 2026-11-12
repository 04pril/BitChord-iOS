import BitChordCore
import SwiftUI
import UIKit

struct LyricsTypographyScreen: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LyricsTypographyPreview(preference: settings.lyricsTypography)
                    .frame(height: 155)
                    .listRowBackground(Color.black.opacity(0.8))
            } header: { Text(L10n.tr("lyrics_font_preview")) }
            Section {
                Toggle(L10n.tr("lyrics_font_separate"), isOn: separateScripts)
            } footer: { Text(L10n.tr("lyrics_font_separate_help")) }
            if settings.lyricsTypography.separateScripts {
                fontControls(L10n.tr("lyrics_font_korean"), choice: $settings.lyricsTypography.korean)
                fontControls(L10n.tr("lyrics_font_english"), choice: $settings.lyricsTypography.english)
            } else {
                fontControls(L10n.tr("lyrics_font_common"), choice: $settings.lyricsTypography.common)
            }
            Section(L10n.tr("lyrics_font_display")) {
                Toggle(L10n.tr("show_lyrics_provider"), isOn: $settings.showLyricsProvider)
                Toggle(L10n.blurUnfocusedLyrics, isOn: $settings.lyricsBlur)
            }
            Section {
                Button(L10n.resetToDefault) {
                    settings.lyricsTypography = .standard
                    settings.showLyricsProvider = false
                    settings.lyricsBlur = true
                }
            } footer: { Text(L10n.tr("lyrics_font_default_help")) }
        }
        .navigationTitle(L10n.tr("lyrics_typography"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.lyricsTypography")
    }

    private var separateScripts: Binding<Bool> {
        Binding(get: { settings.lyricsTypography.separateScripts }, set: { enabled in
            var value = settings.lyricsTypography
            if enabled && value.korean == LyricsFontChoice() && value.english == LyricsFontChoice() {
                value.korean = value.common
                value.english = value.common
            }
            value.separateScripts = enabled
            settings.lyricsTypography = value
        })
    }

    private func fontControls(_ title: String, choice: Binding<LyricsFontChoice>) -> some View {
        Section(title) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.tr("lyrics_font_size"))
                    Spacer()
                    Text("\(Int(choice.wrappedValue.size)) pt").monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: choice.size, in: 22...44, step: 1)
                    .accessibilityLabel(title + ": " + L10n.tr("lyrics_font_size"))
            }
            Picker(L10n.tr("lyrics_font_weight"), selection: choice.weight) {
                ForEach(LyricsFontWeight.allCases, id: \.self) { weight in
                    Text(L10n.tr("lyrics_weight_" + weight.rawValue)).tag(weight)
                }
            }
        }
    }
}

/// The preview uses the same attributed-font builder as the animated renderer.
private struct LyricsTypographyPreview: UIViewRepresentable {
    let preference: LyricsTypography
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isAccessibilityElement = true
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        label.attributedText = LyricTypeface.synced.customized(using: preference)
            .attributedText("You and I\n널 향해 there's no danger", paragraph: paragraph)
        label.accessibilityLabel = L10n.tr("lyrics_font_preview")
    }
}
