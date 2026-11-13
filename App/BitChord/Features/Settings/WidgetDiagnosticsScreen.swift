import BitChordCore
import SwiftUI
import UIKit
import WidgetKit

struct WidgetDiagnosticsScreen: View {
    @Environment(PlayerController.self) private var player
    @State private var canWrite = false
    @State private var report = ""
    @State private var snapshotTitle = ""
    @State private var receiptAt: Date?
    @State private var actionError: String?

    var body: some View {
        Form {
            Section {
                Label(L10n.tr(canWrite ? "widget_link_available" : "widget_link_unavailable"),
                      systemImage: canWrite ? "checkmark.circle" : "exclamationmark.circle")
                LabeledContent(L10n.tr("widget_link_saved_track"), value: snapshotTitle)
                if let receiptAt {
                    LabeledContent(L10n.tr("widget_link_last_read")) { Text(receiptAt, style: .time) }
                } else {
                    Text(L10n.tr("widget_link_not_read")).foregroundStyle(.secondary)
                }
            } footer: { Text(L10n.tr("widget_link_help")) }
            Section {
                Button(L10n.tr("widget_link_publish")) { publish() }
                    .disabled(!canWrite || player.currentSong == nil)
                Button(L10n.tr("widget_link_refresh")) { refresh() }
                Button(L10n.tr("widget_link_copy")) {
                    refresh()
                    UIPasteboard.general.string = report
                }
                if let actionError { Text(actionError).foregroundStyle(.red).textSelection(.enabled) }
            } footer: { Text(L10n.tr("widget_link_steps")) }
        }
        .navigationTitle(L10n.tr("widget_link_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .accessibilityIdentifier("settings.widgetConnection")
    }

    private func refresh() {
        var failure: String?
        do { try SharedAppGroup.probeContainer(); canWrite = true }
        catch { canWrite = false; failure = error.localizedDescription }
        let snapshot = NowPlayingSnapshot.loadShared()
        snapshotTitle = snapshot?.title ?? L10n.tr("widget_link_no_snapshot")
        let receipt = NowPlayingSnapshot.widgetReadReceipt
        receiptAt = nil
        if let data = receipt.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let at = json["at"] as? Double { receiptAt = Date(timeIntervalSince1970: at) }
        report = "BitChord widget diagnostics\n\(DiagnosticLog.launchHeader())\n\(SharedAppGroup.diagnostics)\nreadWrite=\(canWrite)\nerror=\(failure ?? "none")\nsnapshot=\(snapshot?.videoId ?? "none") updated=\(snapshot?.updatedAt.description ?? "none")\nwidgetReceipt=\(receipt)"
    }

    private func publish() {
        guard var snapshot = WidgetSnapshotObserver.snapshot(of: player) else { return }
        if let previous = NowPlayingSnapshot.loadShared(), previous.videoId == snapshot.videoId {
            snapshot.artworkFileName = previous.artworkFileName
        }
        do {
            try snapshot.saveShared()
            WidgetCenter.shared.reloadAllTimelines()
            actionError = nil
            TrackLog.i("Widget", "manual snapshot publish requested", about: snapshot.videoId)
        } catch { actionError = error.localizedDescription }
        refresh()
    }
}
