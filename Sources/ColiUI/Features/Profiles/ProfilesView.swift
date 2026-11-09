import ColiUICore
import SwiftUI

/// Profiles.dc.html: profile list beside the editor card.
struct ProfilesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var profiles = model.profiles
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Colima profiles").font(.ui(15, .semibold))
                    Text(verbatim: "\(profiles.profiles.count) profile\(profiles.profiles.count == 1 ? "" : "s") · \(profiles.runningCount) running")
                        .font(.ui(11))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button { profiles.startNewProfile() } label: {
                    HStack(spacing: 6) {
                        LineIcon(kind: .plus).icon(.white, size: 14, svgStrokeWidth: 2.4)
                        Text("New profile")
                    }
                }
                .buttonStyle(TintButtonStyle())
                .disabled(profiles.isBusy)
                .help("Create another Colima VM")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 60)

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 16) {
                    ProfileList()
                        .frame(minWidth: 0, maxWidth: .infinity)
                    // New profiles are made in their own modal; the editor is for an existing VM.
                    if profiles.selected != nil {
                        ProfileEditor()
                            .frame(width: 360)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .confirmationDialog(
            "Restart “\(profiles.selectedName ?? "")” to apply?",
            isPresented: $profiles.confirmingApply
        ) {
            Button("Apply & restart") { Task { await run { await profiles.apply() } } }
        } message: {
            Text("Running containers stop and start again if their restart policy allows it.")
        }
        .confirmationDialog(
            "Delete “\(profiles.selectedName ?? "")”?",
            isPresented: $profiles.confirmingDelete
        ) {
            Button("Delete", role: .destructive) { Task { await run { await profiles.delete() } } }
        } message: {
            Text("Its VM, images, containers and volumes are removed. This can't be undone.")
        }
    }

    /// Runs a profile operation, then refreshes what depends on the VM.
    private func run(_ operation: () async -> Void) async {
        await operation()
        await model.colima.refresh()
        await model.containers.refresh()
    }
}

private struct ProfileList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let profiles = model.profiles
        VStack(spacing: 0) {
            if profiles.profiles.isEmpty {
                Text(profiles.errorMessage ?? "No Colima profiles yet. Create one with “New profile”.")
                    .font(.ui(13))
                    .foregroundStyle(Palette.secondary)
                    .padding(20)
            }
            ForEach(profiles.profiles) { instance in
                ProfileRow(instance: instance, isSelected: instance.name == profiles.selectedName)
            }
        }
        .padding(6)
        .cardSurface()
    }
}

private struct ProfileRow: View {
    @Environment(AppModel.self) private var model
    let instance: ColimaInstance
    let isSelected: Bool

    var body: some View {
        let profiles = model.profiles
        Hoverable { hovered in
            HStack(spacing: 12) {
                Circle().fill(instance.isRunning ? Palette.greenDot : Palette.grayDot).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.name).font(.ui(14, .semibold))
                    Text(verbatim: "\(instance.resourcesSummary) · \(instance.vmType ?? instance.arch) · \(instance.runtime)")
                        .font(.ui(12))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 8)
                Text(instance.isRunning ? "Running" : "Stopped")
                    .font(.ui(12, .semibold))
                    .foregroundStyle(instance.isRunning ? Palette.greenText : Palette.secondary)
                if instance.name == profiles.activeProfile {
                    Text("docker context")
                        .font(.ui(11, .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Palette.toggleOn, in: .capsule)
                        .help("ColiUI manages this profile's Docker")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? Palette.rowSelected : hovered ? Palette.rowHover : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .onTapGesture {
            guard !profiles.isBusy else { return }
            Task { await profiles.select(instance.name) }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ProfileEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var profiles = model.profiles
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit “\(profiles.selectedName ?? "")”").font(.ui(15, .semibold))
                Text("Applying restarts the VM")
                    .font(.ui(12))
                    .foregroundStyle(Palette.secondary)
            }

            ProfileSettingsFields(settings: $profiles.draft, minimumDisk: profiles.minimumDisk, isNew: false)

            if let error = profiles.errorMessage {
                Text(error).font(.ui(12)).foregroundStyle(Palette.danger)
            }

            HStack(spacing: 8) {
                Button("Delete…") { profiles.confirmingDelete = true }
                    .buttonStyle(PillButtonStyle(foreground: Palette.danger))
                    .help("Delete this profile's VM")
                Spacer()
                Button("Revert") { profiles.revert() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!profiles.isDirty)
                Button {
                    Task {
                        await profiles.requestApply()
                        await model.colima.refresh()
                    }
                } label: {
                    HStack(spacing: 7) {
                        if profiles.operation == .applying {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(profiles.operation == .applying ? "Applying…" : "Apply & restart")
                    }
                }
                .buttonStyle(TintButtonStyle())
                .disabled(!profiles.isDirty || profiles.isBusy)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Palette.rowDivider.frame(height: 1) }
        }
        .disabled(profiles.isBusy)
        .padding(20)
        .cardSurface()
    }
}

/// NewProfileModal.dc.html: a name and the VM's settings; the editor keeps the selected profile behind it.
struct NewProfileModal: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var profiles = model.profiles
        ModalPanel(title: "New profile", lede: "Creates and starts a new Colima VM", width: 520) {
            // The form scrolls only when the window is too short for it.
            ViewThatFits(in: .vertical) {
                form(profiles)
                ScrollView(.vertical) { form(profiles) }
            }
            if let error = profiles.errorMessage {
                Text(error).font(.ui(12)).foregroundStyle(Palette.danger)
            }
        } actions: {
            if let operation = profiles.operation {
                ProgressView().controlSize(.small)
                Text(operation.title).font(.ui(12)).foregroundStyle(Palette.secondary)
            }
            Button("Cancel") { profiles.cancelNewProfile() }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("Create and start") {
                Task {
                    await profiles.create()
                    await model.colima.refresh()
                }
            }
            .buttonStyle(TintButtonStyle())
            .disabled(profiles.isBusy || profiles.nameError != nil)
        }
    }

