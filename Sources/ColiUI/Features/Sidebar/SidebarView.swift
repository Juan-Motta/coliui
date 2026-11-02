import ColiUICore
import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable {
    case containers, images, volumes, networks, cleanup, profiles

    var title: String { rawValue.capitalized }

    var icon: LineIcon.Kind {
        switch self {
        case .containers: .containers
        case .images: .images
        case .volumes: .volumes
        case .networks: .networks
        case .cleanup: .cleanup
        case .profiles: .profiles
        }
    }
}

/// Window layout from the designs: an inset glass sidebar (224 pt, 8 pt margin) beside the content.
/// The title bar is hidden; the system traffic lights sit in the sidebar's top row.
struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            SidebarPanel()
            Group {
                switch model.section ?? .containers {
                case .containers:
                    if let detail = model.detail {
                        ContainerDetailView(detail: detail)
                    } else {
                        ContainersView()
                    }
                case .cleanup:
                    CleanupView()
                case .profiles:
                    ProfilesView()
                case .images:
                    ImagesView()
                case .volumes:
                    VolumesView()
                case .networks:
                    NetworksView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // While a modal is up, the screen behind it takes no clicks or shortcuts (⌘⌫, ⌘N, Esc…).
        .disabled(model.isSettingsPresented || model.presentedModal != nil)
        .foregroundStyle(Palette.text)
        .background(Palette.window)
        .ignoresSafeArea()
        // Create modals (Run, Pull, New volume / network / profile); a click outside closes them.
        .overlay { ModalHost() }
        .animation(.easeOut(duration: 0.18), value: model.presentedModal != nil)
        // A custom modal rather than a sheet: a click outside it closes it.
        .overlay {
            if model.isSettingsPresented {
                ZStack {
                    Color.black.opacity(0.25)
                        .contentShape(.rect)
                        .onTapGesture { model.isSettingsPresented = false }
                        .accessibilityLabel("Close Settings")
                        .accessibilityAddTraits(.isButton)
                    SettingsView()
                        .clipShape(.rect(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.cardBorder, lineWidth: 1))
                        .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
                .ignoresSafeArea()
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.isSettingsPresented)
        .onChange(of: model.settings.showInDock) { model.applySystemSettings() }
        .onAppear { model.mainWindowOpened() }
        .onDisappear { model.mainWindowClosed() }
        .onChange(of: model.settings.theme) { model.applySystemSettings() }
    }
}

struct SidebarPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Color.clear.frame(height: 12) // traffic lights row
            ColimaCard()
            group("DOCKER", [
                (.containers, "\(model.containers.containers.count)"),
                (.images, model.summary.map { "\($0.images)" }),
                (.volumes, model.summary.map { "\($0.volumes)" }),
                (.networks, model.summary.map { "\($0.networks)" }),
            ])
            group("SYSTEM", [
                (.cleanup, model.cleanup.usage.map { _ in ByteFormat.short(model.cleanup.totalReclaimable) }),
                (.profiles, model.colima.profileCount > 0 ? "\(model.colima.profileCount)" : nil),
            ])
            Button { model.isSettingsPresented = true } label: {
                SidebarRowLabel(icon: .settings, title: "Settings", trailing: "⌘,", isSelected: model.isSettingsPresented)
            }
            // Also here: without a Dock icon the app has no menu bar to carry ⌘,.
            .keyboardShortcut(",")
            .buttonStyle(.plain)
            .help("Open Settings (⌘,)")
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 240, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        // Edge to edge like Finder, same surface as the containers card, a hairline on the trailing edge.
        .background(Palette.card)
        .overlay(alignment: .trailing) { Palette.cardBorder.frame(width: 1) }
    }

    private func group(_ title: String, _ items: [(SidebarSection, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.ui(11, .semibold))
                .tracking(0.44)
                .foregroundStyle(Palette.sidebarSecondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            ForEach(items, id: \.0) { section, count in
                Button { model.select(section) } label: {
                    SidebarRowLabel(
                        icon: section.icon,
                        title: section.title,
                        trailing: count,
                        isSelected: (model.section ?? .containers) == section
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits((model.section ?? .containers) == section ? .isSelected : [])
            }
        }
    }
}

/// `.nav`: 30 pt row, 8 pt radius, 10 pt icon gap; selected = blue tint, blue icon, semibold.
struct SidebarRowLabel: View {
    let icon: LineIcon.Kind
    let title: String
    let trailing: String?
    let isSelected: Bool

    var body: some View {
        Hoverable { hovered in
            HStack(spacing: 10) {
                LineIcon(kind: icon).icon(isSelected ? Palette.accent : Palette.sidebarSecondary, size: 16)
                Text(title)
                    .font(.ui(13, isSelected ? .semibold : .regular))
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing).font(.ui(12)).foregroundStyle(Palette.sidebarSecondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isSelected ? Palette.selected : hovered ? Palette.hoverSubtle : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
    }
}

struct ColimaCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let colima = model.colima
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("COLIMA")
                    .font(.ui(11, .semibold))
                    .tracking(0.44)
                    .foregroundStyle(Palette.sidebarSecondary)
                Spacer()
                HStack(spacing: 5) {
                    if colima.isBusy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle().fill(colima.isRunning ? Palette.greenDot : Palette.grayDot).frame(width: 7, height: 7)
                    }
                    Text(colima.statusTitle)
                }
                .font(.ui(11, .semibold))
                .foregroundStyle(colima.isRunning && !colima.isBusy ? Palette.greenText : Palette.sidebarSecondary)
            }
            Text(colima.profile).font(.ui(14, .semibold))
            if let instance = colima.instance {
                Text("\(instance.resourcesSummary) · \(instance.vmType ?? instance.arch)")
                    .font(.ui(12))
                    .foregroundStyle(Palette.sidebarSecondary)
            } else if let error = colima.errorMessage {
                Text(error).font(.ui(12)).foregroundStyle(Palette.sidebarSecondary).lineLimit(3)
            }
            HStack(spacing: 6) {
                if colima.isRunning {
                    pill("Restart", color: Palette.text) { await model.performColima(.restart) }
                        .help("Restart the Colima VM “\(colima.profile)”")
                    pill("Stop", color: Palette.danger) { await model.performColima(.stop) }
                        .help("Stop the Colima VM “\(colima.profile)”")
                } else {
                    pill("Start", color: Palette.greenText) { await model.performColima(.start) }
                        .help("Start the Colima VM “\(colima.profile)”")
                }
            }
            .disabled(colima.isBusy)
            .padding(.top, 4)
        }
        .padding(12)
        .background(Palette.colimaCard, in: .rect(cornerRadius: 12))
    }

    private func pill(_ title: String, color: Color, action: @escaping @MainActor () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Hoverable { hovered in
                Text(title)
                    .font(.ui(12))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Palette.colimaButton, in: .capsule)
                    .overlay(Capsule().fill(hovered ? Palette.hoverSubtle : .clear))
                    .contentShape(.capsule)
            }
        }
        .buttonStyle(.plain)
    }
}
