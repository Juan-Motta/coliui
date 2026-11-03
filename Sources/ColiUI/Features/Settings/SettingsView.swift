import AppKit
import ColiUICore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case notifications = "Notifications"
    case shortcuts = "Shortcuts"
    case about = "About"

    var id: Self { self }

    var icon: LineIcon.Kind {
        switch self {
        case .general: .settings
        case .notifications: .bell
        case .shortcuts: .keyboard
        case .about: .info
        }
    }
}

/// Settings.dc.html as a sheet over the main window: centred glass tab capsule, Done on the trailing side, grouped rows.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        VStack(spacing: 0) {
            ZStack {
                SettingsTabs()
                HStack {
                    Spacer()
                    Button("Done") { model.isSettingsPresented = false }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.cancelAction)
                        .help("Close Settings (Esc)")
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            ScrollView(.vertical) {
                Group {
                    switch settings.tab {
                    case .general: GeneralSettings()
                    case .notifications: NotificationSettings()
                    case .shortcuts: ShortcutSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
            }
        }
        .frame(width: 680, height: 600)
        .foregroundStyle(Palette.text)
        .background(Palette.settingsBackground)
        .task { await model.profiles.load() }
    }
}

/// `.tab` / `.on` buttons in a glass capsule: 30 pt tall, 15 pt icon, 12 pt label.
private struct SettingsTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                let isOn = settings.tab == tab
                Button { settings.tab = tab } label: {
                    Hoverable { hovered in
                        HStack(spacing: 6) {
                            LineIcon(kind: tab.icon).icon(isOn ? Palette.segmentOnText : Palette.segmentOffText, size: 15, svgStrokeWidth: 1.9)
                            Text(tab.rawValue)
                        }
                        .font(.ui(12, isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Palette.segmentOnText : Palette.segmentOffText)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background {
                            if isOn {
                                Capsule().fill(Palette.segmentOn).shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                            } else if hovered {
                                Capsule().fill(Palette.hover)
                            }
                        }
                        .contentShape(.capsule)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .glassSurface(Capsule())
        .frame(maxWidth: .infinity)
    }
}

// MARK: General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        let profiles = Array(Set(model.profiles.profiles.map(\.name) + [settings.defaultProfile, model.colima.profile])).sorted()
        let detected = DockerSocket.resolve(
            environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory(), profile: settings.defaultProfile
        )
        let pendingRelaunch = settings.defaultProfile != model.colima.profile
            || settings.resolvedSocket(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory()) != model.socketPath
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Startup") {
                SwitchRow("Launch ColiUI at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    RowNote(error, color: Palette.danger)
                }
                SwitchRow("Start Colima when ColiUI opens", isOn: $settings.startColimaOnOpen)
                SwitchRow("Show icon in Dock", isOn: $settings.showInDock)
            }

            SettingsSection("Colima") {
                SettingsRow {
                    Text("Default profile")
                    Spacer()
                    PillPicker(selection: $settings.defaultProfile, options: profiles.map { ($0, $0) })
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Docker socket")
                    TextField(detected, text: $settings.socketPath)
                        .textFieldStyle(.plain)
                        .font(.mono(12))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Palette.field, in: .rect(cornerRadius: 10))
                    Text("Detected automatically from the active profile")
                        .font(.ui(11))
                        .foregroundStyle(Palette.secondary)
                }
                .font(.ui(13))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                SettingsRow {
                    Text("Refresh stats every")
                    Spacer()
                    PillPicker(selection: $settings.statsInterval, options: StatsInterval.allCases.map { ($0, $0.rawValue) })
                }
                if pendingRelaunch {
                    RowNote("Profile and socket changes apply the next time ColiUI opens.", color: Palette.secondary)
                }
            }

            SettingsSection("Appearance") {
                SettingsRow {
                    Text("Theme")
                    Spacer()
                    ThemeSegmented(selection: $settings.theme)
                }
            }
        }
    }
}

// MARK: Notifications

private struct NotificationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup {
                ForEach(NotificationKind.allCases) { kind in
                    SettingsRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(.ui(13, .medium))
                            Text(kind.detail).font(.ui(12)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Toggle(kind.title, isOn: Binding(
                            get: { settings.isEnabled(kind) },
                            set: { enabled in
                                settings.setNotification(kind, enabled: enabled)
                                if enabled { model.notifier.requestAuthorization() }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(Palette.switchOn)
                    }
                }
            }
            Text("Delivered through macOS Notification Center — allow ColiUI in System Settings › Notifications.")
                .font(.ui(12))
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 6)
        }
    }
}

// MARK: Shortcuts

/// The keys the app binds.
struct ShortcutItem: Identifiable {
    let action: String
    let keys: String
    var id: String { action }

    static let all = [
        ShortcutItem(action: "Refresh", keys: "⌘R"),
        ShortcutItem(action: "Search", keys: "⌘F"),
        ShortcutItem(action: "Run container", keys: "⌘N"),
        ShortcutItem(action: "Start / stop selected", keys: "Space"),
        ShortcutItem(action: "View logs", keys: "⌘L"),
        ShortcutItem(action: "Open shell", keys: "⌘⇧T"),
        ShortcutItem(action: "Open port in browser", keys: "⌘O"),
        ShortcutItem(action: "Remove selected", keys: "⌘⌫"),
        ShortcutItem(action: "Settings", keys: "⌘,"),
    ]
}

