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
                    ContainersView()
                case let other:
                    PlaceholderScreen(section: other)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(Palette.text)
        .background(Palette.window)
        .background(TrafficLightsPositioner())
        .ignoresSafeArea()
    }
}

struct SidebarPanel: View {
    /// Corner radius of a hidden-title-bar window on macOS 26 (measured at runtime: 16 pt).
    static let windowCornerRadius: CGFloat = 16

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
                (.cleanup, nil),
                (.profiles, model.colima.profileCount > 0 ? "\(model.colima.profileCount)" : nil),
            ])
            SettingsLink {
                SidebarRowLabel(icon: .settings, title: "Settings", trailing: "⌘,", isSelected: false)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 224, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        // Concentric with the window's corners: window radius minus the 8 pt margin.
        .glassSurface(RoundedRectangle(cornerRadius: Self.windowCornerRadius - 8), fill: Palette.sidebar)
        .padding(8)
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
                Button { model.section = section } label: {
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
        .background(isSelected ? Palette.selected : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
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
                    pill("Stop", color: Palette.danger) { await model.performColima(.stop) }
                } else {
                    pill("Start", color: Palette.greenText) { await model.performColima(.start) }
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
            Text(title)
                .font(.ui(12))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(Palette.chip, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// Screens that are designed but not built yet keep the window header.
struct PlaceholderScreen: View {
    let section: SidebarSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.ui(15, .semibold))
                .padding(.leading, 8)
                .frame(minHeight: 60)
            ContentUnavailableView(section.title, systemImage: "hammer", description: Text("Designed, not built yet."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
