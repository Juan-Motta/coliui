import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable {
    case containers, images, volumes, networks, cleanup, profiles

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .containers: "shippingbox"
        case .images: "square.stack.3d.up"
        case .volumes: "cylinder"
        case .networks: "point.3.connected.trianglepath.dotted"
        case .cleanup: "trash"
        case .profiles: "desktopcomputer"
        }
    }
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView(selection: $model.section)
        } detail: {
            switch model.section ?? .containers {
            case .containers:
                ContainersView()
            case let other:
                ContentUnavailableView(
                    other.title,
                    systemImage: other.symbol,
                    description: Text("Designed, not built yet.")
                )
            }
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarSection?

    var body: some View {
        List(selection: $selection) {
            Section("DOCKER") {
                row(.containers, badge: model.containers.containers.count)
                row(.images, badge: model.summary?.images ?? 0)
                row(.volumes, badge: model.summary?.volumes ?? 0)
                row(.networks, badge: model.summary?.networks ?? 0)
            }
            Section("SYSTEM") {
                row(.cleanup)
                row(.profiles, badge: model.colima.profileCount)
            }
        }
        .safeAreaInset(edge: .top) {
            ColimaCard()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom) {
            SettingsLink {
                HStack(spacing: 8) {
                    Label("Settings", systemImage: "gearshape")
                    Spacer()
                    Text("⌘,").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 230)
    }

    /// `.tag` must be the outermost modifier, otherwise the List can't select the row.
    private func row(_ section: SidebarSection, badge: Int = 0) -> some View {
        Label(section.title, systemImage: section.symbol)
            .badge(badge)
            .tag(section)
    }
}

struct ColimaCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let colima = model.colima
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("COLIMA")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(title: colima.statusTitle, tint: colima.statusTint, isBusy: colima.isBusy)
            }
            Text(colima.profile).font(.headline)
            if let instance = colima.instance {
                Text("\(instance.resourcesSummary) · \(instance.arch)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = colima.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: 8) {
                if colima.isRunning {
                    Button { Task { await model.performColima(.restart) } } label: {
                        Text("Restart").frame(maxWidth: .infinity)
                    }
                    Button { Task { await model.performColima(.stop) } } label: {
                        Text("Stop").frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.red)
                } else {
                    Button { Task { await model.performColima(.start) } } label: {
                        Text("Start").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(colima.isBusy)
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
