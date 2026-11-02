import AppKit
import ColiUICore
import SwiftUI

/// Networks.dc.html: header (60 pt), optional create bar, filter row, then the networks card.
struct NetworksView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var networks = model.networks
        let pendingRemoval = networks.pendingRemoval
        VStack(alignment: .leading, spacing: 0) {
            NetworksHeader()
            VStack(alignment: .leading, spacing: 14) {
                if networks.isCreateBarOpen {
                    CreateNetworkBar()
                }
                HStack {
                    CapsuleSegmented(
                        options: NetworkFilter.allCases.map {
                            SegmentOption(value: $0, title: "\($0.rawValue) (\(networks.count(for: $0)))")
                        },
                        selection: $networks.filter
                    )
                    Spacer()
                    Text("bridge, host and none are built in and can't be removed")
                        .font(.ui(12))
                        .foregroundStyle(Palette.secondary)
                }
                if networks.networks.isEmpty {
                    ContentUnavailableView(
                        networks.isLoading ? "Loading networks…" : "No networks",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text(networks.errorMessage ?? "Docker's networks appear here once Colima is running.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NetworksCard()
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .animation(.easeOut(duration: 0.2), value: networks.isCreateBarOpen)
        .confirmationDialog(
            "Remove “\(pendingRemoval?.name ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { networks.pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { network in
            Button("Remove", role: .destructive) { Task { await networks.remove(network) } }
        } message: { _ in
            Text("Containers can't connect to it anymore. Compose recreates its networks on the next “up”.")
        }
        .overlay(alignment: .bottom) {
            if let error = networks.errorMessage, !networks.networks.isEmpty {
                ErrorBanner(message: error) { networks.errorMessage = nil }
                    .padding(.bottom, 16)
            } else if let toast = networks.toast {
                ToastView(message: toast).padding(.bottom, 20)
            }
        }
        .animation(.easeOut(duration: 0.2), value: networks.toast)
    }
}

/// Title + subtitle, spacer, refresh/sort capsule, search capsule, New network.
private struct NetworksHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var networks = model.networks
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Networks").font(.ui(15, .semibold))
                Text(verbatim: networks.summary)
                    .font(.ui(11))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.trailing, 6)

            Spacer(minLength: 10)

            GlassCapsule {
                Button { Task { await networks.refresh() } } label: {
                    Label { Text("Refresh") } icon: { LineIcon(kind: .refresh).icon(Palette.text, size: 16) }
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .keyboardShortcut("r")
                .help("Refresh (⌘R)")

                Menu {
                    Picker("Sort by", selection: $networks.sort) {
                        ForEach(NetworkSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Hoverable { hovered in
                        LineIcon(kind: .sort).icon(Palette.text, size: 16)
                            .frame(width: 34, height: 28)
                            .background(hovered ? Palette.hover : .clear, in: .capsule)
                            .contentShape(.capsule)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort by name or connected containers")
                .accessibilityLabel("Sort")
            }

            HStack(spacing: 6) {
                LineIcon(kind: .search).icon(Palette.secondary, size: 14)
                TextField("Search", text: $networks.searchText)
                    .textFieldStyle(.plain)
                    .font(.ui(13))
            }
            .padding(.horizontal, 12)
            .frame(width: 200, height: 34)
            .glassSurface(Capsule())
            .help("Search by name, driver, subnet or Compose project")

            Button { networks.openCreateBar() } label: {
                HStack(spacing: 6) {
                    LineIcon(kind: .plus).icon(.white, size: 14, svgStrokeWidth: 2.4)
                    Text("New network")
                }
            }
            .buttonStyle(TintButtonStyle())
            .keyboardShortcut("n")
            .help("Create a network (⌘N)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
    }
}

/// Glass bar: "Name" field, "Driver" picker, "Internal (no internet)", Cancel, Create.
private struct CreateNetworkBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var networks = model.networks
        let showNameError = !networks.newName.isEmpty && networks.nameError != nil
        HStack(spacing: 10) {
            Text("Name").font(.ui(13, .medium))
            TextField("backend", text: $networks.newName)
                .textFieldStyle(.plain)
                .font(.mono(12))
                .padding(.horizontal, 10)
                .frame(minWidth: 200, maxWidth: .infinity)
                .frame(height: 30)
                .background(Palette.field, in: .rect(cornerRadius: 10))
                .focused($focused)
                .onSubmit { Task { await networks.create() } }

            Text("Driver").font(.ui(13, .medium))
            Picker("Driver", selection: $networks.newDriver) {
                ForEach(NetworksViewModel.drivers, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help("bridge for containers on this Mac; macvlan gives containers their own address on your LAN")

            Toggle("Internal (no internet)", isOn: $networks.newInternal)
                .toggleStyle(.checkbox)
                .font(.ui(12))
                .foregroundStyle(Palette.tertiary)
                .help("Containers on it can reach each other but not the internet")

            if let error = networks.createError ?? (showNameError ? networks.nameError : nil) {
                Text(error)
                    .font(.ui(12))
                    .foregroundStyle(Palette.danger)
                    .lineLimit(2)
                    .frame(maxWidth: 220, alignment: .leading)
            } else if networks.isCreating {
                ProgressView().controlSize(.small)
            }

            Button("Cancel") { networks.closeCreateBar() }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close")
            Button("Create") { Task { await networks.create() } }
                .buttonStyle(TintButtonStyle())
                .disabled(networks.isCreating || networks.nameError != nil)
        }
        .disabled(networks.isCreating)
        .padding(.leading, 16)
        .padding([.trailing, .vertical], 8)
        .glassSurface(RoundedRectangle(cornerRadius: 22))
        .onAppear { focused = true }
    }
}

/// `grid-template-columns: 2.2fr 0.8fr 1.4fr 1.1fr 2fr 84px; gap: 12px; padding: 0 16px`.
private struct NetworkColumns {
    static let actions: CGFloat = 84
    static let gap: CGFloat = 12
    static let padding: CGFloat = 16

    let name, driver, subnet, gateway, containers: CGFloat

    init(width: CGFloat) {
        let fractions = max(width - 2 * Self.padding - Self.actions - 5 * Self.gap, 0)
        let fr = fractions / 7.5
        name = 2.2 * fr
        driver = 0.8 * fr
        subnet = 1.4 * fr
        gateway = 1.1 * fr
        containers = 2 * fr
    }
}

private struct NetworksCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let networks = model.networks
        GeometryReader { geometry in
            let columns = NetworkColumns(width: geometry.size.width)
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    NetworksHeaderRow(columns: columns)
                    ForEach(networks.visibleNetworks) { network in
                        NetworkListRow(network: network, columns: columns)
                    }
                }
                .frame(width: geometry.size.width)
                .background(Palette.card)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .defaultScrollAnchor(.top)
        }
    }
}

private struct NetworksHeaderRow: View {
    let columns: NetworkColumns

    var body: some View {
        HStack(spacing: NetworkColumns.gap) {
            Text("NAME").frame(width: columns.name, alignment: .leading)
            Text("DRIVER").frame(width: columns.driver, alignment: .leading)
            Text("SUBNET").frame(width: columns.subnet, alignment: .leading)
            Text("GATEWAY").frame(width: columns.gateway, alignment: .leading)
            Text("CONTAINERS").frame(width: columns.containers, alignment: .leading)
            Text("ACTIONS").frame(width: NetworkColumns.actions, alignment: .center)
        }
        .font(.ui(11, .semibold))
        .tracking(0.33)
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, NetworkColumns.padding)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Palette.headerDivider.frame(height: 1) }
    }
}

private struct NetworkListRow: View {
    @Environment(AppModel.self) private var model
    let network: DockerNetwork
    let columns: NetworkColumns

    var body: some View {
        let networks = model.networks
        let connected = networks.connected(network)
        let chip = network.isBuiltIn ? "Built-in" : network.composeProject
        Hoverable { hovered in
            HStack(spacing: NetworkColumns.gap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(network.name)
                        .font(.ui(13, .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(network.isInternal ? "\(network.name) — internal, no internet" : network.name)
                    if let chip {
                        Text(chip)
                            .font(.ui(11))
                            .foregroundStyle(Palette.tertiary)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Palette.chip, in: .capsule)
                            .help(network.isBuiltIn ? "Created by Docker" : "Compose project “\(chip)”")
                    }
                }
                .frame(width: columns.name, alignment: .leading)

                Text(network.driver)
                    .font(.ui(12))
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: columns.driver, alignment: .leading)

                Text(verbatim: network.subnet ?? "—")
                    .font(.mono(12))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                    .frame(width: columns.subnet, alignment: .leading)

                Text(verbatim: network.gateway ?? "—")
                    .font(.mono(12))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                    .frame(width: columns.gateway, alignment: .leading)

                HStack(spacing: 6) {
                    Circle().fill(connected.isEmpty ? Palette.grayDot : Palette.greenDot).frame(width: 8, height: 8)
                    Text(connected.isEmpty ? "No containers" : connected.joined(separator: ", ")).lineLimit(1)
                }
                .font(.ui(12))
                .foregroundStyle(connected.isEmpty ? Palette.secondary : Palette.greenText)
                .frame(width: columns.containers, alignment: .leading)
                .help(connected.isEmpty ? "No container is connected" : "Connected: \(connected.joined(separator: ", "))")

                NetworkActions(network: network, canRemove: networks.canRemove(network), connected: connected)
                    .frame(width: NetworkColumns.actions, alignment: .center)
            }
            .padding(.horizontal, NetworkColumns.padding)
            .frame(height: 52)
            .background(hovered ? Palette.rowHover : .clear)
            .overlay(alignment: .bottom) { Palette.rowDivider.frame(height: 1) }
            .contentShape(.rect)
        }
        .contextMenu {
            Button("Copy Name") { NetworkActions.copy(network.name) }
            if let subnet = network.subnet {
                Button("Copy Subnet") { NetworkActions.copy(subnet) }
            }
            Divider()
            Button("Remove…", role: .destructive) { networks.pendingRemoval = network }
                .disabled(!networks.canRemove(network))
        }
    }
}

private struct NetworkActions: View {
    @Environment(AppModel.self) private var model
    let network: DockerNetwork
    let canRemove: Bool
    let connected: [String]

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var body: some View {
        let networks = model.networks
        HStack(spacing: 2) {
            if networks.removingIDs.contains(network.id) {
                ProgressView().controlSize(.small).frame(width: 58, height: 28)
            } else {
                Button {
                    Self.copy(network.name)
                    networks.showToast("Copied \(network.name)")
                } label: {
                    Label { Text("Copy name") } icon: { LineIcon(kind: .copy).icon(Palette.text, size: 14) }
                }
                .help("Copy “\(network.name)”")

                Button { networks.pendingRemoval = network } label: {
                    Label { Text("Remove") } icon: { LineIcon(kind: .trash).icon(Palette.danger, size: 14) }
                }
                .disabled(!canRemove)
                .opacity(canRemove ? 1 : 0.35)
                .help(canRemove ? "Remove \(network.name)…"
                      : network.isBuiltIn ? "Built-in networks can't be removed"
                      : "Containers are connected — remove or disconnect them first")
            }
        }
        .buttonStyle(ToolbarIconButtonStyle(width: 28))
    }
}
