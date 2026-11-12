import ColiUICore
import Foundation
import Observation

enum ProfileOperation: Equatable {
    case applying, creating, deleting

    var title: String {
        switch self {
        case .applying: "Applying…"
        case .creating: "Creating…"
        case .deleting: "Deleting…"
        }
    }
}

@MainActor
@Observable
final class ProfilesViewModel {
    private(set) var profiles: [ColimaInstance] = []
    private(set) var selectedName: String?
    private(set) var isCreating = false
    private(set) var original: ColimaProfileSettings?
    private(set) var operation: ProfileOperation?
    var draft = ColimaProfileSettings.newProfile
    /// The New profile modal's settings; the editor keeps showing the selected profile behind it.
    var newDraft = ColimaProfileSettings.newProfile
    var newName = ""
    var confirmingApply = false
    var confirmingDelete = false
    var errorMessage: String?
    /// The profile ColiUI talks to (shown with the "docker context" pill).
    let activeProfile: String

    private let runtime: ColimaRuntime

    init(runtime: ColimaRuntime, activeProfile: String) {
        self.runtime = runtime
        self.activeProfile = activeProfile
    }

    var runningCount: Int { profiles.filter(\.isRunning).count }
    var selected: ColimaInstance? { profiles.first { $0.name == selectedName } }
    var isBusy: Bool { operation != nil }
    var isDirty: Bool { draft != original }
    /// Colima disks can grow but never shrink.
    var minimumDisk: Int { original?.diskGiB ?? 20 }

    var nameError: String? {
        let name = newName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "Enter a name." }
        if name.range(of: #"^[a-z0-9][a-z0-9-]*$"#, options: .regularExpression) == nil {
            return "Use lowercase letters, digits and “-”."
        }
        if profiles.contains(where: { $0.name == name }) { return "A profile named “\(name)” already exists." }
        return nil
    }

    func load() async {
        do {
            profiles = try await runtime.instances().sorted { lhs, rhs in
                if (lhs.name == activeProfile) != (rhs.name == activeProfile) { return lhs.name == activeProfile }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let target = profiles.first { $0.name == selectedName }?.name ?? profiles.first?.name
        if let target { await show(target) } else { selectedName = nil }
    }

    /// Picked by the user: clears any previous error.
    func select(_ name: String) async {
        errorMessage = nil
        await show(name)
    }

    /// Reloads keep the last error visible (an apply that failed still reloads the list).
    private func show(_ name: String) async {
        selectedName = name
        let instance = profiles.first { $0.name == name }
        let settings = (try? await runtime.settings(profile: name)) ?? instance.map(Self.fallbackSettings)
        // Another profile was picked while `colima` answered; its settings must not land on that one.
        guard selectedName == name else { return }
        original = settings
        draft = settings ?? .newProfile
    }

    func startNewProfile() {
        isCreating = true
        newDraft = .newProfile
        newName = ""
        errorMessage = nil
    }

    func cancelNewProfile() {
        isCreating = false
    }

    func revert() {
        if let original { draft = original }
    }

    /// Restarting a running VM stops its containers, so ask first.
    func requestApply() async {
        if selected?.isRunning == true {
            confirmingApply = true
        } else {
            await apply()
        }
    }

    func apply() async {
        guard let profile = selected else { return }
        await perform(.applying) {
            try await runtime.apply(draft, to: profile.name, isRunning: profile.isRunning)
        }
        await load()
    }

    func create() async {
        guard nameError == nil else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        let succeeded = await perform(.creating) {
            try await runtime.create(profile: name, settings: newDraft)
        }
        guard succeeded else { return }
        isCreating = false
        selectedName = name
        await load()
    }

    func delete() async {
        guard let profile = selected else { return }
        let succeeded = await perform(.deleting) {
            try await runtime.delete(profile: profile.name)
        }
        if succeeded { selectedName = nil }
        await load()
    }

    @discardableResult
    private func perform(_ kind: ProfileOperation, _ work: () async throws -> Void) async -> Bool {
        operation = kind
        defer { operation = nil }
        do {
            try await work()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private static func fallbackSettings(_ instance: ColimaInstance) -> ColimaProfileSettings {
        ColimaProfileSettings(
            cpus: instance.cpus,
            memoryGiB: Double(instance.memoryBytes) / 1_073_741_824,
            diskGiB: Int(instance.diskBytes / 1_073_741_824),
            vmType: instance.vmType ?? "vz",
            mountType: "virtiofs",
            rosetta: false,
            runtime: instance.runtime
        )
    }
}