    private func form(_ profiles: ProfilesViewModel) -> some View {
        @Bindable var profiles = profiles
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                ModalTextField(label: "Name", placeholder: "work", text: $profiles.newName)
                if !profiles.newName.isEmpty, let error = profiles.nameError {
                    Text(error).font(.ui(11)).foregroundStyle(Palette.danger)
                } else {
                    Text("Lowercase letters, digits and “-”").font(.ui(11)).foregroundStyle(Palette.secondary)
                }
            }
            ProfileSettingsFields(settings: $profiles.newDraft, minimumDisk: 20, isNew: true)
        }
        .disabled(profiles.isBusy)
    }
}

/// CPUs, memory, disk, VM type, mount, Rosetta and runtime: the editor (a VM that exists) and the
/// New profile modal (`isNew`, where the VM type and runtime can still be chosen) share them.
struct ProfileSettingsFields: View {
    @Binding var settings: ColimaProfileSettings
    let minimumDisk: Int
    let isNew: Bool

    var body: some View {
        let rosettaAvailable = settings.vmType == "vz"
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("CPUs").font(.ui(13))
                Spacer()
                HStack(spacing: 8) {
                    stepButton("−", label: "Fewer CPUs") { settings.cpus = max(1, settings.cpus - 1) }
                        .disabled(settings.cpus <= 1)
                    Text(verbatim: "\(settings.cpus)").font(.ui(14, .semibold)).frame(width: 28)
                    stepButton("+", label: "More CPUs") {
                        settings.cpus = min(ProcessInfo.processInfo.activeProcessorCount, settings.cpus + 1)
                    }
                    .disabled(settings.cpus >= ProcessInfo.processInfo.activeProcessorCount)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                valueRow("Memory", value: "\(Int(settings.memoryGiB)) GiB")
                Slider(value: $settings.memoryGiB, in: 1...32, step: 1).tint(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                valueRow("Disk", value: "\(settings.diskGiB) GiB")
                Slider(
                    value: Binding(get: { Double(settings.diskGiB) }, set: { settings.diskGiB = Int($0) }),
                    in: Double(minimumDisk)...Double(max(500, minimumDisk)),
                    step: 10
                )
                .tint(Palette.accent)
                Text("Disk can grow but never shrink").font(.ui(11)).foregroundStyle(Palette.secondary)
            }

            HStack {
                Text("VM type").font(.ui(13))
                Spacer()
                CompactSegmented(options: ["vz", "qemu"], selection: $settings.vmType)
                    .disabled(!isNew)
                    .help(isNew ? "vz is faster on Apple silicon; qemu emulates other architectures" : "Fixed once the VM exists")
            }

            pickerRow("Mount type", selection: $settings.mountType, options: ["virtiofs", "sshfs", "9p"])

            HStack {
                Text("Rosetta (x86 emulation)").font(.ui(13))
                Spacer()
                Toggle("Rosetta", isOn: $settings.rosetta)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Palette.greenDot)
                    .disabled(!rosettaAvailable)
                    .help(rosettaAvailable ? "Run amd64 images faster" : "Rosetta needs the vz VM type")
            }

            pickerRow("Runtime", selection: $settings.runtime, options: ["docker", "containerd", "incus"])
                .disabled(!isNew)
                .help(isNew ? "" : "Fixed once the VM exists")
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Hoverable { hovered in
                Text(symbol)
                    .font(.ui(16))
                    .frame(width: 30, height: 30)
                    .background(hovered ? Palette.fieldHover : Palette.field, in: .circle)
                    .contentShape(.circle)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value).fontWeight(.semibold)
        }
        .font(.ui(13))
    }

    private func pickerRow(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        HStack {
            Text(title).font(.ui(13))
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// Small segmented control on a soft capsule (the editor's VM type).
private struct CompactSegmented: View {
    @Environment(\.isEnabled) private var isEnabled
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button { selection = option } label: {
                    Text(option)
                        .font(.ui(12, isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Palette.segmentOnText : Palette.segmentOffText)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if isOn { Capsule().fill(Palette.segmentOn).shadow(color: .black.opacity(0.14), radius: 2, y: 1) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Palette.field, in: .capsule)
        .opacity(isEnabled ? 1 : 0.6)
    }
}
