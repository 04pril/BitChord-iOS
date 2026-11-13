import BitChordCore
import SwiftUI

/// Selecting a mode stays in the sheet so its own options expand immediately below it.
struct PlaybackModeSheet: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.tr("playback_modes_help"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 18)
                    ForEach(DirectSourceStream.allCases, id: \.self) { mode in
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { settings.directSourceStream = mode }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: settings.directSourceStream == mode ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(settings.directSourceStream == mode ? Color.accentColor : .secondary)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(mode.settingsLabel).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                        Text(mode.settingsDetail).font(.subheadline).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(settings.directSourceStream == mode ? .isSelected : [])
                            if settings.directSourceStream == mode {
                                if mode == .queueOnly {
                                    Toggle(isOn: $settings.automaticSourceSwitch) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(L10n.tr("playback_auto_switch"))
                                            Text(L10n.tr("playback_auto_switch_help"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .tint(.accentColor)
                                    .padding(.leading, 34)
                                    .accessibilityIdentifier("playbackMode.automaticSwitch")
                                } else if mode == .always {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Picker(L10n.tr("playback_addon_wait"), selection: $settings.addonWaitSeconds) {
                                            ForEach(AppSettings.addonWaitChoices, id: \.self) { seconds in
                                                Text("\(seconds)\(L10n.tr("playback_seconds_suffix"))").tag(seconds)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        Text(L10n.tr("playback_addon_wait_help"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 34)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.bottom, 12)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.tr("direct_source_stream"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.close) { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
