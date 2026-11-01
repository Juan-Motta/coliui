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
            Section("Docker") {
                row(.containers).badge(model.containers.containers.count)
                row(.images)
                row(.volumes)
                row(.networks)
            }
            Section("System") {
                row(.cleanup)
                row(.profiles)
            }
        }
        .safeAreaInset(edge: .top) {
            ColimaCard()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 230)
    }

    private func row(_ section: SidebarSection) -> some View {
        Label(section.title, systemImage: section.symbol).tag(section)
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
            HStack {
                if colima.isRunning {
                    Button("Restart") { Task { await model.performColima(.restart) } }
                    Button("Stop", role: .destructive) { Task { await model.performColima(.stop) } }
                } else {
                    Button("Start") { Task { await model.performColima(.start) } }
                        .buttonStyle(.glassProminent)
                }
            }
            .controlSize(.small)
            .disabled(colima.isBusy)
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