private struct ShortcutSettings: View {
    var body: some View {
        SettingsGroup {
            ForEach(ShortcutItem.all) { item in
                SettingsRow {
                    Text(item.action)
                    Spacer()
                    Text(item.keys)
                        .font(.ui(12))
                        .frame(minWidth: 22)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.chip, in: .rect(cornerRadius: 7))
                }
            }
        }
    }
}

// MARK: Building blocks

/// 12 pt semibold caption above a white group.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.ui(12, .semibold))
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 6)
            SettingsGroup { content }
        }
    }
}

/// Settings.dc.html › About: icon, name, version and tagline; "This Mac"; Copy diagnostics and the project links.
private struct AboutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let about = model.about
        VStack(alignment: .center, spacing: 18) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("ColiUI").font(.ui(20, .semibold))
                Text("Version \(about?.appVersion ?? AboutViewModel.bundleVersion)").font(.ui(12)).foregroundStyle(Palette.secondary)
                Text("A native Mac app for Colima and Docker").font(.ui(13)).foregroundStyle(Palette.tertiary)
            }
            .padding(.top, 8)

            UpdatesSettings(updates: model.updates)

            SettingsSection("This Mac") {
                ForEach(about?.rows ?? [], id: \.title) { row in
                    SettingsRow {
                        Text(row.title)
                        Spacer()
                        Text(verbatim: row.value)
                            .font(.mono(12))
                            .foregroundStyle(Palette.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(about?.justCopied == true ? "Copied" : "Copy diagnostics") {
                    Clipboard.copy(about?.diagnostics ?? "")
                    about?.markCopied()
                }
                .buttonStyle(PillButtonStyle())
                .disabled(about?.rows.isEmpty ?? true)
                Link(destination: AboutViewModel.repository) { Text("GitHub repository ↗") }
                    .buttonStyle(PillButtonStyle())
                Link(destination: AboutViewModel.newIssue) { Text("Report an issue ↗") }
                    .buttonStyle(PillButtonStyle())
            }

            Text("Copy diagnostics puts these versions on the clipboard, ready to paste into an issue.")
                .font(.ui(11))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .task { await about?.load(profile: model.colima.profile, vmType: model.colima.instance?.vmType) }
    }
}

/// Updates.dc.html › Settings › About › Updates: the daily-check switch, the status and Check for Updates.
private struct UpdatesSettings: View {
    @Bindable var updates: UpdatesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSection("Updates") {
                SwitchRow("Check for updates automatically", isOn: $updates.automaticallyChecks)
                    .disabled(!updates.canUpdate)
                SettingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            switch updates.status {
                            case .idle, .upToDate:
                                LineIcon(kind: .check).icon(Palette.switchOn, size: 14, svgStrokeWidth: 2.6)
                            case .checking:
                                ProgressView().controlSize(.mini)
                            case .available, .failed:
                                EmptyView()
                            }
                            Text(verbatim: updates.statusText)
                                .foregroundStyle(updates.status.isFailure ? Palette.danger : Palette.text)
                                .lineLimit(2)
                            if updates.status == .available {
                                Text("New")
                                    .font(.ui(10, .semibold))
                                    .foregroundStyle(Palette.accent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Palette.toggleOn, in: .capsule)
                            }
                        }
                        if let lastChecked = updates.lastCheckedText {
                            Text(lastChecked).font(.ui(11)).foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer()
                    if updates.isUpdateWaiting {
                        Button("View update") { updates.viewUpdate() }
                            .buttonStyle(TintButtonStyle(compact: true))
                    } else {
                        Button("Check for Updates") { updates.check() }
                            .buttonStyle(PillButtonStyle())
                            .disabled(!updates.canUpdate || updates.status == .checking)
                    }
                }
            }
            Text(updates.canUpdate
                 ? "Checks once a day. Updates are signed and verified before they install."
                 : "Updates work in the installed app, not in development builds.")
                .font(.ui(11))
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 6)
        }
    }
}

/// `.group`: white, 14 pt radius, hairline border; rows separated by `rgba(0,0,0,0.06)`.
private struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Group(subviews: content) { rows in
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Palette.headerDivider.frame(height: 1) }
                    row
                }
            }
        }
        .background(Palette.card)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }
}

/// `.r`: 44 pt minimum, 8×16 padding, 13 pt text.
private struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) { content }
            .font(.ui(13))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        SettingsRow {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Palette.switchOn)
        }
    }
}

private struct RowNote: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.ui(11))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `.sel`: 28 pt capsule on the field tint with the value and a chevron.
private struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Hoverable { hovered in
                HStack(spacing: 6) {
                    Text(options.first { $0.0 == selection }?.1 ?? "")
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .font(.ui(12))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(hovered ? Palette.fieldHover : Palette.field, in: .capsule)
                .contentShape(.capsule)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// System / Light / Dark: 26 pt segments on a 2 pt-inset field capsule.
private struct ThemeSegmented: View {
    @Binding var selection: AppTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTheme.allCases) { theme in
                let isOn = theme == selection
                Button { selection = theme } label: {
                    Text(theme.rawValue)
                        .font(.ui(12, isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Palette.segmentOnText : Palette.segmentOffText)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background {
                            if isOn { Capsule().fill(Palette.segmentOn).shadow(color: .black.opacity(0.14), radius: 2, y: 1) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Palette.field, in: .capsule)
    }
}
