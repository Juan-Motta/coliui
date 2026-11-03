import AppKit
import ColiUICore
import SwiftUI

/// Updates.dc.html › Update modal: the offer, its release notes, then Available → Downloading → Ready.
struct UpdateModal: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updates = model.updates
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "ColiUI \(updates.offer?.version ?? "") is available").font(.ui(17, .semibold))
                    Text(verbatim: "You have \(updates.offer?.currentVersion ?? "") · \(updates.sizeText) download")
                        .font(.ui(12))
                        .foregroundStyle(Palette.secondary)
                }
            }

            if let notes = updates.offer?.notes, !notes.isEmpty {
                ReleaseNotesView(sections: notes)
            }

            switch updates.step {
            case .downloading, .verifying:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(updates.step == .verifying ? "Verifying" : "Downloading").font(.ui(12, .semibold))
                        Spacer()
                        Text(verbatim: updates.downloadText).font(.ui(11)).foregroundStyle(Palette.secondary).monospacedDigit()
                    }
                    ProgressBar(fraction: updates.step == .verifying ? nil : updates.downloadProgress)
                    Text("You can close this; the download keeps going.").font(.ui(11)).foregroundStyle(Palette.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Palette.field, in: .rect(cornerRadius: 14))
            case .ready, .installing:
                HStack(spacing: 10) {
                    LineIcon(kind: .check).icon(Palette.greenText, size: 16, svgStrokeWidth: 2.6)
                    Text("Downloaded and verified. ColiUI relaunches to finish; your containers keep running.")
                        .font(.ui(12))
                        .foregroundStyle(Palette.greenText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.greenPill, in: .rect(cornerRadius: 14))
            case .available, nil:
                EmptyView()
            }

            HStack(spacing: 8) {
                if updates.step == .available {
                    Button("Skip this version") { updates.skip() }
                        .buttonStyle(.plain)
                        .font(.ui(12))
                        .foregroundStyle(Palette.accent)
                }
                Spacer()
                switch updates.step {
                case .available, nil:
                    Button("Later") { updates.later() }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Install update") { updates.install() }
                        .buttonStyle(TintButtonStyle())
                        .keyboardShortcut(.defaultAction)
                case .downloading, .verifying:
                    Button("Cancel") { updates.cancelDownload() }
                        .buttonStyle(PillButtonStyle())
                        .disabled(updates.step == .verifying)
                    Button("Install update") {}
                        .buttonStyle(TintButtonStyle())
                        .disabled(true)
                case .ready, .installing:
                    Button("Later") { updates.later() }
                        .buttonStyle(PillButtonStyle())
                        .disabled(updates.step == .installing)
                    Button("Relaunch now") { updates.relaunch() }
                        .buttonStyle(TintButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(updates.step == .installing)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .frame(width: 500)
        .modalSurface()
    }
}

/// `.notes`: section headings over bulleted items, the scope in bold; scrolls past 230 pt.
private struct ReleaseNotesView: View {
    let sections: [ReleaseNotes.Section]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = section.title {
                            Text(verbatim: title).font(.ui(12, .semibold))
                        }
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(verbatim: "•")
                                (item.scope.map { Text(verbatim: "\($0): ").bold() } ?? Text(verbatim: ""))
                                    + Text(verbatim: item.text)
                            }
                            .font(.ui(12))
                            .foregroundStyle(Palette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 230)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.field, in: .rect(cornerRadius: 14))
    }
}

/// Updates.dc.html › Menu bar popover: shown while an update waits; View opens the main window with the modal.
struct UpdateBanner: View {
    let version: String
    let onView: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LineIcon(kind: .download).icon(Palette.tint, size: 16, svgStrokeWidth: 2.2)
            VStack(alignment: .leading, spacing: 0) {
                Text("Update available").font(.ui(12, .semibold))
                Text(verbatim: "ColiUI \(version)").font(.ui(11)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button("View", action: onView)
                .buttonStyle(.plain)
                .font(.ui(12, .semibold))
                .foregroundStyle(Palette.accent)
        }
        .padding(10)
        .background(Palette.selected, in: .rect(cornerRadius: 10))
    }
}
