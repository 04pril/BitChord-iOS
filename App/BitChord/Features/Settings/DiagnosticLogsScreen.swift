import BitChordCore
import SwiftUI
import UIKit

struct DiagnosticLogsScreen: View {
    @Environment(AppSettings.self) private var settings
    @State private var working = false
    @State private var share: LogShare?
    @State private var errorMessage: String?
    @State private var confirmClear = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(L10n.tr("full_logs_record"), isOn: $settings.keepDiagnosticLog)
                    .accessibilityIdentifier("settings.fullLogs.record")
                Label(L10n.tr(settings.keepDiagnosticLog ? "full_logs_running" : "full_logs_stopped"),
                      systemImage: settings.keepDiagnosticLog ? "record.circle" : "pause.circle")
                    .foregroundStyle(.secondary)
            } footer: { Text(L10n.tr("full_logs_help")) }
            Section {
                Button {
                    working = true
                    errorMessage = nil
                    Task { @MainActor in
                        defer { working = false }
                        do { share = LogShare(url: try await DiagnosticLog.shared.snapshotForSharing()) }
                        catch { errorMessage = error.localizedDescription }
                    }
                } label: {
                    Label(L10n.tr("full_logs_share"), systemImage: "square.and.arrow.up")
                }
                .disabled(working)
                .accessibilityIdentifier("settings.fullLogs.share")
                Button(role: .destructive) { confirmClear = true } label: {
                    Label(L10n.tr("full_logs_clear"), systemImage: "trash")
                }
                .disabled(working)
                if working { ProgressView() }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            } footer: { Text(L10n.tr("full_logs_storage")) }
        }
        .navigationTitle(L10n.tr("full_logs_title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { item in LogShareSheet(url: item.url) }
        .confirmationDialog(L10n.tr("full_logs_clear_confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L10n.tr("full_logs_clear"), role: .destructive) {
                working = true
                errorMessage = nil
                Task { @MainActor in
                    defer { working = false }
                    do { try await DiagnosticLog.shared.clearFiles() }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .accessibilityIdentifier("settings.fullLogs")
    }
}

private struct LogShare: Identifiable {
    let id = UUID()
    let url: URL
}

private struct LogShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack { DiagnosticLogsScreen().environment(AppSettings.shared) }
}
